--[[
The trail: the words walked through in the viewer, which the breadcrumb shows,
and how it is kept to continue an exploration later.

A trail is a list of crumbs { word =, position =, dictionary = } (position:
the entry's number in that dictionary; word: what the breadcrumb shows, the
word asked for or the entry's own) and the index of the current one. These
functions work on those two; the viewer keeps them.

  Trail.push(trail, index, crumb)     after the current crumb, dropping the
                                      ones after it, like a browser's history;
                                      not when it is the current entry again
  Trail.replace(trail, index, crumb)  in place of the current crumb
  Trail.save(trail, index)            plain values for the settings
  Trail.load(saved, saved_index, counts, current, find)
                                      the crumbs back, each checked when gone to
  Trail.check(crumb)                  that check: if its dictionary changed,
                                      its entry is looked for again by the word
]]

local MAX_SAVED_CRUMBS = 50 -- the latest words of the trail kept to continue an exploration

local Trail = {
	MAX_SAVED_CRUMBS = MAX_SAVED_CRUMBS,
}

--- Adds `crumb` after the current one, dropping the ones after it.
-- @treturn int the index of the current crumb then
-- @treturn bool whether it was added (it isn't when it is the current entry)
function Trail.push(trail, index, crumb)
	local current = trail[index]
	if current.position == crumb.position and current.dictionary == crumb.dictionary then
		return index, false
	end
	for later = #trail, index + 1, -1 do
		trail[later] = nil
	end
	table.insert(trail, crumb)
	return #trail, true
end

--- Puts `crumb` in place of the current one.
function Trail.replace(trail, index, crumb)
	trail[index] = crumb
end

--- The latest MAX_SAVED_CRUMBS crumbs as plain values (a dictionary's name,
-- the headword at the position), with the number of entries of each
-- dictionary: what tells, when continuing, whether a dictionary changed.
-- @treturn table the crumbs
-- @treturn int the index of the current one among them
-- @treturn table { [dictionary name] = number of entries }
function Trail.save(trail, index)
	local start = math.max(1, #trail - MAX_SAVED_CRUMBS + 1)
	local saved, counts = {}, {}
	for position = start, #trail do
		local crumb = trail[position]
		local check = crumb.check -- not gone to since it was loaded: as it was saved
		local name = crumb.dictionary.name
		local entry = check and check.entry
		if not check then
			entry = crumb.dictionary:getEntry(crumb.position)
			entry = entry and entry.word
			counts[name] = crumb.dictionary:getCount()
		elseif not counts[name] then
			counts[name] = check.count
		end
		saved[#saved + 1] = { word = crumb.word, position = crumb.position, dictionary = name, entry = entry }
	end
	return saved, math.max(1, index - start + 1), counts
end

--- The crumbs of a saved trail. Those of other dictionaries are checked when
-- gone to (their dictionaries are not loaded before), and those whose
-- dictionary is gone are left out. Trails saved before they could cross
-- dictionaries have no dictionary in their crumbs: they are `current`'s.
-- @tparam StarDict current the dictionary the exploration is continued in
-- @tparam function find(name) the dictionary called `name`, if any
-- @tparam int current_count the number of entries `current` had when saved
-- @treturn table the crumbs, or nil when none is left
-- @treturn int the index of the current one
function Trail.load(saved, saved_index, counts, current, find, current_count)
	counts = type(counts) == "table" and counts or {}
	saved_index = tonumber(saved_index) or #saved
	local trail, index = {}, nil
	for position, crumb in ipairs(saved) do
		local at = type(crumb) == "table" and tonumber(crumb.position)
		local dictionary
		if at and type(crumb.word) == "string" then
			local name = crumb.dictionary or current.name
			dictionary = name == current.name and current or find(name)
		end
		if dictionary then
			trail[#trail + 1] = {
				word = crumb.word,
				position = at,
				dictionary = dictionary,
				check = { count = counts[dictionary.name] or (dictionary == current and current_count), entry = crumb.entry },
			}
		end
		if position <= saved_index and #trail > 0 then
			index = #trail
		end
	end
	if #trail == 0 then
		return nil
	end
	return trail, index or 1
end

--- Checks a crumb loaded from a saved trail, once its dictionary can be read.
function Trail.check(crumb)
	local check = crumb.check
	if not check then
		return
	end
	crumb.check = nil
	local dictionary = crumb.dictionary
	local entry = dictionary:getEntry(crumb.position)
	if dictionary:getCount() ~= check.count or not entry or (check.entry and entry.word ~= check.entry) then
		crumb.position = dictionary:locate(crumb.word)
	end
end

return Trail
