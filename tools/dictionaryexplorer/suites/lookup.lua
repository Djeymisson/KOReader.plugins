--[[
Finding the entry for a word: what the user types, selects or taps.

  case            a key stored in another case than the one given is found,
                  for any letter, not only A-Z: "ÁRVORE" or a sentence-initial
                  "Pêssego" find "árvore" / "pêssego", "óbidos" finds "Óbidos",
                  "onu" finds "ONU"; the text as given wins when it is a key
  synonyms        a word that is not a headword but is in the .syn leads to its
                  entry (also in another case); a headword wins over a word
                  of the .syn; every word of the fixture's .syn, across its
                  pages, leads where it says; the trail keeps the word asked
                  for; on the Oxford dictionary when installed
  no entry        the viewer opens on the closest entry and says so on the
                  page itself, above the entries, with no notification on top;
                  the next page, word or crumb takes the line away; a long
                  pasted text is cut, so the entries keep their room; opening
                  from the menu or from another plugin says so the same way

It runs on the Fixture Text fixture, and also on the Portuguese dictionary
when it is installed.
]]

return function(H, ui)
	local UIManager = require("ui/uimanager")
	local Screen = require("device").screen
	local by = H.dictionaries().by
	local fixture = by.fx
	if not fixture then
		H.skip("lookups", "the Fixture Text fixture was not found (run the suite with run.sh)")
		H.finish()
		return
	end
	local MISSING = "qqqzzzz"

	local function found(dictionary, text)
		local position, exact = dictionary:locateText(text)
		local entry = dictionary:getEntry(position)
		return exact and entry and entry.word
	end

	-- ---- case ----------------------------------------------------------------
	H.step(1, function()
		for _index, case in ipairs({
			{ "Árvore", "Árvore", "a key in the case given wins" },
			{ "árvore", "árvore", "a key in the case given wins" },
			{ "ÁRVORE", "árvore", "all capitals find the lowercase key" },
			{ "Pêssego", "pêssego", "a capitalized word (start of a sentence) finds the lowercase key" },
			{ "AÇÃO", "ação", "capitals with accents and cedilla" },
			{ "ÉTICA", "ética", "an accented capital first letter" },
			{ "óbidos", "Óbidos", "a lowercase name finds the capitalized key" },
			{ "onu", "ONU", "a lowercase abbreviation finds the uppercase key" },
			{ "CASA", "casa", "ASCII capitals, as before" },
			{ "Pêssego maduro", "pêssego", "a phrase falls back to its first word, in any case" },
		}) do
			local text, expected, description = case[1], case[2], case[3]
			local word = found(fixture, text)
			H.check(string.format("%s: %q finds %q", description, text, expected), word == expected, tostring(word))
		end
		H.check("a word with no entry in any case is not found", not found(fixture, MISSING))

		local pt = by.pt
		if pt then
			for _index, case in ipairs({ { "Árvore", "árvore" }, { "AÇÃO", "ação" }, { "Ética", "ética" } }) do
				local word = found(pt, case[1])
				H.check(string.format("%s: %q finds %q", pt.name:sub(1, 22), case[1], case[2]), word == case[2], tostring(word))
			end
		else
			H.skip("case in the Portuguese dictionary", "dictionary not installed")
		end
	end)

	-- ---- synonyms -----------------------------------------------------------------
	H.step(0.5, function()
		for _index, case in ipairs({
			{ "casas", "casa", "casas", "an inflected form leads to its entry" },
			{ "CASAS", "casa", "casas", "in another case too" },
			{ "arvore", "árvore", "arvore", "an accentless spelling the .syn lists" },
			{ "lisboa", "Óbidos", "Lisboa", "a capitalized word of the .syn, typed in lowercase" },
			{ "mesa", "mesa", nil, "a headword wins over the same word in the .syn" },
			{ "casas grandes", "casa", "casas", "a phrase falls back to its first word, through the .syn" },
		}) do
			local text, expected, expected_synonym, description = case[1], case[2], case[3], case[4]
			local position, exact, synonym = fixture:locateText(text)
			local word = fixture:getEntry(position).word
			H.check(string.format("%s: %q finds %q", description, text, expected), exact and word == expected and synonym == expected_synonym, string.format("%s via %s", word, tostring(synonym)))
		end

		-- Every "...zs" word of the .syn leads to the entry it was made from.
		local content = io.open(fixture.syn_path, "rb"):read("*a")
		local checked, wrong, first_wrong = 0, 0, nil
		local position = 1
		while position <= #content do
			local terminator = content:find("\0", position, true)
			local key = content:sub(position, terminator - 1)
			position = terminator + 5
			if key:sub(-2) == "zs" then
				checked = checked + 1
				local target, exact, synonym = fixture:locate(key)
				if not (exact and synonym == key and fixture:getEntry(target).word == key:sub(1, -3)) then
					wrong = wrong + 1
					first_wrong = first_wrong or key
				end
			end
		end
		H.check(string.format("every one of the %d generated words of the .syn leads to its entry", checked), checked > 300 and wrong == 0, first_wrong)

		local trail_viewer = H.newViewer(fixture, "livro")
		trail_viewer:goToWord("casas")
		H.check(
			"Go to word through the .syn: the entry is highlighted, the trail keeps the word asked for, no notice",
			fixture:getEntry(trail_viewer.highlighted).word == "casa" and trail_viewer.trail[#trail_viewer.trail].word == "casas" and trail_viewer.miss_notice == nil
		)
		trail_viewer:onCloseWidget()

		local ox = by.ox
		if ox and ox.syn then
			for _index, case in ipairs({ { "abomining", "abomine", "abomining" }, { "went", "went", nil } }) do
				local target, exact, synonym = ox:locate(case[1])
				local word = ox:getEntry(target).word
				H.check(string.format("%s: %q finds %q", ox.name:sub(1, 22), case[1], case[2]), exact and word == case[2] and synonym == case[3], string.format("%s via %s", word, tostring(synonym)))
			end
		else
			H.skip("synonyms in the Oxford dictionary", "not installed, or without a .syn")
		end
	end)

	-- ---- no entry ---------------------------------------------------------------
	local viewer
	local function onTop()
		local stack = UIManager._window_stack
		return stack[#stack] and stack[#stack].widget
	end
	local function noticeText()
		local notice = viewer and viewer.miss_notice
		local box = notice and notice[2] and notice[2][2]
		return box and box.text
	end

	H.step(1, function()
		viewer = H.newViewer(fixture, "livro")
		UIManager:show(viewer)
		H.check("no notice when the word has an entry", viewer.miss_notice == nil)
		viewer:goToWord(MISSING)
		H.check("a word with no entry is said on the page", (noticeText() or ""):find(MISSING, 1, true) ~= nil, noticeText())
		H.check("with no notification on top of the viewer", onTop() == viewer)
		H.check("the page with the notice still fits the screen", H.fits(viewer) and viewer.column:getSize().h <= Screen:getHeight())
		H.check("the closest entry is highlighted", viewer.highlighted ~= nil and viewer.first <= viewer.highlighted and viewer.highlighted <= viewer.last)
		viewer:showNext()
		H.check("turning the page takes the notice away", viewer.miss_notice == nil)
		viewer:goToWord(MISSING)
		viewer:goToWord("ÁRVORE")
		H.check("going to a word that has an entry takes it away", viewer.miss_notice == nil and fixture:getEntry(viewer.highlighted).word == "árvore")
		viewer:goToWord(MISSING)
		viewer:goToCrumb(1)
		H.check("going to a crumb takes it away", viewer.miss_notice == nil)

		-- A long pasted text with no entry: the line is cut, and the entries
		-- keep most of the screen.
		local room = viewer:_getContentHeight()
		viewer:goToWord(MISSING)
		local one_line = viewer.miss_notice:getSize().h
		for _index, long in ipairs({ { "a 2,400-character phrase", (MISSING .. " palavra "):rep(150) }, { "a 2,400-character word", ("q"):rep(2400) } }) do
			viewer:goToWord(long[2])
			local left = viewer:_getContentHeight()
			local text = noticeText() or ""
			H.check(
				"for " .. long[1] .. " with no entry, the notice is cut and the entries keep their room",
				viewer.miss_notice:getSize().h <= 2 * one_line and left >= 0.75 * room and #text < 200 and H.fits(viewer)
					and viewer.column:getSize().h <= Screen:getHeight(),
				string.format("notice %d px (one line %d), entries %d of %d px, %d bytes shown", viewer.miss_notice:getSize().h, one_line, left, room, #text)
			)
		end
		viewer:onClose()
	end)

	H.step(1, function()
		local plugin = ui.dictionaryexplorer
		if not plugin then
			H.skip("the notice when opening", "the plugin is not active (it needs KOReader v2026.07 or newer)")
			return
		end
		plugin:openAt(fixture, MISSING)
		viewer = H.findViewer()
		H.check("opening at a word with no entry (menu, gesture) says so on the page", viewer ~= nil and (noticeText() or ""):find(MISSING, 1, true) ~= nil and onTop() == viewer)
		if viewer then
			viewer:onClose()
		end
		plugin:openWord(fixture.name, MISSING)
		viewer = H.findViewer()
		H.check("opening from another plugin or the popup at a word with no entry says so too", viewer ~= nil and (noticeText() or ""):find(MISSING, 1, true) ~= nil)
		if viewer then
			viewer:onClose()
		end
		plugin:openWord(fixture.name, "livro")
		viewer = H.findViewer()
		H.check("and not when the word has an entry", viewer ~= nil and viewer.miss_notice == nil)
		if viewer then
			viewer:onClose()
		end

		-- Opening at a word of the .syn: the trail starts with it, as Go to word's does.
		plugin:openAt(fixture, "casas")
		viewer = H.findViewer()
		if viewer then
			viewer:goToWord("livro")
		end
		H.check("opening from the menu at a word of the .syn starts the trail with it", viewer ~= nil and H.trailText(viewer) == "casas>livro" and fixture:getEntry(viewer.trail[1].position).word == "casa", viewer and H.trailText(viewer))
		if viewer then
			viewer:onClose()
		end
		plugin:openWord(fixture.name, "casas")
		viewer = H.findViewer()
		H.check("so does opening from another plugin or the popup", viewer ~= nil and viewer.trail[1].word == "casas", viewer and viewer.trail[1].word)
		if viewer then
			viewer:onClose()
		end
	end)

	H.finish()
end
