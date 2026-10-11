--[[
Read-only access to StarDict dictionaries by entry position.

sdcv only answers "what does this word mean?". Paging through a dictionary
needs "what is the entry before/after this one?", so this module reads the
.idx itself. Only the shapes this plugin supports are handled: 32-bit offsets
and a single-type sametypesequence of "m" (plain text), "h" (HTML) or "x" (what
the dictionaries that declare it actually hold: text with a tag or two, see
text.lua), with the definitions either in a plain .dict or a
dictzip-compressed .dict.dz.

Large dictionaries (hundreds of thousands of entries) can't be held in memory
on an e-reader, so the .idx is scanned once and only the file offset and key
of every PAGE_SIZE-th entry are kept, cached on disk. Entries are then
fetched a page at a time, and lookups binary-search the page keys.

The .syn, when there is one, is read the same way. It holds other words that
lead to an entry (inflected forms, variant spellings: "abomined" leads to
"abomine"), each with the number of that entry, and is used when a word is not
a headword itself. It is optional: when it is damaged it is left aside and the
dictionary works without it.
]]

local DataStorage = require("datastorage")
local Inflate = require("modules/inflate")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local PAGE_SIZE = 64
local PAGES_KEPT_IN_MEMORY = 8
local CHUNKS_KEPT_IN_MEMORY = 2 -- inflated dictzip chunks, about 58 KB each
local INDEX_READ_CHUNK = 256 * 1024
local INDEX_CACHE_VERSION = 4 -- 3: definitions_end, so a cut .dict is caught on load too; 4: the .syn
local MAX_HOMOGRAPHS = 64
local MAX_SCAN_ENTRIES = PAGE_SIZE * 2

local SUPPORTED_TYPES = { m = true, h = true, x = true }

-- The StarDict spec sorts the .idx with stardict_strcmp: ASCII
-- case-insensitive first, then byte order. Not every dictionary follows it:
-- the Priberam Portuguese one is in plain byte order (capitalized words come
-- before all the lowercase ones), so lookups try both orders. Lua's "<" on
-- strings is a byte comparison as long as LC_COLLATE stays "C", which
-- KOReader doesn't change.
local ASCII_FOLD = {}
for code = string.byte("A"), string.byte("Z") do
	ASCII_FOLD[string.char(code)] = string.char(code + 32)
end

local function foldAscii(text)
	return (text:gsub("[A-Z]", ASCII_FOLD))
end

local function compareFolded(a, b)
	local folded_a, folded_b = foldAscii(a), foldAscii(b)
	if folded_a ~= folded_b then
		return folded_a < folded_b and -1 or 1
	end
	if a == b then
		return 0
	end
	return a < b and -1 or 1
end

local function compareBytes(a, b)
	if a == b then
		return 0
	end
	return a < b and -1 or 1
end

local COMPARATORS = { compareFolded, compareBytes }

-- Case mapping for any letter, not only A-Z ("Árvore" -> "árvore"), through
-- the utf8proc KOReader ships. Without it, only ASCII letters change case.
local Utf8Proc
do
	local ok, module = pcall(require, "ffi/utf8proc")
	Utf8Proc = ok and module or nil
end

local function changeCase(text, lower)
	if Utf8Proc then
		local ok, cased = pcall(Utf8Proc.cased_dumb, text, lower)
		if ok and cased then
			return cased
		end
	end
	return lower and foldAscii(text) or text:upper()
end

