return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	local MENU_HORIZONTAL_MARGIN = Screen:scaleBySize(80)
	local MENU_HEIGHT_RATIO = 0.8
	local TRANSLATION_RELOAD_DELAY = 0.05

	-- isNetworkUnavailable and onlineLookupError are shared globals defined in
	-- modules/utils.lua (also used by wikipedia.lua).

	local function normalizeLanguageCode(lang, fallback)
		lang = tostring(lang or fallback or "en"):lower()
		return lang ~= "" and lang or (fallback or "en")
	end

	local function getSavedTargetLanguage()
		return normalizeLanguageCode(
			G_reader_settings:readSetting("translator_to_language")
				or (Translator.getTargetLanguage and Translator:getTargetLanguage())
				or "en",
			"en"
		)
	end

	local function getTargetLanguage(state)
		return normalizeLanguageCode((state and state.translation_target_lang) or getSavedTargetLanguage(), "en")
	end

	-- The language chosen on the card for this lookup wins over the detected
	-- one and over KOReader's setting.
	local function getSourceLanguage(state)
		return (state and state.translation_source_choice)
			or (state and state.translation_source_lang)
			or (Translator.getSourceLanguage and Translator:getSourceLanguage())
			or G_reader_settings:readSetting("translator_from_language")
			or "auto"
	end

	local function resetTranslationState(state, target_lang)
		state.translation_target_lang = target_lang
		state.translation_payload = nil
		state.translation_text_main = nil
		state.translation_source_lang = nil
		setLoadStatus(state, PAGE_TRANSLATION, LOAD_IDLE)
	end

	-- After a change of language: loadTranslation decides whether to query (or
	-- use what is cached) or to wait for the Load button.
	local function scheduleTranslationReload(plugin, state)
		UIManager:scheduleIn(TRANSLATION_RELOAD_DELAY, function()
			plugin:loadTranslation(state)
		end)
	end

	local function getMenuDimensions()
		return Screen:getWidth() - MENU_HORIZONTAL_MARGIN, math.floor(Screen:getHeight() * MENU_HEIGHT_RATIO)
	end

	-- The text translated is shown below the translation when the setting asks
	-- for it, and always when it is the sentence rather than the selection.
	local function appendSourceBlock(plugin, parts, source_text, always)
		if not (always or plugin:showTranslationSourceText()) then
			return
		end

		parts[#parts + 1] = '<div class="lp-source-label">' .. htmlEscape(_("Source")) .. "</div>"
		parts[#parts + 1] = '<div class="lp-source">' .. plainTextToHtml(source_text) .. "</div>"
	end

	local function cleanupSelectionAfterNativeTranslation(plugin, state)
		plugin.selection_snapshot = nil
		plugin:clearOriginalHighlight(state.dict_self)
		plugin:clearSelection()
		if state.dict_close_callback then
			pcall(state.dict_close_callback)
		end
	end

	local function copyTranslatorMenuItem(plugin, state, translator, menu_item)
		return {
			text = menu_item.text,
			text_func = menu_item.text_func,
			checked_func = menu_item.checked_func,
			enabled_func = menu_item.enabled_func,
			radio = menu_item.radio,
			separator = menu_item.separator,
			callback = function()
				if menu_item.callback then
					menu_item.callback()
				end

				return plugin:refreshTranslationWithTarget(state, translator:getTargetLanguage())
			end,
		}
	end

	local function extractTargetLanguageItems(translator)
		local ok, settings_menu = pcall(function()
			return translator:genSettingsMenu()
		end)
		if not ok or not settings_menu or type(settings_menu.sub_item_table) ~= "table" then
			return nil
		end

		for i = #settings_menu.sub_item_table, 1, -1 do
			local item = settings_menu.sub_item_table[i]
			if type(item) == "table" and type(item.sub_item_table) == "table" then
				return item.sub_item_table
			end
		end

		return nil
	end

	function LookupPreview:closeLanguageMenu()
		if not self.language_menu then
			return
		end

		pcall(function()
			UIManager:close(self.language_menu)
		end)
		self.language_menu = nil
	end

	function LookupPreview:getTranslationTargetLang()
		return getSavedTargetLanguage()
	end

	function LookupPreview:buildTranslationPayload(state)
		state = state or self.current_state or {}

		local text_main = state.translation_text_main or _("No translation found.")
		local source_text = state.translation_source_text or state.search_text or ""
		-- A source language chosen on the card is the one used, whatever the
		-- service says it detected.
		local choice = state.translation_source_choice
		local source_lang = (choice and choice ~= "auto" and choice) or state.translation_source_lang or "auto"
		local target_lang = getTargetLanguage(state)
		local source_name = self:getTranslatorLanguageLabel(Translator, source_lang)
		local target_name = self:getTranslatorLanguageLabel(Translator, target_lang)
		local parts = {
			'<div class="lp-translation">' .. plainTextToHtml(text_main) .. "</div>",
		}

		appendSourceBlock(self, parts, source_text, state.translation_use_sentence)

		return {
			page_type = PAGE_TRANSLATION,
			title = _("Translate"),
			subtitle = string.format("%s → %s ▾", source_name, target_name),
			subtitle_callback = function()
				return self:showTargetLanguageMenu(state)
			end,
			subtitle_hint = _("Choose the languages to translate from and into"),
			html_body = table.concat(parts, "\n"),
			css = FALLBACK_CSS,
		}
	end

	-- Sentence ends: the text after the last one before the selection, and up
	-- to the first one after it, make the sentence. Abbreviations ("Mr.") can
	-- cut it short; that is the price of not parsing the language.
	local SENTENCE_ENDS = { "%.", "!", "%?", "…", "。", "！", "？" }
	local SENTENCE_CONTEXT_WORDS = 40

	local function textAfterLastSentenceEnd(text)
		local cut = 0
		for _, mark in ipairs(SENTENCE_ENDS) do
			local position = 1
			while true do
				local finish = select(2, text:find(mark .. "%S*%s+", position))
				if not finish then
					break
				end
				cut = math.max(cut, finish)
				position = finish + 1
			end
		end
		return text:sub(cut + 1)
	end

	local function textUpToFirstSentenceEnd(text)
		local cut
		for _, mark in ipairs(SENTENCE_ENDS) do
			local finish = select(2, text:find(mark .. "%S*"))
			if finish and (not cut or finish < cut) then
				cut = finish
			end
		end
		return cut and text:sub(1, cut) or text
	end

	local function hasPreviousWord(document, position)
		if type(document.getPrevVisibleWordStart) ~= "function" then
			return true
		end
		local ok, previous = pcall(document.getPrevVisibleWordStart, document, position)
		return not ok or previous ~= nil
	end

	-- A text as far as translating it goes: without the punctuation around it
	-- (a final period, quotes), extra spaces or case. A selection that is the
	-- sentence but for those offers no sentence button: it would translate the
	-- same thing.
	local function comparableText(text)
		text = trim(tostring(text or ""):gsub("%s+", " "))
		if util and util.stripPunctuation then
			local ok, stripped = pcall(util.stripPunctuation, text)
			if ok and stripped then
				text = trim(stripped)
			end
		end
		local ok, Utf8Proc = pcall(require, "ffi/utf8proc")
		if ok and Utf8Proc and Utf8Proc.lowercase then
			local lowered_ok, lowered = pcall(Utf8Proc.lowercase, text)
			if lowered_ok and lowered then
				return lowered
			end
		end
		return text:lower()
	end

	-- The sentence around the text selected in the book, when the document
	-- can tell (reflowable books) and it is more than the selection. Only for
	-- the lookup that opened the carousel: one made inside it has no place in
	-- the book.
	function LookupPreview:getSelectionSentence(state)
		if not state or state.parent then
			return nil
		end
		if state.translation_sentence ~= nil then
			return state.translation_sentence or nil
		end
		state.translation_sentence = false

		local document = self.ui and self.ui.rolling and self.ui.document
		local snapshot = self.selection_snapshot
		local selected = snapshot and snapshot.selected_text
		if not (document and type(document.getSelectedWordContext) == "function" and selected and selected.pos0 and selected.pos1) then
			return nil
		end

		local ok, before, after = pcall(
			document.getSelectedWordContext,
			document,
			selected.text,
			SENTENCE_CONTEXT_WORDS,
			selected.pos0,
			selected.pos1,
			true
		)
		if not ok then
			return nil
		end
		-- With no word before the selection, KOReader still returns the text at
		-- its first position, which is the selection's own: there is nothing
		-- before. (The end is exclusive, so what follows it is real context,
		-- such as the final period.)
		if not hasPreviousWord(document, selected.pos0) then
			before = ""
		end

		local selection = trim(selected.text or "")
		local sentence = trim(
			(textAfterLastSentenceEnd(before or "") .. selection .. textUpToFirstSentenceEnd(after or "")):gsub("%s+", " ")
		)
		if sentence ~= "" and #sentence > #selection and comparableText(sentence) ~= comparableText(selection) then
			state.translation_sentence = sentence
		end
		return state.translation_sentence or nil
	end

	-- Switches the card between translating the selection and the sentence.
	function LookupPreview:toggleTranslationSentence(state)
		if not state or state ~= self.current_state or not self:getSelectionSentence(state) then
			return true
		end
		state.translation_use_sentence = not state.translation_use_sentence
		state.translation_source_lang = nil
		state.translation_text_main = nil
		state.translation_payload = nil
		setLoadStatus(state, PAGE_TRANSLATION, LOAD_IDLE)
		return self:requestTranslationLoad(state)
	end

	-- Copy and Note only when there is a translation; the native view is always
	-- offered, as it may show more than the card.
	function LookupPreview:buildTranslationButtons(state)
		if not state then
			return nil
		end

		local buttons = {}
		local text_main = state.translation_text_main

		if text_main and self.clipboard_available and self:showTranslationCopyButton() then
			buttons[#buttons + 1] = {
				spec = { plugin_icon = ICON_COPY, text = _("Copy") },
				hint = _("Copy the translation to the clipboard"),
				callback = function()
					return self:copyMainTranslation(text_main)
				end,
			}
		end

		-- The note goes on the book's selection, which is not what a lookup made
		-- inside the preview translated.
		if text_main and not state.parent and self:showTranslationNoteButton() then
			buttons[#buttons + 1] = {
				spec = { plugin_icon = ICON_ADD_NOTE, text = _("Note") },
				hint = _("Save the translation as a note on the highlight"),
				callback = function()
					return self:saveMainTranslationToNote(text_main)
				end,
			}
		end

		if self:getSelectionSentence(state) then
			-- The icon shows what a tap does: the sentence (several lines) while
			-- the selection is translated, the selection (short lines) while the
			-- sentence is. The text is only for a missing icon file.
			local use_sentence = state.translation_use_sentence
			buttons[#buttons + 1] = {
				spec = {
					plugin_icon = use_sentence and ICON_TRANSLATE_SELECTION or ICON_TRANSLATE_SENTENCE,
					text = _("Sentence"),
					bold = use_sentence and true or false,
				},
				hint = use_sentence and _("Translate only the selected text") or _("Translate the whole sentence"),
				callback = function()
					return self:toggleTranslationSentence(state)
				end,
			}
		end

		buttons[#buttons + 1] = {
			spec = { plugin_icon = ICON_DETAILS, icon = ICON_DETAILS_FALLBACK },
			hint = _("Open KOReader's original translator view"),
			callback = function()
				return self:openOriginalTranslationFromState(state)
			end,
		}

		return buttons
	end

	-- `refresh` (the Retry button) queries again even when the answer is cached.
	function LookupPreview:buildTranslationManualLoadButtons(state, label, refresh)
		return {
			{
				spec = { plugin_icon = refresh and ICON_RETRY or ICON_LOAD, text = label or _("Load") },
				hint = _("Query the translation service"),
				callback = function()
					return self:requestTranslationLoad(state, refresh)
				end,
			},
		}
	end

	function LookupPreview:buildTranslationLoadingButtons()
		return {
			{
				spec = self:getLoadingButtonSpec(),
				hint = _("Loading…"),
			},
		}
	end

	-- What the Load and Retry buttons do: show the card loading, then query.
	function LookupPreview:requestTranslationLoad(state, refresh)
		state = state or self.current_state
		if not state or state ~= self.current_state or getLoadStatus(state, PAGE_TRANSLATION) == LOAD_LOADING then
			return true
		end

		state.translation_payload = nil
		state.translation_text_main = nil
		setLoadStatus(state, PAGE_TRANSLATION, LOAD_LOADING)
		self:refreshCard(PAGE_TRANSLATION)

		UIManager:scheduleIn(TRANSLATION_RELOAD_DELAY, function()
			if state == self.current_state then
				self:queryTranslation(state, refresh)
			end
		end)
		return true
	end

	function LookupPreview:copyMainTranslation(text_main)
		if not self.clipboard_available then
			return self:notify(_("Clipboard is not available."))
		end

		Device.input.setClipboardText(text_main or "")
		return self:notify(_("Translation copied to clipboard."))
	end

	function LookupPreview:saveMainTranslationToNote(text_main)
		local state = self.current_state
		local highlight = state and self:getActiveHighlight(state.dict_self) or nil

		if not highlight then
			return self:notify(_("No highlight available."))
		end

		self:closeCurrentPopup(true)
		self.current_state = nil

		if highlight.highlight_dialog then
			UIManager:close(highlight.highlight_dialog)
			highlight.highlight_dialog = nil
		end

		if type(highlight.addNote) == "function" then
			highlight:addNote(text_main or "")
			return true
		end

		return self:notify(_("Could not create note."))
	end

	function LookupPreview:openOriginalTranslationFromState(state)
		state = state or self.current_state
		if not state then
			return true
		end

		local text = state.translation_source_text or state.search_text or ""
		local source_lang = state.translation_source_lang
			or G_reader_settings:readSetting("translator_from_language")
			or "auto"
		local target_lang = state.translation_target_lang
			or G_reader_settings:readSetting("translator_to_language")
			or "en"
		local cleanup_state = state

		self:closeCurrentPopup(true)
		self.current_state = nil

		local ok, err = pcall(function()
			Translator:showTranslation(text, true, source_lang, target_lang, false, nil)
		end)

		if not ok then
			logger.warn("LookupPreview: failed to open original translation widget:", err)
			return self:notify(_("Could not open the original translator."))
		end

		-- Unlike the native dictionary popup, the native translator does not receive
		-- the dictionary close callback. Clearing the selection after opening it
		-- prevents the next tap from reopening Lookup Preview from a stale selection.
		UIManager:scheduleIn(TRANSLATION_RELOAD_DELAY, function()
			if cleanup_state then
				cleanupSelectionAfterNativeTranslation(self, cleanup_state)
			end
		end)

		return true
	end

	function LookupPreview:getTargetLanguageMenuItems(state)
		local items = {}
		local target_sub_items = extractTargetLanguageItems(Translator)

		if target_sub_items then
			for _, item in ipairs(target_sub_items) do
				items[#items + 1] = copyTranslatorMenuItem(self, state, Translator, item)
			end
		end

		if #items > 0 then
			return items
		end

		for _, lang in ipairs(COMMON_TARGET_LANGUAGES) do
			local lang_key = lang
			items[#items + 1] = {
				text = string.format("%s (%s)", self:getTranslatorLanguageLabel(Translator, lang_key), lang_key),
				checked_func = function()
					return self:getTranslationTargetLang() == lang_key
				end,
				radio = true,
				callback = function()
					return self:refreshTranslationWithTarget(state, lang_key)
				end,
			}
		end

		return items
	end

	-- The languages to translate this lookup from: KOReader's setting (the
	-- default), detection, or one of the common languages. The choice is for
	-- this lookup only; KOReader's setting stays as it is.
	function LookupPreview:getSourceLanguageMenuItems(state)
		local choice = state and state.translation_source_choice
		local default_source = Translator.getSourceLanguage and Translator:getSourceLanguage() or "auto"
		local function sourceItem(text, lang_key)
			return {
				text = text,
				radio = true,
				checked_func = function()
					return choice == lang_key
				end,
				callback = function()
					return self:refreshTranslationWithSource(state, lang_key)
				end,
			}
		end

		local items = {}
		if default_source == "auto" then
			items[1] = sourceItem(_("Detect automatically"), nil)
		else
			items[1] = sourceItem(
				string.format(_("As in KOReader's settings (%s)"), self:getTranslatorLanguageLabel(Translator, default_source)),
				nil
			)
			items[2] = sourceItem(_("Detect automatically"), "auto")
		end
		items[#items].separator = true

		for lang_index = 1, #COMMON_TARGET_LANGUAGES do
			local lang_key = COMMON_TARGET_LANGUAGES[lang_index]
			items[#items + 1] =
				sourceItem(string.format("%s (%s)", self:getTranslatorLanguageLabel(Translator, lang_key), lang_key), lang_key)
		end
		return items
	end

	-- The card's language menu: the target languages, with the source language
	-- of this lookup first, in a submenu.
	function LookupPreview:showTargetLanguageMenu(state)
		local Menu = require("ui/widget/menu")
		local width, height = getMenuDimensions()
		self:closeLanguageMenu()

		local source = state and (state.translation_source_choice or state.translation_source_lang) or "auto"
		local source_label = source == "auto" and _("Detect automatically")
			or self:getTranslatorLanguageLabel(Translator, source)
		local items = {
			{
				text = string.format("%s: %s", _("Translate from"), source_label),
				sub_item_table = self:getSourceLanguageMenuItems(state),
				separator = true,
			},
		}
		local target_items = self:getTargetLanguageMenuItems(state)
		for item_index = 1, #target_items do
			items[#items + 1] = target_items[item_index]
		end

		self.language_menu = Menu:new({
			title = _("Translate to"),
			item_table = items,
			width = width,
			height = height,
		})

		UIManager:show(self.language_menu)
		return true
	end

	function LookupPreview:refreshTranslationWithSource(state, source_lang)
		self:closeLanguageMenu()
		if not state or state ~= self.current_state then
			return true
		end

		state.translation_source_choice = source_lang
		resetTranslationState(state, getTargetLanguage(state))
		self:showCarousel(state, PAGE_TRANSLATION)
		scheduleTranslationReload(self, state)
		return true
	end

	function LookupPreview:refreshTranslationWithTarget(state, target_lang)
		self:closeLanguageMenu()
		target_lang = normalizeLanguageCode(target_lang, "en")
		G_reader_settings:saveSetting("translator_to_language", target_lang)

		if not state or state ~= self.current_state then
			return true
		end

		resetTranslationState(state, target_lang)
		self:showCarousel(state, PAGE_TRANSLATION)
		scheduleTranslationReload(self, state)
		return true
	end

	function LookupPreview:getTranslatorLanguageLabel(translator, lang)
		if translator and type(translator.getLanguageName) == "function" then
			local ok, name = pcall(function()
				return translator:getLanguageName(lang, lang and lang:upper() or "?")
			end)
			if ok and name then
				return name
			end
		end

		return tostring(lang or "?")
	end

	-- What the card translates: the selection, or the sentence around it.
	local function getTranslationText(state)
		if state.translation_use_sentence and state.translation_sentence then
			return state.translation_sentence
		end
		return state.search_text or ""
	end

	local function getTranslationCacheKey(state)
		return onlineCacheKey("translation", getSourceLanguage(state), getTargetLanguage(state), getTranslationText(state))
	end

	-- Fills the state with an answer of the translation service (or of the
	-- cache): { text_main = string or false, source_lang = detected language }.
	local function applyTranslation(plugin, state, answer)
		state.translation_source_text = getTranslationText(state)
		state.translation_source_lang = answer.source_lang
		state.translation_target_lang = getTargetLanguage(state)
		-- With nothing found the payload says so, and its subtitle still
		-- chooses another target language.
		state.translation_text_main = answer.text_main or nil
		state.translation_payload = plugin:buildTranslationPayload(state)
		setLoadStatus(state, PAGE_TRANSLATION, state.translation_text_main and LOAD_DONE or LOAD_EMPTY)
	end

	-- Loads the card when it is shown. What is cached is shown at once, even
	-- when online cards wait for the Load button, since it needs no network.
	function LookupPreview:loadTranslation(state)
		if not state or state ~= self.current_state then
			return true
		end
		if getLoadStatus(state, PAGE_TRANSLATION) ~= LOAD_IDLE then
			return true
		end
		local cached = getCachedOnlineResult(getTranslationCacheKey(state))
		if not cached and self:useManualOnlineCardLoading() then
			return true
		end

		setLoadStatus(state, PAGE_TRANSLATION, LOAD_LOADING)
		return self:queryTranslation(state)
	end

	-- Queries the translation service for a card already marked as loading,
	-- unless the answer is cached and `refresh` is not set. See runOnlineQuery
	-- for where the query runs.
	function LookupPreview:queryTranslation(state, refresh)
		local text = getTranslationText(state)
		if text == "" then
			setLoadStatus(state, PAGE_TRANSLATION, LOAD_ERROR, _("No text to translate."))
			return self:refreshCard(PAGE_TRANSLATION)
		end

		local cache_key = getTranslationCacheKey(state)
		local cached = not refresh and getCachedOnlineResult(cache_key)
		if cached then
			applyTranslation(self, state, cached)
			return self:refreshCard(PAGE_TRANSLATION)
		end

		if isNetworkUnavailable() then
			setLoadStatus(state, PAGE_TRANSLATION, LOAD_ERROR, _("Network unavailable."))
			return self:refreshCard(PAGE_TRANSLATION)
		end

		local Trapper = require("ui/trapper")
		runOnlineQuery(self, function()
			local ok, err = pcall(function()
				local target_lang = getTargetLanguage(state)
				local source_lang = getSourceLanguage(state)
				local completed, result = Trapper:dismissableRunInSubprocess(function()
					return Translator:loadPage(text, target_lang, source_lang)
				end, _("Querying translation service…"))

				if not completed then
					setLoadStatus(state, PAGE_TRANSLATION, LOAD_ERROR, _("Translation interrupted."))
					return
				end
				if type(result) ~= "table" then
					setLoadStatus(state, PAGE_TRANSLATION, LOAD_ERROR, _("Translation failed."))
					return
				end

				local text_main = extractMainTranslation(result)
				local answer = { text_main = text_main ~= "" and text_main or false, source_lang = result[3] or source_lang }
				cacheOnlineResult(cache_key, answer)
				applyTranslation(self, state, answer)
			end)

			if not ok then
				logger.warn("LookupPreview: translation failed:", err)
				setLoadStatus(state, PAGE_TRANSLATION, LOAD_ERROR, onlineLookupError(err, _("Translation failed.")))
			end

			if state == self.current_state then
				self:refreshCard(PAGE_TRANSLATION)
			end
		end)
		return true
	end
end
