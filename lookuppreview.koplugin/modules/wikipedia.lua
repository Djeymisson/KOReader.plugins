return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	local function normalizeWikipediaLang(lang)
		lang = tostring(lang or "en"):lower()
		return lang ~= "" and lang or "en"
	end

	-- isNetworkUnavailable and onlineLookupError are shared globals defined in
	-- modules/utils.lua (also used by translation.lua).

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
		state.wikipedia_pages = nil
		state.wikipedia_count = nil
		state.wikipedia_index = 1
		setLoadStatus(state, PAGE_WIKIPEDIA, LOAD_IDLE)
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
		self:showCarousel(state, PAGE_WIKIPEDIA)
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

	function LookupPreview:buildWikipediaPayload(state, page)
		state = state or self.current_state or {}
		page = page or {}

		local lang = state.wikipedia_lang or self:getWikipediaLang()
		local title = trim(page.title or state.search_text or _("Wikipedia"))
		local extract = trim(page.extract or "")

		if extract == "" then
			extract = _("No introduction found.")
		end

		local subtitle = title .. " · " .. lang .. " ▾"

		return {
			page_type = PAGE_WIKIPEDIA,
			title = _("Wikipedia"),
			subtitle = subtitle,
			subtitle_callback = function()
				return self:showWikipediaArticleMenu(state)
			end,
			subtitle_hint = _("Choose which article to show"),
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

		state.wikipedia_payload = self:buildWikipediaPayload(state, page)
		return state.wikipedia_payload
	end

	function LookupPreview:switchWikipediaResult(index)
		local state = self.current_state
		if not state then
			return true
		end

		self:updateWikipediaPayload(state, index)
		return self:showCarousel(state, PAGE_WIKIPEDIA)
	end

	function LookupPreview:buildWikipediaLanguageButton(state)
		state = state or self.current_state
		return {
			{
				spec = { text = tostring((state and state.wikipedia_lang) or self:getWikipediaLang()):upper() },
				hint = _("Choose the Wikipedia language"),
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
				spec = { text = tostring((state and state.wikipedia_lang) or self:getWikipediaLang()):upper() },
				hint = _("Choose the Wikipedia language"),
				weight = 0.8,
				callback = function()
					return self:showWikipediaLanguageMenu(state)
				end,
			},
			{
				spec = { text = label or _("Load") },
				hint = _("Query Wikipedia"),
				weight = 1.6,
				callback = function()
					return self:requestWikipediaLoad(state)
				end,
			},
		}
	end

	function LookupPreview:buildWikipediaLoadingButtons(state)
		state = state or self.current_state
		return {
			{
				spec = { text = tostring((state and state.wikipedia_lang) or self:getWikipediaLang()):upper() },
				hint = _("Choose the Wikipedia language"),
				weight = 0.8,
				callback = function()
					return self:showWikipediaLanguageMenu(state)
				end,
			},
			{
				spec = self:getLoadingButtonSpec(),
				hint = _("Loading…"),
				weight = 1.6,
			},
		}
	end

	-- What the Load and Retry buttons do: show the card loading, then query.
	function LookupPreview:requestWikipediaLoad(state)
		state = state or self.current_state
		if not state or state ~= self.current_state or getLoadStatus(state, PAGE_WIKIPEDIA) == LOAD_LOADING then
			return true
		end

		state.wikipedia_payload = nil
		state.wikipedia_pages = nil
		state.wikipedia_count = nil
		state.wikipedia_index = 1
		setLoadStatus(state, PAGE_WIKIPEDIA, LOAD_LOADING)
		self:refreshCard(PAGE_WIKIPEDIA)

		UIManager:scheduleIn(0.05, function()
			if state == self.current_state then
				self:queryWikipedia(state)
			end
		end)
		return true
	end

	function LookupPreview:buildWikipediaButtons(state)
		if not state or not state.wikipedia_payload then
			return nil
		end

		local count = state.wikipedia_count or #(state.wikipedia_pages or {})
		local full_article_icon = self:getPluginIconFile(ICON_WIKIPEDIA)
		local buttons = {
			{
				spec = { text = tostring(state.wikipedia_lang or self:getWikipediaLang()):upper() },
				hint = _("Choose the Wikipedia language"),
				weight = 0.9,
				callback = function()
					return self:showWikipediaLanguageMenu(state)
				end,
			},
		}

		if count > 1 then
			buttons[#buttons + 1] = {
				spec = { icon = ICON_PREVIOUS },
				hint = _("Previous article"),
				weight = 0.85,
				callback = function()
					return self:switchWikipediaResult((state.wikipedia_index or 1) - 1)
				end,
			}
			buttons[#buttons + 1] = {
				spec = {
					text = string.format("%d / %d", state.wikipedia_index or 1, count),
					bold = false,
				},
				hint = string.format(_("Article %d of %d"), state.wikipedia_index or 1, count),
				weight = 0.8,
				separator_before = false,
			}
			buttons[#buttons + 1] = {
				spec = { icon = ICON_NEXT },
				hint = _("Next article"),
				weight = 0.85,
				separator_before = false,
				callback = function()
					return self:switchWikipediaResult((state.wikipedia_index or 1) + 1)
				end,
			}
		end

		buttons[#buttons + 1] = {
			spec = full_article_icon and { icon_file = full_article_icon }
				or { text = C_("Wikipedia", "Full article") },
			hint = _("Open the full Wikipedia article"),
			weight = full_article_icon and 0.85 or 1.75,
			callback = function()
				return self:openFullWikipediaArticleFromState(state)
			end,
		}

		buttons[#buttons + 1] = {
			spec = { plugin_icon = ICON_DETAILS, icon = ICON_DETAILS_FALLBACK },
			hint = _("Open KOReader's original Wikipedia widget"),
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

		local search_text = state.search_text or ""
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

	-- Loads the card when it is shown, unless online cards wait for the Load
	-- button.
	function LookupPreview:loadWikipedia(state)
		if not state or state ~= self.current_state then
			return true
		end
		if self:useManualOnlineCardLoading() then
			return self:refreshCard(PAGE_WIKIPEDIA)
		end
		if getLoadStatus(state, PAGE_WIKIPEDIA) ~= LOAD_IDLE then
			return true
		end

		setLoadStatus(state, PAGE_WIKIPEDIA, LOAD_LOADING)
		return self:queryWikipedia(state)
	end

	-- Searches Wikipedia for a card already marked as loading.
	function LookupPreview:queryWikipedia(state)
		local text = state.search_text or ""
		if text == "" then
			setLoadStatus(state, PAGE_WIKIPEDIA, LOAD_ERROR, _("No text to search on Wikipedia."))
			return self:refreshCard(PAGE_WIKIPEDIA)
		end

		if isNetworkUnavailable() then
			setLoadStatus(state, PAGE_WIKIPEDIA, LOAD_ERROR, _("Network unavailable."))
			return self:refreshCard(PAGE_WIKIPEDIA)
		end

		local ok, err = pcall(function()
			local Wikipedia = require("ui/wikipedia")
			local lang = state.wikipedia_lang or self:getWikipediaLang()
			state.wikipedia_lang = lang
			setWikipediaTrapWidget(Wikipedia, _("Querying Wikipedia…"))

			local wikipedia_results = self:buildWikipediaResults(Wikipedia:searchAndGetIntros(text, lang))
			resetWikipediaTrapWidget()

			if #wikipedia_results == 0 then
				setLoadStatus(state, PAGE_WIKIPEDIA, LOAD_EMPTY, _("No Wikipedia article found."))
				return
			end

			state.wikipedia_pages = wikipedia_results
			state.wikipedia_count = #wikipedia_results
			state.wikipedia_index = normalizeResultIndex(state.wikipedia_index or 1, state.wikipedia_count)
			self:updateWikipediaPayload(state, state.wikipedia_index)
			setLoadStatus(state, PAGE_WIKIPEDIA, LOAD_DONE)
		end)

		if not ok then
			logger.warn("LookupPreview: Wikipedia lookup failed:", err)
			resetWikipediaTrapWidget()
			setLoadStatus(state, PAGE_WIKIPEDIA, LOAD_ERROR, onlineLookupError(err, _("Wikipedia lookup failed.")))
		end

		return self:refreshCard(PAGE_WIKIPEDIA)
	end
end
