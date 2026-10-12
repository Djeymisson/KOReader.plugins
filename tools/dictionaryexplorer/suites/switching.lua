--[[
Going to a word in another dictionary, and the trail through several.

  the dock        a selected word offers, last in the dock, an icon that lists
                  the other dictionaries: only when one of those loaded has
                  the word as it is, or one not loaded yet might; the list
                  then uses what the dock found out
  the list        only the other dictionaries that have the word (also through
                  its accents), with the entry when it is spelled otherwise; one
                  whose index was never prepared is listed as such, and
                  choosing it prepares it first; no dictionary at all is said
  the trail       choosing one goes there, the trail going on through it: back
                  returns to the word, and the dictionary, before, forward to
                  the other one; the dictionary left lets go of what it kept
  not here        a word with no entry here but in other dictionaries says so on
                  the page; its suggestions start with them, and choosing one
                  goes there in place of the missed word in the trail; only
                  dictionaries whose index is ready are asked; for a word no
                  dictionary has, the suggestions end with the closest entries
                  of each other dictionary (3 at most)
  the mark        the header says how many other dictionaries have the word the
                  page is about, and not once it is off the page
  search          the footer's Search lists, for a word typed, what every
                  dictionary has (this one first, with accents too), and
                  choosing one goes there; with none, the closest entries
  the header      tapping it lists the other dictionaries that have the word
                  the page is about, and goes to it there
  continuing      the exploration is one for all dictionaries: it continues in
                  the dictionary it was left in, its trail still crossing them;
                  a word whose dictionary changed since is looked for again by
                  the word, one whose dictionary is gone is left out; what
                  v1.4.0 saved (one exploration per dictionary) is taken over

It runs on the fixtures, through the plugin (it needs KOReader v2026.07 or newer).
]]

