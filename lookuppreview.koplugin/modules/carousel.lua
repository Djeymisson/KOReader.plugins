-- Lookup Preview module: carousel.
-- Auto-split from the original main.lua; loaded by main.lua.
return function(ctx)
    setmetatable(ctx, { __index = _G })
    setfenv(1, ctx)

function LookupPreview:refreshCurrentPage(index)
	if not self.current_state then
		return true
	end

	local active_index = self.current_state.active_index or PAGE_DICTIONARY
	if index and index ~= active_index then
		return true
	end

	return self:showCarousel(self.current_state, active_index, true)
end

function LookupPreview:switchToPage(index)
	if not self.current_state then
		return true
	end
	index = math.max(PAGE_DICTIONARY, math.min(PAGE_WIKIPEDIA, index or PAGE_DICTIONARY))
	if index == self.current_state.active_index then
		return true
	end

	self:showCarousel(self.current_state, index, true)

	local state = self.current_state
	if index == PAGE_TRANSLATION then
		UIManager:scheduleIn(0.05, function()
			self:loadTranslation(state)
		end)
	elseif index == PAGE_WIKIPEDIA then
		UIManager:scheduleIn(0.05, function()
			self:loadWikipedia(state)
		end)
	end

	return true
end

function LookupPreview:showCarousel(state, active_index, preserve_state)
	self:closeCurrentPopup(true)
	state.active_index = active_index or PAGE_DICTIONARY
	self.current_state = state

	local popup = LookupPreviewPopup:new({
		plugin = self,
		state = state,
		active_index = state.active_index,
		selection_bounds = state.selection_bounds,
		dialog = state.dialog,
	})

	self.current_popup = popup
	UIManager:show(popup)
	return true
end

function LookupPreview:closePreview(skip_clear)
	local state = self.current_state
	self.current_popup = nil

	if state and not skip_clear then
		self.selection_snapshot = nil
		self:clearOriginalHighlight(state.dict_self)
		self:clearSelection()
		if state.dict_close_callback then
			pcall(state.dict_close_callback)
		end
	end

	self.current_state = nil
	return true
end

function LookupPreview:showPreview(dict_self, word, results, boxes, link, dict_close_callback)
	local preview_results = buildPreviewResults(results)
	if #preview_results <= 0 then
		return true
	end

	local first_entry = preview_results[1] or {}
	local first_result = first_entry.result or results[1] or {}
	local search_text = self:getSearchText(word, first_result)
	local state = {
		dict_self = dict_self,
		word = word,
		results = results,
		preview_results = preview_results,
		boxes = boxes,
		link = link,
		dict_close_callback = dict_close_callback,
		preview_count = #preview_results,
		dictionary_index = 1,
		search_text = search_text,
		dictionary_search_text = search_text,
		translation_source_text = search_text,
		selection_bounds = getSelectionBounds(boxes),
		dialog = dict_self and dict_self.dialog,
	}

	state.dictionary_payload = self:buildDictionaryPayload(word, first_result, 1, #preview_results)

	return self:showCarousel(state, PAGE_DICTIONARY, false)
end

LookupPreview.showFootnotePreview = LookupPreview.showPreview

return LookupPreview

end
