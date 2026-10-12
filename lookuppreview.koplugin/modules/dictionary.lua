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

	-- The word shown and its dictionary (the card's title is the card's name),
	-- with ▾ when the other results can be chosen from it.
	local function buildSubtitle(shown_word, dict_name, result_count, no_result)
		if no_result then
			return tostring(shown_word)
		end
		local subtitle = string.format("%s · %s", tostring(shown_word), dict_name)
		if result_count and result_count > 1 then
			subtitle = subtitle .. " ▾"
		end
		return subtitle
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

	-- The result the dictionary card is showing.
	local function getCurrentResult(state)
		local preview_count = getPreviewCount(state)
		local preview_index = normalizeResultIndex(state.dictionary_index or 1, preview_count)
		local preview_entry = getPreviewEntry(state, preview_index)
		return preview_entry and preview_entry.result or (state.results and state.results[1]) or {}
	end

	function LookupPreview:buildDictionaryPayload(word, result, _result_index, result_count)
		result = result or {}

		local shown_word = result.word or word or _("Dictionary")
		local dict_name = result.no_result and _("Dictionary") or (result.dict or _("Dictionary"))
		local definition_html, css = buildDefinition(self, result)

		return {
			page_type = PAGE_DICTIONARY,
			title = tostring(shown_word or _("Dictionary")),
			subtitle = buildSubtitle(shown_word, dict_name, result_count, result.no_result),
			html_body = definition_html,
			css = css,
			html_resource_directory = result.dictionary_resource_directory,
		}
	end

	-- Which of the buttons that open the full dictionary to show for a result:
	-- KOReader's popup, Dictionary Explorer at the word, or both, following the
	-- setting. Dictionary Explorer only counts when it is installed and can open
	-- the result's dictionary; the KOReader popup is shown instead when it can't,
	-- so there is always a way to the full entry.
	function LookupPreview:getDetailsButtonKinds(result)
		local mode = self:getDetailsButtonsMode()
		local explorer = self:getDictionaryExplorer()
		local can_explore = false
		if explorer and result and not result.no_result and result.dict then
			local ok, openable = pcall(explorer.canOpen, explorer, result.dict)
			can_explore = ok and openable and true or false
		end

		local show_explorer = can_explore and mode ~= DETAILS_BUTTONS_KOREADER
		local show_koreader = mode ~= DETAILS_BUTTONS_EXPLORER or not show_explorer
		return show_koreader, show_explorer
	end

	function LookupPreview:buildDictionaryButtons(state, search_text)
		if not state then
			return nil
		end

		-- Search, like Highlight, acts on the text selected in the book, also in
		-- a lookup made inside the preview.
		local root = getRootState(state)
		if root ~= state then
			search_text = root.dictionary_search_text or root.search_text or ""
		end
		search_text = search_text or state.dictionary_search_text or state.search_text or ""
		local status = getLoadStatus(state, PAGE_DICTIONARY)

		local button_specs = {
			{
				spec = { plugin_icon = ICON_HIGHLIGHT, text = _("Highlight") },
				hint = _("Highlight the selected text"),
				callback = function()
					self:closeCurrentPopup(true)
					self.current_state = nil
					return self:highlightSelection(state.dict_self, state.dict_close_callback)
				end,
			},
		}

		if status == LOAD_DONE and state.preview_count and state.preview_count > 1 then
			local current_index = state.dictionary_index or 1
			button_specs[#button_specs + 1] = {
				spec = { icon = ICON_PREVIOUS },
				hint = _("Previous dictionary result"),
				callback = function()
					return self:switchDictionaryResult((state.dictionary_index or 1) - 1)
				end,
			}
			button_specs[#button_specs + 1] = {
				spec = {
					text = string.format("%d / %d", current_index, state.preview_count),
					bold = false,
				},
				hint = string.format(_("Dictionary result %d of %d"), current_index, state.preview_count),
				weight = 0.8,
				separator_before = false,
			}
			button_specs[#button_specs + 1] = {
				spec = { icon = ICON_NEXT },
				hint = _("Next dictionary result"),
				separator_before = false,
				callback = function()
					return self:switchDictionaryResult((state.dictionary_index or 1) + 1)
				end,
			}
		end

		button_specs[#button_specs + 1] = {
			spec = { icon = ICON_SEARCH },
			hint = _("Search the selected text in the book"),
			callback = function()
				closePreviewBeforeExternalAction(self, state)
				return self:showSearchDialog(search_text)
			end,
		}

		if status == LOAD_LOADING then
			button_specs[#button_specs + 1] = {
				spec = self:getLoadingButtonSpec(),
				hint = _("Loading…"),
			}
			return button_specs
		elseif status == LOAD_ERROR then
			button_specs[#button_specs + 1] = {
				spec = { plugin_icon = ICON_RETRY, text = _("Retry") },
				hint = _("Look the text up in the dictionary again"),
				callback = function()
					return self:loadDictionary(state, true)
				end,
			}
			return button_specs
		elseif status == LOAD_IDLE or not state.dict_self then
			-- Nothing to open in the full dictionary yet.
			return button_specs
		end

		-- The Vocabulary Builder saves the book's selection as the word's
		-- context, which is not the context of a word looked up in the preview.
		if status == LOAD_DONE and not state.parent and self:showVocabularyButton() then
			if state.vocabulary_added then
				button_specs[#button_specs + 1] = {
					spec = { icon = ICON_VOCABULARY_ADDED },
					hint = _("Added to the vocabulary builder"),
				}
			else
				button_specs[#button_specs + 1] = {
					spec = { plugin_icon = ICON_VOCABULARY, icon = ICON_VOCABULARY_FALLBACK },
					hint = _("Add the word to the vocabulary builder"),
					callback = function()
						return self:addToVocabularyBuilder(state)
					end,
				}
			end
		end

		local show_koreader, show_explorer = self:getDetailsButtonKinds(getCurrentResult(state))
		if show_explorer then
			button_specs[#button_specs + 1] = {
				spec = { plugin_icon = ICON_GO_TO_DICT, text = _("Go to word") },
				hint = _("Go to this word in the dictionary (Dictionary Explorer)"),
				callback = function()
					return self:openDictionaryExplorerFromState(state)
				end,
			}
		end

		if show_koreader then
			button_specs[#button_specs + 1] = {
				spec = { plugin_icon = ICON_DETAILS, icon = ICON_DETAILS_FALLBACK },
				hint = _("Open KOReader's original dictionary popup"),
				callback = function()
					return self:openOriginalDictionaryFromState(state)
				end,
			}
		end

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
		return self:showCarousel(state, PAGE_DICTIONARY)
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

	-- Adds the looked up word to KOReader's Vocabulary Builder, as the button of
	-- KOReader's popup does (with the selection around it as context). When the
	-- word is there already, the Vocabulary Builder shows it in a dialog of its
	-- own; otherwise a notification says it was added.
	function LookupPreview:addToVocabularyBuilder(state)
		local word = trim(state and state.word or "")
		if word == "" or not self:getVocabularyBuilder() then
			return true
		end

		local book_title = self.ui.doc_props and self.ui.doc_props.display_title or _("Dictionary lookup")
		local top_before = UIManager:getTopmostVisibleWidget()
		self.ui:handleEvent(Event:new("WordLookedUp", word, book_title, true))
		state.vocabulary_added = true
		if UIManager:getTopmostVisibleWidget() == top_before then
			self:notify(_("Added to vocabulary builder."))
		end
		return self:refreshCard(PAGE_DICTIONARY)
	end

	-- A link tapped in a definition: "bword://word", or just the word. It is
	-- looked up in the same carousel, in the dictionary of the definition, as
	-- KOReader's popup does; other links (web, resources) are left alone.
	function LookupPreview:followDictionaryLink(state, link)
		local uri = link and link.uri
		if not uri or state ~= self.current_state then
			return false
		end

		local word
		if uri:sub(1, 8) == "bword://" then
			word = uri:sub(9)
		elseif not uri:find("://", 1, true) then
			word = uri
		end
		word = trim(util and util.urlDecode and util.urlDecode(word or "") or word)
		if word == "" then
			return false
		end

		local dict_name = getCurrentResult(state).dict
		self:lookUpInPreview(word, PAGE_DICTIONARY, {
			dictionary_lookup = dict_name and { dict_names = { dict_name }, fuzzy = false } or nil,
		})
		return true
	end

	-- Opens Dictionary Explorer at the word of the result being shown, like the
	-- "Go to dictionary" button of KOReader's own popup does.
	function LookupPreview:openDictionaryExplorerFromState(state)
		state = state or self.current_state
		local explorer = self:getDictionaryExplorer()
		if not (state and explorer) then
			return true
		end

		local result = getCurrentResult(state)
		local word = getFoundWord(self, state, result)
		local dict_name = result.dict
		local definition = result.definition

		closePreviewBeforeExternalAction(self, state)
		explorer:openWord(dict_name, word, definition)
		return true
	end

	-- Whether KOReader's results are definitions, nothing found, or a lookup
	-- that did not finish (results.lookup_cancelled, or a first result saying so).
	local function getResultsStatus(results)
		local first = type(results) == "table" and results[1] or nil
		if not first then
			return LOAD_EMPTY
		end
		if results.lookup_cancelled or first.lookup_cancelled then
			return LOAD_ERROR, first.definition
		end
		for index = 1, #results do
			if not results[index].no_result then
				return LOAD_DONE
			end
		end
		return LOAD_EMPTY
	end

	-- Puts the results of a dictionary lookup in the state, whether KOReader
	-- showed them to us (a lookup started from the book) or the card asked for
	-- them (see loadDictionary). `dict_self` is the ReaderDictionary, needed to
	-- open its own popup from the card.
	function LookupPreview:setDictionaryResults(state, dict_self, word, results)
		local preview_results = buildPreviewResults(results)
		local first_entry = preview_results[1] or {}
		local first_result = first_entry.result or (results and results[1]) or {}

		state.dict_self = dict_self
		state.word = word
		state.results = results or {}
		state.preview_results = preview_results
		state.preview_count = #preview_results
		state.dictionary_index = 1
		state.dictionary_search_text = self:getSearchText(word, first_result)
		state.dictionary_payload = nil
		forgetScrollPositions(state, PAGE_DICTIONARY)

		local status, message = getResultsStatus(results)
		setLoadStatus(state, PAGE_DICTIONARY, status, message)
		if status ~= LOAD_ERROR then
			state.dictionary_payload =
				self:buildDictionaryPayload(word, first_result, 1, #preview_results)
		end
		return status
	end

	-- KOReader's "No results" dialog offers a fuzzy search in an input box. The
	-- card says "No definition found" instead, and its native button still leads
	-- to KOReader's own window, so the dialog is skipped while the card looks up.
	local function skipNoResultsDialog(dictionary)
		dictionary:dismissLookupInfo()
		return false
	end

	-- The dictionary lookups the cards asked for and are still waiting for,
	-- oldest first. Several can be pending (a lookup made inside the carousel
	-- before the previous one answered): each keeps its own state.
	local function pendingCaptures(plugin)
		plugin.dictionary_captures = plugin.dictionary_captures or {}
		return plugin.dictionary_captures
	end

	-- The pending lookup that `word` answers, the oldest first.
	function LookupPreview:findDictionaryCapture(word)
		local captures = pendingCaptures(self)
		for index = 1, #captures do
			if captures[index].word == word then
				return captures[index]
			end
		end
		return nil
	end

	function LookupPreview:isDictionaryCapturePending(capture)
		local captures = pendingCaptures(self)
		for index = 1, #captures do
			if captures[index] == capture then
				return true
			end
		end
		return false
	end

	-- Stops waiting for `capture`, or for every pending lookup without one.
	-- KOReader's "No results" dialog comes back when nothing is pending.
	function LookupPreview:endDictionaryCapture(capture)
		local captures = pendingCaptures(self)
		if not capture then
			self.waiting_dictionary_lookups = nil
			for index = #captures, 1, -1 do
				self:endDictionaryCapture(captures[index])
			end
			return
		end
		if not self:isDictionaryCapturePending(capture) then
			return
		end
		for index = #captures, 1, -1 do
			if captures[index] == capture then
				table.remove(captures, index)
			end
		end

		local dictionary = capture.dictionary
		if dictionary and #captures == 0 then
			if rawget(dictionary, "showNoResultsDialog") == skipNoResultsDialog then
				dictionary.showNoResultsDialog = self.saved_no_results_dialog
			end
			self.saved_no_results_dialog = nil
		end
		if dictionary and type(dictionary.dismissLookupInfo) == "function" then
			pcall(dictionary.dismissLookupInfo, dictionary)
		end
		-- The next waiting lookup starts once KOReader is done with this one.
		if #captures == 0 and self.waiting_dictionary_lookups and #self.waiting_dictionary_lookups > 0 then
			UIManager:nextTick(function()
				self:startNextDictionaryLookup()
			end)
		end
	end

	-- Called by the patched showDict with the results of the lookup the card
	-- asked for.
	function LookupPreview:receiveDictionaryResults(capture, dict_self, word, results)
		self:endDictionaryCapture(capture)
		local state = capture.state
		if not self:isStateOpen(state) then
			-- The carousel was closed while looking up.
			return true
		end

		self:setDictionaryResults(state, dict_self, word, results)
		if state == self.current_state then
			self:refreshCard(PAGE_DICTIONARY)
		end
		return true
	end

	-- Looks the selected text up for a carousel opened from Translate or
	-- Wikipedia, when its dictionary card is first shown. It goes through
	-- KOReader's own lookup, so fuzzy search, the dictionaries enabled for the
	-- book and the lookup history are the same as for a lookup from the book;
	-- its showDict is caught (receiveDictionaryResults) and fills the card
	-- instead of opening a window.
	function LookupPreview:loadDictionary(state, force)
		if not state or state ~= self.current_state then
			return true
		end
		local status = getLoadStatus(state, PAGE_DICTIONARY)
		if status == LOAD_LOADING or (status ~= LOAD_IDLE and not force) then
			return true
		end

		local dictionary = self.ui and self.ui.dictionary
		if not (dictionary and type(dictionary.onLookupWord) == "function") then
			setLoadStatus(state, PAGE_DICTIONARY, LOAD_ERROR, _("The dictionary is not available."))
			return self:refreshCard(PAGE_DICTIONARY)
		end
		if Device:canExternalDictLookup() and G_reader_settings:isTrue("external_dict_lookup") then
			setLoadStatus(state, PAGE_DICTIONARY, LOAD_EMPTY, _("Dictionary lookups open in an external app."))
			return self:refreshCard(PAGE_DICTIONARY)
		end

		setLoadStatus(state, PAGE_DICTIONARY, LOAD_LOADING)
		self:refreshCard(PAGE_DICTIONARY)

		-- KOReader's dictionary does one lookup at a time (they share its
		-- progress message and the trap that cancels them): a lookup asked for
		-- while another runs waits for it (see endDictionaryCapture).
		if #pendingCaptures(self) > 0 then
			local waiting = self.waiting_dictionary_lookups or {}
			self.waiting_dictionary_lookups = waiting
			waiting[#waiting + 1] = state
			return true
		end
		return self:startDictionaryLookup(state)
	end

	-- Starts the lookup of a card marked as loading.
	function LookupPreview:startDictionaryLookup(state)
		local dictionary = self.ui.dictionary
		local text = state.search_text or ""
		local ok_clean, word = pcall(dictionary.cleanSelection, dictionary, text, false)
		word = ok_clean and word or text

		local capture = { state = state, word = word, dictionary = dictionary }
		local captures = pendingCaptures(self)
		if rawget(dictionary, "showNoResultsDialog") ~= skipNoResultsDialog then
			self.saved_no_results_dialog = rawget(dictionary, "showNoResultsDialog")
		end
		captures[#captures + 1] = capture
		dictionary.showNoResultsDialog = skipNoResultsDialog

		-- KOReader calls this instead of showDict when the lookup is cancelled
		-- right after it started.
		local function onCancelled()
			if not self:isDictionaryCapturePending(capture) then
				return
			end
			self:endDictionaryCapture(capture)
			if self:isStateOpen(state) then
				setLoadStatus(state, PAGE_DICTIONARY, LOAD_ERROR, _("Dictionary lookup interrupted."))
			end
			if state == self.current_state then
				self:refreshCard(PAGE_DICTIONARY)
			end
		end

		local ok, err
		local restricted = state.dictionary_lookup
		if restricted then
			-- A followed link: only in its dictionary, as KOReader's popup does.
			ok, err = pcall(function()
				require("ui/trapper"):wrap(function()
					dictionary:stardictLookup(word, restricted.dict_names, restricted.fuzzy, nil, nil, onCancelled)
				end)
			end)
		else
			ok, err = pcall(dictionary.onLookupWord, dictionary, word, true, nil, state.highlight_self, nil, onCancelled)
		end
		if not ok then
			logger.warn("LookupPreview: dictionary lookup failed:", err)
			self:endDictionaryCapture(capture)
			setLoadStatus(state, PAGE_DICTIONARY, LOAD_ERROR, _("Dictionary lookup failed."))
			if state == self.current_state then
				self:refreshCard(PAGE_DICTIONARY)
			end
		end
		return true
	end

	-- Starts the oldest waiting lookup whose card is still open and loading;
	-- the others were closed meanwhile.
	function LookupPreview:startNextDictionaryLookup()
		local waiting = self.waiting_dictionary_lookups or {}
		while #waiting > 0 and #pendingCaptures(self) == 0 do
			local state = table.remove(waiting, 1)
			if self:isStateOpen(state) and getLoadStatus(state, PAGE_DICTIONARY) == LOAD_LOADING then
				return self:startDictionaryLookup(state)
			end
		end
		return true
	end
end
