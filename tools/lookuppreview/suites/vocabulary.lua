--[[
The Dictionary card's button for KOReader's Vocabulary Builder, on its real
database.

  add             the button adds the looked up word, says so, and turns into
                  a mark that it was added
  exists          for a word already there, the Vocabulary Builder's own
                  dialog shows it, with no notification on top
  hidden          not shown with the setting off, when the Vocabulary Builder
                  adds every word by itself, or when nothing was found
]]

local PAGE_DICTIONARY = 1
local ADD = "Add the word to the vocabulary builder"
local ADDED = "Added to the vocabulary builder"

return function(H, ui)
	if not ui.vocabbuilder then
		H.skip("vocabulary builder", "KOReader's vocabbuilder plugin is not loaded")
		H.finish()
		return
	end

	local function hasButton(hint)
		return H.findButton(hint) ~= nil
	end

	local function lookUp(word)
		H.step(0.5, function()
			H.lookUpWord(word)
		end)
	end

	-- ---- add -----------------------------------------------------------------
	lookUp("livro")
	H.step(2, function()
		H.check("the word is not in the vocabulary builder yet", H.vocabularyCount("livro") == 0)
		H.check("the card offers to add it", hasButton(ADD), table.concat(H.buttonHints(), " | "))
		H.check("which is tapped", H.tapButton(ADD))
	end)
	H.step(0.5, function()
		H.check("the word is added", H.vocabularyCount("livro") == 1, H.vocabularyCount("livro"))
		local top = H.topWidget()
		H.check("a notification says so", top and top.text == "Added to vocabulary builder.", top and top.text)
		H.check("the button marks it as added", hasButton(ADDED) and not hasButton(ADD))
		H.check("the carousel stays open", H.popup() ~= nil)
		H.closeCarousel()
	end)

	-- ---- exists --------------------------------------------------------------
	lookUp("livro")
	H.step(2, function()
		H.check("a new lookup offers to add it again", hasButton(ADD))
		H.tapButton(ADD)
	end)
	H.step(0.5, function()
		local top = H.topWidget()
		local title = top and top.title or ""
		H.check("for a word already there, the vocabulary builder's dialog shows it", title:find("livro", 1, true) ~= nil, title)
		H.check("and it is not added twice", H.vocabularyCount("livro") == 1, H.vocabularyCount("livro"))
		if top and top.title then
			require("ui/uimanager"):close(top)
		end
	end)
	H.step(0.3, function()
		H.closeCarousel()
	end)

	-- ---- hidden --------------------------------------------------------------
	H.step(0.3, function()
		G_reader_settings:saveSetting("lookuppreview_dictionary_vocabulary_button", false)
	end)
	lookUp("casa")
	H.step(2, function()
		H.check("with the setting off, no button", not hasButton(ADD) and not hasButton(ADDED))
		H.closeCarousel()
		G_reader_settings:delSetting("lookuppreview_dictionary_vocabulary_button")
		local settings = G_reader_settings:readSetting("vocabulary_builder") or {}
		settings.enabled = true
		G_reader_settings:saveSetting("vocabulary_builder", settings)
	end)
	lookUp("casa")
	H.step(2, function()
		H.check("when the vocabulary builder adds every word, no button", not hasButton(ADD))
		H.closeCarousel()
		G_reader_settings:readSetting("vocabulary_builder").enabled = false
	end)
	lookUp("qqqzzzz")
	H.step(2, function()
		H.check("when nothing was found, no button", H.status(PAGE_DICTIONARY) == "empty" and not hasButton(ADD), H.status(PAGE_DICTIONARY))
		H.closeCarousel()
	end)

	H.finish()
end
