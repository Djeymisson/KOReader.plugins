--[[
The contract a dictionary object has to honour for the viewer (and its
performance machinery) to work with it, checked on every dictionary the plugin
can open. This is what a new dictionary format would have to pass.

  entries      getCount(), getEntry(n): a word and a size (in bytes, known
               without reading the definition: the fit model predicts from it)
  reading      readDefinition(entry) returns exactly `size` bytes
  lookup       locate() finds every headword it is given, exactly; locateText()
               falls back to the first word of a phrase
  sessions     beginReading()/endReading() nest and leave no file open;
               releaseCaches() is safe to call at any time
  metadata     name, is_html, text_type ("m", "h" or "x": how the text is prepared)
]]

return function(H, ui)
	local dictionaries = H.dictionaries().list
	if #dictionaries == 0 then
		H.skip("the dictionary contract", "no dictionary the plugin can open was found")
		H.finish()
		return
	end

	-- A fixed, well spread set of positions: the ends and a deterministic scatter.
	local function positions(count)
		local chosen, seen = { 0, count - 1 }, {}
		local state = 12345
		for _index = 1, 40 do
			state = (state * 1103515245 + 12345) % 2147483648
			chosen[#chosen + 1] = state % count
		end
		local unique = {}
		for _index, position in ipairs(chosen) do
			if not seen[position] then
				seen[position] = true
				unique[#unique + 1] = position
			end
		end
		return unique
	end

	H.step(1, function()
		for _index, dictionary in ipairs(dictionaries) do
			local name = dictionary.name:sub(1, 30)
			local count = dictionary:getCount()

			H.check(name .. ": has a name and says whether it is HTML", type(dictionary.name) == "string" and dictionary.name ~= "" and type(dictionary.is_html) == "boolean")
			H.check(name .. ": says how its text is prepared (text_type m, h or x)", dictionary.text_type == "m" or dictionary.text_type == "h" or dictionary.text_type == "x", dictionary.text_type)
			H.check(name .. ": getCount() is a positive integer", type(count) == "number" and count > 0 and count == math.floor(count), count)
			H.check(name .. ": getEntry() is nil outside the dictionary", dictionary:getEntry(-1) == nil and dictionary:getEntry(count) == nil)

			local entries_ok, sizes_ok, reads_ok, lookups_ok, first_misses = true, true, true, true, nil
			for _position, position in ipairs(positions(count)) do
				local entry = dictionary:getEntry(position)
				if not (entry and type(entry.word) == "string" and entry.word ~= "") then
					entries_ok = false
				elseif type(entry.size) ~= "number" or entry.size < 0 then
					sizes_ok = false
				else
					if entry.size <= 1024 * 1024 then
						local definition = dictionary:readDefinition(entry)
						if type(definition) ~= "string" or #definition ~= entry.size then
							reads_ok = false
						end
					end
					local found, exact = dictionary:locate(entry.word)
					local found_entry = dictionary:getEntry(found)
					if not (exact and found_entry and found_entry.word == entry.word and found <= position) then
						lookups_ok = false
						first_misses = first_misses or string.format("%q at %d found %s", entry.word, position, tostring(found))
					end
				end
			end
			H.check(name .. ": every entry has a word", entries_ok)
			H.check(name .. ": every entry has a size, without reading it", sizes_ok)
			H.check(name .. ": readDefinition() returns exactly `size` bytes", reads_ok)
			H.check(name .. ": locate() finds each headword exactly, at its first position", lookups_ok, first_misses)

			-- A phrase that is not an entry falls back to its first word.
			local sample = dictionary:getEntry(positions(count)[3])
			local position, exact = dictionary:locateText(sample.word .. " zzzz-not-a-word")
			H.check(name .. ": locateText() falls back to the first word of a phrase", exact and dictionary:getEntry(position).word == sample.word)

			-- Reading sessions.
			local entry = dictionary:getEntry(0)
			dictionary:beginReading()
			dictionary:beginReading()
			dictionary:readDefinition(entry)
			dictionary:endReading()
			local held_while_nested = dictionary._dict_file ~= nil -- the outer session is still open
			dictionary:endReading()
			H.check(name .. ": reading sessions nest and leave no file open", dictionary._dict_file == nil, held_while_nested and "kept open between the sessions, closed after the last" or "nothing to hold open")
			dictionary:releaseCaches()
			dictionary:releaseCaches()
			H.check(name .. ": releaseCaches() is safe to repeat, and readDefinition() still works after it", type(dictionary:readDefinition(entry)) == "string")
		end
	end)

	H.finish()
end
