return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	-- Generic helpers ---------------------------------------------------------

	function trim(text)
		return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	end

	function fileExists(path)
		if not path or path == "" then
			return false
		end

		local file = io.open(path, "rb")
		if not file then
			return false
		end

		file:close()
		return true
	end

	function htmlEscape(text)
		text = tostring(text or "")
		text = text:gsub("&", "&amp;")
		text = text:gsub("<", "&lt;")
		text = text:gsub(">", "&gt;")
		text = text:gsub('"', "&quot;")
		return text
	end

	function looksLikeHtml(text)
		return tostring(text or ""):find("<%s*[%a/][^>]*>") ~= nil
	end

	function plainTextToHtml(text)
		text = htmlEscape(text)
		text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
		text = text:gsub("\n\n+", "</p><p>"):gsub("\n", "<br/>")
		return "<p>" .. text .. "</p>"
	end

	function copyTable(value, seen)
		if type(value) ~= "table" then
			return value
		end

		seen = seen or {}
		if seen[value] then
			return seen[value]
		end

		local copy = {}
		seen[value] = copy
		for key, item in pairs(value) do
			copy[copyTable(key, seen)] = copyTable(item, seen)
		end
		return copy
	end

	-- Dictionary HTML helpers -------------------------------------------------

	local function appendStyleAttr(attrs, style)
		attrs = attrs or ""
		if attrs:find("style%s*=") then
			return attrs:gsub('style%s*=%s*"([^"]*)"', 'style="%1; ' .. style .. '"', 1)
		end
		return attrs .. ' style="' .. style .. '"'
	end

	function normalizeDictionaryHtml(definition)
		definition = tostring(definition or "")
		if definition == "" then
			return "<p>" .. htmlEscape(_("No definition.")) .. "</p>"
		end
		if looksLikeHtml(definition) then
			return definition
		end
		return plainTextToHtml(definition)
	end

	local function buildStyleFromClassList(classes)
		classes = tostring(classes or "")
		local cached = CLASS_STYLE_CACHE[classes]
		if cached ~= nil then
			return cached or nil
		end

		local style_parts = {}
		for class_name in classes:gmatch("%S+") do
			local style = dictionary_class_styles[class_name]
			if style then
				style_parts[#style_parts + 1] = style
			end
		end

		local result = #style_parts > 0 and table.concat(style_parts, " ") or false
		CLASS_STYLE_CACHE[classes] = result
		return result or nil
	end

	local function normalizeHeadingTags(html)
		html = html:gsub("<%s*[hH][1-6]([^>]*)>", function(attrs)
			return "<div"
				.. appendStyleAttr(
					attrs,
					"font-size:1em; line-height:1.25; margin:0.35em 0 0.25em 0; font-weight:normal;"
				)
				.. ">"
		end)
		return html:gsub("</%s*[hH][1-6]%s*>", "</div>")
	end

	local function normalizeDictionaryClasses(html)
		return html:gsub('(<%w+)([^>]-class%s*=%s*"([^"]*)"[^>]*)(>)', function(tag, attrs, classes, close)
			local style = buildStyleFromClassList(classes)
			if style then
				return tag .. appendStyleAttr(attrs, style) .. close
			end
			return tag .. attrs .. close
		end)
	end

	local function normalizeDictionaryLists(html)
		html = html:gsub("<%s*[uU][lL]([^>]*)>", function(attrs)
			return "<ul" .. appendStyleAttr(attrs, "margin:0.25em 0 0.35em 1.1em; padding:0;") .. ">"
		end)
		html = html:gsub("<%s*[oO][lL]([^>]*)>", function(attrs)
			return "<ol" .. appendStyleAttr(attrs, "margin:0.25em 0 0.35em 1.1em; padding:0;") .. ">"
		end)
		return html:gsub("<%s*[lL][iI]([^>]*)>", function(attrs)
			return "<li" .. appendStyleAttr(attrs, "margin:0.18em 0;") .. ">"
		end)
	end

	local function shouldNormalizeDictionaryPreviewHtml(html)
		return html:find("<%s*[hH][1-6]")
			or html:find('class%s*=%s*"hw"')
			or html:find('class%s*=%s*"pron"')
			or html:find('class%s*=%s*"ctx"')
			or html:find('class%s*=%s*"ib"')
			or html:find('class%s*=%s*"ql"')
			or html:find('class%s*=%s*"phg"')
	end

	function normalizeDictionaryPreviewHtml(definition)
		local html = normalizeDictionaryHtml(definition)
		if not shouldNormalizeDictionaryPreviewHtml(html) then
			return html
		end

		html = normalizeHeadingTags(html)
		html = normalizeDictionaryClasses(html)
		return normalizeDictionaryLists(html)
	end

	function getDictionaryPanelCss(result)
		local css_justify = G_reader_settings:nilOrTrue("dict_justify") and "text-align: justify;" or ""
		local css = [[
@page {
    margin: 0;
    font-family: ']] .. UI_FONT_FACE .. [[';
}
body {
    margin: 0;
    padding: 0;
    line-height: 1.3;
    font-family: ']] .. UI_FONT_FACE .. [[';
]] .. css_justify .. [[
}
blockquote, dd {
    margin: 0 1em;
}
ol, ul, menu {
    margin: 0;
    padding: 0 1.7em;
}
a {
    color: black;
}
]]
		if result and result.css and result.css ~= "" then
			css = css .. "\n" .. result.css
		end
		return css
	end

	function hasDictionaryCss(result)
		return result and result.css and result.css ~= "" and looksLikeHtml(result.definition)
	end

	-- Selection, translation and widget helpers -------------------------------

	function getSelectionBounds(boxes)
		if type(boxes) ~= "table" or #boxes == 0 then
			return nil
		end

		local top
		local bottom
		for _, box in ipairs(boxes) do
			if type(box) == "table" and box.y and box.h then
				local box_top = tonumber(box.y)
				local box_height = tonumber(box.h)
				local box_bottom = box_top and box_height and (box_top + box_height)
				if box_top and box_bottom then
					top = top and math.min(top, box_top) or box_top
					bottom = bottom and math.max(bottom, box_bottom) or box_bottom
				end
			end
		end

		if not top or not bottom then
			return nil
		end
		return { top = top, bottom = bottom }
	end

	function extractMainTranslation(result)
		if not (result and type(result) == "table" and type(result[1]) == "table") then
			return ""
		end

		local translated = {}
		for _, item in ipairs(result[1]) do
			if type(item) == "table" and type(item[1]) == "string" and item[1] ~= "" then
				translated[#translated + 1] = item[1]
			end
		end
		return trim(table.concat(translated, " "))
	end

	function getWidgetSize(widget)
		local ok, size = pcall(function()
			return widget:getSize()
		end)
		if ok and size then
			return size
		end
		return Geom:new({ w = 0, h = 0 })
	end
end
