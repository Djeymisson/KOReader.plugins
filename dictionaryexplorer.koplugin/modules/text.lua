--[[
Turns the definitions of the text dictionaries into the HTML the viewer shows.

  plainToHtml     sametypesequence "m": plain text, sometimes with a few tags
  xdxfLiteToHtml  sametypesequence "x": what the dictionaries declared as XDXF
                  in practice are (the Dicionário Aberto and the
                  Portuguese-English dictionary): the same kind of text with a
                  tag or two. Real, structured XDXF (<def>, <gr>, <ex>, <abr>)
                  is not converted, and its tags would just be dropped.

Only a few inline tags are kept. KOReader's own popup strips all of them; the
Priberam dictionaries use them for the headword, word class and numbering, which
reads much better with them.

This module is plain Lua and needs no KOReader, so it can be tested on its own.
]]

local KEPT_TAGS = { b = true, i = true, u = true, em = true, strong = true, small = true, big = true, sup = true, sub = true }

local Text = {}

--- "m": tags outside the kept set are dropped, line breaks become <br/>.
function Text.plainToHtml(definition)
	local html = definition:gsub("<[bB][rR] ?/?>", "\n")
	html = html:gsub("<(/?)(%a+)[^>]*>", function(slash, tag)
		tag = tag:lower()
		if KEPT_TAGS[tag] then
			return "<" .. slash .. tag .. ">"
		end
		return ""
	end)
	html = html:gsub("^%s+", ""):gsub("\n", "<br/>")
	return html
end

local function stripTags(text)
	return (text:gsub("<[^>]*>", ""))
end

--- "x": as plain text, tidied up for what these dictionaries look like.
--   - <k>...</k>, the entry's key, becomes the bold headword
--   - the indentation and the blank lines between the lines are dropped
--   - a first line that only repeats the key, when the next line is the key in
--     bold, is dropped
--   - a bold line followed by an italic one (the headword and its word class,
--     which the Dicionário Aberto puts on two lines) becomes one line
-- @string definition the raw definition
-- @string word the key of the entry
function Text.xdxfLiteToHtml(definition, word)
	local lines = {}
	for line in (definition:gsub("<[bB][rR] ?/?>", "\n") .. "\n"):gmatch("(.-)\r?\n") do
		line = line:gsub("<(/?)[kK]>", "<%1b>"):gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then
			lines[#lines + 1] = line
		end
	end

	if #lines >= 2 and stripTags(lines[1]) == word and lines[2]:find("^<b>[^<]*</b>") and stripTags(lines[2]:match("^<b>[^<]*</b>")) == word then
		table.remove(lines, 1)
	end

	local merged = {}
	local index = 1
	while index <= #lines do
		local line = lines[index]
		local following = lines[index + 1]
		if following and line:find("^<b>[^<]*</b>$") and following:find("^<i>[^<]*</i>$") then
			line = line .. " " .. following
			index = index + 1
		end
		merged[#merged + 1] = line
		index = index + 1
	end

	return Text.plainToHtml(table.concat(merged, "\n"))
end

return Text
