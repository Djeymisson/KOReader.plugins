--[[
Continuing an exploration where it was left.

  saving          each page shown keeps where the exploration is, in the
                  settings (in memory: no file is written, nothing redrawn),
                  per dictionary, with the latest 50 words of the trail
  continuing      from the menu, the word dialog's Continue button or the
                  Dispatcher action: the dictionary explored last reopens on
                  the same page, with the same highlighted entry, trail and
                  current word; with nothing explored yet it says so
  changes         an exploration saved from another version of the dictionary
                  reopens at the word it was on; a damaged one is not a crash

It runs on the fixtures, through the plugin (it needs KOReader v2026.07 or newer).
]]

local Dispatcher = require("dispatcher")

return function(H, ui)
	local UIManager = require("ui/uimanager")
	local SETTING = "dictionaryexplorer_explorations"
	local plugin = ui.dictionaryexplorer
	local by = H.dictionaries().by
	local fixture, html = by.fx, by.fh
	if not (plugin and fixture and html) then
		H.skip("continuing an exploration", "the plugin is not active, or the fixtures were not found")
		H.finish()
		return
	end

	local function close()
		local viewer = H.findViewer()
		if viewer then
			viewer:onClose()
		end
	end

	local saved -- what the viewer was showing when it was closed
	local function snapshot(viewer)
		return {
			first = viewer.first,
			last = viewer.last,
			highlighted = viewer.highlighted,
			trail = H.trailText(viewer),
			trail_index = viewer.trail_index,
		}
	end
	local function same(viewer)
		if not viewer then
			return false, "no viewer"
		end
		local now = snapshot(viewer)
		return now.first == saved.first and now.highlighted == saved.highlighted and now.trail == saved.trail and now.trail_index == saved.trail_index,
			string.format("page %d (was %d), trail %s @%d (was %s @%d)", now.first, saved.first, now.trail, now.trail_index, saved.trail, saved.trail_index)
	end

	-- ---- nothing yet --------------------------------------------------------------
	H.step(1, function()
		G_reader_settings:delSetting(SETTING)
		H.check("with nothing explored, there is nothing to continue", plugin:getLastExploration() == nil)
		plugin:continueExploring()
		local message = H.findWidget(function(widget)
			return widget.text == "There is no exploration to continue yet."
		end)
		H.check("and continuing says so", message ~= nil and H.findViewer() == nil)
		if message then
			UIManager:close(message)
		end
	end)

	-- ---- saving --------------------------------------------------------------------
	H.step(0.5, function()
		-- No file written, and the settings not saved to disk either.
		local open, flush, write = io.open, G_reader_settings.flush, 0
		rawset(io, "open", function(path, mode)
			if mode and mode:find("w", 1, true) then
				write = write + 1
			end
			return open(path, mode)
		end)
		G_reader_settings.flush = function(...)
			write = write + 1
			return flush(...)
		end
		plugin:openAt(fixture, "livro")
		local viewer = H.findViewer()
		for _index, word in ipairs({ "amor", "correr", "gato", "mesa" }) do
			viewer:goToWord(word)
		end
		viewer:goToPreviousWord() -- the current word is not the latest
		viewer:showNext()
		viewer:showNext()
		rawset(io, "open", open)
		G_reader_settings.flush = nil -- back to the class's
		saved = snapshot(viewer)
		local state = G_reader_settings:readSetting(SETTING)
		H.check("each page keeps where the exploration is, without writing a file", write == 0 and state and state.last == fixture.name and state.by_dictionary[fixture.name].first == viewer.first, write .. " file(s) written")
		close()
	end)

	-- ---- continuing ------------------------------------------------------------------
	H.step(0.5, function()
		plugin:continueExploring()
		local viewer = H.findViewer()
		local ok, detail = same(viewer)
		H.check("continuing reopens the same page, highlighted entry, trail and current word", ok, detail)
		H.check("with the breadcrumb showing the current word in bold", viewer and H.boldWord(viewer) == viewer.trail[viewer.trail_index].word)
		H.check("and the trail goes on from there", viewer and viewer.dictionary == fixture)
		close()

		-- From the word dialog.
		plugin:showStartWordDialog()
		local dialog = H.findInputDialog()
		local continue
		for _index, button in ipairs(dialog and dialog.buttons[1] or {}) do
			if button.text == "Continue" then
				continue = button
			end
		end
		H.check("the word dialog offers Continue", continue ~= nil and continue.enabled ~= false)
		if continue then
			continue.callback()
		end
		viewer = H.findViewer()
		ok, detail = same(viewer)
		H.check("and it continues the exploration", ok and H.findInputDialog() == nil, detail)
		close()

		-- As a gesture, profile or Quick Dock action.
		Dispatcher:execute({ dictionaryexplorer_continue = true })
		viewer = H.findViewer()
		ok, detail = same(viewer)
		H.check("the Dispatcher action continues it too", ok, detail)
		close()
	end)

	-- ---- the dictionary explored last --------------------------------------------------
	H.step(0.5, function()
		plugin:openAt(html, "apple")
		local viewer = H.findViewer()
		viewer:showNext()
		local first = viewer.first
		close()
		plugin:continueExploring()
		viewer = H.findViewer()
		H.check("continuing opens the dictionary explored last", viewer and viewer.dictionary == html and viewer.first == first)
		close()
		local state = G_reader_settings:readSetting(SETTING)
		H.check("and each dictionary keeps its own place", state.by_dictionary[fixture.name] ~= nil and state.by_dictionary[fixture.name].first == saved.first)
	end)

	-- ---- long trails, changes, damage ------------------------------------------------------
	H.step(0.5, function()
		plugin:openAt(fixture, "livro")
		local viewer = H.findViewer()
		local words = { "amor", "correr", "gato", "mesa", "casa", "zebra" }
		for index = 1, 60 do
			viewer:goToWord(words[index % #words + 1])
		end
		local latest = viewer.trail[#viewer.trail].word
		close()
		local state = G_reader_settings:readSetting(SETTING).by_dictionary[fixture.name]
		H.check("the latest 50 words of the trail are kept", #state.trail == 50 and state.trail[50].word == latest and state.trail_index == 50)
		plugin:continueExploring()
		viewer = H.findViewer()
		H.check("and continue with the latest word current", viewer and #viewer.trail == 50 and viewer.trail_index == 50)
		close()

		-- Saved from another version of the dictionary.
		state = G_reader_settings:readSetting(SETTING).by_dictionary[fixture.name]
		state.count = state.count + 7
		plugin:continueExploring()
		viewer = H.findViewer()
		H.check(
			"an exploration of another version of the dictionary reopens at its word",
			viewer and fixture:getEntry(viewer.highlighted).word == state.word and #viewer.trail == 1,
			viewer and fixture:getEntry(viewer.highlighted).word
		)
		close()

		-- Damaged.
		state = G_reader_settings:readSetting(SETTING).by_dictionary[fixture.name]
		state.trail, state.first, state.word = "nonsense", "x", nil
		local called, err = pcall(function()
			plugin:continueExploring()
		end)
		viewer = H.findViewer()
		H.check("a damaged exploration opens the dictionary anyway, without an error", called and viewer ~= nil, err)
		close()
		G_reader_settings:delSetting(SETTING)
	end)

	H.finish()
end
