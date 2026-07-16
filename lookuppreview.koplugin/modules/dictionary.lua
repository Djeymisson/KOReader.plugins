return function(ctx)
	setmetatable(ctx, { __index = _G })
	setfenv(1, ctx)

	-- Shared by the dictionary card and by the Wikipedia module to keep indexes
	-- cyclic when navigating previous/next results.
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

	local function getPreviewCount(state)
		return state and (state.preview_count or #(state.preview_results or {})) or 0
	end

	local function getPreviewEntry(state, index)
		return state and state.preview_results and state.preview_results[index] or nil
	end

	function reorderResultsFromIndex(results, index)
		if type(results) ~= "table" then
			return results
		end

		local count = #results
		index = tonumber(index) or 1
		if count <= 1 or index <= 1 or index > count then
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

	-- Shared with carousel.lua: filters out artificial no-result placeholders but
	-- keeps a fallback entry when the KOReader dictionary flow only returns one.
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
			preview_results[1] = {
				result = results[1],
				source_index = 1,
			}
		end

		return preview_results
	end

	local function getDictionaryHtmlModeForCache(self)
		return self:useFastRawDictionaryHtml() and DICTIONARY_HTML_FAST_RAW or DICTIONARY_HTML_FORMATTED
	end

	local function getCacheKey(self)
		local mode = getDictionaryHtmlModeForCache(self)
		if mode == DICTIONARY_HTML_FAST_RAW then
			return mode
		end

		local justify = G_reader_settings:nilOrTrue("dict_justify") and "1" or "0"
		return mode .. "|" .. justify
	end

	local function buildFastRawDefinition(result)
		local definition = tostring(result and result.definition or "")
		if definition == "" then
			return "<p>" .. htmlEscape(_("No definition.")) .. "</p>"
		end
		if looksLikeHtml(definition) then
			return definition
		end
		return plainTextToHtml(definition)
	end

	local function getFastRawCss(result)
		local css = FAST_RAW_DICTIONARY_CSS
		if result and result.css and result.css ~= "" then
			css = css .. "\n" .. result.css
		end
		return css
	end

	local function buildDefinitionUncached(self, result)
		if result.no_result then
			return "<p>" .. htmlEscape(_("No definition found.")) .. "</p>", FALLBACK_CSS
		end

		if self:useFastRawDictionaryHtml() then
			return buildFastRawDefinition(result), getFastRawCss(result)
		end

		if hasDictionaryCss(result) then
			return normalizeDictionaryHtml(result.definition), getDictionaryPanelCss(result)
		end

		return normalizeDictionaryPreviewHtml(result.definition), FALLBACK_CSS
	end

	local function buildDefinition(self, result)
		result = result or {}
		if result.no_result then
			return buildDefinitionUncached(self, result)
		end

		local cache_key = getCacheKey(self)
		local definition = tostring(result.definition or "")
		local css_source = tostring(result.css or "")
		local cache = result._lookuppreview_definition_cache
		local cached = cache and cache[cache_key]
		if cached and cached.definition == definition and cached.css_source == css_source then
			return cached.html, cached.css
		end

		local html, css = buildDefinitionUncached(self, result)
		cache = cache or {}
		cache[cache_key] = {
			definition = definition,
			css_source = css_source,
			html = html,
			css = css,
		}
		result._lookuppreview_definition_cache = cache
		return html, css
	end

	local function buildSubtitle(dict_name, result_index, result_count, no_result)
		if no_result or not result_count or result_count <= 1 then
			return dict_name
		end
		return string.format("%s · %d/%d ▾", dict_name, result_index or 1, result_count)
	end

	local function closePreviewBeforeExternalAction(self, state)
		self:closeCurrentPopup(true)
		self.current_state = nil
		self.selection_snapshot = nil
		self:clearOriginalHighlight(state and state.dict_self)
		self:clearSelection()
		if state and state.dict_close_callback then
			pcall(state.dict_close_callback)
		end
	end

	function LookupPreview:buildDictionaryPayload(word, result, result_index, result_count)
		result = result or {}

		local shown_word = result.word or word or _("Dictionary")
		local dict_name = result.no_result and _("Dictionary") or (result.dict or _("Dictionary"))
		local definition_html, css = buildDefinition(self, result)

		return {
			page_type = PAGE_DICTIONARY,
			title = tostring(shown_word or _("Dictionary")),
			subtitle = buildSubtitle(dict_name, result_index, result_count, result.no_result),
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
					closePreviewBeforeExternalAction(self, state)
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

		local preview_count = getPreviewCount(state)
		state.dictionary_index = normalizeResultIndex(index or state.dictionary_index or 1, preview_count)

		local preview_entry = getPreviewEntry(state, state.dictionary_index)
		local result = preview_entry and preview_entry.result or (state.results and state.results[1]) or {}

		state.dictionary_search_text = self:getSearchText(state.word, result)
		state.dictionary_payload =
			self:buildDictionaryPayload(state.word, result, state.dictionary_index, preview_count)
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

	local function getFoundWord(self, state, result)
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

	local function getDictionaryName(result, index)
		local dict_name = trim(result and result.dict or "")
		if dict_name == "" then
			return string.format("%s %d", _("Dictionary"), index)
		end
		return dict_name
	end

	function LookupPreview:getDictionaryMenuItems(state)
		local items = {}
		local preview_results = state and state.preview_results or {}
		local active_index = state and (state.dictionary_index or 1) or 1

		for index, entry in ipairs(preview_results) do
			local result = entry and entry.result or {}
			local dict_name = getDictionaryName(result, index)
			local found_word = getFoundWord(self, state, result)
			local item_text = found_word ~= "" and string.format("%s · %s", found_word, dict_name) or dict_name

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

		local preview_count = getPreviewCount(state)
		local preview_index = normalizeResultIndex(state.dictionary_index or 1, preview_count)
		local preview_entry = getPreviewEntry(state, preview_index)
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
