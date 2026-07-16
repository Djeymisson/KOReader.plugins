return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	local MENU_HORIZONTAL_MARGIN = Screen:scaleBySize(80)
	local MENU_HEIGHT_RATIO = 0.8
	local TRANSLATION_RELOAD_DELAY = 0.05

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

	local function getSourceLanguage(state)
		return (state and state.translation_source_lang)
			or (Translator.getSourceLanguage and Translator:getSourceLanguage())
			or G_reader_settings:readSetting("translator_from_language")
			or "auto"
	end

	local function resetTranslationState(state, target_lang)
		state.translation_target_lang = target_lang
		state.translation_payload = nil
		state.translation_error = nil
		state.translation_loading = nil
		state.translation_text_main = nil
		state.translation_source_lang = nil
	end

	local function scheduleTranslationReload(plugin, state)
		if not plugin:useAutomaticOnlineCardLoading() then
			return
		end

		UIManager:scheduleIn(TRANSLATION_RELOAD_DELAY, function()
			plugin:loadTranslation(state)
		end)
	end

	local function getMenuDimensions()
		return Screen:getWidth() - MENU_HORIZONTAL_MARGIN, math.floor(Screen:getHeight() * MENU_HEIGHT_RATIO)
	end

	local function appendSourceBlock(plugin, parts, source_text)
		if not plugin:showTranslationSourceText() then
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
		local source_lang = state.translation_source_lang or "auto"
		local target_lang = getTargetLanguage(state)
		local source_name = self:getTranslatorLanguageLabel(Translator, source_lang)
		local target_name = self:getTranslatorLanguageLabel(Translator, target_lang)
		local parts = {
			'<div class="lp-translation">' .. plainTextToHtml(text_main) .. "</div>",
		}

		appendSourceBlock(self, parts, source_text)

		return {
			page_type = PAGE_TRANSLATION,
			title = _("Translate"),
			subtitle = string.format("%s → %s ▾", source_name, target_name),
			subtitle_callback = function()
				return self:showTargetLanguageMenu(state)
			end,
			html_body = table.concat(parts, "\n"),
			css = FALLBACK_CSS,
		}
	end

	function LookupPreview:buildTranslationButtons(state)
		if not state or not state.translation_text_main then
			return nil
		end

		local buttons = {}
		local text_main = state.translation_text_main

		if self.clipboard_available and self:showTranslationCopyButton() then
			buttons[#buttons + 1] = {
				spec = { text = _("Copy") },
				callback = function()
					return self:copyMainTranslation(text_main)
				end,
			}
		end

		if self:showTranslationNoteButton() then
			buttons[#buttons + 1] = {
				spec = { text = _("Note") },
				callback = function()
					return self:saveMainTranslationToNote(text_main)
				end,
			}
		end

		buttons[#buttons + 1] = {
			spec = { icon = ICON_DETAILS },
			callback = function()
				return self:openOriginalTranslationFromState(state)
			end,
		}

		return buttons
	end

	function LookupPreview:buildTranslationManualLoadButtons(state, label)
		return {
			{
				spec = { text = label or _("Load") },
				callback = function()
					return self:requestTranslationLoad(state)
				end,
			},
		}
	end

	function LookupPreview:requestTranslationLoad(state)
		state = state or self.current_state
		if not state or state ~= self.current_state then
			return true
		end

		state.translation_payload = nil
		state.translation_error = nil
		state.translation_loading = nil
		state.translation_text_main = nil
		return self:loadTranslation(state, true)
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

	function LookupPreview:showTargetLanguageMenu(state)
		local Menu = require("ui/widget/menu")
		local width, height = getMenuDimensions()
		self:closeLanguageMenu()

		self.language_menu = Menu:new({
			title = _("Translate to"),
			item_table = self:getTargetLanguageMenuItems(state),
			width = width,
			height = height,
		})

		UIManager:show(self.language_menu)
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
		self:showCarousel(state, PAGE_TRANSLATION, true)
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

	function LookupPreview:loadTranslation(state, force)
		if not state or state ~= self.current_state then
			return true
		end
		if not force and self:useManualOnlineCardLoading() then
			return self:refreshCurrentPage(PAGE_TRANSLATION)
		end
		if state.translation_loading or state.translation_payload or state.translation_error then
			return true
		end

		local text = state.search_text or ""
		if text == "" then
			state.translation_error = _("No text to translate.")
			return self:refreshCurrentPage(PAGE_TRANSLATION)
		end

		state.translation_loading = true

		if isNetworkUnavailable() then
			state.translation_error = _("Network unavailable.")
			state.translation_loading = false
			return self:refreshCurrentPage(PAGE_TRANSLATION)
		end

		local ok, err = pcall(function()
			local target_lang = getTargetLanguage(state)
			local source_lang = getSourceLanguage(state)
			local Trapper = require("ui/trapper")
			local completed, result = Trapper:dismissableRunInSubprocess(function()
				return Translator:loadPage(text, target_lang, source_lang)
			end, _("Querying translation service…"))

			if not completed then
				state.translation_error = _("Translation interrupted.")
				return
			end
			if type(result) ~= "table" then
				state.translation_error = _("Translation failed.")
				return
			end

			if result[3] then
				source_lang = result[3]
			end

			local text_main = extractMainTranslation(result)
			if text_main == "" then
				text_main = _("No translation found.")
			end

			state.translation_text_main = text_main
			state.translation_source_text = text
			state.translation_source_lang = source_lang
			state.translation_target_lang = target_lang
			state.translation_payload = self:buildTranslationPayload(state)
		end)

		if not ok then
			logger.warn("LookupPreview: translation failed:", err)
			state.translation_error = onlineLookupError(err, _("Translation failed."))
		end

		state.translation_loading = false
		return self:refreshCurrentPage(PAGE_TRANSLATION)
	end
end
