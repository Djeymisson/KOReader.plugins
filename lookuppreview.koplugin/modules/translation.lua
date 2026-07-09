-- Lookup Preview module: translation.
-- Auto-split from the original main.lua; loaded by main.lua.
return function(ctx)
    setmetatable(ctx, { __index = _G })
    setfenv(1, ctx)

function LookupPreview:closeLanguageMenu()
	if self.language_menu then
		pcall(function()
			UIManager:close(self.language_menu)
		end)
		self.language_menu = nil
	end
end

function LookupPreview:buildTranslationPayload(state)
	state = state or self.current_state or {}
	local text_main = state.translation_text_main or _("No translation found.")
	local source_text = state.translation_source_text or state.search_text or ""
	local source_lang = state.translation_source_lang or "auto"
	local target_lang = state.translation_target_lang or G_reader_settings:readSetting("translator_to_language") or "en"
	local source_name = self:getTranslatorLanguageLabel(Translator, source_lang)
	local target_name = self:getTranslatorLanguageLabel(Translator, target_lang)
	local parts = {
		'<div class="lp-translation">' .. plainTextToHtml(text_main) .. "</div>",
	}

	if self:showTranslationSourceText() then
		parts[#parts + 1] = '<div class="lp-source-label">' .. htmlEscape(_("Source")) .. "</div>"
		parts[#parts + 1] = '<div class="lp-source">' .. plainTextToHtml(source_text) .. "</div>"
	end

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

	local button_specs = {}

	if self.clipboard_available and self:showTranslationCopyButton() then
		button_specs[#button_specs + 1] = {
			spec = { text = _("Copy") },
			callback = function()
				return self:copyMainTranslation(state.translation_text_main)
			end,
		}
	end

	if self:showTranslationNoteButton() then
		button_specs[#button_specs + 1] = {
			spec = { text = _("Note") },
			callback = function()
				return self:saveMainTranslationToNote(state.translation_text_main)
			end,
		}
	end

	button_specs[#button_specs + 1] = {
		spec = { icon = ICON_DETAILS },
		callback = function()
			return self:openOriginalTranslationFromState(state)
		end,
	}

	return button_specs
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
	local target_lang = state.translation_target_lang or G_reader_settings:readSetting("translator_to_language") or "en"
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

	-- The native translator widget does not receive the dictionary close
	-- callback, unlike the native dictionary widget. If we leave the original
	-- selection alive here, the next tap may re-trigger showDict() and reopen
	-- the Lookup Preview carousel. Clear the selection after the translator has
	-- been opened so closing the native widget returns to a clean reader state.
	UIManager:scheduleIn(0.05, function()
		if cleanup_state ~= nil then
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

function LookupPreview:getTargetLanguageMenuItems(state)
	local translator = Translator
	local items = {}

	local ok, settings_menu = pcall(function()
		return translator:genSettingsMenu()
	end)

	if ok and settings_menu and type(settings_menu.sub_item_table) == "table" then
		local target_sub_items

		for i = #settings_menu.sub_item_table, 1, -1 do
			local item = settings_menu.sub_item_table[i]
			if type(item) == "table" and type(item.sub_item_table) == "table" then
				target_sub_items = item.sub_item_table
				break
			end
		end

		if target_sub_items then
			for _, item in ipairs(target_sub_items) do
				local menu_item = item
				items[#items + 1] = {
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

						local selected_lang = translator:getTargetLanguage()
						return self:refreshTranslationWithTarget(state, selected_lang)
					end,
				}
			end
		end
	end

	if #items > 0 then
		return items
	end

	for _, lang in ipairs(COMMON_TARGET_LANGUAGES) do
		local lang_key = lang
		items[#items + 1] = {
			text = string.format("%s (%s)", self:getTranslatorLanguageLabel(translator, lang_key), lang_key),
			checked_func = function()
				return translator:getTargetLanguage() == lang_key
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
	if not state then
		return true
	end

	local Menu = require("ui/widget/menu")
	self:closeLanguageMenu()

	self.language_menu = Menu:new({
		title = _("Translate to"),
		item_table = self:getTargetLanguageMenuItems(state),
		width = Screen:getWidth() - Screen:scaleBySize(80),
		height = math.floor(Screen:getHeight() * 0.8),
	})

	UIManager:show(self.language_menu)
	return true
end

function LookupPreview:refreshTranslationWithTarget(state, target_lang)
	self:closeLanguageMenu()

	if not state or state ~= self.current_state then
		return true
	end

	G_reader_settings:saveSetting("translator_to_language", target_lang)
	state.translation_target_lang = target_lang
	state.translation_payload = nil
	state.translation_error = nil
	state.translation_loading = nil
	state.translation_text_main = nil
	state.translation_source_lang = nil

	self:showCarousel(state, PAGE_TRANSLATION, true)
	UIManager:scheduleIn(0.05, function()
		self:loadTranslation(state)
	end)
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

function LookupPreview:loadTranslation(state)
	if state ~= self.current_state then
		return true
	end
	if not state or state.translation_loading or state.translation_payload or state.translation_error then
		return true
	end

	state.translation_loading = true
	local text = state.search_text or ""
	local translator = Translator

	if text == "" then
		state.translation_error = _("No text to translate.")
		state.translation_loading = false
		return self:refreshCurrentPage(PAGE_TRANSLATION)
	end

	local NetworkMgr = require("ui/network/manager")
	if
		NetworkMgr:willRerunWhenOnline(function()
			state.translation_loading = false
			self:loadTranslation(state)
		end)
	then
		state.translation_error = _("Waiting for network connection.")
		state.translation_loading = false
		return self:refreshCurrentPage(PAGE_TRANSLATION)
	end

	local ok, err = pcall(function()
		local target_lang = state.translation_target_lang
			or (translator.getTargetLanguage and translator:getTargetLanguage())
			or G_reader_settings:readSetting("translator_to_language")
			or "en"
		local source_lang = state.translation_source_lang
			or (translator.getSourceLanguage and translator:getSourceLanguage())
			or G_reader_settings:readSetting("translator_from_language")
			or "auto"
		local Trapper = require("ui/trapper")
		local completed, result = Trapper:dismissableRunInSubprocess(function()
			return translator:loadPage(text, target_lang, source_lang)
		end, _("Querying translation service…"))

		if not completed then
			state.translation_error = _("Translation interrupted.")
			return
		end
		if not result or type(result) ~= "table" then
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
		state.translation_error = tostring(err or _("Translation failed."))
	end

	state.translation_loading = false
	return self:refreshCurrentPage(PAGE_TRANSLATION)
end


end
