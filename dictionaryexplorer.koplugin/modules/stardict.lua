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
local INDEX_CACHE_VERSION = 2
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

local StarDict = {}
StarDict.__index = StarDict

local instances = {}

--- Returns the (shared) dictionary object for an .ifo file.
-- @treturn StarDict dictionary, or nil and a reason ("unreadable"/"unsupported")
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

	local cache_name = base:match("[^/]+$"):gsub("[^%w_%-]", "_")
	local self = setmetatable({
		ifo_path = ifo_path,
		name = info.bookname,
		is_html = info.sametypesequence == "h",
		text_type = info.sametypesequence, -- "m", "h" or "x": how the viewer prepares the text
		idx_path = idx_path,
		dict_path = dict_path,
		compressed = compressed,
		cache_path = DataStorage:getDataDir() .. "/cache/dictionaryexplorer/" .. cache_name .. ".lua",
		offsets = nil, -- file offset of every PAGE_SIZE-th .idx entry
		first_keys = nil, -- the key found at each of those offsets
		count = nil,
		_pages = {},
		_page_order = {},
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
		or type(data.offsets) ~= "table"
		or type(data.first_keys) ~= "table" then
		return false
	end
	self.offsets = data.offsets
	self.first_keys = data.first_keys
	self.count = data.count
	self.idx_size = data.idx_size
	return true
end

--- Whether the page index is ready to use (loading the cached copy if any).
function StarDict:isIndexed()
	if self.offsets then
		return true
	end
	return self:_loadIndexCache()
end

--- Scans the whole .idx and stores the page index. Takes a while on big
-- dictionaries, so callers should show progress first. Only needed once.
function StarDict:buildIndex()
	local file = io.open(self.idx_path, "rb")
	if not file then
		return false, "unreadable"
	end

	local offsets, first_keys, count = {}, {}, 0
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
			if not terminator or terminator + 8 > length then
				break -- the rest is a record split across two chunks
			end
			if count % PAGE_SIZE == 0 then
				offsets[#offsets + 1] = buffer_start + position - 1
				first_keys[#first_keys + 1] = buffer:sub(position, terminator - 1)
			end
			count = count + 1
			position = terminator + 9
		end
		buffer_start = buffer_start + position - 1
		buffer = buffer:sub(position)
	end
	file:close()

	if count == 0 then
		return false, "empty"
	end

	local attributes = lfs.attributes(self.idx_path)
	self.offsets = offsets
	self.first_keys = first_keys
	self.count = count
	self.idx_size = attributes.size
	self._pages, self._page_order = {}, {}

	util.makePath(self.cache_path:match("^(.*)/[^/]+$"))
	util.writeToFile(dump({
		version = INDEX_CACHE_VERSION,
		page_size = PAGE_SIZE,
		idx_size = attributes.size,
		idx_mtime = attributes.modification,
		count = count,
		offsets = offsets,
		first_keys = first_keys,
	}), self.cache_path, true, true)
	return true
end

function StarDict:getCount()
	return self.count
end

-- Returns the entries of one page ({ word, offset, size } records).
function StarDict:_getPage(page)
	local cached = self._pages[page]
	if cached then
		return cached
	end

	local start = self.offsets[page + 1]
	local stop = self.offsets[page + 2] or self.idx_size
	local file = io.open(self.idx_path, "rb")
	if not file then
		return nil
	end
	file:seek("set", start)
	local block = file:read(stop - start)
	file:close()
	if not block then
		return nil
	end

	local entries, position = {}, 1
	while true do
		local terminator = block:find("\0", position, true)
		if not terminator or terminator + 8 > #block then
			break
		end
		local b1, b2, b3, b4, b5, b6, b7, b8 = block:byte(terminator + 1, terminator + 8)
		entries[#entries + 1] = {
			word = block:sub(position, terminator - 1),
			offset = readUInt32BE(b1, b2, b3, b4),
			size = readUInt32BE(b5, b6, b7, b8),
		}
		position = terminator + 9
	end

	self._pages[page] = entries
	table.insert(self._page_order, page)
	if #self._page_order > PAGES_KEPT_IN_MEMORY then
		self._pages[table.remove(self._page_order, 1)] = nil
	end
	return entries
end

--- Returns entry number `position` (0-based), or nil when out of range.
function StarDict:getEntry(position)
	if position < 0 or position >= self.count then
		return nil
	end
	local page = self:_getPage(math.floor(position / PAGE_SIZE))
	return page and page[position % PAGE_SIZE + 1]
end

-- Position of the first entry whose key sorts at or after `word` under the
-- given comparator.
function StarDict:_lowerBound(word, compare)
	-- Last page whose first key sorts before the word.
	local low, high, page = 0, #self.first_keys - 1, 0
	while low <= high do
		local middle = math.floor((low + high) / 2)
		if compare(self.first_keys[middle + 1], word) < 0 then
			page = middle
			low = middle + 1
		else
			high = middle - 1
		end
	end

	local first = page * PAGE_SIZE
	local position = first
	while position < self.count and position - first < MAX_SCAN_ENTRIES do
		local entry = self:getEntry(position)
		if not entry or compare(entry.word, word) >= 0 then
			break
		end
		position = position + 1
	end
	return math.min(position, self.count - 1)
end

-- Position of the first entry keyed exactly `key`, trying every sort order.
function StarDict:_findExact(key)
	for index = 1, #COMPARATORS do
		local position = self:_lowerBound(key, COMPARATORS[index])
		local entry = self:getEntry(position)
		if entry and entry.word == key then
			return position, entry
		end
	end
end

--- Finds where `word` is in the dictionary.
-- `hint` is optional definition text used to pick between entries that share
-- the same key (Priberam, for one, indexes inflected forms under the base word).
-- @treturn int position of the entry, or of the closest one when there is none
-- @treturn bool true when an entry with exactly that key exists
function StarDict:locate(word, hint)
	-- Typed input may differ in case from the key ("Casa" vs "casa").
	local position, entry = self:_findExact(word)
	if not entry then
		local lowered = foldAscii(word)
		if lowered ~= word then
			position, entry = self:_findExact(lowered)
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
				return candidate, true
			end
		end
	end
	return position, true
end

--- Like locate(), for text that may be several words (a selection, or what the
-- user typed): when it isn't an entry as a whole, its first word is tried.
-- @treturn int position of the entry, or of the closest one when there is none
-- @treturn bool true when an entry was found
function StarDict:locateText(text)
	local position, exact = self:locate(text)
	if not exact then
		local first_word = text:match("^(%S+)%s")
		if first_word then
			local first_position, first_exact = self:locate(first_word)
			if first_exact then
				return first_position, true
			end
		end
	end
	return position, exact
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

-- Reads the dictzip header once: where the compressed data starts, the
-- uncompressed chunk length, and where each compressed chunk begins.
function StarDict:_loadDictzipHeader(file)
	if self._dictzip then
		return self._dictzip
	end
	file:seek("set", 0)
	local header = file:read(12)
	if not header or #header < 12 or header:byte(1) ~= 0x1f or header:byte(2) ~= 0x8b then
		return nil
	end
	local flags = header:byte(4)
	if flags % 8 < 4 then -- FEXTRA bit: dictzip keeps its chunk table there
		return nil
	end
	local extra_length = header:byte(11) + header:byte(12) * 256
	local extra = file:read(extra_length)
	if not extra or #extra < extra_length then
		return nil
	end

	local chunk_length, chunk_sizes
	local position = 1
	while position + 3 <= #extra do
		local id = extra:sub(position, position + 1)
		local length = extra:byte(position + 2) + extra:byte(position + 3) * 256
		if id == "RA" then
			local data = extra:sub(position + 4, position + 3 + length)
			chunk_length = data:byte(3) + data:byte(4) * 256
			local chunk_count = data:byte(5) + data:byte(6) * 256
			chunk_sizes = {}
			for index = 1, chunk_count do
				chunk_sizes[index] = data:byte(5 + index * 2) + data:byte(6 + index * 2) * 256
			end
			break
		end
		position = position + 4 + length
	end
	if not chunk_length then
		return nil
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
				return nil
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
	self._dictzip = {
		chunk_length = chunk_length,
		chunk_sizes = chunk_sizes,
		chunk_starts = chunk_starts,
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
	if not definition then
		logger.warn("DictionaryExplorer: could not read entry", entry.word, err)
	end
	return definition, err
end

return StarDict
