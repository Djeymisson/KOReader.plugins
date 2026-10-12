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

	-- Card load status ---------------------------------------------------------
	-- Each card keeps where its content stands in state.load[page]: one of the
	-- LOAD_* values of context.lua, and the message to show for an empty or
	-- failed lookup.

	function getLoadStatus(state, page)
		local load = state and state.load and state.load[page]
		if load then
			return load.status, load.message
		end
		return LOAD_IDLE
	end

	function setLoadStatus(state, page, status, message)
		state.load = state.load or {}
		state.load[page] = { status = status, message = message }
	end

	-- Scroll positions ---------------------------------------------------------
	-- Where each card was scrolled to, for as long as the lookup is open:
	-- state.scroll_positions[key] = { page = n, count = pages }, the key naming
	-- the card and the result it shows (see LookupPreview:getCardScrollKey).

	function getScrollPosition(state, key)
		return key and state and state.scroll_positions and state.scroll_positions[key] or nil
	end

	function saveScrollPosition(state, key, page, count)
		if not (key and state) then
			return
		end
		state.scroll_positions = state.scroll_positions or {}
		state.scroll_positions[key] = { page = page, count = count }
	end

	-- Forgets the positions of one card, when its results are replaced.
	function forgetScrollPositions(state, page)
		local positions = state and state.scroll_positions
		if not positions then
			return
		end
		local prefix = tostring(page) .. ":"
		for key in pairs(positions) do
			if key:sub(1, #prefix) == prefix then
				positions[key] = nil
			end
		end
	end

	-- Online results cache -----------------------------------------------------
	-- What Translate and Wikipedia answered, kept for the whole KOReader session
	-- (across lookups and books), so looking the same text up again needs no
	-- network. Answers only, "nothing found" included; never errors. It lives on
	-- the shared context, which outlasts the plugin instance of each book.

	local ONLINE_CACHE_SIZE = 64

	ONLINE_CACHE = ONLINE_CACHE or { entries = {}, order = {} }

	local function touchCacheKey(key)
		local order = ONLINE_CACHE.order
		for index = #order, 1, -1 do
			if order[index] == key then
				table.remove(order, index)
				break
			end
		end
		order[#order + 1] = key
	end

	function onlineCacheKey(...)
		return table.concat({ ... }, "\n")
	end

	function getCachedOnlineResult(key)
		local value = ONLINE_CACHE.entries[key]
		if value ~= nil then
			touchCacheKey(key)
		end
		return value
	end

	function cacheOnlineResult(key, value)
		touchCacheKey(key)
		ONLINE_CACHE.entries[key] = value
		local order = ONLINE_CACHE.order
		while #order > ONLINE_CACHE_SIZE do
			ONLINE_CACHE.entries[table.remove(order, 1)] = nil
		end
	end

	function clearOnlineCache()
		ONLINE_CACHE.entries = {}
		ONLINE_CACHE.order = {}
	end

	-- Network helpers ----------------------------------------------------------
	-- Shared by translation.lua and wikipedia.lua, which both need to skip a
	-- blocking online lookup when the device has no connectivity, and to turn
	-- a raw pcall error into a user-facing message.

	function isNetworkUnavailable()
		local ok, NetworkMgr = pcall(require, "ui/network/manager")
		if not ok or type(NetworkMgr) ~= "table" then
			return false
		end

		local probes = { "isOnline", "isConnected", "isWifiConnected", "isWifiOn" }
		for _, name in ipairs(probes) do
			local fn = NetworkMgr[name]
			if type(fn) == "function" then
				local probe_ok, available = pcall(fn, NetworkMgr)
				if probe_ok and available ~= nil then
					return not available
				end
			end
		end

		return false
	end

	-- Runs an online query. Under Trapper:wrap, as KOReader does, the query
	-- goes to a subprocess that a tap cancels. Not on macOS: a process forked
	-- from the KOReader app there dies as soon as it resolves a host name
	-- (macOS system services are not fork-safe), so the query never answers;
	-- it runs in KOReader's process instead, as Trapper does when unwrapped.
	function runOnlineQuery(plugin, query)
		if plugin.online_queries_in_subprocess then
			require("ui/trapper"):wrap(query)
		else
			query()
		end
	end

	function onlineLookupError(err, fallback)
		local message = tostring(err or "")
		local lower = message:lower()
		if
			lower:find("network", 1, true)
			or lower:find("connection", 1, true)
			or lower:find("timeout", 1, true)
			or lower:find("host", 1, true)
			or lower:find("socket", 1, true)
			or lower:find("dns", 1, true)
		then
			return _("Network unavailable.")
		end

		return message ~= "" and message or fallback
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
		if not widget then
			return Geom:new({ w = 0, h = 0 })
		end

		-- Called from CardTabButton:paintTo on every tab repaint, so avoid
		-- allocating a wrapper closure just to call widget:getSize().
		local ok, size = pcall(widget.getSize, widget)
		if ok and size then
			return size
		end
		return Geom:new({ w = 0, h = 0 })
	end
end
