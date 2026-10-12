-- Lookup Preview: carousel lifecycle and entry points.
return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	-- Starts loading a card that was just shown, if it was never loaded. The
	-- dictionary is local, so it is always looked up; Translate and Wikipedia
	-- query only when online cards load automatically, but show what is cached
	-- either way (see loadTranslation and loadWikipedia).
	local CARD_LOADERS = {
		[PAGE_DICTIONARY] = "loadDictionary",
		[PAGE_TRANSLATION] = "loadTranslation",
		[PAGE_WIKIPEDIA] = "loadWikipedia",
	}

	function LookupPreview:scheduleCardLoad(state, index)
		if not state or getLoadStatus(state, index) ~= LOAD_IDLE then
			return
		end

		local loader = CARD_LOADERS[index] and self[CARD_LOADERS[index]]
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
		local is_side_card = self:getNeighborCard(active_index, -1) == index or self:getNeighborCard(active_index, 1) == index
		if not self:useTabsMode() and is_side_card and self.current_popup then
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
			local mode = state.translation_use_sentence and "sentence" or "selection"
			return string.format("%d:%s:%s", index, tostring(state.translation_target_lang or ""), mode)
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

		index = self:normalizeCard(index)
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

		state.active_index = self:normalizeCard(active_index)
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
		if state and state.active_index then
			G_reader_settings:saveSetting(SETTING_LAST_CARD, state.active_index)
		end

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

	-- Lookups inside the preview -----------------------------------------------
	-- Following a link, editing the looked up text or holding a word of a card
	-- looks it up in the same carousel: the new lookup is a state of its own,
	-- whose `parent` is the one it came from, and the header's back button goes
	-- back to it as it was (content and scroll positions). Every state of the
	-- chain shares the book's selection: Highlight, Search and closing the
	-- carousel act on the text selected in the book, never on a nested lookup.

	-- The lookup that opened the carousel.
	function getRootState(state)
		while state and state.parent do
			state = state.parent
		end
		return state
	end

	-- Whether `state` is the lookup shown or one the back button leads to.
	function LookupPreview:isStateOpen(state)
		local open = self.current_state
		while open do
			if open == state then
				return true
			end
			open = open.parent
		end
		return false
	end

	-- Shows `state` in the open carousel, on card `index`, in place of the
	-- lookup shown, and loads that card if it was never loaded.
	function LookupPreview:showState(state, index)
		state.active_index = self:normalizeCard(index)
		self.current_state = state
		self:closeLanguageMenu()

		local popup = self.current_popup
		if popup and popup.rebuildVisibleCards then
			popup.state = state
			popup.active_index = state.active_index
			popup:rebuildVisibleCards()
		else
			self:showCarousel(state, state.active_index)
		end
		self:scheduleCardLoad(state, state.active_index)
		return true
	end

	-- Looks `text` up inside the open carousel, on card `index` (the active
	-- one by default). `options.dictionary_lookup` restricts the dictionary
	-- lookup, as following a link does: { dict_names = {...}, fuzzy = false }.
	function LookupPreview:lookUpInPreview(text, index, options)
		local parent = self.current_state
		text = trim(text)
		if not parent or text == "" then
			return true
		end

		local state = {
			parent = parent,
			highlight_self = parent.highlight_self,
			dict_self = parent.dict_self,
			dict_close_callback = parent.dict_close_callback,
			selection_bounds = parent.selection_bounds,
			dialog = parent.dialog,
			word = text,
			results = {},
			preview_results = {},
			preview_count = 0,
			dictionary_index = 1,
			search_text = text,
			dictionary_search_text = text,
			translation_source_text = text,
			dictionary_lookup = options and options.dictionary_lookup,
		}
		return self:showState(state, index or parent.active_index)
	end

	function LookupPreview:goBack()
		local state = self.current_state
		local parent = state and state.parent
		if not parent then
			return true
		end
		return self:showState(parent, parent.active_index)
	end

	-- A word held in a card's text. From the Translate card it is looked up in
	-- the dictionary; from the others, on the same card.
	function LookupPreview:lookUpHeldText(text)
		local state = self.current_state
		if not state then
			return true
		end
		if util and util.cleanupSelectedText then
			local ok, cleaned = pcall(util.cleanupSelectedText, text)
			if ok and cleaned then
				text = cleaned
			end
		end
		local index = state.active_index
		if index == PAGE_TRANSLATION and self:isCardShown(PAGE_DICTIONARY) then
			index = PAGE_DICTIONARY
		end
		return self:lookUpInPreview(text, index)
	end

	-- Asks for another text to look up, starting from the one shown (to fix an
	-- OCR error, punctuation, or look up a longer or shorter expression).
	function LookupPreview:showEditDialog()
		local state = self.current_state
		if not state then
			return true
		end

		local InputDialog = require("ui/widget/inputdialog")
		local dialog
		dialog = InputDialog:new({
			title = _("Look up"),
			input = state.search_text or "",
			buttons = {
				{
					{
						text = _("Cancel"),
						id = "close",
						callback = function()
							UIManager:close(dialog)
						end,
					},
					{
						text = _("Look up"),
						id = "look_up",
						is_enter_default = true,
						callback = function()
							local text = trim(dialog:getInputText())
							UIManager:close(dialog)
							if text ~= "" and text ~= state.search_text and state == self.current_state then
								self:lookUpInPreview(text, state.active_index)
							end
						end,
					},
				},
			},
		})
		self.edit_dialog = dialog
		UIManager:show(dialog)
		dialog:onShowKeyboard()
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

		local index = self:getOpenCard()
		self:showCarousel(state, index)
		self:scheduleCardLoad(state, state.active_index)
		return true
	end

	return LookupPreview
end
