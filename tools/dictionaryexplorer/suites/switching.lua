--[[
All the dictionaries as one, in the viewer: going to a word looks for it in
all of them (the rules are in the library suite).

  going there     Go to word (dock, links, menu, popup) goes to the dictionary
                  that has the word and says so on the page; the dock has no
                  button of its own for other dictionaries any more
  the header      "· ‹ 1/3 ›" says which of the dictionaries that have the word
                  this one is; tapping the right half of the name's line goes
                  to the next one, its left half to the previous one, the same
                  word taking the same place in the trail; tapping the rest
                  lists them
  the trail       goes through dictionaries, each word with its dictionary's
                  short name in the breadcrumb then
  lists           Search and the suggestions show one row per word, with the
                  dictionaries that have it; choosing one goes there
  continuing      the exploration goes on in the dictionary it was left in, its
                  trail still crossing them; what v1.4.0 saved is taken over

It runs on the fixtures, through the plugin (it needs KOReader v2026.07 or
newer), and on the author's dictionaries when they are installed.
]]

return function(H, ui)
	local UIManager = require("ui/uimanager")
	local Screen = require("device").screen
	local SETTING = "dictionaryexplorer_exploration"
	local plugin = ui.dictionaryexplorer
	local by = H.dictionaries().by
	local text, html, xdxf, bytes = by.fx, by.fh, by.fd, by.fb
	if not (plugin and text and html and xdxf and bytes) then
		H.skip("all the dictionaries as one", "the plugin is not active, or the fixtures were not found")
		H.finish()
		return
	end

	local viewer
	local function close()
		local shown = H.findViewer()
		if shown then
			shown:onClose()
		end
	end
	local function entryWord()
		return viewer.dictionary:getEntry(viewer.highlighted).word
	end
	local function noticeText()
		local notice = viewer and viewer.miss_notice
		local box = notice and notice[2] and notice[2][2]
		return box and box.text or ""
	end
	local function labels(dialog)
		local found = {}
		for _index, choice in ipairs(dialog and dialog.choices or {}) do
			found[#found + 1] = choice.text
		end
		return table.concat(found, " | ")
	end
	local function row(dialog, pattern)
		for _index, choice in ipairs(dialog and dialog.choices or {}) do
			if choice.text:find(pattern) then
				return choice
			end
		end
	end
	local function closeList(field)
		if viewer[field] then
			UIManager:close(viewer[field])
		end
	end
	local function escape(name)
		return (name:gsub("%p", "%%%0"))
	end
	-- The first dictionary other than `current`, in KOReader's order, whose
	-- answer for `word` is of `kind` ("exact", "accent").
	local function firstElsewhere(word, current, kind)
		for _index, dictionary in ipairs(viewer.lib:others(current)) do
			if dictionary:isIndexed() and dictionary:resolve(word).kind == kind then
				return dictionary
			end
		end
	end
	local function open(dictionary, word)
		close()
		plugin:openAt(dictionary, word)
		viewer = H.findViewer()
		return viewer
	end

	-- ---- going there --------------------------------------------------------------------
	H.step(1, function()
		G_reader_settings:delSetting(SETTING)
		open(html, "house")
		local holder = firstElsewhere("casa", html, "exact")
		viewer:goToWord("casa")
		H.check(
			"Go to word goes to the dictionary that has the word, and says so",
			viewer.dictionary == holder and entryWord() == "casa"
				and noticeText():find(string.format("No entry for “casa” in %s. Found in %s.", viewer.lib:shortName(html), viewer.lib:shortName(holder)), 1, true) ~= nil,
			noticeText()
		)
		H.check("the trail goes on through it", H.trailText(viewer) == "house>casa" and viewer.trail[2].dictionary == holder)
		-- The word was found: the line just says where, with nothing to tap for.
		UIManager:forceRePaint()
		local area = viewer.html_widget.dimen
		H.gesture("tap", area.x + area.w / 2, area.y - 4)
		H.check(
			"the line only says where the word was found: no suggestions offered, none opened",
			noticeText() ~= "" and noticeText():find("Tap here", 1, true) == nil and viewer.suggestions_dialog == nil,
			noticeText()
		)
		H.check(
			"and the breadcrumb then names each word's dictionary",
			viewer.breadcrumb ~= nil and viewer.breadcrumb.trail[1].word == "house · " .. viewer.lib:shortName(html),
			viewer.breadcrumb and viewer.breadcrumb.trail[1].word
		)
		H.check("the dictionary left lets go of what it kept", html._dict_file == nil and html._chunks == nil)
		viewer:goToCrumb(1)
		H.check("going back to the first word returns to its dictionary", viewer.dictionary == html and entryWord() == "house")
		viewer:goToWord("acao")
		local accented = firstElsewhere("acao", html, "accent")
		H.check(
			"an accented spelling elsewhere is shown, saying which",
			viewer.dictionary == accented and entryWord() == "ação" and noticeText():find("Showing “ação” from " .. viewer.lib:shortName(accented), 1, true) ~= nil,
			noticeText()
		)

		-- From the menu (and the popup), the same.
		plugin:openAt(html, "casa")
		viewer = H.findViewer()
		H.check("opening at a word from the menu goes where it is", viewer.dictionary == holder and noticeText():find("Found in", 1, true) ~= nil)
		close()
		plugin:openWord(html.name, "casa")
		viewer = H.findViewer()
		H.check("and so does opening from the popup or another plugin", viewer.dictionary == holder)

		local en, pt = by.en, by.pt
		if en and pt then
			open(en, "house")
			viewer:goToWord("casa")
			H.check("with the author's dictionaries: “casa” from English–Portuguese goes to the Portuguese one", viewer.dictionary == pt and entryWord() == "casa", viewer.dictionary.name)
		else
			H.skip("from English-Portuguese to Portuguese", "the Priberam dictionaries are not installed")
		end
	end)

	-- The dock: Go to word does all that; there is no other button for it.
	H.step(0.5, function()
		open(html, "house")
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
			H.skip("the dock", "no plain word found on the page")
			return
		end
		local x, y = box.dimen.x + (target.x0 + target.x1) / 2, box.dimen.y + (line.y0 + line.y1) / 2
		H.gesture("hold", x, y)
		H.gesture("hold_release", x, y)
		local buttons = viewer.selection_dock and viewer.selection_dock.buttons[1] or {}
		local icon = false
		for _index, button in ipairs(buttons) do
			icon = icon or (button.icon or ""):match("other_dictionary") ~= nil
		end
		H.check("the dock ends with Go to word, with no button for other dictionaries", #buttons > 0 and buttons[#buttons].text == "Go to word" and not icon)
		viewer:_closeSelectionDock()
		viewer:_clearSelection()
	end)

	-- ---- the header -----------------------------------------------------------------------
	H.step(0.5, function()
		open(text, "casa")
		local holders = viewer.lib:holders("casa", text)
		local index
		for position, holder in ipairs(holders) do
			if holder.dictionary == text then
				index = position
			end
		end
		local mark = viewer.header_mark and viewer.header_mark.text or ""
		H.check("the header says which of the dictionaries that have the word this one is", #holders >= 3 and mark:find(string.format("%d/%d ›", index, #holders), 1, true) ~= nil, mark)

		-- Tapping the right half of the name's line goes to the next one, round
		-- to this one again; the left half to the previous one.
		local function tapName(fraction)
			local visited, ok = {}, true
			for _step = 1, #holders do
				UIManager:forceRePaint()
				local band = viewer._name_band
				H.gesture("tap", Screen:getWidth() * fraction, (band.top + band.bottom) / 2)
				visited[#visited + 1] = viewer.dictionary
				ok = ok and #viewer.trail == 1 and viewer.trail[1].dictionary == viewer.dictionary and entryWord():lower() == "casa"
			end
			return visited, ok
		end
		local visited, ok = tapName(0.75)
		local expected = holders[index % #holders + 1].dictionary
		H.check(
			"tapping the right half of the dictionary's name goes to the word in the next one, the same word taking the same place in the trail",
			visited[1] == expected and ok,
			visited[1] and visited[1].name
		)
		H.check("and round the dictionaries back to this one", viewer.dictionary == text)
		visited, ok = tapName(0.25)
		expected = holders[(index - 2) % #holders + 1].dictionary
		H.check(
			"tapping its left half goes to the word in the previous one, round back to this one too",
			visited[1] == expected and ok and viewer.dictionary == text,
			visited[1] and visited[1].name
		)
		H.check("the mark has both ways", (viewer.header_mark and viewer.header_mark.text or ""):find("‹ %d+/%d+ ›") ~= nil)

		-- The rest of the header lists them.
		UIManager:forceRePaint() -- as a finger finds it: drawn
		H.gesture("tap", Screen:getWidth() / 2, 4)
		local dialog = viewer.dictionaries_dialog
		H.check(
			"tapping the rest of the header lists them, as “word · short name”",
			dialog ~= nil and row(dialog, "^casa · " .. escape(viewer.lib:shortName(xdxf)) .. "$") ~= nil and row(dialog, escape(viewer.lib:shortName(text)) .. "$") == nil,
			labels(dialog)
		)
		closeList("dictionaries_dialog")

		viewer:showNext()
		viewer:showNext()
		H.check("no mark once the word's entry is off the page", viewer.header_mark == nil)
	end)

	-- ---- lists ----------------------------------------------------------------------------
	H.step(0.5, function()
		open(html, "house")
		viewer:searchAll("sofa")
		local dialog = viewer.search_dialog
		local first = dialog and dialog.choices[1].text or ""
		local accented = row(dialog, "^sofá · ")
		H.check(
			"Search shows one row per word, with the dictionaries that have it, this one first",
			first:find("^sofa · " .. escape(viewer.lib:shortName(html))) ~= nil and accented ~= nil and accented.text:find(viewer.lib:shortName(text), 1, true) ~= nil,
			labels(dialog)
		)
		if accented then
			accented.callback()
		end
		H.check("choosing a word goes to it", viewer.dictionary ~= html and entryWord() == "sofá" and viewer.search_dialog == nil)

		-- A word of the .syn leading to the second of two homographs: the result
		-- opens that one, not the first one of the headword shown.
		viewer:goToWordIn(text, "livro")
		local expected = text:resolve("cofre").position
		viewer:searchAll("cofre")
		dialog = viewer.search_dialog
		local banco = row(dialog, "^banco")
		if banco then
			banco.callback()
		end
		H.check(
			"a result found through the .syn opens the entry it leads to, with the word asked for in the trail",
			banco ~= nil and viewer.dictionary == text and viewer.highlighted == expected and viewer.trail[viewer.trail_index].word == "cofre"
				and text:readDefinition(text:getEntry(viewer.highlighted)):find("money", 1, true) ~= nil,
			string.format("%s at %s (expected %s)", tostring(banco and banco.text), tostring(viewer.highlighted), tostring(expected))
		)

		viewer:searchAll("casaz")
		dialog = viewer.search_dialog
		local casa = row(dialog, "^casa · ")
		H.check("a word found in several dictionaries is one row, naming them all", casa ~= nil and casa.text:find(", ", 1, true) ~= nil, labels(dialog))
		closeList("search_dialog")

		-- The suggestions for a word no dictionary has, the same way.
		viewer:goToWordIn(html, "house")
		viewer:goToWord("casaz")
		H.check("a word no dictionary has stays here, with the closest entry, and offers suggestions", viewer.dictionary == html and noticeText():find("Showing the closest one. Tap here for suggestions.", 1, true) ~= nil, noticeText())
		local length = #viewer.trail
		viewer:showSuggestions()
		dialog = viewer.suggestions_dialog
		casa = row(dialog, "^casa · ")
		H.check("its suggestions are one row per word too", casa ~= nil, labels(dialog))
		if casa then
			casa.callback()
		end
		H.check("and the one chosen takes the missed word's place in the trail", entryWord():lower() == "casa" and #viewer.trail == length, H.trailText(viewer))
	end)

	-- ---- continuing ------------------------------------------------------------------------
	H.step(0.5, function()
		open(html, "house")
		viewer:goToWord("casa") -- to another dictionary
		viewer:goToWordIn(xdxf, "sol")
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
		open(text, "gato")
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

	H.finish()
end
