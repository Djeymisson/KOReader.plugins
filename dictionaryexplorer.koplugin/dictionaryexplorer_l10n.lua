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
	["Dictionary Explorer: continue exploring"] = "Dictionary Explorer: continuar a exploração",
	["Continue exploring"] = "Continuar a exploração",
	["Reopens the dictionary you explored last on the page you left it, with the words you walked through. The same action can be assigned to a gesture or added to Quick Dock: look for “Dictionary Explorer: continue exploring” in the list of actions."] = "Reabre o último dicionário explorado na página em que você parou, com as palavras pelas quais passou. A mesma ação pode ser atribuída a um gesto ou adicionada ao Quick Dock: procure “Dictionary Explorer: continuar a exploração” na lista de ações.",
	["Continue"] = "Continuar",
	["There is no exploration to continue yet."] = "Ainda não há exploração para continuar.",
	["Which dictionary “Open dictionary at a word” opens."] = "Qual dicionário “Abrir dicionário em uma palavra” abre.",
	["Automatic (first in KOReader's dictionary order)"] = "Automático (o primeiro na ordem de dicionários do KOReader)",
	["Open dictionary at a word"] = "Abrir dicionário em uma palavra",
	["Word to start from"] = "Palavra de partida",
	["No dictionary that can be opened was found."] = "Nenhum dicionário que possa ser aberto foi encontrado.",

	["Show dock shadow"] = "Mostrar sombra do dock",
	["Show a small dithered shadow along the right and bottom edges of the dock that appears next to selected text in the dictionary viewer."] = "Mostra uma pequena sombra pontilhada nas bordas direita e inferior do dock que aparece perto do texto selecionado no visualizador do dicionário.",

	["Go to dictionary"] = "Ir para o dicionário",
	["Go to word"] = "Ir para a palavra",
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
	["Could not open the dictionary: its files look incomplete. Copying it again may help."] = "Não foi possível abrir o dicionário: os arquivos parecem incompletos. Copiá-lo de novo pode resolver.",
	["Could not read this entry."] = "Não foi possível ler este verbete.",
	["No entry for “%1”. Showing the closest one."] = "Não há verbete para “%1”. Mostrando o mais próximo.",
	["No entry for “%1”. Showing “%2”."] = "Não há verbete para “%1”. Mostrando “%2”.",
	["Tap here for suggestions."] = "Toque aqui para ver sugestões.",
	["Suggestions for “%1”"] = "Sugestões para “%1”",
	["“%1” in other dictionaries"] = "“%1” em outros dicionários",
	["No other dictionary has “%1”."] = "Nenhum outro dicionário tem “%1”.",
	["%1 (index not prepared yet)"] = "%1 (índice ainda não preparado)",
	["No entry for “%1” in %2. Found in %3."] = "Não há verbete para “%1” em %2. Encontrado em %3.",
	["No entry for “%1” in %2. Showing “%3” from %4."] = "Não há verbete para “%1” em %2. Mostrando “%3” de %4.",
	["Search"] = "Buscar",
	["Prepare all dictionaries"] = "Preparar todos os dicionários",
	["Words are looked for in all the dictionaries, as if they were one; a dictionary whose index was never prepared (one never opened here) is left out until it is. This prepares them all now, one after the other. It is only needed once for each."] = "As palavras são procuradas em todos os dicionários, como se fossem um só; um dicionário cujo índice nunca foi preparado (nunca aberto aqui) fica de fora até que seja. Isto prepara todos agora, um depois do outro. Só é preciso uma vez para cada um.",
	["All the dictionaries are ready."] = "Todos os dicionários estão prontos.",
	["Indexes of %1 dictionaries no longer installed removed."] = "Índices de %1 dicionários que não estão mais instalados foram removidos.",
	["%1 dictionaries prepared."] = "%1 dicionários preparados.",
	["%1 of %2 dictionaries prepared; the others' files look incomplete."] = "%1 de %2 dicionários preparados; os arquivos dos outros parecem incompletos.",
	["Preparing dictionary %1 of %2…\n%3"] = "Preparando o dicionário %1 de %2…\n%3",
	["Short names of the dictionaries"] = "Nomes curtos dos dicionários",
	["The names the breadcrumb and the lists give the dictionaries, made from their names (the languages they mention: “EN-PT”). Tap one to change it; leave it empty for the one made from its name."] = "Os nomes que o breadcrumb e as listas dão aos dicionários, feitos a partir dos nomes deles (as línguas que mencionam: “EN-PT”). Toque em um para mudá-lo; deixe vazio para o feito a partir do nome.",
	["Short name"] = "Nome curto",
	["Empty: made from its name"] = "Vazio: feito a partir do nome",
	["Save"] = "Salvar",
	["Searches every dictionary for a word, and lists what each one has."] = "Busca uma palavra em todos os dicionários e lista o que cada um tem.",
	["Search all dictionaries"] = "Buscar em todos os dicionários",
	["Looks for the word in every dictionary (%1), this one first, and lists what each one has."] = "Procura a palavra em todos os dicionários (%1), começando por este, e lista o que cada um tem.",
	["Word"] = "Palavra",
	["Results for “%1”"] = "Resultados para “%1”",
	["No entry for “%1”: the closest ones"] = "Nenhum verbete para “%1”: os mais próximos",
	["Nothing found for “%1”."] = "Nada encontrado para “%1”.",
}

return setmetatable({
	ngettext = gettext.ngettext,
	pgettext = gettext.pgettext,
}, {
	__call = function(_, msgid)
		return pt[msgid] or gettext(msgid)
	end,
})
