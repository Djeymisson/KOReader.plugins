return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	local function normalizeWikipediaLang(lang)
		lang = tostring(lang or "en"):lower()
		return lang ~= "" and lang or "en"
	end

	local function isNetworkUnavailable()
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

	local function onlineLookupError(err, fallback)
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

	local function menuDimensions()
		return Screen:getWidth() - Screen:scaleBySize(80), math.floor(Screen:getHeight() * 0.8)
	end

	local function showMenu(plugin, title, items)
		local Menu = require("ui/widget/menu")
		local width, height = menuDimensions()

		plugin:closeLanguageMenu()
		plugin.language_menu = Menu:new({
			title = title,
			item_table = items,
			width = width,
			height = height,
		})
		UIManager:show(plugin.language_menu)
		return true
	end

	local function setWikipediaTrapWidget(Wikipedia, message)
		if type(Wikipedia.setTrapWidget) == "function" then
			Wikipedia:setTrapWidget(message or _("Querying Wikipedia…"))
		end
	end

	local function resetWikipediaTrapWidget()
		pcall(function()
			local Wikipedia = require("ui/wikipedia")
			if type(Wikipedia.resetTrapWidget) == "function" then
				Wikipedia:resetTrapWidget()
			end
		end)
	end

	local function getPageTitle(entry, fallback)
		return trim((entry and entry.page and entry.page.title) or fallback or "")
	end

	local function resetWikipediaSearchState(state, lang)
		state.wikipedia_lang = normalizeWikipediaLang(lang)
		state.wikipedia_payload = nil
		state.wikipedia_error = nil
		state.wikipedia_loading = nil
		state.wikipedia_full_loading = nil
		state.wikipedia_pages = nil
		state.wikipedia_count = nil
		state.wikipedia_index = 1
	end

	local function getBestPage(pages)
		local best
		if type(pages) ~= "table" then
			return nil
		end

		for _, page in pairs(pages) do
			if type(page) == "table" then
				if not best or tonumber(page.index or 999999) < tonumber(best.index or 999999) then
					best = page
				end
			end
		end

		return best
	end

	function LookupPreview:getWikipediaLanguageLabel(lang)
		if Translator and type(Translator.getLanguageName) == "function" then
			local ok, name = pcall(function()
				return Translator:getLanguageName(lang, lang and lang:upper() or "?")
			end)
			if ok and name then
				return name
			end
		end
		return tostring(lang or "?")
	end

	function LookupPreview:getWikipediaLanguageMenuItems(state)
		local items = {}
		local current_lang = self:getWikipediaLang()
		local current_found = false

		for _, lang in ipairs(COMMON_TARGET_LANGUAGES) do
			local lang_key = lang
			if lang_key == current_lang then
				current_found = true
			end
			items[#items + 1] = {
				text = string.format("%s (%s)", self:getWikipediaLanguageLabel(lang_key), lang_key),
				checked_func = function()
					return self:getWikipediaLang() == lang_key
				end,
				radio = true,
				callback = function()
					return self:refreshWikipediaWithLanguage(state, lang_key)
				end,
			}
		end

		-- Preserve custom/current languages even when they are outside the compact list.
		if not current_found and current_lang ~= "" then
			table.insert(items, 1, {
				text = string.format("%s (%s)", self:getWikipediaLanguageLabel(current_lang), current_lang),
				checked_func = function()
					return self:getWikipediaLang() == current_lang
				end,
				radio = true,
				callback = function()
					return self:refreshWikipediaWithLanguage(state, current_lang)
				end,
			})
		end

		return items
	end

	function LookupPreview:showWikipediaLanguageMenu(state)
		return showMenu(self, _("Wikipedia language"), self:getWikipediaLanguageMenuItems(state))
	end

	function LookupPreview:refreshWikipediaWithLanguage(state, lang)
		self:closeLanguageMenu()
		lang = normalizeWikipediaLang(lang)
		G_reader_settings:saveSetting(SETTING_WIKI_LANG, lang)

		if not state or state ~= self.current_state then
			return true
		end

		resetWikipediaSearchState(state, lang)
		self:showCarousel(state, PAGE_WIKIPEDIA, true)
		if self:useAutomaticOnlineCardLoading() then
			UIManager:scheduleIn(0.05, function()
				self:loadWikipedia(state)
			end)
		end
		return true
	end

	function LookupPreview:buildWikipediaResults(pages)
		local results = {}
		if type(pages) ~= "table" then
			return results
		end

		for _, page in pairs(pages) do
			if type(page) == "table" then
				results[#results + 1] = {
					page = page,
					index = tonumber(page.index or 999999) or 999999,
				}
			end
		end

		table.sort(results, function(a, b)
			if a.index == b.index then
				return tostring(a.page and a.page.title or "") < tostring(b.page and b.page.title or "")
			end
			return a.index < b.index
		end)

		return results
	end

	function LookupPreview:getWikipediaArticleMenuItems(state)
		local items = {}
		local pages = state and state.wikipedia_pages or {}
		local active_index = state and (state.wikipedia_index or 1) or 1

		for index, entry in ipairs(pages) do
			local title = getPageTitle(entry, string.format("%s %d", _("Article"), index))
			if title == "" then
				title = string.format("%s %d", _("Article"), index)
			end

			items[#items + 1] = {
				text = title,
				radio = true,
				checked_func = function()
					return (state and (state.wikipedia_index or 1) or active_index) == index
				end,
				callback = function()
					self:closeLanguageMenu()
					return self:switchWikipediaResult(index)
				end,
			}
		end

		if #items == 0 then
			items[1] = {
				text = _("No Wikipedia article found."),
				enabled_func = function()
					return false
				end,
			}
		end

		return items
	end

	function LookupPreview:showWikipediaArticleMenu(state)
		return showMenu(self, _("Wikipedia"), self:getWikipediaArticleMenuItems(state))
	end

	function LookupPreview:buildWikipediaPayload(state, page, page_index, page_count, is_full_article)
		state = state or self.current_state or {}
		page = page or {}

		local lang = state.wikipedia_lang or self:getWikipediaLang()
		local title = trim(page.title or state.search_text or _("Wikipedia"))
		local extract = trim(page.extract or "")

		if extract == "" then
			extract = is_full_article and _("No full article found.") or _("No introduction found.")
		end

		local subtitle = title .. " · " .. lang
		if page_count and page_count > 1 then
			subtitle = string.format("%s · %d/%d", subtitle, page_index or 1, page_count)
		end
		if is_full_article then
			subtitle = subtitle .. " · " .. _("Full article")
		end
		subtitle = subtitle .. " ▾"

		return {
			page_type = PAGE_WIKIPEDIA,
			title = _("Wikipedia"),
			subtitle = subtitle,
			subtitle_callback = function()
				return self:showWikipediaArticleMenu(state)
			end,
			html_body = '<div class="lp-title">' .. plainTextToHtml(title) .. "</div>" .. plainTextToHtml(extract),
			css = FALLBACK_CSS,
		}
	end

	function LookupPreview:updateWikipediaPayload(state, index)
		if not state then
			return nil
		end

		local pages = state.wikipedia_pages or {}
		local page_count = state.wikipedia_count or #pages
		state.wikipedia_index = normalizeResultIndex(index or state.wikipedia_index or 1, page_count)

		local entry = pages[state.wikipedia_index]
		local page = entry and entry.page or nil
		if not page then
			return nil
		end

		state.wikipedia_payload = self:buildWikipediaPayload(state, page, state.wikipedia_index, page_count, false)
		return state.wikipedia_payload
	end

	function LookupPreview:switchWikipediaResult(index)
		local state = self.current_state
		if not state then
			return true
		end

		self:updateWikipediaPayload(state, index)
		return self:showCarousel(state, PAGE_WIKIPEDIA, true)
	end

	function LookupPreview:buildWikipediaLanguageButton(state)
		state = state or self.current_state
		return {
			{
				spec = { text = tostring((state and state.wikipedia_lang) or self:getWikipediaLang()):upper() },
				weight = 1,
				callback = function()
					return self:showWikipediaLanguageMenu(state)
				end,
			},
		}
	end

	function LookupPreview:buildWikipediaManualLoadButtons(state, label)
		state = state or self.current_state
		return {
			{
				spec = { text = label or _("Load") },
				weight = 1.6,
				callback = function()
					return self:requestWikipediaLoad(state)
				end,
			},
			{
				spec = { text = tostring((state and state.wikipedia_lang) or self:getWikipediaLang()):upper() },
				weight = 0.8,
				callback = function()
					return self:showWikipediaLanguageMenu(state)
				end,
			},
		}
	end

	function LookupPreview:requestWikipediaLoad(state)
		state = state or self.current_state
		if not state or state ~= self.current_state then
			return true
		end

		state.wikipedia_payload = nil
		state.wikipedia_error = nil
		state.wikipedia_loading = nil
		state.wikipedia_full_loading = nil
		state.wikipedia_pages = nil
		state.wikipedia_count = nil
		state.wikipedia_index = 1
		return self:loadWikipedia(state, true)
	end

	function LookupPreview:buildWikipediaButtons(state)
		if not state or not state.wikipedia_payload then
			return nil
		end

		local count = state.wikipedia_count or #(state.wikipedia_pages or {})
		local buttons = {
			{
				spec = { text = C_("Wikipedia", "Full article") },
				weight = 1.75,
				callback = function()
					return self:openFullWikipediaArticleFromState(state)
				end,
			},
			{
				spec = { text = tostring(state.wikipedia_lang or self:getWikipediaLang()):upper() },
				weight = 0.9,
				callback = function()
					return self:showWikipediaLanguageMenu(state)
				end,
			},
		}

		if count > 1 then
			buttons[#buttons + 1] = {
				spec = { icon = ICON_PREVIOUS },
				weight = 0.85,
				callback = function()
					return self:switchWikipediaResult((state.wikipedia_index or 1) - 1)
				end,
			}
			buttons[#buttons + 1] = {
				spec = { icon = ICON_NEXT },
				weight = 0.85,
				callback = function()
					return self:switchWikipediaResult((state.wikipedia_index or 1) + 1)
				end,
			}
		end

		buttons[#buttons + 1] = {
			spec = { icon = ICON_DETAILS },
			weight = 0.85,
			callback = function()
				return self:openOriginalWikipediaFromState(state)
			end,
		}

		return buttons
	end

	function LookupPreview:cleanupSelectionAfterNativeWikipedia(state)
		local cleanup_state = state
		UIManager:scheduleIn(0.05, function()
			if cleanup_state then
				self.selection_snapshot = nil
				self:clearOriginalHighlight(cleanup_state.dict_self)
				self:clearSelection()
				if cleanup_state.dict_close_callback then
					pcall(cleanup_state.dict_close_callback)
				end
			end
		end)
		return true
	end

	local function openNativeWikipedia(plugin, state, query, full_article, empty_message, error_message)
		query = trim(query or "")
		if query == "" then
			return plugin:notify(empty_message)
		end

		local lang = state.wikipedia_lang or plugin:getWikipediaLang()
		local cleanup_state = state

		plugin:closeCurrentPopup(true)
		plugin.current_state = nil

		local ok, err = pcall(function()
			if plugin.ui and plugin.ui.handleEvent then
				return plugin.ui:handleEvent(Event:new("LookupWikipedia", query, true, false, full_article, lang, nil))
			end
		end)

		if not ok then
			logger.warn("LookupPreview: failed to open Wikipedia widget:", err)
			return plugin:notify(error_message)
		end

		return plugin:cleanupSelectionAfterNativeWikipedia(cleanup_state)
	end

	function LookupPreview:openOriginalWikipediaFromState(state)
		state = state or self.current_state
		if not state then
			return true
		end

		local search_text = state.search_text or state.wikipedia_search_text or ""
		return openNativeWikipedia(
			self,
			state,
			search_text,
			false,
			_("No text to search on Wikipedia."),
			_("Could not open Wikipedia.")
		)
	end

	function LookupPreview:openFullWikipediaArticleFromState(state)
		state = state or self.current_state
		if not state then
			return true
		end

		local entry = (state.wikipedia_pages or {})[state.wikipedia_index or 1]
		local title = getPageTitle(entry, state.search_text or "")
		return openNativeWikipedia(
			self,
			state,
			title,
			true,
			_("No Wikipedia article found."),
			_("Could not open Wikipedia article.")
		)
	end

	function LookupPreview:loadFullWikipediaArticle(state)
		state = state or self.current_state
		if state ~= self.current_state then
			return true
		end
		if not state or state.wikipedia_full_loading then
			return true
		end

		local pages = state.wikipedia_pages or {}
		local entry = pages[state.wikipedia_index or 1]
		local title = getPageTitle(entry, state.search_text or "")
		if title == "" then
			return self:notify(_("No Wikipedia article found."))
		end

		state.wikipedia_full_loading = true
		local loading_payload = self:buildWikipediaPayload(
			state,
			entry and entry.page or { title = title },
			state.wikipedia_index or 1,
			state.wikipedia_count or #pages,
			false
		)
		loading_payload.html_body = '<p class="lp-muted">'
			.. htmlEscape(_("Querying full Wikipedia article…"))
			.. "</p>"
		state.wikipedia_payload = loading_payload
		self:refreshCurrentPage(PAGE_WIKIPEDIA)

		if isNetworkUnavailable() then
			state.wikipedia_error = _("Network unavailable.")
			state.wikipedia_full_loading = false
			return self:refreshCurrentPage(PAGE_WIKIPEDIA)
		end

		local ok, err = pcall(function()
			local Wikipedia = require("ui/wikipedia")
			local lang = state.wikipedia_lang or self:getWikipediaLang()
			setWikipediaTrapWidget(Wikipedia, _("Querying Wikipedia…"))

			local full_page = getBestPage(Wikipedia:getFullPage(title, lang))
			resetWikipediaTrapWidget()

			if not full_page then
				state.wikipedia_error = _("No Wikipedia article found.")
				return
			end

			state.wikipedia_payload = self:buildWikipediaPayload(
				state,
				full_page,
				state.wikipedia_index or 1,
				state.wikipedia_count or #pages,
				true
			)
		end)

		if not ok then
			logger.warn("LookupPreview: full Wikipedia article lookup failed:", err)
			resetWikipediaTrapWidget()
			state.wikipedia_error = onlineLookupError(err, _("Wikipedia lookup failed."))
		end

		state.wikipedia_full_loading = false
		return self:refreshCurrentPage(PAGE_WIKIPEDIA)
	end

	function LookupPreview:pickBestWikipediaPage(pages)
		return getBestPage(pages)
	end

	function LookupPreview:loadWikipedia(state, force)
		if state ~= self.current_state then
			return true
		end
		if not state then
			return true
		end
		if not force and self:useManualOnlineCardLoading() then
			return self:refreshCurrentPage(PAGE_WIKIPEDIA)
		end
		if state.wikipedia_loading or state.wikipedia_payload or state.wikipedia_error then
			return true
		end

		state.wikipedia_loading = true
		local text = state.search_text or ""
		if text == "" then
			state.wikipedia_error = _("No text to search on Wikipedia.")
			state.wikipedia_loading = false
			return self:refreshCurrentPage(PAGE_WIKIPEDIA)
		end

		if isNetworkUnavailable() then
			state.wikipedia_error = _("Network unavailable.")
			state.wikipedia_loading = false
			return self:refreshCurrentPage(PAGE_WIKIPEDIA)
		end

		local ok, err = pcall(function()
			local Wikipedia = require("ui/wikipedia")
			local lang = state.wikipedia_lang or self:getWikipediaLang()
			state.wikipedia_lang = lang
			setWikipediaTrapWidget(Wikipedia, _("Querying Wikipedia…"))

			local wikipedia_results = self:buildWikipediaResults(Wikipedia:searchAndGetIntros(text, lang))
			resetWikipediaTrapWidget()

			if #wikipedia_results == 0 then
				state.wikipedia_error = _("No Wikipedia article found.")
				return
			end

			state.wikipedia_pages = wikipedia_results
			state.wikipedia_count = #wikipedia_results
			state.wikipedia_index = normalizeResultIndex(state.wikipedia_index or 1, state.wikipedia_count)
			self:updateWikipediaPayload(state, state.wikipedia_index)
		end)

		if not ok then
			logger.warn("LookupPreview: Wikipedia lookup failed:", err)
			resetWikipediaTrapWidget()
			state.wikipedia_error = onlineLookupError(err, _("Wikipedia lookup failed."))
		end

		state.wikipedia_loading = false
		return self:refreshCurrentPage(PAGE_WIKIPEDIA)
	end
end
