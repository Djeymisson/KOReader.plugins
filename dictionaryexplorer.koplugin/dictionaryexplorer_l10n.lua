-- KOReader's gettext catalog does not contain strings from external plugins.
-- Keep plugin-specific translations here and fall back to KOReader's catalog
-- for languages without a Dictionary Explorer translation (and for native UI
-- terms such as "Cancel"). Mirrors pageanchor.koplugin/pageanchor_l10n.lua.
local gettext = require("gettext")

local locale = type(gettext) == "table" and gettext.current_lang or nil
if not locale or locale == "C" then
	local settings = rawget(_G, "G_reader_settings")
	locale = settings and settings.readSetting and settings:readSetting("language") or locale
end
locale = tostring(locale or "C"):gsub("-", "_")
if not locale:match("^pt_BR") and not locale:match("^pt_PT") then
	return gettext
end

-- Same wording in Brazilian and European Portuguese, so one table serves both.
local pt = {
	["Dictionary Explorer"] = "Dictionary Explorer",
	["Adds a \"Go to dictionary\" button to the dictionary popup that opens the dictionary at the looked-up word, so you can read on through the neighbouring entries like a book."] = "Adiciona ao popup do dicionário um botão \"Ir para o dicionário\" que abre o dicionário na palavra pesquisada, para você continuar lendo os verbetes vizinhos como num livro.",

	["Dictionary Explorer: open at a word"] = "Dictionary Explorer: abrir em uma palavra",
	["Open dictionary at a word…"] = "Abrir dicionário em uma palavra…",
	["Asks for a word and opens the dictionary at it, without looking it up in a book first. The same action can be assigned to a gesture or added to Quick Dock: look for “Dictionary Explorer: open at a word” in the list of actions."] = "Pede uma palavra e abre o dicionário nela, sem precisar pesquisá-la antes em um livro. A mesma ação pode ser atribuída a um gesto ou adicionada ao Quick Dock: procure “Dictionary Explorer: abrir em uma palavra” na lista de ações.",
	["Starting dictionary"] = "Dicionário inicial",
	["Which dictionary “Open dictionary at a word” opens."] = "Qual dicionário “Abrir dicionário em uma palavra” abre.",
	["Automatic (first in KOReader's dictionary order)"] = "Automático (o primeiro na ordem de dicionários do KOReader)",
	["Open dictionary at a word"] = "Abrir dicionário em uma palavra",
	["Word to start from"] = "Palavra de partida",
	["No dictionary that can be opened was found."] = "Nenhum dicionário que possa ser aberto foi encontrado.",

	["Show dock shadow"] = "Mostrar sombra do dock",
	["Show a small dithered shadow along the right and bottom edges of the dock that appears next to selected text in the dictionary viewer."] = "Mostra uma pequena sombra pontilhada nas bordas direita e inferior do dock que aparece perto do texto selecionado no visualizador do dicionário.",

	["Go to dictionary"] = "Ir para o dicionário",
	["Go to word"] = "Ir para a palavra",
	["Go"] = "Ir",
	["Add to vocabulary builder"] = "Adicionar ao construtor de vocabulário",
	["Added to vocabulary builder."] = "Adicionada ao construtor de vocabulário.",
	["Remove from vocabulary builder"] = "Remover do construtor de vocabulário",
	["Removed from vocabulary builder."] = "Removida do construtor de vocabulário.",
	["Remove word \"%1\" from vocabulary builder?"] = "Remover a palavra \"%1\" do construtor de vocabulário?",
	["Entry %1 of %2"] = "Verbete %1 de %2",
	["Entries %1–%2 of %3"] = "Verbetes %1–%2 de %3",

	["Preparing the dictionary index…\nThis is only needed once."] = "Preparando o índice do dicionário…\nIsso só é necessário na primeira vez.",
	["This dictionary can't be opened as a book."] = "Este dicionário não pode ser aberto como livro.",
	["Could not open the dictionary."] = "Não foi possível abrir o dicionário.",
	["Could not read this entry."] = "Não foi possível ler este verbete.",
	["No entry for “%1”. Showing the closest one."] = "Não há verbete para “%1”. Mostrando o mais próximo.",
}

return setmetatable({
	ngettext = gettext.ngettext,
	pgettext = gettext.pgettext,
}, {
	__call = function(_, msgid)
		return pt[msgid] or gettext(msgid)
	end,
})
