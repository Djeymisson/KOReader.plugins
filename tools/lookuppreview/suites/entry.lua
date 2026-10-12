--[[
How a lookup reaches the carousel, with real gestures on the book.

  patches         the plugin replaces ReaderDictionary.showDict and
                  ReaderHighlight's lookupDict / translate / lookupWikipedia,
                  and puts KOReader's own back when it is destroyed
  dictionary      a long press on a word opens the carousel on the Dictionary
                  card with the word's entry, and no dictionary window
  translate       Translate on a selection opens it on the Translate card,
                  with one query for the selected text
  wikipedia       Wikipedia on a selection opens it on the Wikipedia card,
                  with one search for the selected text
  close           a tap outside closes it and forgets the lookup
  disabled        with the preview off, KOReader's own window opens
]]

local PAGE_DICTIONARY, PAGE_TRANSLATION, PAGE_WIKIPEDIA = 1, 2, 3
local PATCHED_HIGHLIGHT = { "lookupDict", "translate", "lookupWikipedia" }

return function(H, ui)
	local plugin = H.plugin
	if not plugin then
		H.check("the plugin is loaded", false)
		H.finish()
		return
	end

	H.stubOnline(function(text)
		return "[en] " .. text
	end, function(text)
		return { { title = text, extract = "An article about " .. text .. "." } }
	end)

	local ReaderDictionary = require("apps/reader/modules/readerdictionary")
	local ReaderHighlight = require("apps/reader/modules/readerhighlight")

	-- ---- patches -------------------------------------------------------------
	H.step(0.5, function()
		H.check("showDict is replaced", rawget(ui.dictionary, "showDict") ~= nil and ui.dictionary.showDict ~= ReaderDictionary.showDict)
		for _, name in ipairs(PATCHED_HIGHLIGHT) do
			H.check("ReaderHighlight." .. name .. " is replaced", rawget(ui.highlight, name) ~= nil and ui.highlight[name] ~= ReaderHighlight[name])
		end
	end)

	-- ---- dictionary ----------------------------------------------------------
	H.step(0.5, function()
		H.lookUpWord("livro")
	end)
	H.step(2, function()
		local popup = H.popup()
		H.check("a long press on a word opens the carousel", popup ~= nil)
		H.check("on the Dictionary card", popup and popup.active_index == PAGE_DICTIONARY, popup and popup.active_index)
		H.check("with the word's entry", H.status(PAGE_DICTIONARY) == "done", H.status(PAGE_DICTIONARY))
		local state = plugin.current_state
		H.check("the entry is the word's", state and state.preview_results[1] and state.preview_results[1].result.word == "livro")
		H.check("and no dictionary window", H.nativeWindows() == 0, H.nativeWindows())
		H.check("Translate is not queried before its card is shown", H.calls.translation == 0, H.calls.translation)
	end)

	-- ---- close ---------------------------------------------------------------
	H.step(0.3, function()
		H.closeCarousel()
	end)
	H.step(0.5, function()
		H.check("a tap outside closes the carousel", H.popup() == nil)
		H.check("and forgets the lookup", plugin.current_state == nil)
	end)

	-- ---- translate -----------------------------------------------------------
	H.step(0.3, function()
		H.holdWord("casa")
	end)
	H.step(0.5, function()
		ui.highlight:translate()
	end)
	H.step(1, function()
		local popup = H.popup()
		H.check("Translate on a selection opens the carousel", popup ~= nil)
		H.check("on the Translate card", popup and popup.active_index == PAGE_TRANSLATION, popup and popup.active_index)
		H.check("with one query for the selected text", H.calls.translation == 1 and H.calls.last_translation == "casa", H.calls.translation .. " " .. tostring(H.calls.last_translation))
		H.check("showing the translation", H.status(PAGE_TRANSLATION) == "done", H.status(PAGE_TRANSLATION))
		H.check("the dictionary is not looked up before its card is shown", H.status(PAGE_DICTIONARY) == "idle", H.status(PAGE_DICTIONARY))
		H.closeCarousel()
	end)

	-- ---- wikipedia -----------------------------------------------------------
	H.step(0.5, function()
		H.holdWord("house")
	end)
	H.step(0.5, function()
		ui.highlight:lookupWikipedia()
	end)
	H.step(1, function()
		local popup = H.popup()
		H.check("Wikipedia on a selection opens the carousel", popup ~= nil)
		H.check("on the Wikipedia card", popup and popup.active_index == PAGE_WIKIPEDIA, popup and popup.active_index)
		H.check("with one search for the selected text", H.calls.wikipedia == 1 and H.calls.last_wikipedia == "house", H.calls.wikipedia)
		H.check("showing the article", H.status(PAGE_WIKIPEDIA) == "done", H.status(PAGE_WIKIPEDIA))
		H.closeCarousel()
	end)

	-- ---- disabled ------------------------------------------------------------
	H.step(0.5, function()
		plugin:setPreviewEnabled(false)
		H.lookUpWord("livro")
	end)
	H.step(2, function()
		H.check("with the preview off, no carousel", H.popup() == nil)
		H.check("and KOReader's own window", H.nativeWindows() == 1, H.nativeWindows())
		local window = require("ui/widget/dictquicklookup").window_list[1]
		if window then
			window:onClose()
		end
		plugin:setPreviewEnabled(true)
	end)

	-- ---- destroy -------------------------------------------------------------
	H.step(0.5, function()
		plugin:destroy()
		H.check("destroy puts showDict back", ui.dictionary.showDict == ReaderDictionary.showDict)
		for _, name in ipairs(PATCHED_HIGHLIGHT) do
			H.check("destroy puts ReaderHighlight." .. name .. " back", ui.highlight[name] == ReaderHighlight[name])
		end
	end)

	H.finish()
end
