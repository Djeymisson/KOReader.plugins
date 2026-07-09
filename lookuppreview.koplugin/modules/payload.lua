-- Lookup Preview module: payload.
-- Auto-split from the original main.lua; loaded by main.lua.
return function(ctx)
    setmetatable(ctx, { __index = _G })
    setfenv(1, ctx)

function LookupPreview:makeLoadingPayload(title, message)
	return {
		title = title,
		subtitle = self.current_state and self.current_state.search_text or "",
		html_body = '<p class="lp-muted">' .. htmlEscape(message or _("Loading…")) .. "</p>",
		css = FALLBACK_CSS,
	}
end

function LookupPreview:getPagePayload(state, index, is_active)
	state = state or self.current_state or {}
	if is_active == nil then
		is_active = true
	end

	if index == PAGE_DICTIONARY then
		local payload = state.dictionary_payload or self:makeLoadingPayload(_("Dictionary"), _("No definition found."))
		if is_active then
			payload = copyTable(payload)
			if state.preview_count and state.preview_count > 1 then
				payload.subtitle_callback = function()
					return self:showDictionaryMenu(state)
				end
			end
			payload.dictionary_buttons =
				self:buildDictionaryButtons(state, state.dictionary_search_text or state.search_text or "")
		end
		return payload
	end

	if index == PAGE_TRANSLATION then
		if state.translation_payload then
			local payload = state.translation_payload
			if is_active then
				payload = copyTable(payload)
				payload.card_buttons = self:buildTranslationButtons(state)
			end
			return payload
		end
		if state.translation_error then
			return {
				page_type = PAGE_TRANSLATION,
				title = _("Translate"),
				subtitle = state.search_text or "",
				html_body = plainTextToHtml(state.translation_error),
				css = FALLBACK_CSS,
			}
		end
		if is_active then
			local payload = self:makeLoadingPayload(_("Translate"), _("Querying translation service…"))
			payload.page_type = PAGE_TRANSLATION
			return payload
		end
		local payload = self:makeLoadingPayload(_("Translate"), _("Swipe to open translation."))
		payload.page_type = PAGE_TRANSLATION
		return payload
	end

	if index == PAGE_WIKIPEDIA then
		if state.wikipedia_payload then
			local payload = state.wikipedia_payload
			if is_active then
				payload = copyTable(payload)
				payload.card_buttons = self:buildWikipediaButtons(state)
			end
			return payload
		end
		if state.wikipedia_error then
			local payload = {
				page_type = PAGE_WIKIPEDIA,
				title = _("Wikipedia"),
				subtitle = state.search_text or "",
				subtitle_callback = function()
					return self:showWikipediaLanguageMenu(state)
				end,
				html_body = plainTextToHtml(state.wikipedia_error),
				css = FALLBACK_CSS,
			}
			if is_active then
				payload.card_buttons = self:buildWikipediaLanguageButton(state)
			end
			return payload
		end
		if is_active then
			local payload = self:makeLoadingPayload(_("Wikipedia"), _("Querying Wikipedia…"))
			payload.page_type = PAGE_WIKIPEDIA
			payload.subtitle_callback = function()
				return self:showWikipediaLanguageMenu(state)
			end
			payload.card_buttons = self:buildWikipediaLanguageButton(state)
			return payload
		end
		local payload = self:makeLoadingPayload(_("Wikipedia"), _("Swipe to open Wikipedia."))
		payload.page_type = PAGE_WIKIPEDIA
		return payload
	end

	return self:makeLoadingPayload(_("Lookup"), _("No content."))
end


end
