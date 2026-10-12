--[[
The Dictionary card of a carousel opened from Translate or Wikipedia: it is
looked up when it is first shown, through KOReader's own lookup (real sdcv on
the fixtures), as a lookup from the book would be.

  idle            before its card is shown, the dictionary is not looked up
  lookup          swiping to the card looks the text up: the entry is shown,
                  with no dictionary window and no "No results" dialog, and
                  the Translate card keeps its translation (no new query)
  native          the card's button opens KOReader's window on the same word
  empty           a word in no dictionary says so on the card, without
                  KOReader's fuzzy search dialog, even with fuzzy search off
  closed          closing the carousel while looking up opens nothing when
                  the results arrive
  side card       results arriving after swiping away fill the side card
  interrupted     a lookup that did not finish says so, and Retry looks the
                  text up again
  wikipedia       the same from a carousel opened from Wikipedia
]]

local PAGE_DICTIONARY, PAGE_TRANSLATION = 1, 2

return function(H, ui)
	local plugin = H.plugin
	-- The translation service finds nothing for the word no dictionary has.
	H.stubOnline(function(text)
		return text == "qqqzzzz" and "" or ("[en] " .. text)
	end, function(text)
		return { { title = text, extract = "An article about " .. text .. "." } }
	end)

	local function swipe(direction)
		local area = H.popup().visible_dimen
		H.gesture("swipe", area.x + math.floor(area.w / 2), area.y + math.floor(area.h / 2), { direction = direction, distance = 200 })
	end

	local function captureCleared()
		return #(plugin.dictionary_captures or {}) == 0 and rawget(ui.dictionary, "showNoResultsDialog") == nil
	end

	local function inputDialogShown()
		return H.findWidget(function(widget)
			return widget.getInputText ~= nil
		end) ~= nil
	end

	local function openFromTranslate(word)
		H.step(0.5, function()
			H.holdWord(word)
		end)
		H.step(0.5, function()
			ui.highlight:translate()
		end)
	end

	-- ---- idle and lookup -----------------------------------------------------
	openFromTranslate("casa")
	H.step(1, function()
		H.check("the carousel opens on Translate", H.popup() and H.popup().active_index == PAGE_TRANSLATION)
		H.check("the dictionary is idle", H.status(PAGE_DICTIONARY) == "idle", H.status(PAGE_DICTIONARY))
		H.check("its side card says so", plugin:getPagePayload(plugin.current_state, PAGE_DICTIONARY, false).html_body:find("Swipe to open the dictionary", 1, true) ~= nil)
		swipe("east")
	end)
	H.step(1.5, function()
		local state = plugin.current_state
		H.check("swiping to the card shows it", H.popup() and H.popup().active_index == PAGE_DICTIONARY)
		H.check("and looks the text up", H.status(PAGE_DICTIONARY) == "done", H.status(PAGE_DICTIONARY))
		local words = {}
		local entries = state and state.preview_results or {}
		for index = 1, #entries do
			words[#words + 1] = entries[index].result.word .. " (" .. entries[index].result.dict .. ")"
		end
		H.check("the entries are the selected word's", table.concat(words, ", "):find("casa (", 1, true) ~= nil, table.concat(words, ", "))
		H.check("no dictionary window opens", H.nativeWindows() == 0, H.nativeWindows())
		H.check("the lookup is no longer caught", captureCleared())
		H.check("Translate keeps its translation", H.status(PAGE_TRANSLATION) == "done" and H.calls.translation == 1, H.calls.translation)
		local hints = table.concat(H.buttonHints(), " | ")
		H.check("the card offers KOReader's window", hints:find("Open KOReader's original dictionary popup", 1, true) ~= nil, hints)
	end)

	-- ---- native --------------------------------------------------------------
	H.step(0.3, function()
		H.check("its button is tapped", H.tapButton("Open KOReader's original dictionary popup"))
	end)
	H.step(1, function()
		local window = require("ui/widget/dictquicklookup").window_list[1]
		H.check("KOReader's window opens", window ~= nil)
		H.check("on the same word", window and window.word == "casa", window and window.word)
		H.check("and the carousel closes", H.popup() == nil)
		if window then
			window:onClose()
		end
	end)

	-- ---- empty ---------------------------------------------------------------
	H.step(0.5, function()
		ui.dictionary.disable_fuzzy_search = true
	end)
	openFromTranslate("qqqzzzz")
	H.step(1, function()
		H.check("a text with no translation is empty", H.status(PAGE_TRANSLATION) == "empty", H.status(PAGE_TRANSLATION))
		local payload = plugin:getPagePayload(plugin.current_state, PAGE_TRANSLATION, true)
		H.check("and says so", payload.html_body:find("No translation found", 1, true) ~= nil, payload.html_body)
		H.check("keeping the language pair in its subtitle", payload.subtitle:find("→", 1, true) ~= nil, payload.subtitle)
		H.check("which still chooses another language", payload.subtitle_callback ~= nil)
		if payload.subtitle_callback then
			payload.subtitle_callback()
			H.check("tapping it opens the language menu", plugin.language_menu ~= nil)
			plugin:closeLanguageMenu()
		end
		swipe("east")
	end)
	H.step(1.5, function()
		H.check("a word in no dictionary is empty", H.status(PAGE_DICTIONARY) == "empty", H.status(PAGE_DICTIONARY))
		local payload = plugin:getPagePayload(plugin.current_state, PAGE_DICTIONARY, true)
		H.check("the card says no definition was found", payload.html_body:find("No definition found", 1, true) ~= nil, payload.html_body)
		H.check("without KOReader's fuzzy search dialog", not inputDialogShown())
		H.check("and the lookup is no longer caught", captureCleared())
		ui.dictionary.disable_fuzzy_search = false
		H.closeCarousel()
	end)

	-- ---- closed while looking up --------------------------------------------
	openFromTranslate("livro")
	H.step(1, function()
		plugin:loadDictionary(plugin.current_state)
		H.check("the card is looking up", H.status(PAGE_DICTIONARY) == "loading", H.status(PAGE_DICTIONARY))
		H.popup():onClose()
	end)
	H.step(1.5, function()
		H.check("closed while looking up: no carousel when the results arrive", H.popup() == nil)
		H.check("and no dictionary window", H.nativeWindows() == 0, H.nativeWindows())
		H.check("and the lookup is no longer caught", captureCleared())
	end)

	-- ---- side card -----------------------------------------------------------
	openFromTranslate("livro")
	H.step(1, function()
		plugin:switchToPage(PAGE_DICTIONARY)
		plugin:loadDictionary(plugin.current_state)
		plugin:switchToPage(PAGE_TRANSLATION)
	end)
	H.step(1.5, function()
		H.check("results after swiping away: the dictionary is done", H.status(PAGE_DICTIONARY) == "done", H.status(PAGE_DICTIONARY))
		local html = H.cardHtml(PAGE_DICTIONARY)
		local body = html and html.html_body or ""
		H.check("and its side card shows the entry", body ~= "" and not body:find("Looking up", 1, true), body:sub(1, 80))
		H.closeCarousel()
	end)

	-- ---- interrupted ---------------------------------------------------------
	openFromTranslate("livro")
	H.step(1, function()
		ui.dictionary.startSdcv = function(_self, word)
			return {
				{ dict = "", word = word, definition = "Dictionary lookup interrupted.", no_result = true, lookup_cancelled = true },
				lookup_cancelled = true,
			}
		end
		swipe("east")
	end)
	H.step(1.5, function()
		local status, message = H.status(PAGE_DICTIONARY)
		H.check("an interrupted lookup is an error", status == "error", status)
		H.check("that says so", message and message:find("interrupted", 1, true) ~= nil, message)
		H.check("with no dictionary window", H.nativeWindows() == 0, H.nativeWindows())
		H.check("and the lookup is no longer caught", captureCleared())
		local retry = H.findButton("Look the text up in the dictionary again")
		H.check("Retry is the retry.svg icon", retry and tostring(retry.icon_file):find("/icons/retry.svg", 1, true) ~= nil, retry and tostring(retry.icon_file))
		ui.dictionary.startSdcv = nil
		H.check("Retry is offered and tapped", H.tapButton("Look the text up in the dictionary again"))
	end)
	H.step(1.5, function()
		H.check("Retry looks the text up again", H.status(PAGE_DICTIONARY) == "done", H.status(PAGE_DICTIONARY))
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
		H.check("from Wikipedia, the dictionary is idle", H.status(PAGE_DICTIONARY) == "idle", H.status(PAGE_DICTIONARY))
		plugin:switchToPage(PAGE_DICTIONARY)
	end)
	H.step(1.5, function()
		local state = plugin.current_state
		H.check("and is looked up when shown", H.status(PAGE_DICTIONARY) == "done", H.status(PAGE_DICTIONARY))
		H.check("with the selected word's entry", state and state.preview_results[1] and state.preview_results[1].result.word == "house")
		H.check("Wikipedia was searched once", H.calls.wikipedia == 1, H.calls.wikipedia)
		H.closeCarousel()
	end)

	H.finish()
end
