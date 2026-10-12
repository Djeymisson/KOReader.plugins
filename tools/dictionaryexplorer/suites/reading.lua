--[[
The dictionary appearance (font size, line height, margins, justification,
header) and the compact header.

  the dialog      opens from the gear left of Search (and the menu); changing a
                  value redraws only the dialog; Cancel leaves everything as it
                  was; Defaults goes back to what each follows
  applying        saves the values and lays the page out once more on the same
                  entry, with the font size, line height, margins and
                  justification asked for; the page still fits, and pages still
                  follow each other with no entry skipped or repeated
  following       unset, the font size and justification follow the dictionary
                  popup's, the margins the book's
  compact header  one line: the page's headwords, the dictionary's short name
                  and "‹ 1/3 ›"; more room for the entries; tapping its right
                  part goes to the word in another dictionary (left half back,
                  right half forward), the rest lists them

It runs on the fixtures, through the plugin (it needs KOReader v2026.07 or newer).
]]

return function(H, ui)
	local UIManager = require("ui/uimanager")
	local Screen = require("device").screen
	local ReadingSettings = require("modules/readingsettings")
	local plugin = ui.dictionaryexplorer
	local by = H.dictionaries().by
	local text = by.fx
	if not (plugin and text) then
		H.skip("the dictionary appearance", "the plugin is not active, or the fixtures were not found")
		H.finish()
		return
	end
	local function clearSettings()
		for _name, key in pairs(ReadingSettings.KEYS) do
			G_reader_settings:delSetting(key)
		end
	end

	local viewer
	local function open(word)
		local shown = H.findViewer()
		if shown then
			shown:onClose()
		end
		plugin:openAt(text, word)
		viewer = H.findViewer()
		return viewer
	end
	local function onTop()
		local stack = UIManager._window_stack
		return stack[#stack] and stack[#stack].widget
	end
	-- The dialog's button whose label starts with `prefix` ({ row, column }).
	local function button(dialog, prefix)
		for _row, row in ipairs(dialog and dialog.buttons or {}) do
			for _column, spec in ipairs(row) do
				if (spec.text or ""):sub(1, #prefix) == prefix then
					return spec, row
				end
			end
		end
	end
	local function label(dialog, prefix)
		local spec = button(dialog, prefix)
		return spec and spec.text
	end
	-- Taps the "+" (or "−") of the row whose label starts with `prefix`.
	local function step(prefix, sign)
		local row = select(2, button(ReadingSettings.shown, prefix))
		for _column, spec in ipairs(row or {}) do
			if spec.text == sign then
				spec.callback()
			end
		end
	end
	local function press(prefix)
		local spec = button(ReadingSettings.shown, prefix)
		if spec then
			spec.callback()
		end
	end

	-- ---- the dialog -------------------------------------------------------------------
	H.step(1, function()
		clearSettings()
		G_reader_settings:delSetting("dictionaryexplorer_exploration")
		open("casa")
		UIManager:forceRePaint()
		local gear = viewer.column[#viewer.column].buttons_layout[1][1]
		H.check("the footer starts with the gear", gear.icon == "appbar.settings")
		H.gesture("tap", gear.dimen.x + gear.dimen.w / 2, gear.dimen.y + gear.dimen.h / 2)
	end)
	H.step(0.5, function()
		local dialog = ReadingSettings.shown
		H.check("the gear opens the dictionary appearance", dialog ~= nil and onTop() == dialog)
		local popup_size = G_reader_settings:readSetting("dict_font_size") or 20
		H.check(
			"unset, the font size follows the system and the margins the book",
			label(dialog, "Font size") == string.format("Font size: %d (follows the system)", popup_size) and label(dialog, "Margins") == "Margins: follow the book",
			label(dialog, "Font size")
		)
		local first = viewer.first
		step("Font size", "+")
		step("Line height", "+")
		H.check(
			"changing a value redraws only the dialog",
			ReadingSettings.shown ~= dialog and label(ReadingSettings.shown, "Font size") == string.format("Font size: %d", popup_size + 1) and viewer.first == first
				and G_reader_settings:readSetting(ReadingSettings.KEYS.font_size) == nil,
			label(ReadingSettings.shown, "Font size")
		)
		press("Cancel")
		H.check("Cancel leaves everything as it was", onTop() == viewer and G_reader_settings:readSetting(ReadingSettings.KEYS.font_size) == nil and viewer.font_size == popup_size)
	end)

	-- ---- applying ----------------------------------------------------------------------
	H.step(0.5, function()
		local highlighted = viewer.highlighted
		viewer:showReadingSettings()
		for _step = 1, 4 do
			step("Font size", "+")
		end
		for _step = 1, 3 do
			step("Line height", "+")
		end
		step("Margins", "+") -- from the default, 16, to 18
		press("Justified") -- from following the popup to yes
		press("Justified") -- to no
		local size = viewer.font_size + 4
		press("Apply")
		H.check(
			"Apply saves the values and lays the page out with them, on the same entry",
			viewer.font_size == size and viewer.line_height == 1.6 and viewer.side_margins.left == Screen:scaleBySize(18)
				and viewer.justify == false and viewer.highlighted == highlighted and onTop() == viewer
				and G_reader_settings:readSetting(ReadingSettings.KEYS.font_size) == size,
			string.format("font %s, line %s, margin %s, justify %s", tostring(viewer.font_size), tostring(viewer.line_height), tostring(viewer.side_margins.left), tostring(viewer.justify))
		)
		local css = viewer:_getCss()
		H.check("the page's style has the line height and no justification", css:find("line-height: 1.6;", 1, true) ~= nil and css:find("text-align: justify", 1, true) == nil)
		H.check("the page still fits", H.fits(viewer))
		local contiguous = true
		for _turn = 1, 20 do
			local previous_last = viewer.last
			viewer:showNext()
			contiguous = contiguous and viewer.first == previous_last + 1 and H.fits(viewer)
		end
		H.check("and pages still follow each other, with no entry skipped or repeated", contiguous)
		viewer:onClose()
		open("livro")
		H.check("a viewer opened later has them too", viewer.font_size == size and viewer.line_height == 1.6)

		viewer:showReadingSettings()
		press("Defaults")
		press("Apply")
		H.check("Defaults goes back to what each follows", G_reader_settings:readSetting(ReadingSettings.KEYS.font_size) == nil and viewer.line_height == 1.3 and viewer.font_size == (G_reader_settings:readSetting("dict_font_size") or 20))
	end)

	-- ---- compact header -------------------------------------------------------------------
	H.step(0.5, function()
		open("casa")
		local room = viewer:_getContentHeight()
		viewer:showReadingSettings()
		press("Header")
		press("Apply")
		local holders = viewer.lib:holders("casa", text)
		H.check(
			"the compact header is one line, with the dictionary's short name and the mark",
			viewer.compact_header and viewer.header_mark ~= nil and viewer.header:getSize().h < Screen:scaleBySize(60) and #holders > 1,
			string.format("%d px", viewer.header:getSize().h)
		)
		H.check("it leaves more room for the entries", viewer:_getContentHeight() > room and H.fits(viewer), string.format("%d px (was %d)", viewer:_getContentHeight(), room))
		local index
		for position, holder in ipairs(holders) do
			if holder.dictionary == text then
				index = position
			end
		end
		UIManager:forceRePaint()
		local band = viewer._name_band
		local y = (band.top + band.bottom) / 2
		H.gesture("tap", band.right - 2, y)
		H.check("tapping the right half of its right part goes to the next dictionary", viewer.dictionary == holders[index % #holders + 1].dictionary, viewer.dictionary.name)
		UIManager:forceRePaint()
		band = viewer._name_band
		H.gesture("tap", band.left + 2, y)
		H.check("and its left half back", viewer.dictionary == text, viewer.dictionary.name)
		UIManager:forceRePaint()
		H.gesture("tap", Screen:getWidth() / 8, y)
		H.check("tapping the headwords lists the dictionaries", viewer.dictionaries_dialog ~= nil)
		if viewer.dictionaries_dialog then
			UIManager:close(viewer.dictionaries_dialog)
		end
		viewer:onClose()
	end)

	-- In a mirrored layout (Arabic, Hebrew...) the name is drawn on the left:
	-- that is where tapping it goes round the dictionaries.
	H.step(0.5, function()
		local BD = require("ui/bidi")
		local was = BD._mirrored_ui_layout
		BD._mirrored_ui_layout = true
		local ok, err = pcall(function()
			open("casa")
			UIManager:forceRePaint()
			local band = viewer._name_band
			local y = (band.top + band.bottom) / 2
			H.check("mirrored, the name's tap area is on the left, where it is drawn", band.left < Screen:getWidth() / 3, string.format("%d..%d", band.left, band.right))
			H.gesture("tap", (band.left + band.right) / 2 + 2, y)
			H.check("and tapping it goes to another dictionary", viewer.dictionary ~= text and viewer.dictionaries_dialog == nil, viewer.dictionary.name)
			UIManager:forceRePaint()
			H.gesture("tap", Screen:getWidth() - Screen:getWidth() / 8, y)
			H.check("while the headwords, on the right, list them", viewer.dictionaries_dialog ~= nil)
			if viewer.dictionaries_dialog then
				UIManager:close(viewer.dictionaries_dialog)
			end
			viewer:onClose()
		end)
		BD._mirrored_ui_layout = was
		if not ok then
			error(err, 0)
		end
		clearSettings()
		G_reader_settings:delSetting("dictionaryexplorer_exploration")
	end)

	H.finish()
end
