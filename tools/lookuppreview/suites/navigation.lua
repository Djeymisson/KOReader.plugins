--[[
Lookups made inside the carousel, and going back, with real gestures.

  link            tapping a link of an HTML definition looks its word up in
                  the same carousel, only in that dictionary, with no dictionary
                  window; the header gets a back button
  back            the back button shows the previous lookup as it was: same
                  result, same scroll position, nothing looked up again
  book selection  in a lookup made inside the carousel, Search acts on the
                  text selected in the book, and the buttons that would use the
                  book's selection for another text (Note, vocabulary builder)
                  are not offered
  hold            holding a word of the active card's text looks it up: on the
                  same card, or in the dictionary from the Translate card
  edit            the header's edit button asks for another text, starting from
                  the one shown, and looks it up on the same card
  close           closing the carousel from a nested lookup closes it all
]]

local PAGE_DICTIONARY, PAGE_TRANSLATION = 1, 2
local BACK_HINT = "Back to %s"
local EDIT_HINT = "Edit the looked up text"

return function(H, ui)
	local plugin = H.plugin
	H.stubOnline(function(text)
		return "[en] " .. text
	end, function(text)
		return { { title = text, extract = "An article about " .. text .. "." } }
	end)

	local root, link_word, root_index, root_page

	local function findLink(html)
		local box = html.htmlbox_widget
		for page = 1, box.page_count do
			local document_page = box.document:openPage(page)
			local links = document_page:getPageLinks()
			document_page:close()
			for _, link in ipairs(links or {}) do
				if link.uri and link.uri:find("^bword://") then
					return page, link
				end
			end
		end
	end

	local function tapAt(box, x, y)
		H.gesture("tap", box.dimen.x + math.floor(x), box.dimen.y + math.floor(y))
	end

	-- ---- link ----------------------------------------------------------------
	H.step(0.5, function()
		H.lookUpWord("house")
	end)
	H.step(2, function()
		root = plugin.current_state
		for index, entry in ipairs(root and root.preview_results or {}) do
			if entry.result.dict:find("Fixture HTML", 1, true) then
				root_index = index
			end
		end
		H.check("the HTML dictionary has the word", root_index ~= nil)
		H.check("the first lookup has no back button", not H.findButton(string.format(BACK_HINT, "house")))
		plugin:switchDictionaryResult(root_index)
	end)
	H.step(0.5, function()
		local html = H.activeHtml()
		local page, link = findLink(html)
		H.check("its definition has a link", link ~= nil)
		link_word = link and link.uri:sub(9)
		while html.htmlbox_widget.page_number < (page or 1) do
			html:scrollText(1)
		end
		root_page = html.htmlbox_widget.page_number
		if link then
			tapAt(html.htmlbox_widget, (link.x0 + link.x1) / 2, (link.y0 + link.y1) / 2)
		end
	end)
	H.step(1.5, function()
		local state = plugin.current_state
		H.check("tapping it looks its word up in the carousel", state and state.parent == root and state.search_text == link_word, state and state.search_text)
		H.check("with its entry", H.status(PAGE_DICTIONARY) == "done", H.status(PAGE_DICTIONARY))
		local only_html = state and #state.preview_results > 0
		for _, entry in ipairs(state and state.preview_results or {}) do
			only_html = only_html and entry.result.dict:find("Fixture HTML", 1, true) ~= nil
		end
		H.check("only in the link's dictionary", only_html)
		H.check("with no dictionary window", H.nativeWindows() == 0, H.nativeWindows())
		H.check("the header gets a back button", H.findButton(string.format(BACK_HINT, "house")) ~= nil, table.concat(H.buttonHints(), " | "))
	end)

	-- ---- book selection ------------------------------------------------------
	H.step(0.3, function()
		local hints = table.concat(H.buttonHints(), " | ")
		H.check("no vocabulary builder button in a nested lookup", not hints:find("vocabulary builder", 1, true), hints)
		H.check("Search is offered", H.tapButton("Search the selected text in the book"))
	end)
	H.step(1, function()
		local dialog = H.findWidget(function(widget)
			return widget.getInputText ~= nil
		end)
		H.check("and searches the text selected in the book", dialog and dialog:getInputText() == "house", dialog and dialog:getInputText())
		if dialog then
			require("ui/uimanager"):close(dialog)
		end
		H.check("closing the carousel", H.popup() == nil)
	end)

	-- ---- back ----------------------------------------------------------------
	local function longResults()
		local lines = {}
		for index = 1, 120 do
			lines[#lines + 1] = string.format("Line %d of a definition long enough to take several pages.", index)
		end
		local definition = table.concat(lines, "\n")
		return {
			{ dict = "Long A", word = "palavra", definition = definition },
			{ dict = "Long B", word = "palavra", definition = definition },
		}
	end

	H.step(0.5, function()
		ui.dictionary:showDict("palavra", longResults())
	end)
	H.step(1, function()
		root = plugin.current_state
		plugin:switchDictionaryResult(2)
		local html = H.activeHtml()
		html:scrollText(1)
		html:scrollText(1)
		root_page = html.htmlbox_widget.page_number
		H.check("a long definition is scrolled", root_page == 3, root_page)
		plugin:lookUpInPreview("casa")
	end)
	H.step(1.5, function()
		H.check("a nested lookup is shown", plugin.current_state.parent == root and H.status(PAGE_DICTIONARY) == "done")
		H.check("starting at the top", H.activePage() == 1, H.activePage())
		H.check("the back button is tapped", H.tapButton(string.format(BACK_HINT, "palavra")))
	end)
	H.step(0.5, function()
		H.check("back shows the previous lookup", plugin.current_state == root)
		H.check("on the same result", root.dictionary_index == 2, root.dictionary_index)
		H.check("at the same place", H.activePage() == root_page, tostring(H.activePage()) .. " " .. tostring(root_page))
		H.check("without looking it up again", H.status(PAGE_DICTIONARY) == "done")
		H.check("and with no back button", not H.findButton(string.format(BACK_HINT, "palavra")))
		H.closeCarousel()
	end)

	H.step(0.5, function()
		H.lookUpWord("house")
	end)
	H.step(2, function()
		root = plugin.current_state
	end)

	-- ---- hold ----------------------------------------------------------------
	H.step(0.3, function()
		plugin:switchDictionaryResult(root_index)
	end)
	H.step(0.5, function()
		local box = H.activeHtml().htmlbox_widget
		local x, y = box.dimen.x + 30, box.dimen.y + 12
		H.gesture("hold", x, y)
		H.gesture("hold_release", x, y)
	end)
	H.step(1.5, function()
		local state = plugin.current_state
		H.check("holding a word of the card looks it up in the carousel", state.parent == root and state.search_text ~= "", state.search_text)
		H.check("on the same card", state.active_index == PAGE_DICTIONARY and H.status(PAGE_DICTIONARY) ~= "idle", H.status(PAGE_DICTIONARY))
		plugin:goBack()
		plugin:switchToPage(PAGE_TRANSLATION)
	end)
	H.step(1, function()
		local hints = table.concat(H.buttonHints(), " | ")
		H.check("the first lookup's translation offers a note", hints:find("Save the translation as a note", 1, true) ~= nil, hints)
		local box = H.activeHtml().htmlbox_widget
		local x, y = box.dimen.x + 20, box.dimen.y + 12
		H.gesture("hold", x, y)
		H.gesture("hold_release", x, y)
	end)
	H.step(1.5, function()
		local state = plugin.current_state
		H.check("from the Translate card, the word is looked up in the dictionary", state.parent == root and state.active_index == PAGE_DICTIONARY, state.active_index)
		plugin:switchToPage(PAGE_TRANSLATION)
	end)
	H.step(1, function()
		local hints = table.concat(H.buttonHints(), " | ")
		H.check("a nested translation offers no note", not hints:find("Save the translation as a note", 1, true), hints)
		H.check("but can be copied", hints:find("Copy the translation", 1, true) ~= nil, hints)
	end)

	-- ---- edit ----------------------------------------------------------------
	H.step(0.3, function()
		H.check("the edit button is tapped", H.tapButton(EDIT_HINT))
	end)
	H.step(0.5, function()
		local dialog = plugin.edit_dialog
		H.check("it asks for the text, starting from the one shown", dialog and dialog:getInputText() == plugin.current_state.search_text, dialog and dialog:getInputText())
		if dialog then
			dialog:setInputText("mesa")
			local button = dialog.button_table:getButtonById("look_up")
			local dimen = button.dimen
			H.gesture("tap", dimen.x + math.floor(dimen.w / 2), dimen.y + math.floor(dimen.h / 2))
		end
	end)
	H.step(1, function()
		local state = plugin.current_state
		H.check("and looks it up on the same card", state.search_text == "mesa" and state.active_index == PAGE_TRANSLATION, state.search_text .. " " .. state.active_index)
		H.check("translating it", H.status(PAGE_TRANSLATION) == "done" and H.calls.last_translation == "mesa", H.calls.last_translation)
		H.check("going back keeps the text it was edited from", state.parent and state.parent.search_text ~= "mesa")
	end)

	-- ---- overlapping lookups -------------------------------------------------
	-- Two lookups started before the first one answers: each gets its own
	-- results, and nothing else opens.
	local overlap_root
	H.step(0.3, function()
		overlap_root = plugin.current_state
		plugin:lookUpInPreview("livro", PAGE_DICTIONARY)
		plugin:loadDictionary(plugin.current_state)
		plugin:lookUpInPreview("casa", PAGE_DICTIONARY)
		plugin:loadDictionary(plugin.current_state)
	end)
	H.step(2, function()
		local state = plugin.current_state
		local first = state and state.parent
		H.check("overlapping lookups: the last one is shown", state and state.search_text == "casa" and first and first.parent == overlap_root, state and state.search_text)
		H.check("with its own results", H.status(PAGE_DICTIONARY) == "done" and state.preview_results[1] and state.preview_results[1].result.word:lower() == "casa", H.status(PAGE_DICTIONARY))
		local first_status = first and first.load and first.load[PAGE_DICTIONARY] and first.load[PAGE_DICTIONARY].status
		H.check("the first one gets its own results too", first_status == "done" and first.preview_results[1] and first.preview_results[1].result.word == "livro", first_status)
		H.check("nothing else opens", H.nativeWindows() == 0 and H.popup() ~= nil, H.nativeWindows())
		H.check("and no lookup is left caught", #(plugin.dictionary_captures or {}) == 0 and rawget(ui.dictionary, "showNoResultsDialog") == nil)
	end)

	-- ---- close ---------------------------------------------------------------
	H.step(0.3, function()
		H.closeCarousel()
	end)
	H.step(0.5, function()
		H.check("closing from a nested lookup closes the carousel", H.popup() == nil and plugin.current_state == nil)
		H.check("and leaves no dictionary lookup caught", #(plugin.dictionary_captures or {}) == 0)
	end)

	H.finish()
end
