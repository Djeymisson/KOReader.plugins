-- Lookup Preview: plugin lifecycle, settings, KOReader hooks and selection helpers.
return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	local function callIfPresent(callback, ...)
		if callback then
			return pcall(callback, ...)
		end
	end

	local function schedulePreviewLoad(plugin, state, page_index)
		if not plugin:useAutomaticOnlineCardLoading() then
			return
		end

		if page_index == PAGE_TRANSLATION then
			UIManager:scheduleIn(0.05, function()
				plugin:loadTranslation(state)
			end)
		elseif page_index == PAGE_WIKIPEDIA then
			UIManager:scheduleIn(0.05, function()
				plugin:loadWikipedia(state)
			end)
		end
	end

	local function refreshTranslationPayloadIfLoaded(plugin)
		local state = plugin.current_state
		if state and state.translation_text_main then
			state.translation_payload = plugin:buildTranslationPayload(state)
			plugin:refreshCurrentPage(PAGE_TRANSLATION)
		end
	end

	local function normalizeLeftAction(action)
		return LEFT_ACTION_BY_ID[action] and action or DEFAULT_LEFT_ACTION
	end

	local function applyCardStyleMode(plugin, rounded)
		plugin:setRoundedCards(rounded)
		return plugin:refreshVisibleCards()
	end

	local function applySidePreviewMode(plugin, mode)
		plugin:setSidePreviewMode(mode)
		return plugin:refreshVisibleCards()
	end

	local function applyOnlineCardLoadMode(plugin, mode)
		plugin:setOnlineCardLoadMode(mode)
		return plugin:refreshVisibleCards()
	end

	local function applyDictionaryHtmlMode(plugin, mode)
		plugin:setDictionaryHtmlMode(mode)
		local state = plugin.current_state
		if state then
			state.dictionary_payload = nil
			state.dictionary_payload_cache = nil
			if plugin.updateDictionaryPayload then
				plugin:updateDictionaryPayload(state, state.dictionary_index)
			end
		end
		return plugin:refreshVisibleCards()
	end

	function LookupPreview:init()
		self.current_popup = nil
		self.current_state = nil

		self.original_showDict = nil
		self.patched_dictionary = nil
		self.opening_original_popup = false
		self.native_dict_popup_active = false
		self.native_dict_popup_count = 0

		self.patched_highlight = nil
		self.original_highlight_lookupDict = nil
		self.original_highlight_translate = nil
		self.original_highlight_lookupWikipedia = nil

		self.selection_snapshot = nil
		self.plugin_icon_cache = {}
		self.language_menu = nil
		self.clipboard_available = Device:hasClipboard()

		if self.ui and self.ui.menu then
			self.ui.menu:registerToMainMenu(self)
		end

		self:patchDictionary()
		self:patchHighlightActions()
	end

	function LookupPreview:addToMainMenu(menu_items)
		menu_items.lookuppreview = {
			text = _("Lookup preview"),
			sorting_hint = "tools",
			sub_item_table = {
				{
					text = _("Enable lookup preview"),
					checked_func = function()
						return self:isPreviewEnabled()
					end,
					callback = function()
						self:setPreviewEnabled(not self:isPreviewEnabled())
					end,
				},
				{
					text_func = function()
						local mode = self:useRoundedCards() and _("Rounded") or _("Square")
						return string.format("%s: %s", _("Card corners"), mode)
					end,
					sub_item_table = {
						{
							text = _("Square"),
							radio = true,
							checked_func = function()
								return not self:useRoundedCards()
							end,
							callback = function()
								return applyCardStyleMode(self, false)
							end,
						},
						{
							text = _("Rounded"),
							radio = true,
							checked_func = function()
								return self:useRoundedCards()
							end,
							callback = function()
								return applyCardStyleMode(self, true)
							end,
						},
					},
				},
				{
					text_func = function()
						local mode = self:useTabsMode() and _("Tabs") or _("Full cards")
						return string.format("%s: %s", _("Side card previews"), mode)
					end,
					sub_item_table = {
						{
							text = _("Full cards"),
							radio = true,
							checked_func = function()
								return not self:useTabsMode()
							end,
							callback = function()
								return applySidePreviewMode(self, SIDE_PREVIEW_FULL_CARDS)
							end,
						},
						{
							text = _("Tabs"),
							radio = true,
							checked_func = function()
								return self:useTabsMode()
							end,
							callback = function()
								return applySidePreviewMode(self, SIDE_PREVIEW_TABS)
							end,
						},
					},
				},
				{
					text_func = function()
						local mode = self:useManualOnlineCardLoading() and _("Manual only") or _("Automatic")
						return string.format("%s: %s", _("Online card loading"), mode)
					end,
					sub_item_table = {
						{
							text = _("Automatic"),
							radio = true,
							checked_func = function()
								return self:useAutomaticOnlineCardLoading()
							end,
							callback = function()
								return applyOnlineCardLoadMode(self, ONLINE_CARD_LOAD_AUTOMATIC)
							end,
						},
						{
							text = _("Manual only"),
							radio = true,
							checked_func = function()
								return self:useManualOnlineCardLoading()
							end,
							callback = function()
								return applyOnlineCardLoadMode(self, ONLINE_CARD_LOAD_MANUAL_ONLY)
							end,
						},
					},
				},
				{
					text_func = function()
						local mode = self:useFastRawDictionaryHtml() and _("Fast / Raw") or _("Formatted")
						return string.format("%s: %s", _("Dictionary HTML"), mode)
					end,
					sub_item_table = {
						{
							text = _("Formatted"),
							radio = true,
							checked_func = function()
								return not self:useFastRawDictionaryHtml()
							end,
							callback = function()
								return applyDictionaryHtmlMode(self, DICTIONARY_HTML_FORMATTED)
							end,
						},
						{
							text = _("Fast / Raw"),
							radio = true,
							checked_func = function()
								return self:useFastRawDictionaryHtml()
							end,
							callback = function()
								return applyDictionaryHtmlMode(self, DICTIONARY_HTML_FAST_RAW)
							end,
						},
					},
				},
				{
					text_func = function()
						return string.format("%s: %s", _("Wikipedia language"), self:getWikipediaLang())
					end,
					sub_item_table_func = function()
						return self:getWikipediaLanguageMenuItems(self.current_state)
					end,
				},
				{
					text = _("Translation"),
					sub_item_table = {
						{
							text_func = function()
								return string.format("%s: %s", _("Target language"), self:getTranslationTargetLang())
							end,
							sub_item_table_func = function()
								return self:getTargetLanguageMenuItems(self.current_state)
							end,
						},
						{
							text = _("Show source text"),
							checked_func = function()
								return self:showTranslationSourceText()
							end,
							callback = function()
								G_reader_settings:saveSetting(
									SETTING_TRANSLATION_SHOW_SOURCE,
									not self:showTranslationSourceText()
								)
								refreshTranslationPayloadIfLoaded(self)
							end,
						},
						{
							text = _("Buttons"),
							sub_item_table = {
								{
									text = _("Show copy button"),
									checked_func = function()
										return self:showTranslationCopyButton()
									end,
									callback = function()
										G_reader_settings:saveSetting(
											SETTING_TRANSLATION_SHOW_COPY_BUTTON,
											not self:showTranslationCopyButton()
										)
										self:refreshCurrentPage(PAGE_TRANSLATION)
									end,
								},
								{
									text = _("Show note button"),
									checked_func = function()
										return self:showTranslationNoteButton()
									end,
									callback = function()
										G_reader_settings:saveSetting(
											SETTING_TRANSLATION_SHOW_NOTE_BUTTON,
											not self:showTranslationNoteButton()
										)
										self:refreshCurrentPage(PAGE_TRANSLATION)
									end,
								},
							},
						},
					},
				},
				{
					text = string.format("%s: %s", _("Version"), PLUGIN_VERSION),
					callback = function()
						self:notify(string.format("%s %s", _("Lookup Preview"), PLUGIN_VERSION))
					end,
					separator = true,
				},
			},
		}
	end

	function LookupPreview:isPreviewEnabled()
		return G_reader_settings:nilOrTrue(SETTING_ENABLED)
	end

	function LookupPreview:setPreviewEnabled(enabled)
		G_reader_settings:saveSetting(SETTING_ENABLED, enabled and true or false)
	end

	function LookupPreview:useRoundedCards()
		return G_reader_settings:readSetting(SETTING_CARD_ROUNDED) == true
	end

	function LookupPreview:setRoundedCards(enabled)
		G_reader_settings:saveSetting(SETTING_CARD_ROUNDED, enabled and true or false)
	end

	function LookupPreview:getCardRadius()
		return self:useRoundedCards() and CARD_ROUNDED_RADIUS or CARD_RADIUS
	end

	function LookupPreview:getSidePreviewMode()
		local mode = G_reader_settings:readSetting(SETTING_SIDE_PREVIEW_MODE) or DEFAULT_SIDE_PREVIEW_MODE
		if mode ~= SIDE_PREVIEW_TABS then
			return SIDE_PREVIEW_FULL_CARDS
		end
		return mode
	end

	function LookupPreview:useTabsMode()
		return self:getSidePreviewMode() == SIDE_PREVIEW_TABS
	end

	function LookupPreview:setSidePreviewMode(mode)
		if mode ~= SIDE_PREVIEW_TABS then
			mode = SIDE_PREVIEW_FULL_CARDS
		end
		G_reader_settings:saveSetting(SETTING_SIDE_PREVIEW_MODE, mode)
	end

	function LookupPreview:getOnlineCardLoadMode()
		local mode = G_reader_settings:readSetting(SETTING_ONLINE_CARD_LOAD_MODE) or DEFAULT_ONLINE_CARD_LOAD_MODE
		if mode == ONLINE_CARD_LOAD_MANUAL_ONLY then
			return ONLINE_CARD_LOAD_MANUAL_ONLY
		end
		return ONLINE_CARD_LOAD_AUTOMATIC
	end

	function LookupPreview:useAutomaticOnlineCardLoading()
		return self:getOnlineCardLoadMode() == ONLINE_CARD_LOAD_AUTOMATIC
	end

	function LookupPreview:useManualOnlineCardLoading()
		return self:getOnlineCardLoadMode() == ONLINE_CARD_LOAD_MANUAL_ONLY
	end

	function LookupPreview:setOnlineCardLoadMode(mode)
		if mode ~= ONLINE_CARD_LOAD_MANUAL_ONLY then
			mode = ONLINE_CARD_LOAD_AUTOMATIC
		end
		G_reader_settings:saveSetting(SETTING_ONLINE_CARD_LOAD_MODE, mode)
	end

	function LookupPreview:getDictionaryHtmlMode()
		local mode = G_reader_settings:readSetting(SETTING_DICTIONARY_HTML_MODE) or DEFAULT_DICTIONARY_HTML_MODE
		if mode == DICTIONARY_HTML_FAST_RAW or mode == "raw" then
			return DICTIONARY_HTML_FAST_RAW
		end
		return DICTIONARY_HTML_FORMATTED
	end

	function LookupPreview:useFastRawDictionaryHtml()
		return self:getDictionaryHtmlMode() == DICTIONARY_HTML_FAST_RAW
	end

	function LookupPreview:useRawDictionaryHtml()
		return self:useFastRawDictionaryHtml()
	end

	function LookupPreview:setDictionaryHtmlMode(mode)
		if mode ~= DICTIONARY_HTML_FAST_RAW then
			mode = DICTIONARY_HTML_FORMATTED
		end
		G_reader_settings:saveSetting(SETTING_DICTIONARY_HTML_MODE, mode)
	end

	function LookupPreview:refreshVisibleCards()
		local popup = self.current_popup
		if popup and popup.rebuildVisibleCards then
			return popup:rebuildVisibleCards()
		end

		if self.current_state then
			return self:showCarousel(self.current_state, self.current_state.active_index)
		end

		return true
	end

	function LookupPreview:showTranslationSourceText()
		return G_reader_settings:readSetting(SETTING_TRANSLATION_SHOW_SOURCE) == true
	end

	function LookupPreview:showTranslationCopyButton()
		return G_reader_settings:nilOrTrue(SETTING_TRANSLATION_SHOW_COPY_BUTTON)
	end

	function LookupPreview:showTranslationNoteButton()
		return G_reader_settings:nilOrTrue(SETTING_TRANSLATION_SHOW_NOTE_BUTTON)
	end

	function LookupPreview:getWikipediaLang()
		local lang = G_reader_settings:readSetting(SETTING_WIKI_LANG)
			or G_reader_settings:readSetting("wikipedia_language")
			or G_reader_settings:readSetting("wikipedia_lang")
			or G_reader_settings:readSetting("translator_to_language")
			or "en"

		lang = tostring(lang or "en"):lower()
		return lang ~= "" and lang or "en"
	end

	function LookupPreview:getLeftButtonAction()
		return normalizeLeftAction(G_reader_settings:readSetting(SETTING_LEFT_ACTION) or DEFAULT_LEFT_ACTION)
	end

	function LookupPreview:setLeftButtonAction(action)
		G_reader_settings:saveSetting(SETTING_LEFT_ACTION, normalizeLeftAction(action))
	end

	function LookupPreview:getPluginIconFile(action_id)
		self.plugin_icon_cache = self.plugin_icon_cache or {}
		if self.plugin_icon_cache[action_id] ~= nil then
			return self.plugin_icon_cache[action_id] or nil
		end

		local candidates = PLUGIN_LEFT_ICON_CANDIDATES[action_id]
		if not candidates or not self.path or self.path == "" then
			self.plugin_icon_cache[action_id] = false
			return nil
		end

		local icons_dir = self.path .. "/icons"
		for _, basename in ipairs(candidates) do
			for _, ext in ipairs(PLUGIN_ICON_EXTENSIONS) do
				local path = icons_dir .. "/" .. basename .. ext
				if fileExists(path) then
					self.plugin_icon_cache[action_id] = path
					return path
				end
			end
		end

		self.plugin_icon_cache[action_id] = false
		return nil
	end

	function LookupPreview:getLeftButtonSpec(action_id)
		action_id = normalizeLeftAction(action_id or self:getLeftButtonAction())

		if action_id == LEFT_ACTION_SEARCH_BOOK then
			return { icon = ICON_SEARCH }
		end

		local plugin_icon = self:getPluginIconFile(action_id)
		if plugin_icon then
			return { icon_file = plugin_icon }
		end

		return { text = LEFT_ACTION_BY_ID[action_id].label }
	end

	-- Kept for compatibility with older menu layouts that exposed a configurable left action.
	function LookupPreview:genLeftButtonActionMenu()
		local items = {}
		for _, action in ipairs(LEFT_ACTIONS) do
			items[#items + 1] = {
				text = action.label,
				radio = true,
				checked_func = function()
					return self:getLeftButtonAction() == action.id
				end,
				callback = function()
					self:setLeftButtonAction(action.id)
				end,
			}
		end
		return items
	end

	function LookupPreview:notify(message)
		UIManager:show(Notification:new({ text = message }))
		return true
	end

	function LookupPreview:destroy()
		self:closeLanguageMenu()
		self:closeCurrentPopup(true)

		if self.patched_highlight and self.patched_highlight._lookuppreview_highlight_patched == self then
			if self.original_highlight_lookupDict then
				self.patched_highlight.lookupDict = self.original_highlight_lookupDict
			end
			if self.original_highlight_translate then
				self.patched_highlight.translate = self.original_highlight_translate
			end
			if self.original_highlight_lookupWikipedia then
				self.patched_highlight.lookupWikipedia = self.original_highlight_lookupWikipedia
			end
			self.patched_highlight._lookuppreview_highlight_patched = nil
		end

		if
			self.patched_dictionary
			and self.original_showDict
			and self.patched_dictionary._lookuppreview_patched == self
		then
			self.patched_dictionary.showDict = self.original_showDict
			self.patched_dictionary._lookuppreview_patched = nil
		end

		self.original_showDict = nil
		self.patched_dictionary = nil
		self.patched_highlight = nil
		self.original_highlight_lookupDict = nil
		self.original_highlight_translate = nil
		self.original_highlight_lookupWikipedia = nil
		self.selection_snapshot = nil
		self.current_state = nil
		self.plugin_icon_cache = nil
		self:resetNativeDictionaryPopupGuard()

		if WidgetContainer.destroy then
			WidgetContainer.destroy(self)
		end
	end

	function LookupPreview:patchDictionary()
		local dictionary = self.ui and self.ui.dictionary
		if not dictionary then
			logger.warn("LookupPreview: ReaderDictionary not available.")
			return
		end
		if dictionary._lookuppreview_patched then
			return
		end

		self.original_showDict = dictionary.showDict
		self.patched_dictionary = dictionary

		local plugin = self
		dictionary.showDict = function(dict_self, word, results, boxes, link, dict_close_callback)
			if not plugin:isPreviewEnabled() or plugin.opening_original_popup or not results or not results[1] then
				return plugin.original_showDict(dict_self, word, results, boxes, link, dict_close_callback)
			end

			if plugin.native_dict_popup_active then
				local wrapped_close_callback = plugin:beginNativeDictionaryPopup(dict_close_callback)
				return plugin.original_showDict(dict_self, word, results, boxes, link, wrapped_close_callback)
			end

			plugin:rememberSelection(dict_self)
			if dict_self.dismissLookupInfo then
				pcall(function()
					dict_self:dismissLookupInfo()
				end)
			end

			return plugin:showPreview(dict_self, word, results, boxes, link, dict_close_callback)
		end

		dictionary._lookuppreview_patched = self
	end

	function LookupPreview:patchHighlightActions()
		local highlight = self.ui and self.ui.highlight
		if not highlight then
			logger.warn("LookupPreview: ReaderHighlight not available.")
			return
		end
		if highlight._lookuppreview_highlight_patched then
			return
		end

		self.patched_highlight = highlight
		self.original_highlight_lookupDict = highlight.lookupDict
		self.original_highlight_translate = highlight.translate
		self.original_highlight_lookupWikipedia = highlight.lookupWikipedia

		local plugin = self

		if self.original_highlight_lookupDict then
			highlight.lookupDict = function(highlight_self, ...)
				if plugin:isPreviewEnabled() and not plugin.opening_original_popup then
					plugin:rememberSelection(highlight_self)
				end
				return plugin.original_highlight_lookupDict(highlight_self, ...)
			end
		end

		if self.original_highlight_translate then
			highlight.translate = function(highlight_self, ...)
				if not plugin:isPreviewEnabled() or plugin.opening_original_popup then
					return plugin.original_highlight_translate(highlight_self, ...)
				end

				if plugin:showSelectionPreviewFromHighlight(highlight_self, PAGE_TRANSLATION) then
					return true
				end

				return plugin.original_highlight_translate(highlight_self, ...)
			end
		end

		if self.original_highlight_lookupWikipedia then
			highlight.lookupWikipedia = function(highlight_self, ...)
				if not plugin:isPreviewEnabled() or plugin.opening_original_popup then
					return plugin.original_highlight_lookupWikipedia(highlight_self, ...)
				end

				if plugin:showSelectionPreviewFromHighlight(highlight_self, PAGE_WIKIPEDIA) then
					return true
				end

				return plugin.original_highlight_lookupWikipedia(highlight_self, ...)
			end
		end

		highlight._lookuppreview_highlight_patched = self
	end

	function LookupPreview:getHighlightSelectionText(highlight)
		local selected_text = highlight and highlight.selected_text
		local text = ""

		if type(selected_text) == "table" then
			text = selected_text.text or selected_text.word or ""
		elseif type(selected_text) == "string" then
			text = selected_text
		end

		if text == "" and highlight and type(highlight.getSelectedText) == "function" then
			local ok, selected = pcall(function()
				return highlight:getSelectedText()
			end)
			if ok and selected then
				text = selected
			end
		end

		if util and util.cleanupSelectedText then
			local ok, cleaned = pcall(function()
				return util.cleanupSelectedText(text)
			end)
			if ok and cleaned then
				text = cleaned
			end
		end

		return trim(text)
	end

	function LookupPreview:getHighlightSelectionBounds(highlight)
		if not highlight then
			return nil
		end

		local screen_height = Screen:getHeight()
		local top
		local bottom

		local function addY(y)
			y = tonumber(y)
			if not y or y < 0 or y > screen_height then
				return
			end
			top = top and math.min(top, y) or y
			bottom = bottom and math.max(bottom, y) or y
		end

		local function addPosition(pos)
			if type(pos) == "table" then
				addY(pos.y)
			end
		end

		local function addBox(box)
			if type(box) ~= "table" then
				return
			end
			if box.rect then
				box = box.rect
			end

			local y = tonumber(box.y)
			local h = tonumber(box.h)
			if y and h then
				addY(y)
				addY(y + h)
			end
		end

		addPosition(highlight.hold_pos)

		local selected_text = highlight.selected_text
		if type(selected_text) == "table" then
			addPosition(selected_text.pos0)
			addPosition(selected_text.pos1)
			if type(selected_text.boxes) == "table" then
				for _, box in ipairs(selected_text.boxes) do
					addBox(box)
				end
			end
		end

		if top and bottom then
			return { top = top, bottom = bottom }
		end
		return nil
	end

	function LookupPreview:buildSelectionStateFromHighlight(highlight)
		local text = self:getHighlightSelectionText(highlight)
		if text == "" then
			return nil
		end

		self:rememberSelection(highlight)

		local state = {
			dict_self = nil,
			highlight_self = highlight,
			word = text,
			results = {
				{
					word = text,
					no_result = true,
				},
			},
			preview_results = {},
			boxes = nil,
			link = nil,
			preview_count = 0,
			dictionary_index = 1,
			search_text = text,
			dictionary_search_text = text,
			translation_source_text = text,
			selection_bounds = self:getHighlightSelectionBounds(highlight),
			dialog = highlight and highlight.dialog or (self.ui and self.ui.highlight and self.ui.highlight.dialog),
		}

		state.dict_close_callback = function()
			if highlight and type(highlight.clear) == "function" then
				pcall(function()
					highlight:clear()
				end)
			end
		end

		state.dictionary_payload = self:buildDictionaryPayload(text, state.results[1], 1, 0)
		return state
	end

	function LookupPreview:showSelectionPreviewFromHighlight(highlight, active_index)
		local state = self:buildSelectionStateFromHighlight(highlight)
		if not state then
			return false
		end

		-- Close the selection action popup before showing our floating carousel.
		if highlight and type(highlight.onClose) == "function" then
			pcall(function()
				highlight:onClose(true)
			end)
		end

		self:showCarousel(state, active_index or PAGE_DICTIONARY)
		schedulePreviewLoad(self, state, active_index)

		return true
	end

	function LookupPreview:beginNativeDictionaryPopup(dict_close_callback)
		self.native_dict_popup_count = (self.native_dict_popup_count or 0) + 1
		self.native_dict_popup_active = true

		local plugin = self
		local closed = false
		return function(...)
			if not closed then
				closed = true
				plugin.native_dict_popup_count = math.max(0, (plugin.native_dict_popup_count or 1) - 1)
				plugin.native_dict_popup_active = plugin.native_dict_popup_count > 0
			end
			if dict_close_callback then
				return dict_close_callback(...)
			end
		end
	end

	function LookupPreview:resetNativeDictionaryPopupGuard()
		self.native_dict_popup_count = 0
		self.native_dict_popup_active = false
	end

	function LookupPreview:showOriginalDictionaryPopup(dict_self, word, results, boxes, link, dict_close_callback)
		if not self.original_showDict then
			return true
		end

		self.opening_original_popup = true
		local wrapped_close_callback = self:beginNativeDictionaryPopup(dict_close_callback)
		local ok, err = pcall(function()
			self.original_showDict(dict_self, word, results, boxes, link, wrapped_close_callback)
		end)
		self.opening_original_popup = false

		if not ok then
			self:resetNativeDictionaryPopupGuard()
			logger.warn("LookupPreview: failed to open original dictionary popup:", err)
		end

		return true
	end

	function LookupPreview:closeCurrentPopup(preserve_state)
		self:closeLanguageMenu()
		if self.current_popup then
			if self.current_popup.closePageMenu then
				self.current_popup:closePageMenu()
			end
			self.current_popup.skip_close_callback = true
			pcall(function()
				UIManager:close(self.current_popup)
			end)
			self.current_popup = nil
		end
		if not preserve_state then
			self.current_state = nil
		end
	end

	function LookupPreview:clearOriginalHighlight(dict_self)
		local highlight = dict_self and dict_self.highlight
		if not highlight then
			return
		end

		local ok, clear_id = pcall(function()
			return highlight:getClearId()
		end)
		if ok and clear_id then
			pcall(function()
				highlight:clear(clear_id)
			end)
		else
			pcall(function()
				highlight:clear()
			end)
		end
		dict_self.highlight = nil
	end

	function LookupPreview:clearSelection()
		if self.ui and self.ui.handleEvent then
			pcall(function()
				self.ui:handleEvent(Event:new("ClearSelection"))
			end)
		end
	end

	function LookupPreview:getActiveHighlight(dict_self)
		local candidates = {}
		if dict_self and dict_self.highlight then
			candidates[#candidates + 1] = dict_self.highlight
		end
		if self.ui and self.ui.highlight then
			candidates[#candidates + 1] = self.ui.highlight
		end
		if dict_self and dict_self.ui and dict_self.ui.highlight then
			candidates[#candidates + 1] = dict_self.ui.highlight
		end

		local fallback
		for _, highlight in ipairs(candidates) do
			if highlight then
				if highlight.selected_text or highlight.hold_pos then
					return highlight
				end
				if
					not fallback
					and (
						type(highlight.showHighlightPrompt) == "function"
						or type(highlight.lookupWikipedia) == "function"
						or type(highlight.clear) == "function"
					)
				then
					fallback = highlight
				end
			end
		end
		return fallback
	end

	function LookupPreview:rememberSelection(dict_self)
		local highlight = self:getActiveHighlight(dict_self)
		if not highlight then
			self.selection_snapshot = nil
			return nil
		end

		if
			not highlight.selected_text
			and highlight.hold_pos
			and type(highlight.highlightFromHoldPos) == "function"
		then
			pcall(function()
				highlight:highlightFromHoldPos()
			end)
		end

		self.selection_snapshot = {
			highlight = highlight,
			selected_text = copyTable(highlight.selected_text),
			hold_pos = copyTable(highlight.hold_pos),
			selected_link = copyTable(highlight.selected_link),
			is_word_selection = highlight.is_word_selection,
		}

		return self.selection_snapshot
	end

	function LookupPreview:restoreSelection(dict_self)
		local snapshot = self.selection_snapshot
		local highlight = snapshot and snapshot.highlight or self:getActiveHighlight(dict_self)
		if not highlight then
			return nil
		end

		if snapshot then
			if snapshot.selected_text then
				highlight.selected_text = copyTable(snapshot.selected_text)
			end
			if snapshot.hold_pos then
				highlight.hold_pos = copyTable(snapshot.hold_pos)
			end
			if snapshot.selected_link then
				highlight.selected_link = copyTable(snapshot.selected_link)
			end
			highlight.is_word_selection = false
		end

		if
			not highlight.selected_text
			and highlight.hold_pos
			and type(highlight.highlightFromHoldPos) == "function"
		then
			pcall(function()
				highlight:highlightFromHoldPos()
			end)
		end

		return highlight
	end

	function LookupPreview:getSearchText(word, result)
		result = result or {}
		local text = word or result.word or ""
		if type(text) == "table" then
			text = text.text or text.word or ""
		end

		text = tostring(text or "")
		if util and util.stripPunctuation then
			local ok, stripped = pcall(function()
				return util.stripPunctuation(text)
			end)
			if ok and stripped and stripped ~= "" then
				text = stripped
			end
		end

		return trim(text)
	end

	function LookupPreview:showSearchDialog(search_text)
		search_text = trim(search_text)
		if search_text == "" then
			return true
		end

		local function openSearchInput()
			if self.ui and self.ui.search and type(self.ui.search.onShowFulltextSearchInput) == "function" then
				local ok, err = pcall(function()
					self.ui.search:onShowFulltextSearchInput(search_text)
				end)
				if ok then
					return true
				end
				logger.warn("LookupPreview: direct search input failed:", err)
			end

			if self.ui and self.ui.handleEvent then
				local ok, err = pcall(function()
					self.ui:handleEvent(Event:new("ShowFulltextSearchInput", search_text))
				end)
				if ok then
					return true
				end
				logger.warn("LookupPreview: search input event failed:", err)
			end

			if self.ui and self.ui.search and type(self.ui.search.searchText) == "function" then
				local ok, err = pcall(function()
					self.ui.search:searchText(search_text)
				end)
				if ok then
					return true
				end
				logger.warn("LookupPreview: direct search execution failed:", err)
			end

			if self.ui and self.ui.handleEvent then
				local ok, err = pcall(function()
					self.ui:handleEvent(Event:new("ShowSearchDialog", search_text, 0, false, true))
				end)
				if not ok then
					logger.warn("LookupPreview: search dialog fallback failed:", err)
				end
			end

			return true
		end

		local ok = pcall(function()
			UIManager:scheduleIn(0.05, openSearchInput)
		end)
		if not ok then
			openSearchInput()
		end

		return true
	end

	function LookupPreview:highlightSelection(dict_self, dict_close_callback)
		local highlight = self:restoreSelection(dict_self)
		if not highlight then
			return self:notify(_("No selection to highlight."))
		end

		if
			not highlight.selected_text
			and highlight.hold_pos
			and type(highlight.highlightFromHoldPos) == "function"
		then
			pcall(function()
				highlight:highlightFromHoldPos()
			end)
		end

		if not (highlight.selected_text and highlight.selected_text.pos0 and highlight.selected_text.pos1) then
			return self:notify(_("No selection to highlight."))
		end

		UIManager:scheduleIn(0.05, function()
			local ok, err = pcall(function()
				if type(highlight.showHighlightPrompt) == "function" then
					highlight:showHighlightPrompt(function(...)
						self.selection_snapshot = nil
						callIfPresent(dict_close_callback, ...)
					end)
				elseif type(highlight.saveHighlight) == "function" then
					local index = highlight:saveHighlight(true)
					if type(highlight.clear) == "function" then
						highlight:clear()
					end
					self.selection_snapshot = nil
					callIfPresent(dict_close_callback, index)
				end
			end)

			if not ok then
				logger.warn("LookupPreview: highlight action failed:", err)
			end
		end)

		return true
	end

	function LookupPreview:lookupWikipedia(dict_self, search_text)
		local highlight = self:restoreSelection(dict_self)

		if
			highlight
			and type(highlight.lookupWikipedia) == "function"
			and (highlight.selected_text or highlight.hold_pos)
		then
			UIManager:scheduleIn(0.05, function()
				local ok, err = pcall(function()
					if
						not highlight.selected_text
						and highlight.hold_pos
						and type(highlight.highlightFromHoldPos) == "function"
					then
						highlight:highlightFromHoldPos()
					end
					highlight:lookupWikipedia()
					self.selection_snapshot = nil
				end)

				if not ok then
					logger.warn("LookupPreview: Wikipedia action failed:", err)
				end
			end)
			return true
		end

		search_text = trim(search_text)
		if search_text ~= "" and self.ui and self.ui.handleEvent then
			self.ui:handleEvent(Event:new("LookupWikipedia", search_text))
			return true
		end

		return self:notify(_("No selection to look up."))
	end

	function LookupPreview:runLeftButtonAction(action, state, search_text)
		if not state then
			return true
		end

		action = normalizeLeftAction(action)
		self:closeCurrentPopup(true)
		self.current_state = nil

		if action == LEFT_ACTION_HIGHLIGHT then
			return self:highlightSelection(state.dict_self, state.dict_close_callback)
		end

		self.selection_snapshot = nil
		self:clearOriginalHighlight(state.dict_self)
		self:clearSelection()
		callIfPresent(state.dict_close_callback)
		return self:showSearchDialog(search_text)
	end
end
