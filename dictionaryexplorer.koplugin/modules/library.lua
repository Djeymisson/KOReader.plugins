--[[
The dictionaries the viewer can go to, and how to ask them about a word.

The viewer shows one dictionary at a time; this is what it asks when a word
may be in the others. There are two ways of asking, by what they cost:

  quick   for what the viewer shows unasked (the dock's button, the header's
          mark): the word as it is (in any case, or through the .syn), and
          only the dictionaries already loaded, so nothing is read from disk
          but their pages
  full    for what the user asked for (a list, a search): accents too, and
          the dictionaries whose index cache is on disk are loaded for it

  Library.new(provider)        provider: { list = function() -> dictionaries
                               (enabled, in KOReader's order), find =
                               function(name), prepare = function(dictionary,
                               callback) }, or nil for none but the viewer's
  library:others(current)      the dictionaries other than `current`
  library:quick(word, current) { [dictionary] = its entry, or false }, and
                               whether one not loaded yet might have it
  library:closest(dictionary, word)
                               the entries of `dictionary` closest to a word it
                               has none for (its accented spellings, then the
                               ones spelled most like it)
  library:find(name), library:prepare(dictionary, callback)
  Library.anyFound(known)      whether a quick() answer found it anywhere

As if they were one big dictionary, a word is looked for in all of them:

  library:resolve(word, current, hint)
                               where `word` leads, by priority: an exact entry
                               in `current` (any case, the .syn), then an exact
                               entry in another dictionary (KOReader's order),
                               then an accented spelling in `current`, then one
                               in another; else the closest entry in `current`.
                               StarDict:resolve()'s answer, with `dictionary`
                               (where it leads) and `from` (`current`, when
                               that is another one)
  library:holders(word, current)
                               the dictionaries with an exact entry for it, in
                               KOReader's order, `current` among them if it is
  library:shortName(dictionary)
                               a short name, for the breadcrumb and the lists:
                               "EN-PT", "PT", "EN" (see shortNames())
]]

local Spelling = require("modules/spelling")

local CLOSEST_ELSEWHERE = 3 -- entries of each other dictionary among the suggestions for a missed word
local CLOSEST_SHARED = 2 -- letters they must begin with as the word does

local Library = {
	CLOSEST_ELSEWHERE = CLOSEST_ELSEWHERE,
}
Library.__index = Library

function Library.new(provider)
	return setmetatable({ provider = provider }, Library)
end

--- Whether there are other dictionaries at all (a provider was given).
function Library:hasProvider()
	return self.provider ~= nil
end

--- The dictionaries other than `current`, in KOReader's order.
function Library:others(current)
	local others = {}
	if self.provider then
		for _index, dictionary in ipairs(self.provider.list()) do
			if dictionary ~= current then
				others[#others + 1] = dictionary
			end
		end
	end
	return others
end

--- Asks the dictionaries other than `current` already loaded about `word` as
-- it is (see the top of this file).
-- @treturn table { [dictionary] = its entry for the word, or false }
-- @treturn bool whether a dictionary not loaded yet might have it
function Library:quick(word, current)
	local known, unknown = {}, false
	for _index, dictionary in ipairs(self:others(current)) do
		if dictionary.idx then
			local position, exact = dictionary:locateText(word)
			known[dictionary] = exact and dictionary:getEntry(position).word or false
		else
			unknown = true
		end
	end
	return known, unknown
end

--- Whether a quick() answer found the word in some dictionary.
function Library.anyFound(known)
	for _dictionary, entry in pairs(known) do
		if entry then
			return true
		end
	end
	return false
end

--- The entries of `dictionary` closest to a word it has no entry for: its
-- accented spellings first, then the ones spelled most like it (see
-- StarDict:nearest()), if they begin as it does: entries that only happen to
-- sort near it would be noise. At most CLOSEST_ELSEWHERE.
function Library:closest(dictionary, word)
	local lookup = dictionary:resolve(word)
	local count = dictionary:getCount()
	local positions, seen = {}, {}
	local function add(position)
		if position >= 0 and position < count and not seen[position] and #positions < CLOSEST_ELSEWHERE then
			seen[position] = true
			positions[#positions + 1] = position
		end
	end
	for _index, position in ipairs(lookup.spellings or {}) do
		add(position)
	end
	for _index, position in ipairs(dictionary:nearest(word, CLOSEST_ELSEWHERE, CLOSEST_SHARED)) do
		add(position)
	end
	return positions
end

--- Where `word` leads among all the dictionaries (see the top of this file).
-- Only dictionaries whose index is ready are asked (their cache is loaded on
-- the first word that needs them), so nothing is prepared for it.
-- @treturn table StarDict:resolve()'s answer, with `dictionary` and `from`
function Library:resolve(word, current, hint)
	local here = current:resolve(word, hint)
	here.dictionary = current
	if here.kind == "exact" then
		return here
	end
	local exact, accent
	for _index, dictionary in ipairs(self:others(current)) do
		if dictionary:isIndexed() then
			local lookup = dictionary:resolve(word)
			if lookup.kind == "exact" then
				exact = { lookup = lookup, dictionary = dictionary }
				break
			elseif lookup.kind == "accent" and not accent then
				accent = { lookup = lookup, dictionary = dictionary }
			end
		end
	end
	local elsewhere = exact or (here.kind ~= "accent" and accent)
	if elsewhere then
		local lookup = elsewhere.lookup
		lookup.dictionary, lookup.from = elsewhere.dictionary, current
		return lookup
	end
	return here
end

--- The dictionaries with an exact entry for `word` (any case, the .syn), in
-- KOReader's order, `current` among them where it is in that order. Only the
-- ones whose index is ready.
-- @treturn table { { dictionary =, position =, entry = } ... }
function Library:holders(word, current)
	local dictionaries = self.provider and self.provider.list() or { current }
	local found, has_current = {}, false
	for _index, dictionary in ipairs(dictionaries) do
		if dictionary == current or dictionary:isIndexed() then
			local position, exact = dictionary:locateText(word)
			if exact then
				found[#found + 1] = { dictionary = dictionary, position = position, entry = dictionary:getEntry(position).word }
				has_current = has_current or dictionary == current
			end
		end
	end
	if not has_current then
		-- The viewer's own dictionary may be disabled in KOReader's settings.
		local position, exact = current:locateText(word)
		if exact then
			table.insert(found, 1, { dictionary = current, position = position, entry = current:getEntry(position).word })
		end
	end
	return found
end

-- The languages a dictionary's name may mention, by their ISO 639-1 code.
local LANGUAGES = {
	EN = { "english", "inglês", "ingles", "anglais", "englisch", "inglés" },
	PT = { "portuguese", "português", "portugues", "portuguesa", "portugais", "portugiesisch", "portugués" },
	ES = { "spanish", "español", "espanol", "espanhol", "espagnol", "spanisch" },
	FR = { "french", "français", "francais", "francês", "frances", "französisch", "francés" },
	DE = { "german", "deutsch", "alemão", "alemao", "allemand", "alemán" },
	IT = { "italian", "italiano", "italien", "italienisch" },
	RU = { "russian", "русский", "russo", "russe", "russisch", "ruso" },
	LA = { "latin", "latim", "latín", "latein" },
	NL = { "dutch", "nederlands", "holandês", "néerlandais", "niederländisch" },
	JA = { "japanese", "japonês", "japonais", "japanisch", "japonés" },
	ZH = { "chinese", "chinês", "chinois", "chinesisch", "chino" },
}
local LANGUAGE_OF = {}
for code, names in pairs(LANGUAGES) do
	for _index, name in ipairs(names) do
		LANGUAGE_OF[name] = code
	end
end
-- Words a dictionary's name has that say nothing about which one it is.
local FILLERS = {}
for _index, word in ipairs({
	"dictionary", "dicionário", "dicionario", "diccionario", "dictionnaire", "wörterbuch", "словарь",
	"da", "de", "do", "of", "the", "la", "le", "der", "língua", "lingua", "language", "ed", "edition", "edição", "and", "e", "y",
}) do
	FILLERS[word] = true
end

-- What a name is made of: its words (in their case), and the languages it
-- mentions, as codes, in order.
local function nameParts(name)
	local words, codes = {}, {}
	for token in name:gmatch("[%w\128-\255]+") do
		local lower = Spelling.changeCase(token, true)
		local code = LANGUAGE_OF[lower]
		if code then
			codes[#codes + 1] = code
		elseif not FILLERS[lower] and not lower:match("^%d") and #Spelling.characters(token) > 1 then
			words[#words + 1] = token
		end
	end
	return words, codes
end

-- The short names a dictionary may get, shortest first. They depend on its
-- name only, so they are made once per name: the breadcrumb and the header
-- ask for them on every page.
local candidates_by_name = {}
local function candidates(dictionary)
	local name = dictionary.name
	local found = candidates_by_name[name]
	if not found then
		local words, codes = nameParts(name)
		local languages = table.concat(codes, "-")
		local first, second = words[1] or name, words[2]
		found = {
			languages ~= "" and languages or first,
			languages ~= "" and (first .. " " .. languages) or (second and (first .. " " .. second) or first),
			name,
		}
		candidates_by_name[name] = found
	end
	return found
end

--- Short names for the dictionaries, made from their names: the languages
-- they mention ("Priberam English - Portuguese Dictionary" is "EN-PT"), or,
-- when that doesn't tell them apart (or there is none), a word of the name
-- too ("Oxford EN"), or two words; else the whole name. One set in the
-- plugin's settings (dictionaryexplorer_short_names, by name) wins.
-- @treturn table { [dictionary] = short name }
function Library:shortNames()
	local dictionaries = self.provider and self.provider.list() or {}
	local names = {}
	for level = 1, 3 do
		local counts, taken = {}, {}
		for _dictionary, name in pairs(names) do
			taken[name] = true
		end
		for _index, dictionary in ipairs(dictionaries) do
			if not names[dictionary] then
				local name = candidates(dictionary)[level]
				counts[name] = (counts[name] or 0) + 1
			end
		end
		for _index, dictionary in ipairs(dictionaries) do
			if not names[dictionary] then
				local name = candidates(dictionary)[level]
				if level == 3 or (counts[name] == 1 and not taken[name]) then
					names[dictionary] = name
				end
			end
		end
	end
	local overrides = G_reader_settings:readSetting("dictionaryexplorer_short_names") or {}
	for _index, dictionary in ipairs(dictionaries) do
		local override = overrides[dictionary.name]
		if type(override) == "string" and override ~= "" then
			names[dictionary] = override
		end
	end
	return names
end

--- The short name of one dictionary (see shortNames()).
function Library:shortName(dictionary)
	return self:shortNames()[dictionary] or candidates(dictionary)[1]
end

--- The dictionary called `name`, if it can be opened.
function Library:find(name)
	return self.provider and self.provider.find(name)
end

--- Runs `callback` once `dictionary` can be read: at once when its index is
-- ready, after preparing it (with a notice) otherwise; never without a provider.
function Library:prepare(dictionary, callback)
	if dictionary:isIndexed() then
		callback()
	elseif self.provider then
		self.provider.prepare(dictionary, callback)
	end
end

return Library