return function(H, ui)
	local UIManager = require("ui/uimanager")
	local Screen = require("device").screen
	local SETTING = "dictionaryexplorer_exploration"
	local plugin = ui.dictionaryexplorer
	local by = H.dictionaries().by
	local text, html, xdxf = by.fx, by.fh, by.fd
	if not (plugin and text and html and xdxf) then
		H.skip("other dictionaries", "the plugin is not active, or the fixtures were not found")
		H.finish()
		return
	end

	local viewer
	local function onTop()
		local stack = UIManager._window_stack
		return stack[#stack] and stack[#stack].widget
	end
	local function close()
		local shown = H.findViewer()
		if shown then
			shown:onClose()
		end
	end
	local function entryWord()
		return viewer.dictionary:getEntry(viewer.highlighted).word
	end
	-- A list's choices, whatever its page (see Viewer:_showList()).
	local function listLabels(dialog)
		local labels = {}
		for _index, choice in ipairs(dialog and dialog.choices or {}) do
			labels[#labels + 1] = choice.text
		end
		return labels
	end
	local function listed(dialog, prefix)
		for _index, choice in ipairs(dialog and dialog.choices or {}) do
			if choice.text:sub(1, #prefix) == prefix then
				return choice
			end
		end
	end

	-- ---- the dock --------------------------------------------------------------------
	-- Selects a plain word of the page with a real long press, and returns it
	-- with the dock's last button.
	local function selectWord()
		UIManager:forceRePaint()
		local box = viewer.html_widget.htmlbox_widget
		local page = box.document:openPage(box.page_number)
		local lines = page:getPageText()
		page:close()
		local target, line
		for _index, candidate in ipairs(lines) do
			for _index2, word in ipairs(candidate) do
				if not target and type(word) == "table" and word.word:match("^%a%a%a%a+$") then
					target, line = word, candidate
				end
			end
		end
		if not target then
			return nil
		end
		local x, y = box.dimen.x + (target.x0 + target.x1) / 2, box.dimen.y + (line.y0 + line.y1) / 2
		H.gesture("hold", x, y)
		H.gesture("hold_release", x, y)
		local buttons = viewer.selection_dock and viewer.selection_dock.buttons[1] or {}
		local last = buttons[#buttons]
		local offered = last ~= nil and (last.icon or ""):match("icons/other_dictionary%.svg$") ~= nil
		return target.word, offered and last or nil
	end
	-- Whether another dictionary has `word` as it is, asked directly.
	local function elsewhere(word)
		for _index, dictionary in ipairs(viewer:_otherDictionaries()) do
			if dictionary:isIndexed() and select(2, dictionary:locateText(word)) then
				return true
			end
		end
		return false
	end

	H.step(1, function()
		G_reader_settings:delSetting(SETTING)
		plugin:openAt(html, "house")
		viewer = H.findViewer()
		local word, button = selectWord()
		if not word then
			H.skip("the dock's other dictionaries button", "no plain word found on the page")
			return
		end
		H.check(
			"with every dictionary loaded, the dock offers the other dictionaries only when one has the word",
			(button ~= nil) == elsewhere(word),
			string.format("%q: %s", word, button and "offered" or "not offered")
		)
		viewer:_closeSelectionDock()
		viewer:_clearSelection()

		-- A dictionary not loaded yet might have it: the button is offered.
		xdxf.idx, xdxf.syn, xdxf.offsets, xdxf.first_keys, xdxf.count = nil, nil, nil, nil, nil
		word, button = selectWord()
		H.check("with a dictionary not loaded yet, it is offered", button ~= nil, word)
		if button then
			button.callback()
		end
		-- The list, or, when no other dictionary has the word, a message saying so.
		local dialog = viewer.dictionaries_dialog
		local message = H.findWidget(function(widget)
			return type(widget.text) == "string" and widget.text:find("No other dictionary has", 1, true) ~= nil
		end)
		H.check("and it looks the word up in the others, loading that one then", (dialog ~= nil and onTop() == dialog or message ~= nil) and viewer.selection_dock == nil and xdxf.idx ~= nil)
		if dialog then
			UIManager:close(dialog)
		end
		if message then
			UIManager:close(message)
		end

		-- What the dock asks: the word as it is only (no accent search), quickly.
		local started = os.clock()
		local known, unknown = viewer:_checkSelection("casa")
		local cpu = (os.clock() - started) * 1000
		H.check("the dock's check finds the word in the dictionaries that have it", known[text] == "casa" and known[xdxf] == "casa" and known[html] == nil and not unknown)
		known = viewer:_checkSelection("acao")
		H.check("but does not look for its accents (a selection is spelled right)", known[text] == false)
		H.say(string.format("  the dock's check of %d other dictionaries: %.2f ms CPU (not checked)", #viewer:_otherDictionaries(), cpu))

		-- The list then uses what the dock found out.
		local asked = {}
		local resolve = H.StarDict.resolve
		H.StarDict.resolve = function(dictionary, ...)
			asked[dictionary] = true
			return resolve(dictionary, ...)
		end
		known = viewer:_checkSelection("casa")
		viewer:showOtherDictionaries("casa", known)
		H.StarDict.resolve = resolve
		H.check("and the list does not ask them again", not asked[text] and not asked[xdxf] and listed(viewer.dictionaries_dialog, text.name) ~= nil)
		if viewer.dictionaries_dialog then
			UIManager:close(viewer.dictionaries_dialog)
		end
	end)

	-- ---- the list --------------------------------------------------------------------
	H.step(0.5, function()
		viewer:showOtherDictionaries("casa")
		local dialog = viewer.dictionaries_dialog
		H.check(
			"the list has the other dictionaries with the word, not this one",
			listed(dialog, text.name) ~= nil and listed(dialog, xdxf.name) ~= nil and listed(dialog, html.name) == nil,
			table.concat(listLabels(dialog), " | ")
		)
		if dialog then
			UIManager:close(dialog)
		end

		viewer:showOtherDictionaries("acao")
		dialog = viewer.dictionaries_dialog
		local row = listed(dialog, text.name)
		H.check("a dictionary that has it with accents shows the entry", row ~= nil and row.text == text.name .. " (ação)" and listed(dialog, xdxf.name) == nil, row and row.text)
		if dialog then
			UIManager:close(dialog)
		end

		viewer:showOtherDictionaries("qqqzzzz")
		local message = H.findWidget(function(widget)
			return type(widget.text) == "string" and widget.text:find("No other dictionary has", 1, true) ~= nil
		end)
		H.check("when no other dictionary has it, that is said, with no list", message ~= nil and viewer.dictionaries_dialog == nil)
		if message then
			UIManager:close(message)
		end
	end)

	-- ---- the trail --------------------------------------------------------------------
	H.step(0.5, function()
		viewer:showOtherDictionaries("casa")
		local row = listed(viewer.dictionaries_dialog, text.name)
		if row then
			row.callback()
		end
		H.check(
			"choosing one goes to the word there, with the list gone",
			viewer.dictionary == text and entryWord() == "casa" and viewer.dictionaries_dialog == nil and onTop() == viewer
		)
		H.check("the trail goes on through it", H.trailText(viewer) == "house>casa" and viewer.trail[1].dictionary == html and viewer.trail[2].dictionary == text, H.trailText(viewer))
		H.check("the dictionary left lets go of what it kept", html._dict_file == nil and html._chunks == nil)
		H.check("the header names the dictionary shown", viewer.column ~= nil and viewer.dictionary.name == text.name)

		viewer:goToWord("livro")
		H.check("Go to word goes on in the new dictionary", viewer.dictionary == text and entryWord() == "livro" and H.trailText(viewer) == "house>casa>livro")
		viewer:goToCrumb(1)
		H.check("going back to the first word returns to its dictionary", viewer.dictionary == html and entryWord() == "house")
		viewer:goToCrumb(2)
		H.check("and the next one to the other one again", viewer.dictionary == text and entryWord() == "casa")
		H.check("the trail stays as it was", H.trailText(viewer) == "house>casa>livro")
	end)

	-- The case this is for, with the author's dictionaries: an English word in the
	-- English-Portuguese one, then a Portuguese word in the Portuguese one.
	H.step(0.5, function()
		local en, pt = by.en, by.pt
		if not (en and pt) then
			H.skip("from English-Portuguese to Portuguese", "the Priberam dictionaries are not installed")
			return
		end
		close()
		plugin:openAt(en, "house")
		viewer = H.findViewer()
		viewer:showOtherDictionaries("casa")
		local row = listed(viewer.dictionaries_dialog, pt.name)
		if row then
			row.callback()
		end
		H.check("an English word, then “casa” in the Portuguese dictionary", row ~= nil and viewer.dictionary == pt and entryWord() == "casa", viewer.dictionary.name)
		viewer:goToCrumb(1)
		-- Priberam's English-Portuguese dictionary has it as "House".
		H.check("and back to the English one", viewer.dictionary == en and entryWord():lower() == "house", string.format("%s: %s, trail %s @%d", viewer.dictionary.name, tostring(viewer.highlighted and entryWord()), H.trailText(viewer), viewer.trail_index))
		close()
		plugin:openAt(html, "house")
		viewer = H.findViewer()
		viewer:goToWordIn(text, "casa")
		viewer:goToWord("livro")
	end)

	-- ---- not here ---------------------------------------------------------------------
	local function noticeText()
		local notice = viewer and viewer.miss_notice
		local box = notice and notice[2] and notice[2][2]
		return box and box.text or ""
	end

	H.step(0.5, function()
		close()
		plugin:openAt(html, "house")
		viewer = H.findViewer()
		viewer:goToWord("casa")
		-- The first of the other dictionaries that have it, in KOReader's order.
		local holder, holders = nil, 0
		for _index, dictionary in ipairs(viewer:_otherDictionaries()) do
			if dictionary:resolve("casa").kind == "exact" then
				holder = holder or dictionary
				holders = holders + 1
			end
		end
		H.check(
			"a word with no entry here but elsewhere: the page says where",
			holder ~= nil and viewer.dictionary == html and noticeText():find(string.format("It is in %s and %d more", holder.name, holders - 1), 1, true) ~= nil,
			noticeText()
		)
		viewer:showSuggestions()
		local first = viewer.suggestions_dialog and viewer.suggestions_dialog.choices[1]
		H.check("its suggestions start with the other dictionaries", holder ~= nil and first ~= nil and first.text == "“casa” in " .. holder.name, first and first.text)
		if first then
			first.callback()
		end
		H.check(
			"choosing one goes there, in place of the missed word in the trail",
			viewer.dictionary == holder and entryWord() == "casa" and H.trailText(viewer) == "house>casa" and viewer.trail[2].dictionary == holder and viewer.miss_notice == nil,
			H.trailText(viewer)
		)

		viewer:goToWord("qqqzzzz")
		H.check("a word no dictionary has: no other dictionary named", noticeText():find("It is in", 1, true) == nil and noticeText() ~= "")
	end)

	-- ---- the header ---------------------------------------------------------------------
	H.step(0.5, function()
		viewer:goToWord("casa") -- in the dictionary chosen above
		local here = viewer.dictionary
		UIManager:forceRePaint()
		H.gesture("tap", Screen:getWidth() / 2, 10)
		local dialog = viewer.dictionaries_dialog
		local row = here ~= xdxf and listed(dialog, xdxf.name)
		H.check("tapping the header lists the other dictionaries with the word on the page", row and listed(dialog, here.name) == nil, table.concat(listLabels(dialog), " | "))
		if row then
			row.callback()
		end
		H.check("and goes to it there", viewer.dictionary == xdxf and entryWord() == "casa" and viewer.trail[#viewer.trail].dictionary == xdxf)
	end)

	-- A dictionary whose index was never prepared.
	H.step(0.5, function()
		viewer:goToCrumb(1) -- in html
		local cache = xdxf.cache_path
		xdxf.idx, xdxf.syn, xdxf.offsets, xdxf.first_keys, xdxf.count = nil, nil, nil, nil, nil
		os.remove(cache)
		viewer:showOtherDictionaries("casa")
		local row = listed(viewer.dictionaries_dialog, xdxf.name)
		H.check("a dictionary never prepared is listed as such", row ~= nil and row.text == xdxf.name .. " (index not prepared yet)", row and row.text)
		if row then
			-- A missed word is not looked for in it either, so nothing is prepared.
			UIManager:close(viewer.dictionaries_dialog)
			viewer:goToWord("sol") -- the XDXF fixture has it (and the Portuguese dictionary, when installed)
			local asked = false
			for _index, found in ipairs(viewer.miss and viewer.miss.elsewhere or {}) do
				asked = asked or found.dictionary == xdxf
			end
			H.check("a dictionary never prepared is not asked about a missed word", not asked and not xdxf:isIndexed(), noticeText())
			-- isIndexed() would have loaded a cache: there is none.
			viewer:showOtherDictionaries("casa")
			row = listed(viewer.dictionaries_dialog, xdxf.name)
		end
		if row then
			row.callback() -- prepares it (with a notice), then goes there
		end
	end)
	H.step(1, function()
		H.check("choosing it prepares it, then goes to the word there", viewer.dictionary == xdxf and entryWord() == "casa" and xdxf:isIndexed())
		H.closeStartupMessages()
	end)

	-- ---- continuing --------------------------------------------------------------------
	H.step(0.5, function()
		local trail, length = H.trailText(viewer), #viewer.trail
		close()
		local state = G_reader_settings:readSetting(SETTING)
		H.check("one exploration, in the dictionary it was left in", state and state.dictionary == xdxf.name and #state.trail == length and state.trail[length].dictionary == xdxf.name, state and state.dictionary)
		plugin:continueExploring()
		viewer = H.findViewer()
		H.check("continuing reopens it there, with the trail crossing dictionaries", viewer and viewer.dictionary == xdxf and H.trailText(viewer) == trail, viewer and H.trailText(viewer))
		viewer:goToCrumb(1)
		H.check("and a word of another dictionary still goes there", viewer.dictionary == html and entryWord() == "house")
		close()

		-- A dictionary of the trail changed since: its word is looked for again.
		state = G_reader_settings:readSetting(SETTING)
		state.counts[html.name] = state.counts[html.name] + 3
		state.trail[1].position = 0
		plugin:continueExploring()
		viewer = H.findViewer()
		viewer:goToCrumb(1)
		H.check("a word whose dictionary changed is looked for again by the word", viewer.dictionary == html and entryWord() == "house", entryWord())
		close()

		-- A dictionary of the trail is gone.
		state = G_reader_settings:readSetting(SETTING)
		state.trail[2].dictionary = "A dictionary that is not installed"
		length = #state.trail
		plugin:continueExploring()
		viewer = H.findViewer()
		H.check("a word whose dictionary is gone is left out", viewer and #viewer.trail == length - 1)
		close()
	end)

	-- What v1.4.0 saved.
	H.step(0.5, function()
		plugin:openAt(text, "gato")
		viewer = H.findViewer()
		viewer:goToWord("mesa")
		local first = viewer.first
		close()
		local state = G_reader_settings:readSetting(SETTING)
		state.dictionary, state.counts = nil, nil
		for _index, crumb in ipairs(state.trail) do
			crumb.dictionary, crumb.entry = nil, nil
		end
		G_reader_settings:delSetting(SETTING)
		G_reader_settings:saveSetting("dictionaryexplorer_explorations", { last = text.name, by_dictionary = { [text.name] = state } })
		plugin:continueExploring()
		viewer = H.findViewer()
		H.check(
			"what v1.4.0 saved is continued, then replaced",
			viewer and viewer.dictionary == text and viewer.first == first and H.trailText(viewer) == "gato>mesa"
				and G_reader_settings:readSetting("dictionaryexplorer_explorations") == nil
		)
		close()
		G_reader_settings:delSetting(SETTING)
	end)

	-- ---- searching all dictionaries --------------------------------------------------------
	-- Types `word` in the footer's Search dialog, as a user does.
	local function search(word)
		viewer:showGoToDialog()
		local dialog = H.findInputDialog()
		dialog:setInputText(word)
		for _index, button in ipairs(dialog.buttons[1]) do
			if button.text == "Search" then
				button.callback()
			end
		end
		return viewer.search_dialog
	end
	-- The dictionary and the entry a result row names ("entry — dictionary").
	local function results(dialog)
		local found = {}
		for _index, choice in ipairs(dialog and dialog.choices or {}) do
			local entry, name = choice.text:match("^(.-) — (.+)$")
			found[#found + 1] = { entry = entry, name = name, choice = choice }
		end
		return found
	end

	H.step(0.5, function()
		close()
		plugin:openAt(text, "livro")
		viewer = H.findViewer()
		H.check("the footer's button is Search", H.footer(viewer)[1].text == "Search")
		local holders = { text.name }
		for _index, dictionary in ipairs(viewer:_otherDictionaries()) do
			if dictionary:resolve("casa").kind ~= "closest" then
				holders[#holders + 1] = dictionary.name
			end
		end
		local dialog = search("casa")
		local found = results(dialog)
		local names = {}
		for _index, result in ipairs(found) do
			names[#names + 1] = result.name
		end
		H.check(
			"Search lists every dictionary that has the word, this one first, each with its entry",
			dialog ~= nil and table.concat(names, "|") == table.concat(holders, "|") and found[1].entry == "casa",
			table.concat(listLabels(dialog), " | ")
		)
		H.check("the page stays as it was until a result is chosen", viewer.dictionary == text and entryWord() == "livro")
		if dialog then
			UIManager:close(dialog)
		end

		-- Typed without its accents: "sofa" in English, "sofá" in Portuguese.
		viewer:goToWordIn(html, "house")
		found = results(search("sofa"))
		local sofa
		for _index, result in ipairs(found) do
			if result.name == text.name then
				sofa = result
			end
		end
		H.check("with its accents too: “sofa” finds “sofá” in Portuguese", found[1] and found[1].name == html.name and sofa ~= nil and sofa.entry == "sofá", table.concat(listLabels(viewer.search_dialog), " | "))
		if sofa then
			sofa.choice.callback()
		end
		H.check("choosing a result goes there, the trail going on", viewer.dictionary == text and entryWord() == "sofá" and viewer.search_dialog == nil and viewer.trail[#viewer.trail].dictionary == text)

		local en, pt = by.en, by.pt
		if en and pt then
			viewer:goToWordIn(en, "house")
			found = results(search("sofa"))
			local in_pt
			for _index, result in ipairs(found) do
				if result.name == pt.name then
					in_pt = result
				end
			end
			H.check("with the author's dictionaries: “sofa” in English–Portuguese also lists “sofá” in Portuguese", found[1] and found[1].name == en.name and in_pt ~= nil and in_pt.entry == "sofá", table.concat(listLabels(viewer.search_dialog), " | "))
			if viewer.search_dialog then
				UIManager:close(viewer.search_dialog)
			end
		end

		-- A word no dictionary has: the closest entries, here and elsewhere.
		viewer:goToWordIn(text, "livro")
		dialog = search("casaz")
		found = results(dialog)
		local here, in_others = false, false
		for _index, result in ipairs(found) do
			here = here or result.name == text.name
			in_others = in_others or (result.name ~= text.name and result.entry:lower():find("^casa") ~= nil)
		end
		H.check("a word no dictionary has lists the closest entries, here and in the others", dialog ~= nil and dialog.title:find("the closest ones", 1, true) ~= nil and here and in_others, table.concat(listLabels(dialog), " | "))
		if dialog then
			UIManager:close(dialog)
		end
		close()
		G_reader_settings:delSetting(SETTING)
	end)

	-- ---- closest elsewhere ----------------------------------------------------------------
	-- A word no dictionary has: the suggestions also offer the entries closest
	-- to it in the other dictionaries.
	H.step(0.5, function()
		plugin:openAt(html, "house")
		viewer = H.findViewer()
		viewer:goToWord("casaz")
		viewer:showSuggestions()
		local dialog = viewer.suggestions_dialog
		local row
		for _index, candidate in ipairs(dialog and dialog.choices or {}) do
			local label = candidate.text
			if not row and label:sub(-#text.name) == text.name and label:find("^“casa") then
				row = candidate
			end
		end
		H.check("the suggestions for a word no dictionary has include the closest entries of the others", row ~= nil, table.concat(listLabels(dialog), " | "))
		local others = 0
		for _index, candidate in ipairs(dialog and dialog.choices or {}) do
			if candidate.text:sub(-#text.name) == text.name then
				others = others + 1
			end
		end
		H.check("at most 3 for each other dictionary", others >= 1 and others <= 3, others)
		-- Spelled most like it, not merely next to it: Fixture Text has casa,
		-- Casa, casaco and casado around "casaz".
		local alike = 0
		for _index, candidate in ipairs(dialog and dialog.choices or {}) do
			local label = candidate.text
			if label:sub(-#text.name) == text.name and label:lower():find("^“casa") then
				alike = alike + 1
			end
		end
		H.check("the ones spelled most like it", alike == others, string.format("%d of %d", alike, others))
		local noise = false
		for _index, candidate in ipairs(dialog and dialog.choices or {}) do
			local label = candidate.text
			if label:find("” in ", 1, true) and not label:lower():find("^“ca") then
				noise = true
			end
		end
		H.check("and none of the others' entries that only sort near it", not noise)
		if row then
			row.callback()
		end
		H.check(
			"choosing one goes there, in place of the missed word in the trail",
			viewer.dictionary == text and entryWord():find("^casa") ~= nil and #viewer.trail == 2 and viewer.trail[2].dictionary == text,
			H.trailText(viewer)
		)
		close()
		G_reader_settings:delSetting(SETTING)
	end)

	-- ---- the header's mark ---------------------------------------------------------------
	-- When other dictionaries have the word the page is about, the header says
	-- how many, next to the dictionary's name.
	local function mark()
		return viewer.header_mark and viewer.header_mark.text or ""
	end
	H.step(0.5, function()
		plugin:openAt(text, "casa")
		viewer = H.findViewer()
		local others = 0
		for _dictionary, entry in pairs((viewer:_checkSelection("casa"))) do
			if entry then
				others = others + 1
			end
		end
		H.check("the header says how many other dictionaries have the word", others >= 2 and mark():find(string.format("also in %d more", others), 1, true) ~= nil, mark())
		viewer:showNext()
		viewer:showNext()
		H.check("not once the word's entry is off the page", mark() == "")
		-- A word only this dictionary has.
		local only
		for position = 0, text:getCount() - 1 do
			local word = text:getEntry(position).word
			if not only and word:sub(1, 1) == "q" and not viewer:_anyFound((viewer:_checkSelection(word))) then
				only = word
			end
		end
		viewer:goToWord(only)
		H.check("nor for a word only this dictionary has", mark() == "", only)
		viewer:goToWord("casa")
		H.check("and the page still fits with it", mark() ~= "" and H.fits(viewer) and viewer.column:getSize().h <= require("device").screen:getHeight(),
			string.format("mark %q, fits %s, %d of %d px", mark(), tostring(H.fits(viewer)), viewer.column:getSize().h, require("device").screen:getHeight()))
		close()
		G_reader_settings:delSetting(SETTING)
	end)

	H.finish()
end
