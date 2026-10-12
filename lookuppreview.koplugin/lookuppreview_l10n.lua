-- KOReader's gettext catalog does not contain strings from external plugins.
-- Keep plugin-specific translations here and fall back to KOReader's catalog
-- for languages without a Lookup Preview translation (and for native UI terms
-- such as "Cancel" or "Dictionary"). Mirrors
-- dictionaryexplorer.koplugin/dictionaryexplorer_l10n.lua.
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
	["Lookup Preview"] = "Lookup Preview",
	["Shows a floating carousel for selected text with dictionary, translation, and Wikipedia previews."] = "Mostra um carrossel flutuante para o texto selecionado, com prévias do dicionário, da tradução e da Wikipédia.",

	-- Settings menu
	["Lookup preview"] = "Lookup Preview",
	["Enable lookup preview"] = "Ativar o Lookup Preview",
	["Turns the floating lookup preview on or off without removing the plugin."] = "Liga ou desliga o carrossel flutuante de consulta sem remover o plugin.",
	["Appearance"] = "Aparência",
	["Choose the card corner style, side card previews, shadows, and custom icon filenames."] = "Escolha o estilo dos cantos dos cartões, as prévias dos cartões laterais, as sombras e os nomes dos ícones personalizados.",
	["Card corners"] = "Cantos dos cartões",
	["Choose square or rounded corners for the preview cards."] = "Escolha cantos retos ou arredondados para os cartões.",
	["Square"] = "Retos",
	["Rounded"] = "Arredondados",
	["Side card previews"] = "Prévias dos cartões laterais",
	["Choose how the other available cards (dictionary, translation, Wikipedia) are shown beside the active one."] = "Escolha como os outros cartões disponíveis (dicionário, tradução, Wikipédia) aparecem ao lado do ativo.",
	["Full cards"] = "Cartões inteiros",
	["Tabs"] = "Abas",
	["Card height"] = "Altura dos cartões",
	["Choose how tall the cards open. Spreading two fingers on a card expands it and pinching makes it compact again, for that lookup."] = "Escolha a altura com que os cartões abrem. Afastar dois dedos sobre um cartão o expande, e juntá-los o deixa compacto de novo, para aquela consulta.",
	["Compact"] = "Compacta",
	["Expanded"] = "Expandida",
	["Text size"] = "Tamanho do texto",
	["Choose the size of the text of the cards' content."] = "Escolha o tamanho do texto do conteúdo dos cartões.",
	["default"] = "padrão",
	["Show card shadows"] = "Mostrar sombras dos cartões",
	["Show matching dithered shadows along the right and bottom edges of preview cards."] = "Mostra sombras pontilhadas nas bordas direita e inferior dos cartões.",
	["Custom icon filenames"] = "Nomes dos ícones personalizados",
	["Lists the SVG and PNG filenames accepted from the plugin's icons folder."] = "Lista os nomes de arquivos SVG e PNG aceitos na pasta de ícones do plugin.",
	["Accepted filenames"] = "Nomes aceitos",
	["Content"] = "Conteúdo",
	["Choose how online cards load, dictionary HTML rendering, and Wikipedia/translation language and buttons."] = "Escolha como os cartões online carregam, como o HTML do dicionário é exibido, e os idiomas e botões da Wikipédia e da tradução.",
	["Cards"] = "Cartões",
	["Choose which cards the carousel shows and in which order, and which card a lookup from the book opens on. A hidden card's action (Dictionary, Translate or Wikipedia) opens KOReader's own window instead."] = "Escolha quais cartões o carrossel mostra e em que ordem, e em qual cartão abre uma consulta feita no livro. A ação de um cartão oculto (Dicionário, Traduzir ou Wikipédia) abre a janela do próprio KOReader.",
	["Show and order cards"] = "Mostrar e ordenar cartões",
	["At least one card must be shown."] = "Pelo menos um cartão precisa ser mostrado.",
	["Open on the dictionary card"] = "Abrir no cartão do dicionário",
	["A long press on a word opens the carousel on the Dictionary card."] = "Um toque longo numa palavra abre o carrossel no cartão Dicionário.",
	["Open on the last card used"] = "Abrir no último cartão usado",
	["A long press on a word opens the carousel on the card that was shown when it was last closed. Translate and Wikipedia from the selection menu still open on their own card."] = "Um toque longo numa palavra abre o carrossel no cartão que estava à vista quando ele foi fechado pela última vez. Traduzir e Wikipédia, escolhidos no menu da seleção, continuam abrindo no próprio cartão.",
	["Online card loading"] = "Carregamento dos cartões online",
	["Choose whether translation and Wikipedia cards load automatically or only when you open them."] = "Escolha se os cartões de tradução e da Wikipédia carregam sozinhos ou só quando você pedir.",
	["Automatic"] = "Automático",
	["Manual only"] = "Só manual",
	["Dictionary HTML"] = "HTML do dicionário",
	["Choose between fully formatted dictionary entries or a faster, minimally styled rendering."] = "Escolha entre verbetes totalmente formatados ou uma exibição mais rápida, com formatação mínima.",
	["Formatted"] = "Formatado",
	["Fast / Raw"] = "Rápido / Bruto",
	["Dictionary buttons"] = "Botões do dicionário",
	["Choose which buttons open the full dictionary from the dictionary card: KOReader's original popup, the Dictionary Explorer at the word, or both. Dictionary Explorer must be installed; without it, or for a dictionary it can't open, the KOReader popup button is shown."] = "Escolha quais botões abrem o dicionário completo a partir do cartão do dicionário: o popup original do KOReader, o Dictionary Explorer na palavra, ou os dois. O Dictionary Explorer precisa estar instalado; sem ele, ou num dicionário que ele não abre, aparece o botão do popup do KOReader.",
	["KOReader popup only"] = "Só o popup do KOReader",
	["Dictionary Explorer only"] = "Só o Dictionary Explorer",
	["Both"] = "Os dois",
	["KOReader popup"] = "Popup do KOReader",
	["Dictionary Explorer"] = "Dictionary Explorer",
	["Dictionary Explorer is not installed or is too old."] = "O Dictionary Explorer não está instalado ou é antigo demais.",
	["Show vocabulary builder button"] = "Mostrar botão do construtor de vocabulário",
	["Shows a button on the dictionary card that adds the word to KOReader's vocabulary builder, like the one in KOReader's dictionary popup. It is not shown when the vocabulary builder adds every looked up word by itself."] = "Mostra no cartão do dicionário um botão que adiciona a palavra ao construtor de vocabulário do KOReader, como o do popup do dicionário do KOReader. Ele não aparece quando o construtor de vocabulário já adiciona sozinho toda palavra consultada.",
	["Wikipedia language"] = "Idioma da Wikipédia",
	["Choose the language Wikipedia articles are shown in."] = "Escolha o idioma dos artigos da Wikipédia.",
	["Translation"] = "Tradução",
	["Choose the target language, whether the original text is shown, and which card buttons appear."] = "Escolha o idioma de destino, se o texto original aparece, e quais botões o cartão mostra.",
	["Target language"] = "Idioma de destino",
	["Choose the language translations are shown in."] = "Escolha o idioma em que as traduções aparecem.",
	["Show source text"] = "Mostrar texto de origem",
	["Shows the original selected text below its translation."] = "Mostra o texto selecionado original abaixo da tradução.",
	["Buttons"] = "Botões",
	["Choose which action buttons appear on the translation card."] = "Escolha quais botões aparecem no cartão de tradução.",
	["Show copy button"] = "Mostrar botão de copiar",
	["Show note button"] = "Mostrar botão de nota",
	["Version"] = "Versão",

	-- Custom icon filenames
	["Full-text search"] = "Busca no texto completo",
	["Open native details"] = "Abrir os detalhes nativos",
	["Go to word in Dictionary Explorer"] = "Ir para a palavra no Dictionary Explorer",
	["Copy translation"] = "Copiar tradução",
	["Add translation note"] = "Adicionar a tradução como nota",
	["Full article"] = "Artigo completo",
	["Loading"] = "Carregando",
	["Translate the whole sentence"] = "Traduzir a frase inteira",
	["Translate only the selected text"] = "Traduzir só o texto selecionado",
	["Load an online card"] = "Carregar um cartão online",
	["Edit the looked up text"] = "Editar o texto consultado",

	-- Cards
	["Lookup"] = "Consulta",
	["No content."] = "Sem conteúdo.",
	["Loading…"] = "Carregando…",
	["Load"] = "Carregar",
	["Choose which card to show"] = "Escolher qual cartão mostrar",
	["Show the %s card"] = "Mostrar o cartão %s",
	["Back to %s"] = "Voltar para %s",
	["Look up"] = "Consultar",

	-- Dictionary card
	["Looking up the dictionary…"] = "Consultando o dicionário…",
	["Swipe to open the dictionary."] = "Deslize para abrir o dicionário.",
	["No definition."] = "Sem definição.",
	["No definition found."] = "Nenhuma definição encontrada.",
	["Choose which dictionary result to show"] = "Escolher qual resultado do dicionário mostrar",
	["Highlight the selected text"] = "Destacar o texto selecionado",
	["Previous dictionary result"] = "Resultado anterior do dicionário",
	["Dictionary result %d of %d"] = "Resultado %d de %d do dicionário",
	["Next dictionary result"] = "Próximo resultado do dicionário",
	["Search the selected text in the book"] = "Buscar o texto selecionado no livro",
	["Look the text up in the dictionary again"] = "Consultar o texto no dicionário de novo",
	["Add the word to the vocabulary builder"] = "Adicionar a palavra ao construtor de vocabulário",
	["Added to the vocabulary builder"] = "Adicionada ao construtor de vocabulário",
	["Added to vocabulary builder."] = "Adicionada ao construtor de vocabulário.",
	["Go to word"] = "Ir para a palavra",
	["Go to this word in the dictionary (Dictionary Explorer)"] = "Ir para esta palavra no dicionário (Dictionary Explorer)",
	["Open KOReader's original dictionary popup"] = "Abrir o popup original do dicionário do KOReader",
	["No selection to highlight."] = "Não há seleção para destacar.",
	["The dictionary is not available."] = "O dicionário não está disponível.",
	["Dictionary lookups open in an external app."] = "As consultas ao dicionário abrem em um app externo.",
	["Dictionary lookup failed."] = "A consulta ao dicionário falhou.",

	-- Translate card
	["Querying translation service…"] = "Consultando o serviço de tradução…",
	["Tap Load to query the translation service."] = "Toque em Carregar para consultar o serviço de tradução.",
	["Swipe to open translation."] = "Deslize para abrir a tradução.",
	["Choose the languages to translate from and into"] = "Escolher os idiomas de origem e de destino",
	["Choose the language to translate into"] = "Escolher o idioma de destino",
	["Source"] = "Origem",
	["No translation found."] = "Nenhuma tradução encontrada.",
	["No text to translate."] = "Não há texto para traduzir.",
	["Copy the translation to the clipboard"] = "Copiar a tradução para a área de transferência",
	["Save the translation as a note on the highlight"] = "Salvar a tradução como nota do destaque",
	["Sentence"] = "Frase",
	["Open KOReader's original translator view"] = "Abrir o tradutor original do KOReader",
	["Query the translation service"] = "Consultar o serviço de tradução",
	["Clipboard is not available."] = "A área de transferência não está disponível.",
	["Translation copied to clipboard."] = "Tradução copiada para a área de transferência.",
	["No highlight available."] = "Nenhum destaque disponível.",
	["Could not create note."] = "Não foi possível criar a nota.",
	["Could not open the original translator."] = "Não foi possível abrir o tradutor original.",
	["Translate from"] = "Traduzir de",
	["Translate to"] = "Traduzir para",
	["Detect automatically"] = "Detectar automaticamente",
	["As in KOReader's settings (%s)"] = "Como nas configurações do KOReader (%s)",
	["Network unavailable."] = "Rede indisponível.",

	-- Wikipedia card
	["Querying Wikipedia…"] = "Consultando a Wikipédia…",
	["Tap Load to query Wikipedia."] = "Toque em Carregar para consultar a Wikipédia.",
	["Swipe to open Wikipedia."] = "Deslize para abrir a Wikipédia.",
	["Choose the Wikipedia language"] = "Escolher o idioma da Wikipédia",
	["Choose which article to show"] = "Escolher qual artigo mostrar",
	["Query Wikipedia"] = "Consultar a Wikipédia",
	["Article"] = "Artigo",
	["Previous article"] = "Artigo anterior",
	["Article %d of %d"] = "Artigo %d de %d",
	["Next article"] = "Próximo artigo",
	["Open the full Wikipedia article"] = "Abrir o artigo completo da Wikipédia",
	["Open KOReader's original Wikipedia widget"] = "Abrir a Wikipédia original do KOReader",
	["No Wikipedia article found."] = "Nenhum artigo da Wikipédia encontrado.",
	["No introduction found."] = "Nenhuma introdução encontrada.",
	["No text to search on Wikipedia."] = "Não há texto para buscar na Wikipédia.",
	["Could not open Wikipedia."] = "Não foi possível abrir a Wikipédia.",
	["Could not open Wikipedia article."] = "Não foi possível abrir o artigo da Wikipédia.",
	["Wikipedia lookup interrupted."] = "Consulta à Wikipédia interrompida.",
	["Wikipedia lookup failed."] = "A consulta à Wikipédia falhou.",
}

return setmetatable({
	ngettext = gettext.ngettext,
	-- The plugin's strings with a context (pgettext) are translated here too.
	pgettext = function(context, msgid)
		return pt[msgid] or gettext.pgettext(context, msgid)
	end,
}, {
	__call = function(_, msgid)
		return pt[msgid] or gettext(msgid)
	end,
})
