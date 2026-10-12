-- Lookup Preview: carousel lifecycle and entry points.
return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	local function normalizePageIndex(index)
		return math.max(PAGE_DICTIONARY, math.min(PAGE_WIKIPEDIA, index or PAGE_DICTIONARY))
	end

	-- Starts loading a card that was just shown. The dictionary is local, so it
	-- is always looked up; Translate and Wikipedia only load by themselves when
	-- online cards load automatically.
	function LookupPreview:scheduleCardLoad(state, index)
		if not state then
			return
		end

		local loader
		if index == PAGE_DICTIONARY then
			if getLoadStatus(state, PAGE_DICTIONARY) == LOAD_IDLE then
				loader = self.loadDictionary
			end
		elseif self:useAutomaticOnlineCardLoading() then
			if index == PAGE_TRANSLATION then
				loader = self.loadTranslation
			elseif index == PAGE_WIKIPEDIA then
				loader = self.loadWikipedia
			end
		end

		if loader then
			UIManager:scheduleIn(0.05, function()
				loader(self, state)
			end)
		end
	end

	-- Redraws card `index` after its content changed: the active card, or a side
	-- card shown beside it (full cards only; tabs show no content).
	function LookupPreview:refreshCard(index)
		local state = self.current_state
		if not state then
			return true
		end

		local active_index = state.active_index or PAGE_DICTIONARY
		if index == active_index then
			return self:refreshCurrentPage(index)
		end
		if not self:useTabsMode() and math.abs(index - active_index) == 1 and self.current_popup then
			return self:refreshVisibleCards()
		end
		return true
	end

	-- What a card's scroll position is remembered by: the card and the result it
	-- shows, so each dictionary result, translation language and Wikipedia
	-- article keeps its own. Nil while the card has no content to scroll.
	function LookupPreview:getCardScrollKey(state, index)
		if getLoadStatus(state, index) ~= LOAD_DONE then
			return nil
		end

		if index == PAGE_DICTIONARY then
			return string.format("%d:%d", index, state.dictionary_index or 1)
		elseif index == PAGE_TRANSLATION then
			return string.format("%d:%s", index, tostring(state.translation_target_lang or ""))
		elseif index == PAGE_WIKIPEDIA then
			return string.format("%d:%s:%d", index, tostring(state.wikipedia_lang or ""), state.wikipedia_index or 1)
		end
		return nil
	end

	function LookupPreview:refreshCurrentPage(index)
		local state = self.current_state
		if not state then
			return true
		end

		local active_index = state.active_index or PAGE_DICTIONARY
		if index and index ~= active_index then
			return true
		end

		local popup = self.current_popup
		if popup and popup.state == state and popup.updateCurrentPage then
			return popup:updateCurrentPage(active_index)
		end

		return self:showCarousel(state, active_index)
	end

	function LookupPreview:switchToPage(index)
		local state = self.current_state
		if not state then
			return true
		end

		index = normalizePageIndex(index)
		if index == state.active_index then
			return true
		end

		local popup = self.current_popup
		if popup and popup.state == state and popup.switchToPage then
			popup:switchToPage(index)
			state.active_index = index
		else
			self:showCarousel(state, index)
		end
		self:scheduleCardLoad(state, index)

		return true
	end

	function LookupPreview:showCarousel(state, active_index)
		if not state then
			return true
		end

		state.active_index = normalizePageIndex(active_index)
		self.current_state = state

		local popup = self.current_popup
		if popup and popup.state == state then
			if popup.active_index ~= state.active_index and popup.switchToPage then
				popup:switchToPage(state.active_index)
			elseif popup.updateCurrentPage then
				popup:updateCurrentPage(state.active_index)
			end
			return true
		end

		self:closeCurrentPopup(true)

		popup = LookupPreviewPopup:new({
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
		if #preview_results == 0 then
			return true
		end

		local first_result = preview_results[1].result or {}
		local search_text = self:getSearchText(word, first_result)
		local state = {
			boxes = boxes,
			link = link,
			dict_close_callback = dict_close_callback,
			search_text = search_text,
			translation_source_text = search_text,
			selection_bounds = getSelectionBounds(boxes),
			dialog = dict_self and dict_self.dialog,
		}
		self:setDictionaryResults(state, dict_self, word, results)

		return self:showCarousel(state, PAGE_DICTIONARY)
	end

	return LookupPreview
end
