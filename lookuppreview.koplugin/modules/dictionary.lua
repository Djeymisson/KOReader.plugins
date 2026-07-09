-- Lookup Preview module: dictionary.
-- Auto-split from the original main.lua; loaded by main.lua.
return function(ctx)
    setmetatable(ctx, { __index = _G })
    setfenv(1, ctx)

function normalizeResultIndex(index, count)
	if not count or count <= 0 then
		return 1
	end

	index = tonumber(index) or 1
	if index < 1 then
		return count
	elseif index > count then
		return 1
	end
	return index
end

function reorderResultsFromIndex(results, index)
	if type(results) ~= "table" then
		return results
	end

	local count = #results
	if count <= 1 or index == 1 then
		return results
	end

	local reordered = {}
	for i = index, count do
		reordered[#reordered + 1] = results[i]
	end
	for i = 1, index - 1 do
		reordered[#reordered + 1] = results[i]
	end
	return reordered
end

function buildPreviewResults(results)
	local preview_results = {}
	if type(results) ~= "table" then
		return preview_results
	end
	for index, result in ipairs(results) do
		if result and not result.no_result then
			preview_results[#preview_results + 1] = {
				result = result,
				source_index = index,
			}
		end
	end
	if #preview_results == 0 and results[1] then
		preview_results[#preview_results + 1] = {
			result = results[1],
			source_index = 1,
		}
	end
	return preview_results
end

function LookupPreview:buildDictionaryPayload(word, result, result_index, result_count)
	result = result or {}
	local shown_word = result.word or word or _("Dictionary")
	local dict_name = result.dict or _("Dictionary")
	local definition_html
	local css

	if result.no_result then
		dict_name = _("Dictionary")
		definition_html = "<p>" .. htmlEscape(_("No definition found.")) .. "</p>"
		css = FALLBACK_CSS
	elseif hasDictionaryCss(result) then
		definition_html = normalizeDictionaryHtml(result.definition)
		css = getDictionaryPanelCss(result)
	else
		definition_html = normalizeDictionaryPreviewHtml(result.definition)
		css = FALLBACK_CSS
	end

	local count_label = ""
	if not result.no_result and result_count and result_count > 1 then
		count_label = string.format("%d/%d", result_index or 1, result_count)
	end

	local subtitle = dict_name
	if count_label ~= "" then
		subtitle = string.format("%s · %s ▾", dict_name, count_label)
	end

	return {
		page_type = PAGE_DICTIONARY,
		title = tostring(shown_word or _("Dictionary")),
		subtitle = subtitle,
		html_body = definition_html,
		css = css,
		html_resource_directory = result.dictionary_resource_directory,
	}
end

function LookupPreview:buildDictionaryButtons(state, search_text)
	if not state then
		return nil
	end

	search_text = search_text or state.dictionary_search_text or state.search_text or ""

	local button_specs = {
		{
			spec = self:getLeftButtonSpec(LEFT_ACTION_HIGHLIGHT),
			callback = function()
				self:closeCurrentPopup(true)
				self.current_state = nil
				return self:highlightSelection(state.dict_self, state.dict_close_callback)
			end,
		},
		{
			spec = self:getLeftButtonSpec(LEFT_ACTION_SEARCH_BOOK),
			callback = function()
				self:closeCurrentPopup(true)
				self.current_state = nil
				self.selection_snapshot = nil
				self:clearOriginalHighlight(state.dict_self)
				self:clearSelection()
				if state.dict_close_callback then
					pcall(state.dict_close_callback)
				end
				return self:showSearchDialog(search_text)
			end,
		},
	}

	if state.preview_count and state.preview_count > 1 then
		button_specs[#button_specs + 1] = {
			spec = { icon = ICON_PREVIOUS },
			callback = function()
				return self:switchDictionaryResult((state.dictionary_index or 1) - 1)
			end,
		}
		button_specs[#button_specs + 1] = {
			spec = { icon = ICON_NEXT },
			callback = function()
				return self:switchDictionaryResult((state.dictionary_index or 1) + 1)
			end,
		}
	end

	button_specs[#button_specs + 1] = {
		spec = { icon = ICON_DETAILS },
		callback = function()
			return self:openOriginalDictionaryFromState(state)
		end,
	}

	return button_specs
end

function LookupPreview:updateDictionaryPayload(state, index)
	if not state then
		return nil
	end

	local preview_count = state.preview_count or #(state.preview_results or {})
	state.dictionary_index = normalizeResultIndex(index or state.dictionary_index or 1, preview_count)

	local preview_entry = state.preview_results and state.preview_results[state.dictionary_index] or nil
	local result = preview_entry and preview_entry.result or (state.results and state.results[1]) or {}

	state.dictionary_search_text = self:getSearchText(state.word, result)
	state.dictionary_payload = self:buildDictionaryPayload(state.word, result, state.dictionary_index, preview_count)
	return state.dictionary_payload
end

function LookupPreview:switchDictionaryResult(index)
	local state = self.current_state
	if not state then
		return true
	end

	self:updateDictionaryPayload(state, index)
	return self:showCarousel(state, PAGE_DICTIONARY, true)
end

function LookupPreview:getDictionaryMenuItems(state)
	local items = {}
	local preview_results = state and state.preview_results or {}
	local active_index = state and (state.dictionary_index or 1) or 1

	local function getFoundWord(result)
		local found_word = result and result.word or ""
		if type(found_word) == "table" then
			found_word = found_word.text or found_word.word or ""
		end

		found_word = trim(found_word)
		if found_word == "" then
			found_word = self:getSearchText(state and state.word or "", result)
		end
		if found_word == "" and state then
			found_word = trim(state.search_text or "")
		end

		return found_word
	end

	for index, entry in ipairs(preview_results) do
		local result = entry and entry.result or {}
		local dict_name = trim(result.dict or "")
		if dict_name == "" then
			dict_name = string.format("%s %d", _("Dictionary"), index)
		end

		local found_word = getFoundWord(result)
		local item_text = dict_name
		if found_word ~= "" then
			item_text = string.format("%s · %s", found_word, dict_name)
		end

		items[#items + 1] = {
			text = item_text,
			radio = true,
			checked_func = function()
				return (state and (state.dictionary_index or 1) or active_index) == index
			end,
			callback = function()
				self:closeLanguageMenu()
				return self:switchDictionaryResult(index)
			end,
		}
	end

	if #items == 0 then
		items[1] = {
			text = _("No definition found."),
			enabled_func = function()
				return false
			end,
		}
	end

	return items
end

function LookupPreview:showDictionaryMenu(state)
	local Menu = require("ui/widget/menu")
	self:closeLanguageMenu()

	self.language_menu = Menu:new({
		title = _("Dictionary"),
		item_table = self:getDictionaryMenuItems(state),
		width = Screen:getWidth() - Screen:scaleBySize(80),
		height = math.floor(Screen:getHeight() * 0.8),
	})

	UIManager:show(self.language_menu)
	return true
end

function LookupPreview:openOriginalDictionaryFromState(state)
	state = state or self.current_state
	if not state then
		return true
	end

	local preview_count = state.preview_count or #(state.preview_results or {})
	local preview_index = normalizeResultIndex(state.dictionary_index or 1, preview_count)
	local preview_entry = state.preview_results and state.preview_results[preview_index] or nil
	local source_index = preview_entry and preview_entry.source_index or 1
	local selected_results = reorderResultsFromIndex(state.results, source_index)

	self:closeCurrentPopup(true)
	self.current_state = nil
	return self:showOriginalDictionaryPopup(
		state.dict_self,
		state.word,
		selected_results,
		state.boxes,
		state.link,
		state.dict_close_callback
	)
end


end
