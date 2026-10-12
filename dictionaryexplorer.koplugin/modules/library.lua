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
  library:elsewhere(word, current)
                               { { dictionary =, entry = } ... } (full), or nil
  library:closest(dictionary, word)
                               the entries of `dictionary` closest to a word it
                               has none for (its accented spellings, then the
                               ones spelled most like it)
  library:find(name), library:prepare(dictionary, callback)
  Library.anyFound(known)      whether a quick() answer found it anywhere
]]

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

--- The dictionaries other than `current` that have `word`, also through its
-- accents (full); only the ones whose index is ready, so nothing is prepared.
-- @treturn table { { dictionary =, entry = } ... } in KOReader's order, or nil
function Library:elsewhere(word, current)
	local found = {}
	for _index, dictionary in ipairs(self:others(current)) do
		if dictionary:isIndexed() then
			local lookup = dictionary:resolve(word)
			if lookup.kind ~= "closest" then
				found[#found + 1] = { dictionary = dictionary, entry = dictionary:getEntry(lookup.position).word }
			end
		end
	end
	return #found > 0 and found or nil
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
