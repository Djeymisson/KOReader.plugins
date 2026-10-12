--[[
The plugin in Brazilian Portuguese (run.sh starts this suite with KOReader's
language set to pt_BR).

  complete        every text the plugin passes to _() or C_() is translated,
                  by lookuppreview_l10n.lua or by KOReader's own catalog, but
                  for the plugin's names
  placeholders    a translation keeps the %s and %d of its text
  interface       the menu, the card's title and the buttons' hints show up in
                  Portuguese
]]

local PAGE_DICTIONARY = 1

-- Names that stay as they are.
local SAME = {
	["Lookup Preview"] = true,
	["Dictionary Explorer"] = true,
}

return function(H)
	local plugin = H.plugin
	local _ = require("lookuppreview_l10n")

	local function readFile(path)
		local file = assert(io.open(path, "r"))
		local content = file:read("*a")
		file:close()
		return content
	end

	-- The texts given to _("...") and C_("context", "..."), and to _([[...]]).
	local function pluginTexts()
		local texts = {}
		local files = { plugin.path .. "/_meta.lua" }
		local modules = { "carousel", "context", "core", "dictionary", "payload", "translation", "utils", "widgets", "wikipedia" }
		for index = 1, #modules do
			files[#files + 1] = plugin.path .. "/modules/" .. modules[index] .. ".lua"
		end
		for index = 1, #files do
			local path = files[index]
			local source = readFile(path)
			for text in source:gmatch('[^%w_.]_%(%s*"(.-)"%s*%)') do
				texts[text] = path
			end
			for text in source:gmatch('[^%w_.]_%(%s*%[%[(.-)%]%]%s*%)') do
				texts[text] = path
			end
			for context, text in source:gmatch('C_%(%s*"(.-)"%s*,%s*"(.-)"%s*%)') do
				texts[context .. "\4" .. text] = path
			end
		end
		return texts
	end

	local function placeholders(text)
		local found = {}
		for placeholder in text:gmatch("%%[sd]") do
			found[#found + 1] = placeholder
		end
		return table.concat(found, " ")
	end

	-- ---- complete and placeholders -------------------------------------------
	H.step(0.5, function()
		local count, untranslated, broken = 0, {}, {}
		for key in pairs(pluginTexts()) do
			count = count + 1
			local context, text = key:match("^(.-)\4(.*)$")
			local translated
			if context then
				translated = _.pgettext(context, text)
			else
				text = key
				translated = _(text)
			end
			if translated == text and not SAME[text] then
				untranslated[#untranslated + 1] = text
			elseif placeholders(translated) ~= placeholders(text) then
				broken[#broken + 1] = text .. " -> " .. translated
			end
		end
		H.check("the plugin's texts are found", count > 150, count)
		H.check("every one of them is translated", #untranslated == 0, table.concat(untranslated, " | "))
		H.check("with its placeholders", #broken == 0, table.concat(broken, " | "))
	end)

	-- ---- interface -----------------------------------------------------------
	H.step(0.3, function()
		local ok, item = pcall(H.menuItem, "Aparência", "Altura dos cartões", "Expandida")
		H.check("the menu is in Portuguese", ok and item ~= nil, item)
		H.lookUpWord("livro")
	end)
	H.step(2, function()
		local title = H.findButton("Escolher qual cartão mostrar")
		H.check("the card's title is the card's name in Portuguese", title and title.text == "Dicionário ▾", title and title.text)
		local hints = table.concat(H.buttonHints(), " | ")
		H.check("and so are the buttons' hints", hints:find("Destacar o texto selecionado", 1, true) ~= nil and hints:find("Buscar o texto selecionado no livro", 1, true) ~= nil, hints)
		H.check("the dictionary card shows", H.status(PAGE_DICTIONARY) == "done", H.status(PAGE_DICTIONARY))
		-- KOReader in pt_BR makes the target language "pt_br", which the
		-- translator lists as "pt".
		local Translator = require("ui/translator")
		H.check("a target language in KOReader's pt_br form gets its name", plugin:getTranslatorLanguageLabel(Translator, "pt_br") == Translator:getLanguageName("pt"), plugin:getTranslatorLanguageLabel(Translator, "pt_br"))
		H.check("and pt_pt finds pt-PT", plugin:getTranslatorLanguageLabel(Translator, "pt_pt") == Translator:getLanguageName("pt-PT"), plugin:getTranslatorLanguageLabel(Translator, "pt_pt"))
		H.closeCarousel()
	end)

	H.finish()
end
