--[[
The plugin's settings menu, through its real items and callbacks.

  appearance      the display (Carousel or Tabs) and the corners are styles
  content         Content has the general options first (Cards, Online card
                  loading: Automatic or Manual), then one submenu per card,
                  named as the card, with the same shape: the card's options,
                  and its buttons in Buttons
  dictionary      Dictionary: Dictionary HTML, and Buttons with one checkbox
                  per button (KOReader popup, Dictionary Explorer, vocabulary
                  builder); the last button that opens the full dictionary
                  cannot be unchecked, so there is always a way to it
  translate       Translate: target language, source text, and Buttons with
                  copy and note
  wikipedia       Wikipedia: its language
  same settings   each option moved keeps its setting: changing it from its
                  new place changes what it always did
]]

return function(H)
	local plugin = H.plugin

	local function texts(item)
		local items = item.sub_item_table or (item.sub_item_table_func and item.sub_item_table_func()) or {}
		local found = {}
		for index = 1, #items do
			local text = items[index].text or (items[index].text_func and items[index].text_func()) or "?"
			found[#found + 1] = (text:gsub(":.*$", ""))
		end
		return table.concat(found, " | ")
	end

	local function menuItem(...)
		local ok, item = pcall(H.menuItem, ...)
		return ok and item or nil
	end

	-- ---- structure -----------------------------------------------------------
	H.step(0.5, function()
		local appearance = menuItem("Appearance")
		H.check("Appearance: the display and the corners are styles", appearance and texts(appearance):find("^Display style | Corner style | ") ~= nil, appearance and texts(appearance))
		local display = menuItem("Appearance", "Display style")
		H.check("the display style is Carousel or Tabs", display and texts(display) == "Carousel | Tabs", display and texts(display))
		local corners = menuItem("Appearance", "Corner style")
		H.check("the corner style is Square or Rounded", corners and texts(corners) == "Square | Rounded", corners and texts(corners))

		local content = menuItem("Content")
		H.check("Content: general options, then one submenu per card, named as the card", content and texts(content) == "Cards | Online card loading | Dictionary | Translate | Wikipedia", content and texts(content))
		local loading = menuItem("Content", "Online card loading")
		H.check("online cards load Automatic or Manual", loading and texts(loading) == "Automatic | Manual", loading and texts(loading))

		local dictionary = menuItem("Content", "Dictionary")
		H.check("Dictionary: its HTML and its buttons", dictionary and texts(dictionary) == "Dictionary HTML | Buttons", dictionary and texts(dictionary))
		local dictionary_buttons = menuItem("Content", "Dictionary", "Buttons")
		H.check("its buttons: one checkbox each", dictionary_buttons and texts(dictionary_buttons) == "Show KOReader popup button | Show Dictionary Explorer button | Show vocabulary builder button", dictionary_buttons and texts(dictionary_buttons))

		local translate = menuItem("Content", "Translate")
		H.check("Translate: target language, source text, buttons", translate and texts(translate) == "Target language | Show source text | Buttons", translate and texts(translate))
		local translate_buttons = menuItem("Content", "Translate", "Buttons")
		H.check("its buttons: copy and note", translate_buttons and texts(translate_buttons) == "Show copy button | Show note button", translate_buttons and texts(translate_buttons))

		local wikipedia = menuItem("Content", "Wikipedia")
		H.check("Wikipedia: its language", wikipedia and texts(wikipedia) == "Language", wikipedia and texts(wikipedia))

		-- The languages by their names, as on the cards, not their codes.
		local Translator = require("ui/translator")
		local target = menuItem("Content", "Translate", "Target language")
		local target_text = target and target.text_func()
		H.check("the target language is shown by its name", target_text == "Target language: " .. plugin:getTranslatorLanguageLabel(Translator, plugin:getTranslationTargetLang()) and not target_text:find(": %l%l$"), target_text)
		local language = menuItem("Content", "Wikipedia", "Language")
		local language_text = language and language.text_func()
		H.check("and so is the Wikipedia language", language_text == "Language: " .. plugin:getWikipediaLanguageLabel(plugin:getWikipediaLang()) and not language_text:find(": %l%l$"), language_text)
	end)

	-- ---- dictionary buttons --------------------------------------------------
	H.step(0.3, function()
		local function button(name)
			return menuItem("Content", "Dictionary", "Buttons", name)
		end
		local function checked(name)
			local item = button(name)
			return item and item.checked_func()
		end
		local function enabled(name)
			local item = button(name)
			return item and (item.enabled_func == nil or item.enabled_func())
		end

		-- Without Dictionary Explorer, KOReader's popup is the only way to the
		-- full dictionary.
		H.check("both full dictionary buttons are shown by default", checked("Show KOReader popup button") and checked("Show Dictionary Explorer button"))
		H.check("without Dictionary Explorer, its checkbox is disabled", not enabled("Show Dictionary Explorer button"))
		H.check("and KOReader's popup cannot be unchecked", not enabled("Show KOReader popup button"))

		local original = plugin.getDictionaryExplorer
		plugin.getDictionaryExplorer = function()
			return {}
		end
		button("Show KOReader popup button").callback()
		H.check("with Dictionary Explorer, unchecking KOReader's popup leaves Dictionary Explorer", plugin:getDetailsButtonsMode() == "explorer", plugin:getDetailsButtonsMode())
		H.check("whose checkbox, the last one, cannot be unchecked", not enabled("Show Dictionary Explorer button"))
		button("Show KOReader popup button").callback()
		H.check("checking KOReader's popup again shows both", plugin:getDetailsButtonsMode() == "both", plugin:getDetailsButtonsMode())
		button("Show Dictionary Explorer button").callback()
		H.check("unchecking Dictionary Explorer leaves KOReader's popup", plugin:getDetailsButtonsMode() == "koreader", plugin:getDetailsButtonsMode())
		plugin.getDictionaryExplorer = original
		G_reader_settings:delSetting("lookuppreview_dictionary_details_buttons")
	end)

	-- ---- same settings -------------------------------------------------------
	H.step(0.3, function()
		local item = menuItem("Content", "Dictionary", "Dictionary HTML", "Fast / Raw")
		if item then
			item.callback()
		end
		H.check("Dictionary HTML still sets the dictionary HTML", plugin:useFastRawDictionaryHtml())
		item = menuItem("Content", "Dictionary", "Dictionary HTML", "Formatted")
		if item then
			item.callback()
		end

		item = menuItem("Content", "Dictionary", "Buttons", "Show vocabulary builder button")
		if item then
			item.callback()
		end
		H.check("the vocabulary builder button still has its setting", G_reader_settings:readSetting("lookuppreview_dictionary_vocabulary_button") == false)
		G_reader_settings:delSetting("lookuppreview_dictionary_vocabulary_button")

		item = menuItem("Content", "Translate", "Show source text")
		if item then
			item.callback()
		end
		H.check("Show source text still has its setting", plugin:showTranslationSourceText())
		G_reader_settings:delSetting("lookuppreview_translation_show_source")

		item = menuItem("Content", "Translate", "Buttons", "Show copy button")
		if item then
			item.callback()
		end
		H.check("the copy button still has its setting", not plugin:showTranslationCopyButton())
		G_reader_settings:delSetting("lookuppreview_translation_show_copy_button")

		item = menuItem("Content", "Wikipedia", "Language", "Portuguese")
		if item then
			item.callback()
		end
		H.check("the Wikipedia language still has its setting", plugin:getWikipediaLang() == "pt", plugin:getWikipediaLang())
	end)

	H.finish()
end
