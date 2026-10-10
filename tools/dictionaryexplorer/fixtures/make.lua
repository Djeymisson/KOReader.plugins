--[[
Makes the synthetic StarDict dictionaries the suites run on, so that they can
run anywhere, with or without the author's dictionaries.

  luajit make.lua DICT_DIR INTEGRITY_DIR

DICT_DIR gets dictionaries the plugin can open, one of each shape it supports:

  Fixture Text    "m", plain .dict, StarDict order, with a .syn; every word the
                  Portuguese profile of the suites walks through, homographs,
                  words that differ only in case (also accented capitals), and
                  some entries longer than a screen
  Fixture HTML    "h", dictzip .dict.dz, with links between entries
  Fixture XDXF    "x", plain .dict, the XDXF-lite of the Dicionário Aberto
  Fixture Bytes   "m", plain .dict, sorted in plain byte order (capitalized
                  words before all the lowercase ones), like Priberam's

INTEGRITY_DIR gets what only the integrity suite opens:

  twin_a/twin.*, twin_b/twin.*   two dictionaries with the same file name, the
                                 same .idx size and different words
  truncated_idx/                 .idx cut short (its .ifo says how big it was)
  truncated_idx_noinfo/          the same, with no idxfilesize in the .ifo
  wrong_count/                   .ifo wordcount that does not match the .idx
  truncated_dict/                .dict cut short
  truncated_dz/                  .dict.dz cut short
  short_dz/                      .dict.dz whole, but the .idx points past its
                                 end, into the unused room of the last chunk
  malformed_ra/                  .dict.dz whose RA field is too short to hold
                                 a chunk table
  cut_after_index/               valid; the suite indexes it, then cuts its
  cut_after_index_dz/            .dict / .dict.dz, as a later bad copy would

Everything is deterministic: the same files every run. Plain Lua 5.1 (it runs
on the luajit KOReader ships), no library needed: the dictzip chunks are
"stored" deflate blocks, which any inflater reads. The gzip CRC is left at zero:
the plugin never checks it.
]]

local dict_dir, integrity_dir = arg[1], arg[2]
if not (dict_dir and integrity_dir) then
	io.stderr:write("usage: make.lua DICT_DIR INTEGRITY_DIR\n")
	os.exit(2)
end

local DICTZIP_CHUNK_LENGTH = 2048 -- small, so entries span chunks

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function mkdir(path)
	assert(os.execute(string.format("mkdir -p '%s'", path)))
end

local function writeFile(path, content)
	local file = assert(io.open(path, "wb"))
	file:write(content)
	file:close()
end

local function uint32BE(value)
	return string.char(math.floor(value / 16777216) % 256, math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256)
end

local function uint16LE(value)
	return string.char(value % 256, math.floor(value / 256) % 256)
end

local function readUInt32BE(text, position)
	local b1, b2, b3, b4 = text:byte(position, position + 3)
	return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

local function uint32LE(value)
	return uint16LE(value % 65536) .. uint16LE(math.floor(value / 65536) % 65536)
end

-- A small deterministic generator (Park-Miller), so runs are reproducible. Its
-- products stay below 2^53, so it is exact with luajit's doubles too.
local function random(seed)
	local state = seed
	return function(low, high)
		state = (state * 16807) % 2147483647
		return low + state % (high - low + 1)
	end
end

-- The two orders StarDict dictionaries come in (see modules/stardict.lua).
local function foldAscii(text)
	return (text:gsub("[A-Z]", function(letter)
		return letter:lower()
	end))
end

local function stardictLess(a, b)
	local folded_a, folded_b = foldAscii(a), foldAscii(b)
	if folded_a ~= folded_b then
		return folded_a < folded_b
	end
	return a < b
end

local function byteLess(a, b)
	return a < b
end

-- ---------------------------------------------------------------------------
-- Words and definitions
-- ---------------------------------------------------------------------------

local SYLLABLES = { "ba", "be", "ca", "co", "da", "di", "fa", "fo", "ga", "gu", "la", "li", "ma", "mo", "na", "ni", "pa", "pe", "ra", "ri", "sa", "so", "ta", "te", "va", "vi", "za" }

