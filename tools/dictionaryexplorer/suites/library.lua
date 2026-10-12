--[[
The dictionaries as one: how a word is looked for in all of them (the
Library), apart from what the viewer shows of it (see the switching suite).

  short names     made from the dictionaries' names (the languages they
                  mention, "EN-PT"; a word of the name when that doesn't tell
                  them apart), one set by the user winning, and the menu's
                  editor showing the name as it is now
  priority        a word leads to: its exact entry here, then an exact entry
                  elsewhere (KOReader's order), then an accented spelling here,
                  then one elsewhere; else the closest entry here
  preparing       a dictionary never prepared is not asked (nor prepared) by a
                  word; it is listed as such, and the menu prepares them all,
                  removing the index caches of dictionaries no longer installed
  the list        a dictionary installed, removed or copied again in its place
                  during the session is seen as it is without restarting: by
                  the popup's button, when the viewer opens, and by the
                  starting-word dialog

It runs on the fixtures, through the plugin (it needs KOReader v2026.07 or
newer), and on the author's dictionaries when they are installed.
]]

return function(H, ui)
	local UIManager = require("ui/uimanager")
	local lfs = require("libs/libkoreader-lfs")
	local SETTING = "dictionaryexplorer_exploration"
	local plugin = ui.dictionaryexplorer
	local by = H.dictionaries().by
	local text, html, xdxf, bytes = by.fx, by.fh, by.fd, by.fb
	if not (plugin and text and html and xdxf and bytes) then
		H.skip("the dictionaries as one", "the plugin is not active, or the fixtures were not found")
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

	-- ---- short names ------------------------------------------------------------------
	H.step(1, function()
		G_reader_settings:delSetting(SETTING)
		G_reader_settings:delSetting("dictionaryexplorer_short_names")
		open(html, "house")
		local names = viewer.lib:shortNames()
		H.check(
			"short names tell the fixtures apart with a word of their names",
			names[text] == "Fixture Text" and names[html] == "Fixture HTML" and names[xdxf] == "Fixture XDXF" and names[bytes] == "Fixture Bytes",
			string.format("%s, %s, %s, %s", tostring(names[text]), tostring(names[html]), tostring(names[xdxf]), tostring(names[bytes]))
		)
		local en, pt, ox = by.en, by.pt, by.ox
		if en and pt and ox then
			H.check("and the author's dictionaries with the languages they mention", names[en] == "EN-PT" and names[pt] == "PT" and names[ox] == "EN", string.format("%s, %s, %s", names[en], names[pt], names[ox]))
		else
			H.skip("short names of the author's dictionaries", "not installed")
		end
		G_reader_settings:saveSetting("dictionaryexplorer_short_names", { [text.name] = "FT" })
		H.check("a short name set by the user wins", viewer.lib:shortName(text) == "FT")
		G_reader_settings:delSetting("dictionaryexplorer_short_names")

		-- The menu's editor shows the name as it is now, each time it opens.
		local item
		for _index, candidate in ipairs(plugin:getShortNamesMenu()) do
			if candidate.text_func():find(text.name, 1, true) == 1 then
				item = candidate
			end
		end
		local function edit(new_name)
			item.callback()
			local editor = H.findInputDialog()
			local shown = editor and editor:getInputText()
			if editor and new_name then
				editor:setInputText(new_name)
				for _index, button in ipairs(editor.buttons[1]) do
					if button.text == "Save" then
						button.callback()
					end
				end
			elseif editor then
				UIManager:close(editor)
			end
			return shown
		end
		local before = item and edit("CUSTOM")
		local after = item and edit(nil)
		H.check("the short-name editor shows the name saved last, not the one the menu was made with", before == "Fixture Text" and after == "CUSTOM", string.format("%s, then %s", tostring(before), tostring(after)))
		G_reader_settings:delSetting("dictionaryexplorer_short_names")
	end)

	-- ---- priority -----------------------------------------------------------------------
	H.step(0.5, function()
		local lib = viewer.lib
		local function check(description, word, current, dictionary, kind, from)
			local lookup = lib:resolve(word, current)
			H.check(
				string.format("%s: %q from %s", description, word, current.name),
				dictionary ~= nil and lookup.dictionary == dictionary and lookup.kind == kind and lookup.from == from,
				string.format("%s, %s, from %s", lookup.dictionary.name, lookup.kind, lookup.from and lookup.from.name or "-")
			)
		end
		check("an exact entry here stays here", "house", html, html, "exact", nil)
		check("no entry here, an exact one elsewhere goes there", "casa", html, firstElsewhere("casa", html, "exact"), "exact", html)
		check("an exact entry elsewhere wins over an accented spelling here", "sofa", text, firstElsewhere("sofa", text, "exact"), "exact", text)
		check("an accented spelling here, with no exact entry anywhere, stays here", "acao", text, text, "accent", nil)
		check("no exact entry anywhere and no spelling here: an accented one elsewhere", "acao", html, firstElsewhere("acao", html, "accent"), "accent", html)
		check("nothing anywhere: the closest entry here", "qqqzzzz", html, html, "closest", nil)
	end)

	-- ---- preparing --------------------------------------------------------------------------
	H.step(0.5, function()
		open(html, "house")
		os.remove(xdxf.cache_path)
		xdxf.idx, xdxf.syn, xdxf.offsets, xdxf.first_keys, xdxf.count = nil, nil, nil, nil, nil
		local lookup = viewer.lib:resolve("sol", html) -- the XDXF fixture has it (and the Portuguese dictionary)
		H.check("a dictionary never prepared is not asked, nor prepared, by a word", lookup.dictionary ~= xdxf and not xdxf:isIndexed())
		viewer:showOtherDictionaries("casa")
		local unprepared = row(viewer.dictionaries_dialog, "index not prepared yet")
		H.check("it is listed as such", unprepared ~= nil and unprepared.text:find(xdxf.name, 1, true) ~= nil, labels(viewer.dictionaries_dialog))
		closeList("dictionaries_dialog")
		plugin:prepareAll()
	end)
	H.step(1.5, function()
		H.check("the menu's Prepare all dictionaries prepares it", xdxf:isIndexed())
		H.closeStartupMessages()
		H.check("and then a word finds it", viewer.lib:resolve("sol", html).kind ~= "closest")
	end)

	-- ---- the list --------------------------------------------------------------------------
	-- A dictionary copied in during the session: a copy of an integrity
	-- fixture, under a name of its own.
	local late_dir = os.getenv("KO_HOME") .. "/data/dict/fixtures/late"
	local function readFile(path)
		local file = io.open(path, "rb")
		local content = file:read("*a")
		file:close()
		return content
	end
	local function writeFile(path, content)
		local file = io.open(path, "wb")
		file:write(content)
		file:close()
	end
	H.step(0.5, function()
		close()
		local source = os.getenv("DE_INTEGRITY") .. "/tiny_bytes/tiny_bytes"
		lfs.mkdir(late_dir)
		writeFile(late_dir .. "/late.ifo", (readFile(source .. ".ifo"):gsub("bookname=[^\n]*", "bookname=Fixture Late")))
		writeFile(late_dir .. "/late.idx", readFile(source .. ".idx"))
		writeFile(late_dir .. "/late.dict", readFile(source .. ".dict"))
		H.check("a dictionary installed during the session gets the popup's button", plugin:canOpen("Fixture Late"))
		open(html, "house")
		local listed = false
		for _index, dictionary in ipairs(viewer.lib:others(html)) do
			listed = listed or dictionary.name == "Fixture Late"
		end
		H.check("and is among the dictionaries the viewer asks", listed)
		close()
		os.remove(late_dir .. "/late.ifo")
		os.remove(late_dir .. "/late.idx")
		os.remove(late_dir .. "/late.dict")
		lfs.rmdir(late_dir)
		open(html, "house")
		listed = false
		for _index, dictionary in ipairs(viewer.lib:others(html)) do
			listed = listed or dictionary.name == "Fixture Late"
		end
		H.check("one removed is no longer asked once the viewer opens again", not listed and not plugin:canOpen("Fixture Late"))
		close()
	end)

	-- Copied again in the same place, with other contents: nothing of the old
	-- dictionary is kept (its name, its index, its entries).
	local function install(name, source)
		lfs.mkdir(late_dir)
		writeFile(late_dir .. "/late.ifo", (readFile(source .. ".ifo"):gsub("bookname=[^\n]*", "bookname=" .. name)))
		writeFile(late_dir .. "/late.idx", readFile(source .. ".idx"))
		writeFile(late_dir .. "/late.dict", readFile(source .. ".dict"))
	end
	local function uninstall()
		os.remove(late_dir .. "/late.ifo")
		os.remove(late_dir .. "/late.idx")
		os.remove(late_dir .. "/late.dict")
		lfs.rmdir(late_dir)
	end
	H.step(0.5, function()
		local integrity = os.getenv("DE_INTEGRITY")
		install("Fixture Late", integrity .. "/tiny_bytes/tiny_bytes")
		plugin:refreshDictionaries()
		local before = plugin:getDictionary("Fixture Late")
		local had = before and (before:isIndexed() or before:buildIndex()) and select(2, before:locate("Zulu"))
		-- Another dictionary in its place (another name and other words).
		install("Fixture Late Two", integrity .. "/syn_ok/syn_ok")
		local later = os.time() + 5
		for _index, extension in ipairs({ ".ifo", ".idx", ".dict" }) do
			lfs.touch(late_dir .. "/late" .. extension, later, later)
		end
		plugin:refreshDictionaries()
		local after = plugin:getDictionary("Fixture Late Two")
		local indexed = after and (after:isIndexed() or after:buildIndex())
		H.check(
			"a dictionary copied again in its place is the new one, with nothing of the old",
			had and after ~= nil and after ~= before and indexed and after.name == "Fixture Late Two"
				and plugin:getDictionary("Fixture Late") == nil and not select(2, after:locate("Zulu")),
			after and after.name
		)
		uninstall()
		plugin:refreshDictionaries()
	end)

	-- The starting-word dialog, with its dictionary removed meanwhile.
	H.step(0.5, function()
		install("Fixture Late", os.getenv("DE_INTEGRITY") .. "/tiny_bytes/tiny_bytes")
		G_reader_settings:saveSetting("dictionaryexplorer_start_dictionary", "Fixture Late")
		plugin:showStartWordDialog()
		local dialog = H.findInputDialog()
		H.check("the dialog opens on the starting dictionary", dialog ~= nil and dialog.description == "Fixture Late", dialog and dialog.description)
		uninstall()
		if dialog then
			dialog:setInputText("casa")
			for _index, button in ipairs(dialog.buttons[1]) do
				if button.text == "Open" then
					button.callback()
				end
			end
		end
		local opened = H.findViewer()
		H.check("removed while it was open, Open goes to another dictionary", opened ~= nil and opened.dictionary.name ~= "Fixture Late", opened and opened.dictionary.name)
		if opened then
			opened:onClose()
		end
		plugin:showStartWordDialog()
		dialog = H.findInputDialog()
		H.check("and the dialog, opened again, no longer offers it", dialog ~= nil and dialog.description ~= "Fixture Late", dialog and dialog.description)
		if dialog then
			UIManager:close(dialog)
		end
		G_reader_settings:delSetting("dictionaryexplorer_start_dictionary")
		G_reader_settings:delSetting(SETTING)
	end)

	-- The index caches of dictionaries no longer installed go with Prepare all.
	local orphan
	H.step(0.5, function()
		local StarDict = H.StarDict
		orphan = StarDict.cacheDir() .. "gone-0123abcd.lua"
		writeFile(orphan, "return {}\n")
		plugin:prepareAll()
	end)
	H.step(1, function()
		local message = H.findWidget(function(widget)
			return type(widget.text) == "string" and widget.text:find("no longer installed", 1, true) ~= nil
		end)
		H.check(
			"Prepare all removes the caches of dictionaries no longer installed, and says so",
			lfs.attributes(orphan, "mode") == nil and lfs.attributes(text.cache_path, "mode") == "file" and message ~= nil
		)
		H.closeStartupMessages()
		G_reader_settings:delSetting(SETTING)
	end)

	H.finish()
end
