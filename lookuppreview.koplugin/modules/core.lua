-- Lookup Preview: plugin lifecycle, settings, KOReader hooks and selection helpers.
return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	local function callIfPresent(callback, ...)
		if callback then
			return pcall(callback, ...)
		end
	end

	local function refreshTranslationPayloadIfLoaded(plugin)
		local state = plugin.current_state
		if state and state.translation_payload then
			state.translation_payload = plugin:buildTranslationPayload(state)
			plugin:refreshCurrentPage(PAGE_TRANSLATION)
		end
	end

	local DETAILS_BUTTONS_MODES = {
		[DETAILS_BUTTONS_BOTH] = true,
		[DETAILS_BUTTONS_KOREADER] = true,
		[DETAILS_BUTTONS_EXPLORER] = true,
	}

	local function normalizeDetailsButtons(mode)
		return DETAILS_BUTTONS_MODES[mode] and mode or DEFAULT_DETAILS_BUTTONS
	end

	local function applyCardStyleMode(plugin, rounded)
		plugin:setRoundedCards(rounded)
		return plugin:refreshVisibleCards()
	end

	local function applyCardShadowMode(plugin, enabled)
		plugin:setCardShadows(enabled)
		return plugin:reopenCarousel()
	end

	-- Tabs make the row taller than full cards, so an open carousel is shown
	-- again, placed for its new height.
	local function applySidePreviewMode(plugin, mode)
		plugin:setSidePreviewMode(mode)
		return plugin:reopenCarousel()
	end

	local function applyOnlineCardLoadMode(plugin, mode)
		plugin:setOnlineCardLoadMode(mode)
		return plugin:refreshVisibleCards()
	end

	local function applyDictionaryHtmlMode(plugin, mode)
		plugin:setDictionaryHtmlMode(mode)
		local state = plugin.current_state
		if state and getLoadStatus(state, PAGE_DICTIONARY) == LOAD_DONE then
			plugin:updateDictionaryPayload(state, state.dictionary_index)
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
		-- See runOnlineQuery in utils.lua.
		self.online_queries_in_subprocess = jit.os ~= "OSX"

		if self.ui and self.ui.menu then
			self.ui.menu:registerToMainMenu(self)
		end

		self:patchDictionary()
		self:patchHighlightActions()
	end

	function LookupPreview:addToMainMenu(menu_items)
		local version = plugin_meta and plugin_meta.version or "?"
		local card_corners_item = {
			text_func = function()
				local mode = self:useRoundedCards() and _("Rounded") or _("Square")
				return string.format("%s: %s", _("Card corners"), mode)
			end,
			help_text = _("Choose square or rounded corners for the preview cards."),
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
		}

		local cards_item = {
			text = _("Cards"),
			help_text = _(
				"Choose which cards the carousel shows and in which order, and which card a lookup from the book opens on. A hidden card's action (Dictionary, Translate or Wikipedia) opens KOReader's own window instead."
			),
			sub_item_table = {
				{
					text = _("Show and order cards"),
					keep_menu_open = true,
					callback = function()
						return self:showCardOrderDialog()
					end,
					separator = true,
				},
				{
					text = _("Open on the dictionary card"),
					help_text = _("A long press on a word opens the carousel on the Dictionary card."),
					radio = true,
					checked_func = function()
						return self:getOpenCardMode() == OPEN_CARD_DICTIONARY
					end,
					callback = function()
						G_reader_settings:saveSetting(SETTING_OPEN_CARD, OPEN_CARD_DICTIONARY)
					end,
				},
				{
					text = _("Open on the last card used"),
					help_text = _(
						"A long press on a word opens the carousel on the card that was shown when it was last closed. Translate and Wikipedia from the selection menu still open on their own card."
					),
					radio = true,
					checked_func = function()
						return self:getOpenCardMode() == OPEN_CARD_LAST
					end,
					callback = function()
						G_reader_settings:saveSetting(SETTING_OPEN_CARD, OPEN_CARD_LAST)
					end,
				},
			},
		}

		local card_height_item = {
			text_func = function()
				local mode = self:getCardHeightMode() == CARD_HEIGHT_EXPANDED and _("Expanded") or _("Compact")
				return string.format("%s: %s", _("Card height"), mode)
			end,
			help_text = _(
				"Choose how tall the cards open. Spreading two fingers on a card expands it and pinching makes it compact again, for that lookup."
			),
			sub_item_table = {
				{
					text = _("Compact"),
					radio = true,
					checked_func = function()
						return self:getCardHeightMode() == CARD_HEIGHT_COMPACT
					end,
					callback = function()
						self:setCardHeightMode(CARD_HEIGHT_COMPACT)
						return self:reopenCarousel()
					end,
				},
				{
					text = _("Expanded"),
					radio = true,
					checked_func = function()
						return self:getCardHeightMode() == CARD_HEIGHT_EXPANDED
					end,
					callback = function()
						self:setCardHeightMode(CARD_HEIGHT_EXPANDED)
						return self:reopenCarousel()
					end,
				},
			},
		}

		local text_size_item = {
			text_func = function()
				return string.format("%s: %d", _("Text size"), self:getTextSize())
			end,
			help_text = _("Choose the size of the text of the cards' content."),
			sub_item_table_func = function()
				local items = {}
				local default_label = _("default")
				for size_index = 1, #TEXT_SIZES do
					local size = TEXT_SIZES[size_index]
					items[#items + 1] = {
						text = size == DEFAULT_TEXT_SIZE and string.format("%d (%s)", size, default_label) or tostring(size),
						radio = true,
						checked_func = function()
							return self:getTextSize() == size
						end,
						callback = function()
							G_reader_settings:saveSetting(SETTING_TEXT_SIZE, size)
							return self:refreshVisibleCards()
						end,
					}
				end
				return items
			end,
		}

		local side_previews_item = {
			text_func = function()
				local mode = self:useTabsMode() and _("Tabs") or _("Full cards")
				return string.format("%s: %s", _("Side card previews"), mode)
			end,
			help_text = _("Choose how the other available cards (dictionary, translation, Wikipedia) are shown beside the active one."),
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
		}

		local online_loading_item = {
			text_func = function()
				local mode = self:useManualOnlineCardLoading() and _("Manual only") or _("Automatic")
				return string.format("%s: %s", _("Online card loading"), mode)
			end,
			help_text = _("Choose whether translation and Wikipedia cards load automatically or only when you open them."),
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
		}

		local dictionary_html_item = {
			text_func = function()
				local mode = self:useFastRawDictionaryHtml() and _("Fast / Raw") or _("Formatted")
				return string.format("%s: %s", _("Dictionary HTML"), mode)
			end,
			help_text = _("Choose between fully formatted dictionary entries or a faster, minimally styled rendering."),
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
		}

		local details_buttons_item = {
			text_func = function()
				local labels = {
					[DETAILS_BUTTONS_BOTH] = _("Both"),
					[DETAILS_BUTTONS_KOREADER] = _("KOReader popup"),
					[DETAILS_BUTTONS_EXPLORER] = _("Dictionary Explorer"),
				}
				return string.format("%s: %s", _("Dictionary buttons"), labels[self:getDetailsButtonsMode()])
			end,
			help_text = _(
				"Choose which buttons open the full dictionary from the dictionary card: KOReader's original popup, the Dictionary Explorer at the word, or both. Dictionary Explorer must be installed; without it, or for a dictionary it can't open, the KOReader popup button is shown."
			),
			sub_item_table_func = function()
				local items = {}
				local options = {
					{ mode = DETAILS_BUTTONS_KOREADER, label = _("KOReader popup only") },
					{ mode = DETAILS_BUTTONS_EXPLORER, label = _("Dictionary Explorer only"), needs_explorer = true },
					{ mode = DETAILS_BUTTONS_BOTH, label = _("Both"), needs_explorer = true },
				}
				for option_index = 1, #options do
					local option = options[option_index]
					items[#items + 1] = {
						text = option.label,
						radio = true,
						enabled_func = function()
							return not option.needs_explorer or self:getDictionaryExplorer() ~= nil
						end,
						checked_func = function()
							return self:getDetailsButtonsMode() == option.mode
						end,
						callback = function()
							self:setDetailsButtonsMode(option.mode)
							self:refreshCurrentPage(PAGE_DICTIONARY)
						end,
					}
				end
				if not self:getDictionaryExplorer() then
					items[#items + 1] = {
						text = _("Dictionary Explorer is not installed or is too old."),
						enabled = false,
					}
				end
				return items
			end,
		}

		local translation_item = {
			text = _("Translation"),
			help_text = _("Choose the target language, whether the original text is shown, and which card buttons appear."),
			sub_item_table = {
				{
					text_func = function()
						return string.format("%s: %s", _("Target language"), self:getTranslationTargetLang())
					end,
					help_text = _("Choose the language translations are shown in."),
					sub_item_table_func = function()
						return self:getTargetLanguageMenuItems(self.current_state)
					end,
				},
				{
					text = _("Show source text"),
					help_text = _("Shows the original selected text below its translation."),
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
					help_text = _("Choose which action buttons appear on the translation card."),
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
		}

		menu_items.lookuppreview = {
			text = _("Lookup preview"),
			sorting_hint = "tools",
			sub_item_table = {
				{
					text = _("Enable lookup preview"),
					help_text = _("Turns the floating lookup preview on or off without removing the plugin."),
					checked_func = function()
						return self:isPreviewEnabled()
					end,
					callback = function()
						self:setPreviewEnabled(not self:isPreviewEnabled())
					end,
					separator = true,
				},
				{
					text = _("Appearance"),
					help_text = _("Choose the card corner style, side card previews, shadows, and custom icon filenames."),
					sub_item_table = {
						card_corners_item,
						side_previews_item,
						card_height_item,
						text_size_item,
						{
							text = _("Show card shadows"),
							help_text = _(
								"Show matching dithered shadows along the right and bottom edges of preview cards."
							),
							checked_func = function()
								return self:showCardShadows()
							end,
							callback = function()
								return applyCardShadowMode(self, not self:showCardShadows())
							end,
						},
						{
							text = _("Custom icon filenames"),
							help_text = _("Lists the SVG and PNG filenames accepted from the plugin's icons folder."),
							sub_item_table_func = function()
								return self:getExpectedIconFilenamesMenu()
							end,
						},
					},
				},
				{
					text = _("Content"),
					help_text = _("Choose how online cards load, dictionary HTML rendering, and Wikipedia/translation language and buttons."),
					separator = true,
					sub_item_table = {
						cards_item,
						online_loading_item,
						dictionary_html_item,
						details_buttons_item,
						{
							text = _("Show vocabulary builder button"),
							help_text = _(
								"Shows a button on the dictionary card that adds the word to KOReader's vocabulary builder, like the one in KOReader's dictionary popup. It is not shown when the vocabulary builder adds every looked up word by itself."
							),
							enabled_func = function()
								return self:getVocabularyBuilder() ~= nil
							end,
							checked_func = function()
								return G_reader_settings:nilOrTrue(SETTING_DICTIONARY_VOCABULARY_BUTTON)
							end,
							callback = function()
								G_reader_settings:saveSetting(
									SETTING_DICTIONARY_VOCABULARY_BUTTON,
									not G_reader_settings:nilOrTrue(SETTING_DICTIONARY_VOCABULARY_BUTTON)
								)
								self:refreshCurrentPage(PAGE_DICTIONARY)
							end,
						},
						{
							text_func = function()
								return string.format("%s: %s", _("Wikipedia language"), self:getWikipediaLang())
							end,
							help_text = _("Choose the language Wikipedia articles are shown in."),
							sub_item_table_func = function()
								return self:getWikipediaLanguageMenuItems(self.current_state)
							end,
						},
						translation_item,
					},
				},
				{
					text = string.format("%s: %s", _("Version"), version),
					callback = function()
						self:notify(string.format("%s %s", _("Lookup Preview"), version))
					end,
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

	function LookupPreview:showCardShadows()
		return G_reader_settings:nilOrTrue(SETTING_CARD_SHADOWS)
	end

	function LookupPreview:setCardShadows(enabled)
		G_reader_settings:saveSetting(SETTING_CARD_SHADOWS, enabled and true or false)
	end

	-- Cards ----------------------------------------------------------------------
	-- The cards are always the three of CARD_IDS; the settings give their order
	-- and which are hidden. A hidden card's action is left to KOReader.

	function LookupPreview:getCardOrder()
		local saved = G_reader_settings:readSetting(SETTING_CARD_ORDER)
		local order, seen = {}, {}
		if type(saved) == "table" then
			for position = 1, #saved do
				local id = tonumber(saved[position])
				if id and PAGE_TITLES[id] and not seen[id] then
					order[#order + 1] = id
					seen[id] = true
				end
			end
		end
		for position = 1, #CARD_IDS do
			if not seen[CARD_IDS[position]] then
				order[#order + 1] = CARD_IDS[position]
			end
		end
		return order
	end

	function LookupPreview:isCardShown(id)
		local hidden = G_reader_settings:readSetting(SETTING_HIDDEN_CARDS)
		return not (type(hidden) == "table" and hidden[tostring(id)])
	end

	-- The cards shown, in order (all of them if every one was hidden).
	function LookupPreview:getVisibleCards()
		local order = self:getCardOrder()
		local cards = {}
		for position = 1, #order do
			if self:isCardShown(order[position]) then
				cards[#cards + 1] = order[position]
			end
		end
		return #cards > 0 and cards or order
	end

	-- The card shown before (step -1) or after (step 1) card `id`, if any.
	function LookupPreview:getNeighborCard(id, step, cards)
		cards = cards or self:getVisibleCards()
		for position = 1, #cards do
			if cards[position] == id then
				return cards[position + step]
			end
		end
		return nil
	end

	-- `id` when it is shown, or else the first card shown.
	function LookupPreview:normalizeCard(id)
		local cards = self:getVisibleCards()
		for position = 1, #cards do
			if cards[position] == id then
				return id
			end
		end
		return cards[1]
	end

	function LookupPreview:getOpenCardMode()
		return G_reader_settings:readSetting(SETTING_OPEN_CARD) == OPEN_CARD_LAST and OPEN_CARD_LAST
			or OPEN_CARD_DICTIONARY
	end

	-- The card a lookup from the book opens on.
	function LookupPreview:getOpenCard()
		if self:getOpenCardMode() == OPEN_CARD_LAST then
			local last = tonumber(G_reader_settings:readSetting(SETTING_LAST_CARD))
			if last and self:isCardShown(last) then
				return last
			end
		end
		return self:normalizeCard(PAGE_DICTIONARY)
	end

	-- Sorting and showing or hiding the cards, with KOReader's SortWidget (as
	-- for its dictionaries). At least one card stays shown.
	function LookupPreview:showCardOrderDialog()
		local SortWidget = require("ui/widget/sortwidget")
		local hidden = {}
		for position = 1, #CARD_IDS do
			hidden[CARD_IDS[position]] = not self:isCardShown(CARD_IDS[position])
		end

		local items = {}
		local order = self:getCardOrder()
		for position = 1, #order do
			local id = order[position]
			items[#items + 1] = {
				text = PAGE_TITLES[id],
				id = id,
				checked_func = function()
					return not hidden[id]
				end,
				callback = function()
					hidden[id] = not hidden[id]
				end,
			}
		end

		UIManager:show(SortWidget:new({
			title = _("Show and order cards"),
			item_table = items,
			callback = function()
				local new_order, new_hidden, shown = {}, {}, 0
				for position = 1, #items do
					local id = items[position].id
					new_order[#new_order + 1] = id
					if hidden[id] then
						new_hidden[tostring(id)] = true
					else
						shown = shown + 1
					end
				end
				if shown == 0 then
					return self:notify(_("At least one card must be shown."))
				end
				G_reader_settings:saveSetting(SETTING_CARD_ORDER, new_order)
				G_reader_settings:saveSetting(SETTING_HIDDEN_CARDS, new_hidden)
				return self:reopenCarousel()
			end,
		}))
		return true
	end

	function LookupPreview:getCardHeightMode()
		local mode = G_reader_settings:readSetting(SETTING_CARD_HEIGHT)
		return mode == CARD_HEIGHT_EXPANDED and CARD_HEIGHT_EXPANDED or CARD_HEIGHT_COMPACT
	end

	function LookupPreview:setCardHeightMode(mode)
		G_reader_settings:saveSetting(SETTING_CARD_HEIGHT, mode == CARD_HEIGHT_EXPANDED and mode or CARD_HEIGHT_COMPACT)
	end

	-- Whether the cards of a lookup are expanded: as set by a spread or pinch
	-- on the carousel showing it, or else as the setting says.
	function LookupPreview:isCardExpanded(state)
		local root = getRootState(state)
		if root and root.card_expanded ~= nil then
			return root.card_expanded
		end
		return self:getCardHeightMode() == CARD_HEIGHT_EXPANDED
	end

	function LookupPreview:getCardHeightRatio(state)
		return self:isCardExpanded(state) and CARD_EXPANDED_HEIGHT_RATIO or CARD_HEIGHT_RATIO
	end

	-- Expands or compacts the cards of the open lookup (and of the lookups made
	-- inside it). The carousel is shown again at its new height; each card
	-- keeps the same proportion of its content in view.
	function LookupPreview:setCardExpanded(expanded)
		local state = self.current_state
		if not state or self:isCardExpanded(state) == expanded then
			return true
		end
		getRootState(state).card_expanded = expanded
		return self:reopenCarousel()
	end

	function LookupPreview:getTextSize()
		local size = tonumber(G_reader_settings:readSetting(SETTING_TEXT_SIZE))
		return size and size > 0 and size or DEFAULT_TEXT_SIZE
	end

	function LookupPreview:getBodyFontSize()
		return Screen:scaleBySize(self:getTextSize())
	end

	-- Shows the open carousel again from scratch, for changes that move or
	-- resize it. The lookup and its scroll positions are kept. When the active
	-- card is no longer shown (hidden in the settings), another one takes its
	-- place, and is loaded if it never was.
	function LookupPreview:reopenCarousel()
		local state = self.current_state
		if not (state and self.current_popup) then
			return true
		end
		local active_index = state.active_index or PAGE_DICTIONARY
		self:closeCurrentPopup(true)
		self:showCarousel(state, active_index)
		self:scheduleCardLoad(state, state.active_index)
		return true
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

	-- Dictionary Explorer, when installed and recent enough to be opened from
	-- another plugin.
	function LookupPreview:getDictionaryExplorer()
		local explorer = self.ui and self.ui.dictionaryexplorer
		if explorer and type(explorer.openWord) == "function" and type(explorer.canOpen) == "function" then
			return explorer
		end
		return nil
	end

	-- KOReader's Vocabulary Builder, when enabled. Plugins are registered on the
	-- UI by their folder name (vocabbuilder.koplugin), not their own `name`.
	-- Words reach it through its WordLookedUp event, as from KOReader's popup.
	function LookupPreview:getVocabularyBuilder()
		local vocabulary_builder = self.ui and self.ui.vocabbuilder
		return type(vocabulary_builder) == "table" and vocabulary_builder or nil
	end

	-- Whether the Vocabulary Builder adds every looked up word by itself, in
	-- which case it shows no button in KOReader's popup, and neither do we.
	function LookupPreview:vocabularyAddsAutomatically()
		local settings = G_reader_settings:readSetting("vocabulary_builder")
		return type(settings) == "table" and settings.enabled == true
	end

	function LookupPreview:showVocabularyButton()
		return G_reader_settings:nilOrTrue(SETTING_DICTIONARY_VOCABULARY_BUTTON)
			and self:getVocabularyBuilder() ~= nil
			and not self:vocabularyAddsAutomatically()
	end

	function LookupPreview:getDetailsButtonsMode()
		return normalizeDetailsButtons(G_reader_settings:readSetting(SETTING_DICTIONARY_DETAILS_BUTTONS))
	end

	function LookupPreview:setDetailsButtonsMode(mode)
		G_reader_settings:saveSetting(SETTING_DICTIONARY_DETAILS_BUTTONS, normalizeDetailsButtons(mode))
	end

	function LookupPreview:getPluginIconFile(icon_id)
		self.plugin_icon_cache = self.plugin_icon_cache or {}
		if self.plugin_icon_cache[icon_id] ~= nil then
			return self.plugin_icon_cache[icon_id] or nil
		end

		local candidates = PLUGIN_ICON_CANDIDATES[icon_id]
		if not candidates or not self.path or self.path == "" then
			self.plugin_icon_cache[icon_id] = false
			return nil
		end

		local icons_dir = self.path .. "/icons"
		for _, basename in ipairs(candidates) do
			for _, ext in ipairs(PLUGIN_ICON_EXTENSIONS) do
				local path = icons_dir .. "/" .. basename .. ext
				if fileExists(path) then
					self.plugin_icon_cache[icon_id] = path
					return path
				end
			end
		end

		self.plugin_icon_cache[icon_id] = false
		return nil
	end

	function LookupPreview:getExpectedIconFilenamesMenu()
		local items = {}
		for definition_index, definition in ipairs(PLUGIN_ICON_DEFINITIONS) do
			local accepted = {}
			for _, basename in ipairs(definition.basenames) do
				for _, extension in ipairs(PLUGIN_ICON_EXTENSIONS) do
					accepted[#accepted + 1] = basename .. extension
				end
			end

			local primary = definition.basenames[1]
			items[#items + 1] = {
				id = "lookuppreview_icon_filename_" .. tostring(definition_index),
				text = definition.label .. ": " .. primary .. ".svg",
				help_text = _("Accepted filenames") .. ": " .. table.concat(accepted, ", "),
				enabled = false,
			}
		end
		return items
	end

	function LookupPreview:getLoadingButtonSpec()
		local icon_file = self:getPluginIconFile(ICON_LOADING)
		if icon_file then
			return { icon_file = icon_file }
		end
		return { text = _("Loading…") }
	end

	function LookupPreview:notify(message)
		UIManager:show(Notification:new({ text = message }))
		return true
	end

	function LookupPreview:destroy()
		self:closeLanguageMenu()
		self:closeCurrentPopup(true)
		if self.endDictionaryCapture then
			self:endDictionaryCapture()
		end

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
			-- The lookup the dictionary card asked for (see loadDictionary). Any
			-- other word is a lookup of its own and goes the usual way.
			local capture = not plugin.opening_original_popup and plugin:findDictionaryCapture(word)
			if capture then
				return plugin:receiveDictionaryResults(capture, dict_self, word, results)
			end

			if
				not plugin:isPreviewEnabled()
				or not plugin:isCardShown(PAGE_DICTIONARY)
				or plugin.opening_original_popup
				or not results
				or not results[1]
			then
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
				if
					not plugin:isPreviewEnabled()
					or not plugin:isCardShown(PAGE_TRANSLATION)
					or plugin.opening_original_popup
				then
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
				if
					not plugin:isPreviewEnabled()
					or not plugin:isCardShown(PAGE_WIKIPEDIA)
					or plugin.opening_original_popup
				then
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
			-- The dictionary card looks the text up when it is first shown.
			results = {},
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
			load = { [PAGE_DICTIONARY] = { status = LOAD_IDLE } },
		}

		state.dict_close_callback = function()
			if highlight and type(highlight.clear) == "function" then
				pcall(function()
					highlight:clear()
				end)
			end
		end

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
		self:scheduleCardLoad(state, state.active_index)

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
		local state = self.current_state
		if self.current_popup and state and state.active_index then
			G_reader_settings:saveSetting(SETTING_LAST_CARD, state.active_index)
		end
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
end