-- Made-up headwords, none of them a real word the suites look for.
local function fillerWords(seed, count, capitalized_every)
	local next_random = random(seed)
	local words, seen = {}, {}
	while #words < count do
		local parts = {}
		for index = 1, next_random(2, 4) do
			parts[index] = SYLLABLES[next_random(1, #SYLLABLES)]
		end
		local word = "q" .. table.concat(parts) -- "q..." so no filler is a real word
		if capitalized_every and #words % capitalized_every == 0 then
			word = word:sub(1, 1):upper() .. word:sub(2)
		end
		if not seen[word] then
			seen[word] = true
			words[#words + 1] = word
		end
	end
	return words
end

-- Plain words of three letters or more: the selection tests look for them.
local VOCABULARY = {
	"the", "house", "small", "room", "with", "door", "and", "window", "used", "for", "living", "place", "where",
	"people", "work", "read", "books", "write", "letters", "common", "word", "meaning", "example", "old", "new",
	"large", "river", "near", "city", "garden", "table", "chair", "light", "street", "market", "morning", "evening",
}

local function sentences(next_random, count)
	local parts = {}
	for index = 1, count do
		local words = {}
		for word_index = 1, next_random(6, 14) do
			words[word_index] = VOCABULARY[next_random(1, #VOCABULARY)]
		end
		local sentence = table.concat(words, " ")
		parts[index] = sentence:sub(1, 1):upper() .. sentence:sub(2) .. "."
	end
	return table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------
-- Writing a dictionary
-- ---------------------------------------------------------------------------

local function dictzip(data)
	local chunks, sizes = {}, {}
	local count = math.ceil(#data / DICTZIP_CHUNK_LENGTH)
	for index = 1, count do
		local piece = data:sub((index - 1) * DICTZIP_CHUNK_LENGTH + 1, index * DICTZIP_CHUNK_LENGTH)
		-- One stored block: BFINAL on the last chunk, BTYPE 00, LEN, NLEN.
		local block = string.char(index == count and 1 or 0) .. uint16LE(#piece) .. uint16LE(65535 - #piece) .. piece
		chunks[index], sizes[index] = block, #block
	end
	local ra = { uint16LE(1), uint16LE(DICTZIP_CHUNK_LENGTH), uint16LE(count) }
	for index = 1, count do
		ra[#ra + 1] = uint16LE(sizes[index])
	end
	local ra_data = table.concat(ra)
	local extra = "RA" .. uint16LE(#ra_data) .. ra_data
	local header = "\31\139\8\4" .. uint32LE(0) .. "\0\3" .. uint16LE(#extra) .. extra
	return header .. table.concat(chunks) .. uint32LE(0) .. uint32LE(#data % 4294967296)
end

--- Writes a dictionary and returns its files' contents, to make broken copies.
-- spec: { bookname, type, entries = { {word, definition}... }, less = fn,
--         compressed = bool, synonyms = { {word, target_word}... },
--         ifo_overrides = { key = value or false } }
local function writeDictionary(directory, base, spec)
	mkdir(directory)
	table.sort(spec.entries, function(a, b)
		if a[1] == b[1] then
			return a.order < b.order -- homographs keep the order they were given in
		end
		return spec.less(a[1], b[1])
	end)

	local idx, dict, offset = {}, {}, 0
	local index_of = {}
	for index, entry in ipairs(spec.entries) do
		idx[#idx + 1] = entry[1] .. "\0" .. uint32BE(offset) .. uint32BE(#entry[2])
		dict[#dict + 1] = entry[2]
		offset = offset + #entry[2]
		index_of[entry[1]] = index_of[entry[1]] or index - 1
	end
	local files = { idx = table.concat(idx), dict = table.concat(dict) }

	local ifo = {
		{ "version", "2.4.2" },
		{ "wordcount", tostring(#spec.entries) },
		{ "idxfilesize", tostring(#files.idx) },
		{ "bookname", spec.bookname },
		{ "sametypesequence", spec.type },
	}
	if spec.synonyms then
		table.sort(spec.synonyms, function(a, b)
			return spec.less(a[1], b[1])
		end)
		local syn = {}
		for _index, synonym in ipairs(spec.synonyms) do
			syn[#syn + 1] = synonym[1] .. "\0" .. uint32BE(assert(index_of[synonym[2]], synonym[2]))
		end
		files.syn = table.concat(syn)
		table.insert(ifo, 3, { "synwordcount", tostring(#spec.synonyms) })
	end
	local lines = { "StarDict's dict ifo file" }
	for _index, pair in ipairs(ifo) do
		local value = pair[2]
		if spec.ifo_overrides and spec.ifo_overrides[pair[1]] ~= nil then
			value = spec.ifo_overrides[pair[1]]
		end
		if value then
			lines[#lines + 1] = pair[1] .. "=" .. value
		end
	end
	files.ifo = table.concat(lines, "\n") .. "\n"

	local path = directory .. "/" .. base
	writeFile(path .. ".ifo", files.ifo)
	writeFile(path .. ".idx", files.idx)
	if spec.compressed then
		files.dz = dictzip(files.dict)
		writeFile(path .. ".dict.dz", files.dz)
	else
		writeFile(path .. ".dict", files.dict)
	end
	if files.syn then
		writeFile(path .. ".syn", files.syn)
	end
	files.path = path
	return files
end

local function numbered(entries)
	for index, entry in ipairs(entries) do
		entry.order = index
	end
	return entries
end

-- ---------------------------------------------------------------------------
-- The dictionaries the plugin can open
-- ---------------------------------------------------------------------------

-- What the suites' Portuguese profile opens on and walks through, plus words
-- for the lookups (case, accents, homographs).
local TEXT_WORDS = {
	"casa", "Casa", "casaco", "casado", "livro", "amor", "correr", "constitucionalmente", "responsabilidade",
	"gato", "mesa", "extraordinariamente", "zebra", "árvore", "Árvore", "ação", "ética", "Ética", "pêssego",
}

local function textDictionary()
	local next_random = random(101)
	local entries = {}
	for _index, word in ipairs(TEXT_WORDS) do
		entries[#entries + 1] = { word, word .. "\n1. " .. sentences(next_random, next_random(1, 3)) .. "\n2. " .. sentences(next_random, 1) }
	end
	-- Homographs: the same key twice, told apart by their text.
	entries[#entries + 1] = { "banco", "banco\n1. (seat) " .. sentences(next_random, 2) }
	entries[#entries + 1] = { "banco", "banco\n1. (money) " .. sentences(next_random, 2) }
	for index, word in ipairs(fillerWords(7, 1200)) do
		-- Every 97th entry is longer than a screen, so it gets a scrolling page.
		local count = index % 97 == 0 and 80 or next_random(1, 4)
		entries[#entries + 1] = { word, word .. "\n1. " .. sentences(next_random, count) }
	end
	return writeDictionary(dict_dir .. "/text", "fixture_text", {
		bookname = "Fixture Text (m)",
		type = "m",
		less = stardictLess,
		entries = numbered(entries),
		synonyms = { { "casas", "casa" }, { "livros", "livro" }, { "gatos", "gato" }, { "arvore", "árvore" } },
	})
end

local function htmlDictionary()
	local next_random = random(202)
	local words = { "apple", "house", "cat", "dog", "bookshop", "Apple" }
	for _index, word in ipairs(fillerWords(11, 1200)) do
		words[#words + 1] = word
	end
	local entries = {}
	for index, word in ipairs(words) do
		local link = words[next_random(1, #words)]
		local count = index % 89 == 0 and 70 or next_random(1, 4)
		entries[#entries + 1] = {
			word,
			string.format('<p><b>%s</b> <i>n.</i> %s See <a href="bword://%s">%s</a>.</p>', word, sentences(next_random, count), link, link),
		}
	end
	return writeDictionary(dict_dir .. "/html", "fixture_html", {
		bookname = "Fixture HTML (h, dictzip)",
		type = "h",
		less = stardictLess,
		compressed = true,
		entries = numbered(entries),
	})
end

local function xdxfDictionary()
	local next_random = random(303)
	local words = { "casa", "sol", "mesa", "luz", "mar" }
	for _index, word in ipairs(fillerWords(13, 900)) do
		words[#words + 1] = word
	end
	local entries = {}
	for _index, word in ipairs(words) do
		entries[#entries + 1] = {
			word,
			string.format("<k>%s</k>\n\t<b>%s</b>\n\t<i>s. m.</i>\n\t%s\n\n\t%s", word, word, sentences(next_random, next_random(1, 3)), sentences(next_random, 1)),
		}
	end
	return writeDictionary(dict_dir .. "/xdxf", "fixture_xdxf", {
		bookname = "Fixture XDXF (x)",
		type = "x",
		less = stardictLess,
		entries = numbered(entries),
	})
end

local function bytesDictionary()
	local next_random = random(404)
	local words = { "Abacaxi", "Zulu", "abacate", "zebra", "Casa", "casa" }
	for _index, word in ipairs(fillerWords(17, 900, 5)) do
		words[#words + 1] = word
	end
	local entries = {}
	for _index, word in ipairs(words) do
		entries[#entries + 1] = { word, word .. "\n" .. sentences(next_random, next_random(1, 4)) }
	end
	return writeDictionary(dict_dir .. "/bytes", "fixture_bytes", {
		bookname = "Fixture Bytes (m, byte order)",
		type = "m",
		less = byteLess,
		entries = numbered(entries),
	})
end

-- ---------------------------------------------------------------------------
-- What only the integrity suite opens
-- ---------------------------------------------------------------------------

-- Two dictionaries with the same file name and the same .idx size: words and
-- definitions of the same lengths, different text.
local function twin(letter, prefix)
	local entries = {}
	for index = 1, 300 do
		entries[#entries + 1] = { string.format("%s%03d", prefix, index), string.format("Twin %s entry %03d.", letter, index) }
	end
	writeDictionary(integrity_dir .. "/twin_" .. letter:lower(), "twin", {
		bookname = "Fixture Twin " .. letter,
		type = "m",
		less = stardictLess,
		entries = numbered(entries),
	})
end

local function smallEntries(seed)
	local next_random = random(seed)
	local entries = {}
	for _index, word in ipairs(fillerWords(seed, 300)) do
		entries[#entries + 1] = { word, word .. "\n" .. sentences(next_random, next_random(1, 3)) }
	end
	return numbered(entries)
end

local function broken(name, spec, cut)
	spec.type, spec.less = "m", stardictLess
	spec.bookname = "Fixture Broken " .. name
	spec.entries = smallEntries(#name * 31)
	local files = writeDictionary(integrity_dir .. "/" .. name, name, spec)
	if cut then
		cut(files)
	end
end

local function cutHalf(content)
	return content:sub(1, math.floor(#content / 2))
end

textDictionary()
htmlDictionary()
xdxfDictionary()
bytesDictionary()

twin("A", "alfa")
twin("B", "beta")
broken("truncated_idx", {}, function(files)
	writeFile(files.path .. ".idx", files.idx:sub(1, #files.idx - 5))
end)
broken("truncated_idx_noinfo", { ifo_overrides = { idxfilesize = false } }, function(files)
	writeFile(files.path .. ".idx", files.idx:sub(1, #files.idx - 5))
end)
broken("wrong_count", { ifo_overrides = { wordcount = "305" } })
broken("truncated_dict", {}, function(files)
	writeFile(files.path .. ".dict", cutHalf(files.dict))
end)
broken("truncated_dz", { compressed = true }, function(files)
	writeFile(files.path .. ".dict.dz", cutHalf(files.dz))
end)
broken("short_dz", { compressed = true }, function(files)
	-- The last record of the .idx is the entry stored last: make it run into
	-- the room the last chunk has left, so only the real size tells.
	local room = math.ceil(#files.dict / DICTZIP_CHUNK_LENGTH) * DICTZIP_CHUNK_LENGTH - #files.dict
	assert(room > 0, "short_dz: the last chunk is full, change its entries")
	local last_size = readUInt32BE(files.idx, #files.idx - 3)
	writeFile(files.path .. ".idx", files.idx:sub(1, #files.idx - 4) .. uint32BE(last_size + room))
end)
broken("malformed_ra", { compressed = true }, function(files)
	local header_length = 12 + files.dz:byte(11) + files.dz:byte(12) * 256
	local extra = "RA" .. uint16LE(2) .. uint16LE(1) -- a version, and nothing else
	writeFile(files.path .. ".dict.dz", "\31\139\8\4" .. uint32LE(0) .. "\0\3" .. uint16LE(#extra) .. extra .. files.dz:sub(header_length + 1))
end)
broken("cut_after_index", {})
broken("cut_after_index_dz", { compressed = true })
