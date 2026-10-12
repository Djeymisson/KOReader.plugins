--[[
Each card keeps where it was scrolled to, for as long as the lookup is open,
on content several pages long.

  dictionary      a definition scrolled with real swipes is shown at the same
                  place after going to another card and back, and its side
                  card shows that place too
  results         each dictionary result keeps its own place; a result not
                  scrolled yet starts at the top
  translation     the same for the Translate card; another target language
                  starts at the top
  rebuild         changing the appearance (tabs) keeps the place; changing the
                  dictionary HTML keeps the same proportion of the content
  new lookup      a new lookup, even of the same word, starts at the top
]]

local PAGE_DICTIONARY, PAGE_TRANSLATION = 1, 2

return function(H, ui)
	local plugin = H.plugin

	local function longText(label, lines)
		local parts = {}
		for index = 1, lines do
			parts[#parts + 1] = string.format("%s, line %d of a long text that takes several pages of the card.", label, index)
		end
		return table.concat(parts, "\n")
	end

	H.stubOnline(function(text, target)
		return longText("[" .. tostring(target) .. "] " .. text, 80)
	end, function(text)
		return { { title = text, extract = longText("Article", 60) } }
	end)

	local function results()
		return {
			{ dict = "Long A", word = "palavra", definition = longText("First definition", 120) },
			{ dict = "Long B", word = "palavra", definition = longText("Second definition", 120) },
		}
	end

	local function swipeUp(times)
		local area = H.popup().visible_dimen
		for _ = 1, times do
			H.gesture("swipe", area.x + math.floor(area.w / 2), area.y + math.floor(area.h / 2), { direction = "north", distance = 120 })
		end
	end

	local function page()
		return (H.activePage())
	end

	-- ---- dictionary ----------------------------------------------------------
	H.step(0.5, function()
		ui.dictionary:showDict("palavra", results())
	end)
	H.step(1, function()
		local current, count = H.activePage()
		H.check("a long definition opens at the top", current == 1, current)
		H.check("and takes several pages", count and count >= 4, count)
		swipeUp(2)
	end)
	H.step(0.5, function()
		H.check("two swipes up show its third page", page() == 3, page())
		plugin:switchToPage(PAGE_TRANSLATION)
	end)
	H.step(1, function()
		-- The side card has no buttons, so more of the content fits a page: it
		-- shows the same proportion of it.
		local side = H.cardHtml(PAGE_DICTIONARY)
		local box = side and side.htmlbox_widget
		local saved = plugin.current_state.scroll_positions["1:1"]
		local expected = box and saved and 1 + math.floor((saved.page - 1) * box.page_count / saved.count)
		H.check("the side card shows the definition where it was left", box and expected > 1 and box.page_number == expected, box and string.format("%d (expected %s)", box.page_number, tostring(expected)))
		plugin:switchToPage(PAGE_DICTIONARY)
	end)
	H.step(0.5, function()
		H.check("back on the card, the definition is where it was left", page() == 3, page())
	end)

	-- ---- results -------------------------------------------------------------
	H.step(0.3, function()
		plugin:switchDictionaryResult(2)
	end)
	H.step(0.5, function()
		H.check("a result not scrolled yet starts at the top", page() == 1, page())
		swipeUp(1)
	end)
	H.step(0.5, function()
		H.check("and scrolls on its own", page() == 2, page())
		plugin:switchDictionaryResult(1)
	end)
	H.step(0.5, function()
		H.check("the first result is where it was left", page() == 3, page())
		plugin:switchDictionaryResult(2)
	end)
	H.step(0.5, function()
		H.check("and so is the second", page() == 2, page())
		plugin:switchDictionaryResult(1)
	end)

	-- ---- translation ---------------------------------------------------------
	H.step(0.5, function()
		plugin:switchToPage(PAGE_TRANSLATION)
	end)
	H.step(1, function()
		local current, count = H.activePage()
		H.check("a long translation opens at the top", current == 1 and count and count >= 3, tostring(current) .. "/" .. tostring(count))
		swipeUp(2)
	end)
	H.step(0.5, function()
		H.check("the translation scrolls", page() == 3, page())
		plugin:switchToPage(PAGE_DICTIONARY)
	end)
	H.step(0.5, function()
		H.check("the dictionary is still where it was left", page() == 3, page())
		plugin:switchToPage(PAGE_TRANSLATION)
	end)
	H.step(0.5, function()
		H.check("and so is the translation", page() == 3, page())
		plugin:refreshTranslationWithTarget(plugin.current_state, "fr")
	end)
	H.step(1, function()
		H.check("another target language starts at the top", page() == 1, page())
		plugin:refreshTranslationWithTarget(plugin.current_state, "en")
	end)
	H.step(1, function()
		H.check("going back to the first language finds its place", page() == 3, page())
		plugin:switchToPage(PAGE_DICTIONARY)
	end)

	-- ---- rebuild -------------------------------------------------------------
	local full_count
	H.step(0.5, function()
		full_count = select(2, H.activePage())
		plugin:setSidePreviewMode("tabs")
		plugin:refreshVisibleCards()
	end)
	H.step(0.5, function()
		-- With tabs the card has no title, so more of the content fits a page:
		-- the same proportion of it is shown.
		local current, count = H.activePage()
		local expected = 1 + math.floor(2 * count / full_count)
		H.check("switching to tabs keeps the place", current == expected, string.format("%d (expected %d, %d -> %d pages)", current, expected, full_count, count))
		plugin:setSidePreviewMode("full_cards")
		plugin:refreshVisibleCards()
	end)
	H.step(0.5, function()
		H.check("and switching back finds it again", page() == 3, page())
	end)
	H.step(0.5, function()
		local old_count = select(2, H.activePage())
		plugin:setDictionaryHtmlMode("fast_raw")
		plugin:updateDictionaryPayload(plugin.current_state, plugin.current_state.dictionary_index)
		plugin:refreshVisibleCards()
		local new_count = select(2, H.activePage())
		local expected = 1 + math.floor(2 * new_count / old_count)
		H.check("another dictionary HTML keeps the proportion", page() == expected, string.format("%s (expected %d, %d -> %d pages)", tostring(page()), expected, old_count, new_count))
		plugin:setDictionaryHtmlMode("formatted")
	end)

	-- ---- new lookup ----------------------------------------------------------
	H.step(0.3, function()
		H.closeCarousel()
	end)
	H.step(0.5, function()
		ui.dictionary:showDict("palavra", results())
	end)
	H.step(1, function()
		H.check("a new lookup of the same word starts at the top", page() == 1, page())
		H.closeCarousel()
	end)

	H.finish()
end