--- The other casings a key may be stored under: all lowercase (a word at the
-- start of a sentence), capitalized (a name typed in lowercase) and all
-- uppercase (an abbreviation), each once and none the same as `word`.
local function caseVariants(word)
	local lowered = changeCase(word, true)
	local first, rest = lowered:match("^([%z\1-\127\194-\244][\128-\191]*)(.*)$")
	local candidates = { lowered, first and (changeCase(first, false) .. rest), changeCase(word, false) }
	local variants, seen = {}, { [word] = true }
	for index = 1, 3 do
		local candidate = candidates[index]
		if candidate and not seen[candidate] then
			seen[candidate] = true
			variants[#variants + 1] = candidate
		end
	end
	return variants
end

local function readFile(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content
end

local function parseIfo(path)
	local content = readFile(path)
	if not content then
		return nil
	end
	local info = {}
	for key, value in content:gmatch("([%w_]+)=([^\r\n]*)") do
		info[key] = value
	end
	return info
end

local function readUInt32BE(b1, b2, b3, b4)
	return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

-- A short hash of a path (djb2), so that dictionaries with the same file name
-- in different folders get different cache files.
local function pathHash(path)
	local hash = 5381
	for index = 1, #path do
		hash = (hash * 33 + path:byte(index)) % 4294967296
	end
	return string.format("%08x", hash)
end

local StarDict = {}
StarDict.__index = StarDict

local instances = {}

--- Returns the (shared) dictionary object for an .ifo file.
-- @treturn StarDict dictionary, or nil and a reason ("unreadable",
-- "unsupported", or "incomplete" when the .idx is not the size the .ifo says)
function StarDict.get(ifo_path)
	if instances[ifo_path] then
		return instances[ifo_path]
	end

	local info = parseIfo(ifo_path)
	if not info or not info.bookname then
		return nil, "unreadable"
	end
	if not SUPPORTED_TYPES[info.sametypesequence or ""] then
		return nil, "unsupported"
	end
	if info.idxoffsetbits and info.idxoffsetbits ~= "32" then
		return nil, "unsupported"
	end

	local base = ifo_path:gsub("%.ifo$", "")
	local idx_path = base .. ".idx"
	local dict_path = base .. ".dict"
	local compressed = false
	if lfs.attributes(dict_path, "mode") ~= "file" then
		dict_path = base .. ".dict.dz"
		compressed = true
	end
	if lfs.attributes(idx_path, "mode") ~= "file" or lfs.attributes(dict_path, "mode") ~= "file" then
		return nil, "unreadable"
	end
	-- A copy cut short (an interrupted transfer) would page through garbage.
	if info.idxfilesize and tonumber(info.idxfilesize) ~= lfs.attributes(idx_path, "size") then
		logger.warn("DictionaryExplorer: the .idx is not the size its .ifo says:", idx_path)
		return nil, "incomplete"
	end

	local cache_dir = DataStorage:getDataDir() .. "/cache/dictionaryexplorer/"
	local cache_name = base:match("[^/]+$"):gsub("[^%w_%-]", "_")
	local self = setmetatable({
		ifo_path = ifo_path,
		name = info.bookname,
		is_html = info.sametypesequence == "h",
		text_type = info.sametypesequence, -- "m", "h" or "x": how the viewer prepares the text
		wordcount = tonumber(info.wordcount), -- what the .ifo says, checked against the .idx
		synwordcount = tonumber(info.synwordcount), -- the same for the .syn
		idx_path = idx_path,
		syn_path = base .. ".syn",
		dict_path = dict_path,
		compressed = compressed,
		cache_path = cache_dir .. cache_name .. "-" .. pathHash(ifo_path) .. ".lua",
		legacy_cache_path = cache_dir .. cache_name .. ".lua", -- before v1.0.1, shared by same-named files
		index_error = nil, -- why buildIndex() failed, if it did
		syn_error = nil, -- why the .syn was left aside, if it was
		-- The .idx records (see newRecords): offsets and first_keys are the file
		-- offset and the key of every PAGE_SIZE-th entry.
		idx = nil,
		offsets = nil, -- idx.offsets
		first_keys = nil, -- idx.first_keys
		count = nil, -- idx.count
		syn = nil, -- the .syn records, when there is a usable .syn
	}, StarDict)
	instances[ifo_path] = self
	return self
end

--- Lists dictionaries under a StarDict data directory.
-- @string data_dir directory to scan recursively
-- @treturn table array of { name = bookname, file = path to .ifo }
function StarDict.scan(data_dir)
	local found = {}
	local function walk(dir)
		local ok, iterator, dir_obj = pcall(lfs.dir, dir)
		if not ok then
			return
		end
		for entry in iterator, dir_obj do
			if entry ~= "." and entry ~= ".." then
				local path = dir .. "/" .. entry
				local mode = lfs.attributes(path, "mode")
				if mode == "directory" then
					walk(path)
				elseif mode == "file" and path:match("%.ifo$") then
					local info = parseIfo(path)
					if info and info.bookname then
						table.insert(found, { name = info.bookname, file = path })
					end
				end
			end
		end
	end
	walk(data_dir)
	return found
end

-- ---------------------------------------------------------------------------
-- Index
-- ---------------------------------------------------------------------------

-- The .idx and the .syn are both runs of records: a key ended by "\0", then
-- TRAILER bytes (offset and size of the definition in the .idx, the number of
-- an entry in the .syn). They are paged through the same way.
local IDX_TRAILER, SYN_TRAILER = 8, 4

local function newRecords(path, trailer, size, count, offsets, first_keys)
	return {
		path = path,
		trailer = trailer,
		size = size, -- of the file
		count = count,
		offsets = offsets,
		first_keys = first_keys,
		pages = {},
		page_order = {},
	}
end

-- Whether a cached run of records adds up.
local function recordsAddUp(data)
	return type(data) == "table"
		and type(data.count) == "number"
		and data.count > 0
		and type(data.offsets) == "table"
		and type(data.first_keys) == "table"
		and #data.offsets == math.ceil(data.count / PAGE_SIZE)
		and #data.first_keys == #data.offsets
end

--- Scans a whole .idx or .syn once.
-- @treturn table { offsets, first_keys, count, highest }, where `highest` is
-- the end of the last definition (.idx) or the highest entry number (.syn);
-- or nil and "unreadable" / "truncated" (a record cut in the middle)
local function scanRecords(path, trailer)
	local file = io.open(path, "rb")
	if not file then
		return nil, "unreadable"
	end
	local offsets, first_keys, count, highest = {}, {}, 0, -1
	local buffer_start = 0 -- file offset of the first byte of `buffer`
	local buffer = ""
	while true do
		local chunk = file:read(INDEX_READ_CHUNK)
		if not chunk then
			break
		end
		buffer = buffer .. chunk

		local position, length = 1, #buffer
		while true do
			local terminator = buffer:find("\0", position, true)
			if not terminator or terminator + trailer > length then
				break -- the rest is a record split across two chunks
			end
			if count % PAGE_SIZE == 0 then
				offsets[#offsets + 1] = buffer_start + position - 1
				first_keys[#first_keys + 1] = buffer:sub(position, terminator - 1)
			end
			local value
			if trailer == IDX_TRAILER then
				local b1, b2, b3, b4, b5, b6, b7, b8 = buffer:byte(terminator + 1, terminator + 8)
				value = readUInt32BE(b1, b2, b3, b4) + readUInt32BE(b5, b6, b7, b8)
			else
				value = readUInt32BE(buffer:byte(terminator + 1, terminator + 4))
			end
			if value > highest then
				highest = value
			end
			count = count + 1
			position = terminator + trailer + 1
		end
		buffer_start = buffer_start + position - 1
		buffer = buffer:sub(position)
	end
	file:close()
	if buffer ~= "" then
		return nil, "truncated"
	end
	return { offsets = offsets, first_keys = first_keys, count = count, highest = highest }
end

-- Returns the records of one page: { word, offset, size } from the .idx,
-- { word, index } from the .syn.
local function getPage(records, page)
	local cached = records.pages[page]
	if cached then
		return cached
	end

	local start = records.offsets[page + 1]
	local stop = records.offsets[page + 2] or records.size
	local file = io.open(records.path, "rb")
	if not file then
		return nil
	end
	file:seek("set", start)
	local block = file:read(stop - start)
	file:close()
	if not block then
		return nil
	end

	local trailer = records.trailer
	local entries, position = {}, 1
	while true do
		local terminator = block:find("\0", position, true)
		if not terminator or terminator + trailer > #block then
			break
		end
		if trailer == IDX_TRAILER then
			local b1, b2, b3, b4, b5, b6, b7, b8 = block:byte(terminator + 1, terminator + 8)
			entries[#entries + 1] = {
				word = block:sub(position, terminator - 1),
				offset = readUInt32BE(b1, b2, b3, b4),
				size = readUInt32BE(b5, b6, b7, b8),
			}
		else
			entries[#entries + 1] = {
				word = block:sub(position, terminator - 1),
				index = readUInt32BE(block:byte(terminator + 1, terminator + 4)),
			}
		end
		position = terminator + trailer + 1
	end

	records.pages[page] = entries
	table.insert(records.page_order, page)
	if #records.page_order > PAGES_KEPT_IN_MEMORY then
		records.pages[table.remove(records.page_order, 1)] = nil
	end
	return entries
end

local function getRecord(records, position)
	if position < 0 or position >= records.count then
		return nil
	end
	local page = getPage(records, math.floor(position / PAGE_SIZE))
	return page and page[position % PAGE_SIZE + 1]
end

-- Position of the first record whose key sorts at or after `word` under the
-- given comparator.
local function lowerBound(records, word, compare)
	-- Last page whose first key sorts before the word.
	local first_keys = records.first_keys
	local low, high, page = 0, #first_keys - 1, 0
	while low <= high do
		local middle = math.floor((low + high) / 2)
		if compare(first_keys[middle + 1], word) < 0 then
			page = middle
			low = middle + 1
		else
			high = middle - 1
		end
	end

	local first = page * PAGE_SIZE
	local position = first
	while position < records.count and position - first < MAX_SCAN_ENTRIES do
		local record = getRecord(records, position)
		if not record or compare(record.word, word) >= 0 then
			break
		end
		position = position + 1
	end
	return math.min(position, records.count - 1)
end

-- Position of the first record keyed exactly `key`, trying every sort order.
local function findExact(records, key)
	for index = 1, #COMPARATORS do
		local position = lowerBound(records, key, COMPARATORS[index])
		local record = getRecord(records, position)
		if record and record.word == key then
			return position, record
		end
	end
end

function StarDict:_useIndex(idx, syn)
	self.idx, self.syn = idx, syn
	self.offsets, self.first_keys, self.count = idx.offsets, idx.first_keys, idx.count
end

function StarDict:_loadIndexCache()
	local ok, data = pcall(dofile, self.cache_path)
	if not ok or type(data) ~= "table" then
		return false
	end
	local attributes = lfs.attributes(self.idx_path)
	if data.version ~= INDEX_CACHE_VERSION
		or data.page_size ~= PAGE_SIZE
		or data.idx_size ~= attributes.size
		or data.idx_mtime ~= attributes.modification
		or not recordsAddUp(data)
		or (self.wordcount and data.count ~= self.wordcount)
		or type(data.definitions_end) ~= "number" then
		return false
	end
	-- The .syn, as it was when the cache was written: none, or the same file.
	local syn_attributes = lfs.attributes(self.syn_path)
	local syn_file = data.syn_file
	if (syn_attributes == nil) ~= (syn_file == nil)
		or (syn_file and (syn_file.size ~= syn_attributes.size or syn_file.mtime ~= syn_attributes.modification))
		or (data.syn and not recordsAddUp(data.syn)) then
		return false
	end
	-- The definitions file may have been replaced by a shorter copy since.
	if not self:_checkDefinitions(data.definitions_end) then
		return false
	end
	local syn = data.syn and newRecords(self.syn_path, SYN_TRAILER, syn_file.size, data.syn.count, data.syn.offsets, data.syn.first_keys)
	self.syn_error = data.syn_error
	self:_useIndex(newRecords(self.idx_path, IDX_TRAILER, data.idx_size, data.count, data.offsets, data.first_keys), syn)
	return true
end

--- Whether the page index is ready to use (loading the cached copy if any).
function StarDict:isIndexed()
	if self.idx then
		return true
	end
	return self:_loadIndexCache()
end

-- Whether the definitions file holds everything the .idx points into: a copy
-- cut short is refused here rather than failing entry by entry.
-- @treturn bool true, or false and why ("truncated definitions", "invalid dictzip header")
function StarDict:_checkDefinitions(definitions_end)
	local available
	if self.compressed then
		local file = io.open(self.dict_path, "rb")
		if not file then
			return false, "truncated definitions"
		end
		local header, problem = self:_loadDictzipHeader(file)
		file:close()
		if not header then
			return false, problem == "truncated" and "truncated definitions" or "invalid dictzip header"
		end
		available = header.uncompressed_size
	else
		available = lfs.attributes(self.dict_path, "size") or 0
	end
	if available < definitions_end then
		return false, "truncated definitions"
	end
	return true
end

--- Scans the whole .idx (and .syn) and stores the page index. Takes a while
-- on big dictionaries, so callers should show progress first. Only needed once.
-- @treturn bool true, or false and why ("unreadable", "empty", "truncated
-- index", "incomplete index", "truncated definitions", "invalid dictzip
-- header"), also kept in index_error
function StarDict:buildIndex()
	local ok, err = self:_buildIndex()
	self.index_error = not ok and err or nil
	if not ok then
		logger.warn("DictionaryExplorer: not indexing", self.ifo_path, err)
	end
	return ok, err
end

-- Scans the .syn, if there is one. One that doesn't add up is left aside:
-- the dictionary works without it.
-- @treturn table scan, or nil and why it was left aside (nil when there is no .syn)
function StarDict:_scanSynonyms(count)
	if lfs.attributes(self.syn_path, "mode") ~= "file" then
		return nil
	end
	local scan, err = scanRecords(self.syn_path, SYN_TRAILER)
	if not scan then
		return nil, err == "truncated" and "truncated synonyms" or "unreadable synonyms"
	end
	if scan.count == 0 then
		return nil, "empty synonyms"
	end
	if self.synwordcount and scan.count ~= self.synwordcount then
		return nil, "incomplete synonyms"
	end
	if scan.highest >= count then
		return nil, "synonyms out of range" -- they lead past the last entry
	end
	return scan
end

function StarDict:_buildIndex()
	local scan, err = scanRecords(self.idx_path, IDX_TRAILER)
	if not scan then
		return false, err == "truncated" and "truncated index" or err
	end
	local count = scan.count
	if count == 0 then
		return false, "empty"
	end
	if self.wordcount and count ~= self.wordcount then
		return false, "incomplete index"
	end
	local definitions_end = math.max(scan.highest, 0) -- where the last definition ends in the .dict
	local complete, problem = self:_checkDefinitions(definitions_end)
	if not complete then
		return false, problem
	end

	local syn_scan, syn_error = self:_scanSynonyms(count)
	if syn_error then
		logger.warn("DictionaryExplorer: leaving the .syn aside:", self.syn_path, syn_error)
	end
	local attributes = lfs.attributes(self.idx_path)
	local syn_attributes = lfs.attributes(self.syn_path)
	local syn
	if syn_scan then
		syn = newRecords(self.syn_path, SYN_TRAILER, syn_attributes.size, syn_scan.count, syn_scan.offsets, syn_scan.first_keys)
	end
	self.syn_error = syn_error
	self:_useIndex(newRecords(self.idx_path, IDX_TRAILER, attributes.size, count, scan.offsets, scan.first_keys), syn)

	-- Written aside and then renamed, so that an interrupted write never leaves
	-- a half cache behind. The cache of older versions goes: it is not read.
	util.makePath(self.cache_path:match("^(.*)/[^/]+$"))
	local temporary = self.cache_path .. ".tmp"
	local written = util.writeToFile(dump({
		version = INDEX_CACHE_VERSION,
		page_size = PAGE_SIZE,
		idx_size = attributes.size,
		idx_mtime = attributes.modification,
		count = count,
		definitions_end = definitions_end,
		offsets = scan.offsets,
		first_keys = scan.first_keys,
		syn_file = syn_attributes and { size = syn_attributes.size, mtime = syn_attributes.modification } or nil,
		syn = syn_scan and { count = syn_scan.count, offsets = syn_scan.offsets, first_keys = syn_scan.first_keys } or nil,
		syn_error = syn_error,
	}), temporary, true, true)
	if not (written and os.rename(temporary, self.cache_path)) then
		os.remove(temporary)
	end
	os.remove(self.legacy_cache_path)
	return true
end

function StarDict:getCount()
	return self.count
end

--- Returns entry number `position` (0-based), or nil when out of range.
function StarDict:getEntry(position)
	return getRecord(self.idx, position)
end

-- Position of the first entry whose key sorts at or after `word` under the
-- given comparator.
function StarDict:_lowerBound(word, compare)
	return lowerBound(self.idx, word, compare)
end

-- The entry a word of the .syn leads to, if it is one.
-- @treturn int position of the entry, or nil
-- @treturn string the key as the .syn has it
function StarDict:_findSynonym(key)
	if not self.syn then
		return nil
	end
	local record = select(2, findExact(self.syn, key))
	if record and record.index < self.count then
		return record.index, record.word
	end
end

--- Finds where `word` is in the dictionary.
-- `hint` is optional definition text used to pick between entries that share
-- the same key (Priberam, for one, indexes inflected forms under the base word).
-- @treturn int position of the entry, or of the closest one when there is none
-- @treturn bool true when an entry was found for the word
-- @treturn string the word as the .syn has it, when the entry was found through
-- the .syn (the word is not a headword itself, but leads to this one)
function StarDict:locate(word, hint)
	-- Typed or selected text may differ in case from the key ("Casa" or
	-- "CASA" for "casa", "Árvore" for "árvore", "óbidos" for "Óbidos"), and
	-- may be an inflected form only the .syn knows. The text as given wins over
	-- other casings, and a headword over a word of the .syn.
	local candidates = caseVariants(word)
	table.insert(candidates, 1, word)
	local position, entry, synonym
	for _index, candidate in ipairs(candidates) do
		position, entry = findExact(self.idx, candidate)
		if entry then
			break
		end
		local target, key = self:_findSynonym(candidate)
		if target then
			position, entry, synonym = target, self:getEntry(target), key
			break
		end
	end
	if not entry then
		-- A key that differs only in case ("House" for "house") sorts just
		-- before where the word would go; take the first of those.
		local folded = foldAscii(word)
		local closest = self:_lowerBound(word, compareFolded)
		local start = closest
		for _step = 1, MAX_HOMOGRAPHS do
			local previous = start > 0 and self:getEntry(start - 1)
			if not (previous and foldAscii(previous.word) == folded) then
				break
			end
			start = start - 1
		end
		local candidate = self:getEntry(start)
		if candidate and foldAscii(candidate.word) == folded then
			return start, true
		end
		return closest, false
	end

	if hint and hint ~= "" then
		local wanted = self.normalizeForMatch(hint)
		for candidate = position, math.min(position + MAX_HOMOGRAPHS, self.count) - 1 do
			local other = self:getEntry(candidate)
			if not other or other.word ~= entry.word then
				break
			end
			local definition = self:readDefinition(other)
			if definition and self.normalizeForMatch(definition) == wanted then
				return candidate, true, synonym
			end
		end
	end
	return position, true, synonym
end

--- Like locate(), for text that may be several words (a selection, or what the
-- user typed): when it isn't an entry as a whole, its first word is tried.
-- @treturn int position of the entry, or of the closest one when there is none
-- @treturn bool true when an entry was found
-- @treturn string the word as the .syn has it, when found through the .syn
function StarDict:locateText(text)
	local position, exact, synonym = self:locate(text)
	if not exact then
		local first_word = text:match("^(%S+)%s")
		if first_word then
			local first_position, first_exact, first_synonym = self:locate(first_word)
			if first_exact then
				return first_position, true, first_synonym
			end
		end
	end
	return position, exact, synonym
end

--- Reduces a definition to its first letters and digits, so text that went
-- through KOReader's markup clean-up still matches the raw definition.
function StarDict.normalizeForMatch(definition)
	local text = definition:gsub("%b<>", ""):gsub("&%w+;", ""):gsub("[%s%p]+", "")
	return text:sub(1, 60)
end

-- ---------------------------------------------------------------------------
-- Definitions
-- ---------------------------------------------------------------------------

local function readUInt16LE(text, position)
	local low, high = text:byte(position, position + 1)
	return low + high * 256
end

-- Reads the dictzip header once: where the compressed data starts, the
-- uncompressed chunk length, where each compressed chunk begins, and the
-- uncompressed size. Every length is checked before it is used, so a damaged
-- file gives nil instead of an error.
-- @treturn table header, or nil and "truncated" (the file ends before its
-- chunks do) or "invalid" (it is not a dictzip file it says it is)
function StarDict:_loadDictzipHeader(file)
	if self._dictzip then
		return self._dictzip
	end
	local file_size = file:seek("end")
	file:seek("set", 0)
	local header = file:read(12)
	if not header or #header < 12 or header:byte(1) ~= 0x1f or header:byte(2) ~= 0x8b then
		return nil, "invalid"
	end
	local flags = header:byte(4)
	if flags % 8 < 4 then -- FEXTRA bit: dictzip keeps its chunk table there
		return nil, "invalid"
	end
	local extra_length = readUInt16LE(header, 11)
	local extra = file:read(extra_length)
	if not extra or #extra < extra_length then
		return nil, "truncated"
	end

	-- The RA subfield: version, chunk length, chunk count, then one 16-bit
	-- compressed size per chunk.
	local chunk_length, chunk_sizes
	local position = 1
	while position + 3 <= #extra do
		local id = extra:sub(position, position + 1)
		local length = readUInt16LE(extra, position + 2)
		if position + 3 + length > #extra then
			return nil, "invalid"
		end
		if id == "RA" then
			if length < 6 then
				return nil, "invalid"
			end
			local data = extra:sub(position + 4, position + 3 + length)
			chunk_length = readUInt16LE(data, 3)
			local chunk_count = readUInt16LE(data, 5)
			if chunk_length == 0 or chunk_count == 0 or length < 6 + 2 * chunk_count then
				return nil, "invalid"
			end
			chunk_sizes = {}
			for index = 1, chunk_count do
				chunk_sizes[index] = readUInt16LE(data, 5 + index * 2)
			end
			break
		end
		position = position + 4 + length
	end
	if not chunk_length then
		return nil, "invalid"
	end

	-- The optional file name / comment / header CRC sit between the extra
	-- field and the compressed data.
	local data_start = 12 + extra_length
	file:seek("set", data_start)
	if flags % 16 >= 8 or flags % 32 >= 16 then
		local strings_to_skip = (flags % 16 >= 8 and 1 or 0) + (flags % 32 >= 16 and 1 or 0)
		local skipped = 0
		while skipped < strings_to_skip do
			local byte = file:read(1)
			if not byte then
				return nil, "truncated"
			end
			data_start = data_start + 1
			if byte == "\0" then
				skipped = skipped + 1
			end
		end
	end
	if flags % 4 >= 2 then
		data_start = data_start + 2
	end

	local chunk_starts, running = {}, data_start
	for index, compressed_size in ipairs(chunk_sizes) do
		chunk_starts[index] = running
		running = running + compressed_size
	end
	-- The chunks and the 8-byte gzip trailer must all be there.
	if running + 8 > file_size then
		return nil, "truncated"
	end

	-- The trailer's ISIZE is the uncompressed size modulo 2^32. Every chunk
	-- but the last is full, which says which multiple of 2^32 to add (for a
	-- file over 4 GB), and whether it is plausible at all.
	file:seek("set", file_size - 4)
	local trailer = file:read(4)
	if not trailer or #trailer < 4 then
		return nil, "truncated"
	end
	local uncompressed_size = readUInt16LE(trailer, 1) + readUInt16LE(trailer, 3) * 65536
	local lowest = (#chunk_sizes - 1) * chunk_length + 1
	while uncompressed_size < lowest do
		uncompressed_size = uncompressed_size + 4294967296
	end
	if uncompressed_size > #chunk_sizes * chunk_length then
		return nil, "invalid"
	end

	self._dictzip = {
		chunk_length = chunk_length,
		chunk_sizes = chunk_sizes,
		chunk_starts = chunk_starts,
		uncompressed_size = uncompressed_size,
	}
	return self._dictzip
end

-- The inflated chunk number `chunk` (0-based). Neighbouring entries usually
-- live in the same chunk, so the last few are kept instead of being inflated
-- again for every entry.
function StarDict:_getChunk(file, header, chunk)
	self._chunks = self._chunks or {}
	local inflated = self._chunks[chunk]
	if inflated then
		return inflated
	end
	local compressed_size = header.chunk_sizes[chunk + 1]
	if not compressed_size then
		return nil, "chunk out of range"
	end
	file:seek("set", header.chunk_starts[chunk + 1])
	local err
	inflated, err = Inflate.raw(file:read(compressed_size), header.chunk_length)
	if not inflated then
		return nil, err
	end
	self._chunks[chunk] = inflated
	self._chunk_order = self._chunk_order or {}
	table.insert(self._chunk_order, chunk)
	if #self._chunk_order > CHUNKS_KEPT_IN_MEMORY then
		self._chunks[table.remove(self._chunk_order, 1)] = nil
	end
	return inflated
end

function StarDict:_readDictzip(file, offset, size)
	local header = self:_loadDictzipHeader(file)
	if not header then
		return nil, "invalid dictzip header"
	end
	local first_chunk = math.floor(offset / header.chunk_length)
	local last_chunk = math.floor((offset + size - 1) / header.chunk_length)
	local skip = offset - first_chunk * header.chunk_length
	if first_chunk == last_chunk then
		local inflated, err = self:_getChunk(file, header, first_chunk)
		return inflated and inflated:sub(skip + 1, skip + size), err
	end
	local parts = {}
	for chunk = first_chunk, last_chunk do
		local inflated, err = self:_getChunk(file, header, chunk)
		if not inflated then
			return nil, err
		end
		parts[#parts + 1] = inflated
	end
	return table.concat(parts):sub(skip + 1, skip + size)
end

--- Starts a reading session: the definitions file stays open across
-- readDefinition() calls, instead of being opened for each one, until the
-- matching endReading(). Sessions nest.
function StarDict:beginReading()
	self._readers = (self._readers or 0) + 1
end

function StarDict:endReading()
	self._readers = math.max((self._readers or 0) - 1, 0)
	if self._readers == 0 and self._dict_file then
		self._dict_file:close()
		self._dict_file = nil
	end
end

--- Lets go of what is kept for speed: the open file and the inflated chunks.
function StarDict:releaseCaches()
	self._readers = 0
	if self._dict_file then
		self._dict_file:close()
		self._dict_file = nil
	end
	self._chunks, self._chunk_order = nil, nil
end

--- Returns the raw definition text of an entry.
-- @treturn string definition, or nil and an error message
function StarDict:readDefinition(entry)
	local file, opened_here = self._dict_file, false
	if not file then
		file = io.open(self.dict_path, "rb")
		if not file then
			return nil, "unreadable"
		end
		if (self._readers or 0) > 0 then
			self._dict_file = file
		else
			opened_here = true
		end
	end
	local definition, err
	if self.compressed then
		definition, err = self:_readDictzip(file, entry.offset, entry.size)
	else
		file:seek("set", entry.offset)
		definition = file:read(entry.size)
	end
	if opened_here then
		file:close()
	end
	if definition and #definition < entry.size then
		definition, err = nil, "truncated"
	end
	if not definition then
		logger.warn("DictionaryExplorer: could not read entry", entry.word, err)
	end
	return definition, err
end

return StarDict
