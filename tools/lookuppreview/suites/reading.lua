--[[
Reading comfort: card height and text size, the source language, the sentence,
which cards are shown and in which order, and keys.

  height          spreading two fingers on the carousel expands the cards and
                  pinching compacts them, keeping the same proportion of the
                  content in view; the setting makes new lookups open expanded
  text size       a larger text size lays the content on more pages
  side previews   switching to tabs with the carousel open places it for its
                  new height, inside the screen
  source          the card's language menu offers the source language of this
                  lookup first; choosing one translates from it, without
                  changing KOReader's setting
  sentence        the Translate card can translate the whole sentence around
                  the selection, showing it, and go back to the selection; a
                  lookup made inside the carousel has no sentence
  cards           a hidden card is left out of the carousel, its action left to
                  KOReader; the order is the one chosen; "last card used" opens
                  a lookup from the book on the card it was closed on
  keys            left and right go to the previous and next card, page turn
                  buttons scroll the card
]]

local PAGE_DICTIONARY, PAGE_TRANSLATION, PAGE_WIKIPEDIA = 1, 2, 3

return function(H, ui)
	local plugin = H.plugin
	local Screen = require("device").screen
	H.stubOnline(function(text, target)
		return "[" .. tostring(target) .. "] " .. text
	end, function(text)
		return { { title = text, extract = "An article about " .. text .. "." } }
	end)

	local function longResults()
		local lines = {}
		for index = 1, 120 do
			lines[#lines + 1] = string.format("Line %d of a definition long enough to take several pages.", index)
		end
		return { { dict = "Long", word = "palavra", definition = table.concat(lines, "\n") } }
	end

	local function center()
		local area = H.popup().visible_dimen
		return area.x + math.floor(area.w / 2), area.y + math.floor(area.h / 2)
	end

	local function cardHeight()
		return H.popup() and H.popup().card_height
	end

	local compact = math.floor(Screen:getHeight() * 0.38)
	local expanded = math.floor(Screen:getHeight() * 0.75)
	local page_before, count_before

	-- ---- height --------------------------------------------------------------
	H.step(0.5, function()
		ui.dictionary:showDict("palavra", longResults())
	end)
	H.step(1, function()
		H.check("cards open compact", cardHeight() == compact, cardHeight())
		local html = H.activeHtml()
		for _ = 1, 4 do
			html:scrollText(1)
		end
		page_before, count_before = H.activePage()
		local x, y = center()
		H.gesture("spread", x, y, { distance = 200, direction = "horizontal" })
	end)
	H.step(1, function()
		H.check("a spread expands them", cardHeight() == expanded, cardHeight())
		local page, count = H.activePage()
		local expected = 1 + math.floor((page_before - 1) * count / count_before)
		H.check("keeping the same proportion of the content in view", page == expected, string.format("%d of %d (expected %d; was %d of %d)", page, count, expected, page_before, count_before))
		local area = H.popup().visible_dimen
		H.check("inside the screen", area.y >= 0 and area.y + area.h <= Screen:getHeight(), area.y .. "+" .. area.h)
		local x, y = center()
		H.gesture("pinch", x, y, { distance = 200, direction = "horizontal" })
	end)
	H.step(1, function()
		H.check("a pinch compacts them again", cardHeight() == compact, cardHeight())
		H.check("back at the same place", H.activePage() == page_before, H.activePage())
		H.closeCarousel()
	end)
	H.step(0.5, function()
		H.menuItem("Appearance", "Card height", "Expanded").callback()
		ui.dictionary:showDict("palavra", longResults())
	end)
	H.step(1, function()
		H.check("with the setting, new lookups open expanded", cardHeight() == expanded, cardHeight())
		H.menuItem("Appearance", "Card height", "Compact").callback()
		H.check("and changing it with the carousel open applies at once", cardHeight() == compact, cardHeight())
	end)

	-- ---- text size -----------------------------------------------------------
	H.step(0.5, function()
		count_before = select(2, H.activePage())
		H.menuItem("Appearance", "Text size", "24").callback()
	end)
	H.step(0.5, function()
		local count = select(2, H.activePage())
		H.check("a larger text takes more pages", count > count_before, count_before .. " -> " .. count)
		H.menuItem("Appearance", "Text size", "18").callback()
	end)

	-- ---- side previews -------------------------------------------------------
	H.step(0.5, function()
		H.menuItem("Appearance", "Display style", "Tabs").callback()
	end)
	H.step(0.5, function()
		local area = H.popup().visible_dimen
		H.check("switching to tabs keeps the carousel inside the screen", area.y + area.h <= Screen:getHeight(), area.y .. "+" .. area.h .. " of " .. Screen:getHeight())
		H.menuItem("Appearance", "Display style", "Carousel").callback()
	end)
	-- A new carousel is drawn on the next refresh; a tap before that would land
	-- on buttons not placed yet, which no finger can do.
	H.step(0.5, function()
		H.closeCarousel()
	end)

	-- ---- source --------------------------------------------------------------
	H.step(0.5, function()
		H.holdWord("casa")
	end)
	H.step(0.5, function()
		ui.highlight:translate()
	end)
	H.step(1, function()
		plugin:showTargetLanguageMenu(plugin.current_state)
		local first = plugin.language_menu and plugin.language_menu.item_table[1]
		local edit_icon = plugin:getPluginIconFile("edit") or ""
		H.check("the edit button uses the plugin's edit_lookup.svg", edit_icon:find("/icons/edit_lookup.svg", 1, true) ~= nil, edit_icon)
		H.check("the language menu offers the source language first", first and first.text:find("Translate from", 1, true) == 1 and first.sub_item_table ~= nil, first and first.text)
		plugin:refreshTranslationWithSource(plugin.current_state, "es")
	end)
	H.step(1, function()
		H.check("choosing one translates from it", H.calls.last_source == "es", H.calls.last_source)
		local payload = plugin:getPagePayload(plugin.current_state, PAGE_TRANSLATION, true)
		H.check("and the subtitle says so", payload.subtitle:find("Spanish", 1, true) ~= nil, payload.subtitle)
		H.check("without changing KOReader's setting", G_reader_settings:readSetting("translator_from_language") == nil)
	end)

	-- ---- sentence ------------------------------------------------------------
	H.step(0.3, function()
		local button = H.findButton("Translate the whole sentence")
		H.check("the sentence is offered", button ~= nil, table.concat(H.buttonHints(), " | "))
		H.check("by an icon, translate_sentence.svg", button and tostring(button.icon_file):find("/icons/translate_sentence.svg", 1, true) ~= nil, button and tostring(button.icon_file))
		H.tapButton("Translate the whole sentence")
	end)
	H.step(1, function()
		H.check("and translated", H.calls.last_translation == "O livro fica na casa qqqzzzz.", H.calls.last_translation)
		local payload = plugin:getPagePayload(plugin.current_state, PAGE_TRANSLATION, true)
		H.check("showing the sentence", payload.html_body:find("lp-source", 1, true) ~= nil and payload.html_body:find("O livro fica", 1, true) ~= nil)
		local count = H.calls.translation
		local button = H.findButton("Translate only the selected text")
		H.check("the button's icon turns into translate_selection.svg", button and tostring(button.icon_file):find("/icons/translate_selection.svg", 1, true) ~= nil, button and tostring(button.icon_file))
		H.check("the selection can be translated again", H.tapButton("Translate only the selected text"))
		H.step(1, function()
			H.check("with no new query", H.calls.translation == count and H.status(PAGE_TRANSLATION) == "done", H.calls.translation .. " " .. count)
			plugin:lookUpInPreview("mesa")
		end)
		H.step(1, function()
			local hints = table.concat(H.buttonHints(), " | ")
			H.check("a lookup made inside the carousel has no sentence", not hints:find("whole sentence", 1, true), hints)
			H.closeCarousel()
		end)

		-- The sentence of a selection, from the book itself: a selection that is
		-- already the sentence but for its final period offers none (it would
		-- translate the same thing), and one at the very start of the text gets
		-- its sentence with nothing repeated.
		H.step(0.5, function()
			local function sentenceOf(text)
				local hit = ui.document:findAllText(text, false, 0, 1)[1]
				plugin.selection_snapshot = { selected_text = { text = text, pos0 = hit.start, pos1 = hit["end"] } }
				return plugin:getSelectionSentence({})
			end
			local sentence = sentenceOf("livro fica na casa qqqzzzz")
			H.check("a selection shorter than its sentence offers it", sentence == "O livro fica na casa qqqzzzz.", sentence)
			sentence = sentenceOf("O livro")
			H.check("also at the start of the text, with nothing repeated", sentence == "O livro fica na casa qqqzzzz.", sentence)
			sentence = sentenceOf("O livro fica na casa qqqzzzz")
			H.check("a selection that is the sentence but for its final period offers no sentence", sentence == nil, sentence)
			sentence = sentenceOf("near a bookshop")
			-- KOReader gives no context after the last word of the text, so the
			-- sentence comes without its final period there.
			H.check("one at the end of the text gets its sentence", sentence == "The house is near a bookshop", sentence)
			plugin.selection_snapshot = nil
		end)

		-- ---- cards -----------------------------------------------------------
		H.step(0.5, function()
			G_reader_settings:saveSetting("lookuppreview_hidden_cards", { ["3"] = true })
			H.lookUpWord("livro")
		end)
		H.step(2, function()
			local row = H.popup().card_container
			H.check("a hidden card is left out", #row.card_order == 2 and row.next_index == PAGE_TRANSLATION, table.concat(row.card_order, ","))

			-- ---- title: the card's name opens the list of cards -------------
			local title = H.findButton("Choose which card to show")
			H.check("the card's title is its name, with ▾", title and title.text == "Dictionary ▾", title and title.text)
			local dictionary_payload = plugin:getPagePayload(plugin.current_state, PAGE_DICTIONARY, true)
			H.check("the word moves to the subtitle, with its dictionary", dictionary_payload.subtitle:find("livro · ", 1, true) == 1, dictionary_payload.subtitle)
			local card_buttons = select(2, table.concat(H.buttonHints(), "|"):gsub("Choose which card to show", ""))
			H.check("there is no ☰ button any more: only the title chooses cards", card_buttons == 1, card_buttons)
			H.tapButton("Choose which card to show")
		end)
		H.step(0.5, function()
			local menu = H.popup() and H.popup().page_menu
			H.check("tapping the title opens the list of cards", menu ~= nil and table.concat(menu.cards, ",") == "1,2", menu and table.concat(menu.cards, ","))
			local title_dimen = H.findButton("Choose which card to show").dimen
			H.check("below the title, on its left", menu and math.abs(menu.visible_dimen.x - title_dimen.x) <= 2, menu and (menu.visible_dimen.x .. " vs " .. title_dimen.x))
			H.popup():closePageMenu()
			G_reader_settings:saveSetting("lookuppreview_hidden_cards", { ["2"] = true, ["3"] = true })
			plugin:reopenCarousel()
		end)
		H.step(0.5, function()
			local only = H.findButton("Choose which card to show")
			H.check("with one card shown, the title opens nothing", only == nil, only and only.text)
			G_reader_settings:saveSetting("lookuppreview_hidden_cards", { ["3"] = true })
			plugin:setSidePreviewMode("tabs")
			plugin:reopenCarousel()
		end)
		H.step(0.5, function()
			H.check("with tabs, no title: the tabs name the cards", H.findButton("Choose which card to show") == nil)
			plugin:setSidePreviewMode("full_cards")
			plugin:reopenCarousel()
		end)
		H.step(0.5, function()
			plugin:switchToPage(PAGE_TRANSLATION)
		end)
		H.step(1, function()
			local x, y = center()
			H.gesture("swipe", x, y, { direction = "west", distance = 200 })
		end)
		H.step(0.5, function()
			H.check("swiping past the last card shown stays", H.popup().active_index == PAGE_TRANSLATION, H.popup().active_index)
			H.closeCarousel()
			local native_called = false
			local original = plugin.original_highlight_lookupWikipedia
			plugin.original_highlight_lookupWikipedia = function()
				native_called = true
			end
			ui.highlight:lookupWikipedia()
			plugin.original_highlight_lookupWikipedia = original
			H.check("and its action is left to KOReader", native_called and H.popup() == nil)
			G_reader_settings:delSetting("lookuppreview_hidden_cards")
			G_reader_settings:saveSetting("lookuppreview_card_order", { 2, 1, 3 })
			H.lookUpWord("livro")
		end)
		H.step(2, function()
			local row = H.popup().card_container
			H.check("the cards follow the order chosen", table.concat(row.card_order, ",") == "2,1,3", table.concat(row.card_order, ","))
			H.check("the dictionary's neighbours follow it", row.prev_index == PAGE_TRANSLATION and row.next_index == PAGE_WIKIPEDIA)
			H.popup():showPageMenu()
			local menu = H.popup().page_menu
			H.check("and so does the card menu", menu and table.concat(menu.cards, ",") == "2,1,3")
			H.popup():closePageMenu()
			G_reader_settings:delSetting("lookuppreview_card_order")
			H.menuItem("Content", "Cards", "Open on the last card used").callback()
			plugin:switchToPage(PAGE_WIKIPEDIA)
		end)
		H.step(1, function()
			H.closeCarousel()
		end)
		H.step(0.5, function()
			H.lookUpWord("casa")
		end)
		H.step(2, function()
			H.check("with \"last card used\", a lookup opens on the card it was closed on", H.popup() and H.popup().active_index == PAGE_WIKIPEDIA)
			H.check("loading it", H.status(PAGE_WIKIPEDIA) == "done", H.status(PAGE_WIKIPEDIA))
			H.menuItem("Content", "Cards", "Open on the dictionary card").callback()
			-- Hiding the card shown, as Show and order cards does.
			plugin:switchToPage(PAGE_DICTIONARY)
			G_reader_settings:saveSetting("lookuppreview_hidden_cards", { ["1"] = true })
			plugin:reopenCarousel()
		end)
		H.step(1, function()
			H.check("hiding the card shown shows the next one", H.popup().active_index == PAGE_TRANSLATION, H.popup().active_index)
			H.check("loaded", H.status(PAGE_TRANSLATION) == "done", H.status(PAGE_TRANSLATION))
			G_reader_settings:delSetting("lookuppreview_hidden_cards")
			plugin:reopenCarousel()
			plugin:switchToPage(PAGE_WIKIPEDIA)
		end)
		H.step(0.5, function()

			-- ---- keys --------------------------------------------------------
			H.key("Left")
		end)
		H.step(0.5, function()
			H.check("Left goes to the previous card", H.popup().active_index == PAGE_TRANSLATION, H.popup().active_index)
			H.key("Left")
		end)
		H.step(0.5, function()
			H.check("and again", H.popup().active_index == PAGE_DICTIONARY, H.popup().active_index)
			H.key("Right")
		end)
		H.step(0.5, function()
			H.check("Right goes to the next card", H.popup().active_index == PAGE_TRANSLATION, H.popup().active_index)
			H.closeCarousel()
			ui.dictionary:showDict("palavra", longResults())
		end)
		H.step(1, function()
			H.key("RPgFwd")
		end)
		H.step(0.5, function()
			H.check("a page turn button scrolls the card", H.activePage() == 2, H.activePage())
			H.key("RPgBack")
		end)
		H.step(0.5, function()
			H.check("and back", H.activePage() == 1, H.activePage())
			H.closeCarousel()
			H.finish()
		end)
	end)
end
