--[[
Functional regression: the behaviour of the viewer, checked with real gestures
(swipes, taps, long presses) sent down the same path a finger takes.

  opening        the entry is centred and highlighted, the page fits one screen
  paging         by swipe, key and tap; contiguous in both directions
  walking        the breadcrumb, the back and forward buttons, the trail's semantics
  selection      the dock, Go to word, Copy and the vocabulary button
  formats        the dictzip (Oxford) and plain (English-Portuguese) paths, and the
                 three kinds of text (m, h, x)
  the action     "open at a word" through KOReader's Dispatcher, and the
                 caches being released when the viewer closes

A check whose dictionary is not installed is reported as SKIP.
]]

local Dispatcher = require("dispatcher")
local Device = require("device")

return function(H, ui)
	local dictionaries = H.dictionaries().by
	local pt, en, ox = dictionaries.pt, dictionaries.en, dictionaries.ox
	local viewer
	local selected_word -- { select = fn, word = string } once the selection step has found a word

	-- ---- opening ----------------------------------------------------------
	H.step(1, function()
		for _index, spec in ipairs({ { pt, "pt" }, { en, "en" }, { ox, "ox" } }) do
			local dictionary, key = spec[1], spec[2]
			local word = H.profiles[key].open
			if dictionary then
				local opened = H.newViewer(dictionary, word)
				local entry = dictionary:getEntry(opened.highlighted)
				H.check(
					string.format("opens at '%s' in %s: entry centred, page fits one screen", word, dictionary.name:sub(1, 22)),
					entry.word:lower():find(word, 1, true) ~= nil
						and opened.first <= opened.highlighted
						and opened.highlighted <= opened.last
						and H.fits(opened),
					string.format("page %d..%d", opened.first, opened.last)
				)
				opened:onCloseWidget()
			else
				H.skip("opens at '" .. word .. "' (" .. key .. ")", "dictionary not installed")
			end
		end
	end)

	-- ---- paging ------------------------------------------------------------
	H.step(1, function()
		if not pt then
			H.skip("paging, walking and selection", "the Portuguese dictionary is not installed")
			return
		end
		viewer = H.newViewer(pt, "casa")
		require("ui/uimanager"):show(viewer)
		H.check("no breadcrumb at the start, and the footer is Go to word + close", viewer.breadcrumb == nil and #H.footer(viewer) == 2)
	end)
	H.step(1, function()
		if not viewer then
			return
		end
		local area = viewer.html_widget.dimen
		local x, y = area.x + area.w / 2, area.y + area.h / 2
		local start = viewer.first
		H.gesture("swipe", x, y, { direction = "west" })
		local next_start = viewer.first
		H.check("swipe left goes to the next page", next_start > start)
		H.gesture("swipe", x, y, { direction = "east" })
		H.check("swipe right goes to the previous page", viewer.first < next_start)

		local contiguous = true
		for _step = 1, 40 do
			local previous_last = viewer.last
			viewer:showNext()
			contiguous = contiguous and viewer.first == previous_last + 1
		end
		for _step = 1, 40 do
			local previous_first = viewer.first
			viewer:showPrevious()
			contiguous = contiguous and viewer.last == previous_first - 1
		end
		H.check("40 pages forward and 40 back are always contiguous", contiguous)
		H.check("every page fits one screen", H.fits(viewer))
	end)

	-- ---- walking -----------------------------------------------------------
	H.step(1, function()
		if not viewer then
			return
		end
		viewer:goToWord("livro")
		H.check("the breadcrumb appears after the first Go to word", viewer.breadcrumb ~= nil and H.trailText(viewer) == "casa>livro")
		local footer = H.footer(viewer)
		H.check(
			"the footer becomes < | Go to word | > | close, with > dimmed on the latest word",
			#footer == 4 and footer[1].icon == "chevron.left" and footer[1].enabled and footer[2].text == "Go to word"
				and footer[3].icon == "chevron.right" and not footer[3].enabled and footer[4].icon == "close"
		)
		for _index, word in ipairs(H.profiles.pt.walk) do
			viewer:goToWord(word)
		end
		H.check("the latest word is bold and the page fits", H.boldWord(viewer) == viewer.trail[#viewer.trail].word and H.fits(viewer))
		H.tapButton(viewer, "chevron.right")
	end)
	H.step(0.5, function()
		if viewer then
			H.check("forward does nothing on the last word", viewer.trail_index == #viewer.trail)
		end
	end)

	-- One real tap per step: the Button runs its callback on the next tick.
	local intact, always_visible, snapshot = true, true, nil
	for _index = 1, 8 do
		H.step(0.4, function()
			if viewer then
				snapshot = H.trailText(viewer)
				H.tapButton(viewer, "chevron.left")
			end
		end)
		H.step(0.4, function()
			if viewer then
				intact = intact and H.trailText(viewer) == snapshot
				always_visible = always_visible and H.boldWord(viewer) == viewer.trail[viewer.trail_index].word
			end
		end)
	end
	H.step(0.4, function()
		if viewer then
			H.check("back walks to the first word", viewer.trail_index == 1, "index " .. viewer.trail_index)
			H.check("the trail stays intact and the bold word in view while walking back", intact and always_visible)
		end
	end)
	for _index = 1, 8 do
		H.step(0.4, function()
			if viewer then
				H.tapButton(viewer, "chevron.right")
			end
		end)
	end
	H.step(0.5, function()
		if viewer then
			H.check("forward walks to the last word again", viewer.trail_index == #viewer.trail, "index " .. viewer.trail_index)
		end
	end)
	H.step(0.4, function()
		if viewer then
			H.tapButton(viewer, "chevron.left")
		end
	end)
	H.step(0.4, function()
		if viewer then
			H.tapButton(viewer, "chevron.left")
		end
	end)
	H.step(0.5, function()
		if not viewer then
			return
		end
		local kept = {}
		for index = 1, viewer.trail_index do
			kept[#kept + 1] = viewer.trail[index].word
		end
		viewer:goToWord("zebra")
		local words = {}
		for _index, crumb in ipairs(viewer.trail) do
			words[#words + 1] = crumb.word
		end
		local expected_length = #kept + 1
		local same_start = table.concat(words, ">", 1, #kept) == table.concat(kept, ">")
		H.check("a new word after going back replaces what came after", #words == expected_length and same_start, table.concat(words, ">"))
	end)

	-- ---- selection ---------------------------------------------------------
	H.step(1, function()
		if not viewer then
			return
		end
		local box = viewer.html_widget.htmlbox_widget
		local page = box.document:openPage(box.page_number)
		local lines = page:getPageText()
		page:close()
		local target, line
		for _index, candidate in ipairs(lines) do
			local words = {}
			for _index2, word in ipairs(candidate) do
				if type(word) == "table" and word.word:match("^%a%a%a+$") then
					words[#words + 1] = word
				end
			end
			if #words >= 3 and not target then
				target, line = words[2], candidate
			end
		end
		if not target then
			H.skip("selection dock", "no plain word found on the page")
			return
		end
		local x = box.dimen.x + (target.x0 + target.x1) / 2
		local y = box.dimen.y + (line.y0 + line.y1) / 2
		local function select()
			H.gesture("hold", x, y)
			H.gesture("hold_release", x, y)
			return viewer.selection_dock
		end
		local builder = ui.vocabbuilder ~= nil
		selected_word = { select = select, word = target.word }
		local dock = select()
		local buttons = dock and dock.buttons[1] or {}
		H.check(
			"the dock for one word is " .. (builder and "vocabulary builder, " or "") .. "Copy, Go to word, in that order",
			dock ~= nil and #buttons == (builder and 3 or 2) and buttons[#buttons].text == "Go to word" and buttons[#buttons - 1].text == "Copy"
				and (not builder or (buttons[1].icon or ""):match("icons/add_word%.svg$"))
		)
		if dock then
			buttons[#buttons - 1].callback()
		end
		H.check("Copy puts the word on the clipboard and closes the dock", Device.input.getClipboardText() == target.word and viewer.selection_dock == nil, Device.input.getClipboardText())

		-- The vocabulary button: an icon, so holding it says what it does.
		if not builder then
			H.skip("the vocabulary button", "KOReader's vocabulary builder is not active")
			return
		end
		-- The dock is laid out when it is painted, and a button acts on the next
		-- tick: each stage waits a moment (all within this step: the next one
		-- starts a second later).
		local UIManager = require("ui/uimanager")
		dock = select()
		UIManager:scheduleIn(0.4, function()
			local icon_button = dock.buttontable.buttons_layout[1][1]
			H.check("the vocabulary button is narrower than a text button", icon_button.dimen.w < dock.buttontable.buttons_layout[1][2].dimen.w)
			H.gesture("hold", icon_button.dimen.x + icon_button.dimen.w / 2, icon_button.dimen.y + icon_button.dimen.h / 2)
			H.gesture("hold_release", icon_button.dimen.x + icon_button.dimen.w / 2, icon_button.dimen.y + icon_button.dimen.h / 2)
		end)
		UIManager:scheduleIn(0.8, function()
			H.check(
				"holding it shows what it does",
				H.findWidget(function(widget)
					return widget.text == "Add to vocabulary builder" and widget.timeout ~= nil
				end) ~= nil
			)
			local DB = package.loaded["db"]
			H.check("the word is not in the vocabulary yet", DB and not DB:hasWord(target.word))
			dock.buttons[1][1].callback()
			local added = DB and DB:hasWord(target.word)
			H.check("tapping it adds the word and closes the dock", added and viewer.selection_dock == nil, target.word)
			H.check("the book's own selection is not stored as the word's context", added and added.highlight == nil and added.prev_context == nil)
			H.closeStartupMessages() -- the hint
		end)
	end)

	-- Once the word is in the vocabulary the same button shows another icon and
	-- takes it out again (after asking).
	H.step(1, function()
		if not (viewer and selected_word and ui.vocabbuilder) then
			return
		end
		local UIManager = require("ui/uimanager")
		local DB = package.loaded["db"]
		local dock = selected_word.select()
		local button = dock and dock.buttons[1][1]
		H.check("for a word that is in the vocabulary the button shows the remove icon", button ~= nil and (button.icon or ""):match("icons/remove_word%.svg$") ~= nil)
		UIManager:scheduleIn(0.4, function()
			local icon_button = dock.buttontable.buttons_layout[1][1]
			local cx, cy = icon_button.dimen.x + icon_button.dimen.w / 2, icon_button.dimen.y + icon_button.dimen.h / 2
			H.gesture("hold", cx, cy)
			H.gesture("hold_release", cx, cy)
		end)
		UIManager:scheduleIn(0.8, function()
			H.check(
				"holding it now says it removes",
				H.findWidget(function(widget)
					return widget.text == "Remove from vocabulary builder" and widget.timeout ~= nil
				end) ~= nil
			)
			H.closeStartupMessages() -- the hint
			dock.buttons[1][1].callback()
		end)
		UIManager:scheduleIn(1.2, function()
			local box = H.findWidget(function(widget)
				return widget.ok_callback ~= nil
			end)
			H.check("tapping it asks before removing", box ~= nil and viewer.selection_dock == nil and DB:hasWord(selected_word.word) ~= nil)
			if box then
				box.ok_callback()
				UIManager:close(box)
			end
			H.check("confirming removes the word", not DB:hasWord(selected_word.word))
			H.closeStartupMessages()
		end)
	end)

	-- ---- the other formats -------------------------------------------------
	H.step(1, function()
		for _index, spec in ipairs({ { ox, "ox", "love" }, { en, "en", "apple" }, { dictionaries.da, "da", "sol" }, { dictionaries.pe, "pe", "disco" }, { dictionaries.wk, "wk", "apple" } }) do
			local dictionary, key, goto_word = spec[1], spec[2], spec[3]
			if dictionary then
				local opened = H.newViewer(dictionary, H.profiles[key].open)
				local fine = true
				for _step = 1, 15 do
					local previous_last = opened.last
					opened:showNext()
					fine = fine and opened.first == previous_last + 1 and H.fits(opened)
				end
				opened:goToWord(goto_word)
				local reached = dictionary:getEntry(opened.highlighted).word:lower():find(goto_word, 1, true) ~= nil
				H.check(dictionary.name:sub(1, 22) .. ": 15 contiguous pages that fit, then Go to word", fine and reached)
				opened:onCloseWidget()
			else
				H.skip("other formats (" .. key .. ")", "dictionary not installed")
			end
		end
	end)

	-- ---- the "x" text ---------------------------------------------------------
	H.step(1, function()
		for _index, key in ipairs({ "da", "pe" }) do
			local dictionary = dictionaries[key]
			if dictionary then
				local word = H.profiles[key].open
				local opened = H.newViewer(dictionary, word)
				local entry = dictionary:getEntry(opened.highlighted)
				local html = opened:_readHtml(entry)
				H.check(
					dictionary.name:sub(1, 22) .. ': "x" text comes out tidy (bold headword first, no <k>, no tabs, no blank lines)',
					dictionary.text_type == "x" and html:find("^<b>" .. entry.word:gsub("%p", "%%%0")) ~= nil
						and not html:find("<k>", 1, true) and not html:find("\t", 1, true) and not html:find("<br/><br/>", 1, true),
					html:sub(1, 80)
				)
				opened:onCloseWidget()
			else
				H.skip('"x" text (' .. key .. ")", "dictionary not installed")
			end
		end
	end)

	-- ---- the action ---------------------------------------------------------
	H.step(1, function()
		if viewer then
			viewer:onClose()
		end
		local plugin = ui.dictionaryexplorer
		if not plugin then
			H.skip("the Dispatcher action", "the plugin is not active (it needs KOReader v2026.07 or newer)")
			return
		end
		Dispatcher:execute({ dictionaryexplorer_open_at_word = true })
		local dialog = H.findInputDialog()
		H.check("the Dispatcher action shows the word dialog", dialog ~= nil)
		if dialog then
			local word = pt and "livro" or H.profiles.en.open
			dialog:setInputText(word)
			dialog.buttons[1][2].callback()
		end
	end)
	H.step(2, function()
		local opened = H.findViewer()
		if not H.findInputDialog() and not opened then
			return
		end
		H.check("the action opens the viewer", opened ~= nil)
		if opened then
			H.check("no file is left open and no HTML is kept while idle", opened.dictionary._dict_file == nil and opened._html_cache == nil)
			opened:onClose()
			H.check("closing releases the dictionary caches", opened.dictionary._dict_file == nil and opened.dictionary._chunks == nil)
		end
	end)

	H.finish()
end
