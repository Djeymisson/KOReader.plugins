return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	local function messagePayload(title, subtitle, message, page_type, subtitle_callback)
		return {
			page_type = page_type,
			title = title,
			subtitle = subtitle or "",
			subtitle_callback = subtitle_callback,
			html_body = '<p class="lp-muted">' .. htmlEscape(message or _("Loading…")) .. "</p>",
			css = FALLBACK_CSS,
		}
	end

	local function textPayload(title, subtitle, text, page_type, subtitle_callback)
		return {
			page_type = page_type,
			title = title,
			subtitle = subtitle or "",
			subtitle_callback = subtitle_callback,
			html_body = plainTextToHtml(text or ""),
			css = FALLBACK_CSS,
		}
	end

	local function addDictionaryRuntimeFields(plugin, payload, state)
		payload = copyTable(payload)

		if state.preview_count and state.preview_count > 1 then
			payload.subtitle_callback = function()
				return plugin:showDictionaryMenu(state)
			end
		end

		payload.dictionary_buttons =
			plugin:buildDictionaryButtons(state, state.dictionary_search_text or state.search_text or "")

		return payload
	end

	local function getDictionaryPayload(plugin, state, is_active)
		local payload = state.dictionary_payload
			or plugin:makeLoadingPayload(_("Dictionary"), _("No definition found."), PAGE_DICTIONARY)

		if not is_active then
			return payload
		end

		return addDictionaryRuntimeFields(plugin, payload, state)
	end

	local function getTranslationPayload(plugin, state, is_active)
		if state.translation_payload then
			if not is_active then
				return state.translation_payload
			end

			local payload = copyTable(state.translation_payload)
			payload.card_buttons = plugin:buildTranslationButtons(state)
			return payload
		end

		if state.translation_error then
			return textPayload(_("Translate"), state.search_text, state.translation_error, PAGE_TRANSLATION)
		end

		if is_active then
			return plugin:makeLoadingPayload(_("Translate"), _("Querying translation service…"), PAGE_TRANSLATION)
		end

		return plugin:makeLoadingPayload(_("Translate"), _("Swipe to open translation."), PAGE_TRANSLATION)
	end

	local function getWikipediaLanguageCallback(plugin, state)
		return function()
			return plugin:showWikipediaLanguageMenu(state)
		end
	end

	local function addWikipediaLanguageButton(plugin, payload, state)
		payload.card_buttons = plugin:buildWikipediaLanguageButton(state)
		return payload
	end

	local function getWikipediaPayload(plugin, state, is_active)
		if state.wikipedia_payload then
			if not is_active then
				return state.wikipedia_payload
			end

			local payload = copyTable(state.wikipedia_payload)
			payload.card_buttons = plugin:buildWikipediaButtons(state)
			return payload
		end

		if state.wikipedia_error then
			local payload = textPayload(
				_("Wikipedia"),
				state.search_text,
				state.wikipedia_error,
				PAGE_WIKIPEDIA,
				getWikipediaLanguageCallback(plugin, state)
			)

			if is_active then
				addWikipediaLanguageButton(plugin, payload, state)
			end
			return payload
		end

		if is_active then
			local payload = plugin:makeLoadingPayload(_("Wikipedia"), _("Querying Wikipedia…"), PAGE_WIKIPEDIA)
			payload.subtitle_callback = getWikipediaLanguageCallback(plugin, state)
			return addWikipediaLanguageButton(plugin, payload, state)
		end

		return plugin:makeLoadingPayload(_("Wikipedia"), _("Swipe to open Wikipedia."), PAGE_WIKIPEDIA)
	end

	function LookupPreview:makeLoadingPayload(title, message, page_type)
		local subtitle = self.current_state and self.current_state.search_text or ""
		return messagePayload(title, subtitle, message, page_type)
	end

	function LookupPreview:getPagePayload(state, index, is_active)
		state = state or self.current_state or {}
		if is_active == nil then
			is_active = true
		end

		if index == PAGE_DICTIONARY then
			return getDictionaryPayload(self, state, is_active)
		elseif index == PAGE_TRANSLATION then
			return getTranslationPayload(self, state, is_active)
		elseif index == PAGE_WIKIPEDIA then
			return getWikipediaPayload(self, state, is_active)
		end

		return self:makeLoadingPayload(_("Lookup"), _("No content."))
	end
end
