-- KOReader's gettext catalog does not contain strings from external plugins.
-- Keep plugin-specific translations here and fall back to KOReader's catalog
-- for languages without a Page Anchor translation (and for native UI terms).
-- Mirrors quickdock.koplugin/quickdock_l10n.lua.
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

-- This plugin's vocabulary (page, percentage, anchor, back/forward, timers)
-- has no wording differences between Brazilian and European Portuguese,
-- unlike quickdock's file-browser terms, so a single table serves both
-- locales.
--
-- Only strings with no exact match in KOReader's own "koreader" textdomain
-- belong here -- anything already translated by KOReader itself (checked
-- against apps/.../*.lua and ui/elements/common_info_menu_table.lua in
-- KOReader's own source, since this repo has no local koreader.pot/.mo to
-- check translated output against) is deliberately left out and falls
-- through to gettext(msgid) below. That way it picks up KOReader's own
-- translation, in every language KOReader supports -- not just the two
-- covered here -- instead of a second, possibly drifting copy kept here.
-- Left out for that reason: "Page Anchor" (a proper noun, untranslated
-- either way), "Enable"/"Disable" (readerdictionary.lua, readerrolling.lua,
-- etc.), "Off" (readerhighlight.lua), "Discard" (readerui.lua, inputdialog.lua),
-- and "Version: %1" (common_info_menu_table.lua).
local pt = {
	["Shows floating back and forward buttons so you can review another part of a book without losing either reading position."] = "Mostra botões flutuantes de voltar e avançar para você revisar outra parte do livro sem perder nenhuma das duas posições de leitura.",

	["Turns Page Anchor off entirely, without losing the navigation history it uses."] = "Desativa o Page Anchor por completo, sem perder o histórico de navegação que ele usa.",

	["Button size"] = "Tamanho dos botões",
	["Scales the floating buttons up for an easier target, without changing their shape."] = "Aumenta os botões flutuantes para facilitar o toque, sem mudar o formato deles.",
	-- Masculine forms (agreeing with "tamanho"): kept separate from Quick
	-- Dock's own "Small"/"Large" entries, which are feminine there
	-- (agreeing with "escala da dock") -- same English source string, but
	-- these two plugins need it to agree with a different Portuguese noun.
	["Small"] = "Pequeno",
	["Medium"] = "Médio",
	["Large"] = "Grande",

	["Show destination on button"] = "Mostrar destino no botão",
	["Writes where the arrow leads next to it, so you don't have to hold the button to find out: the destination page, or how many pages away it is."] = "Escreve ao lado da seta para onde ela leva, para você não precisar segurar o botão: a página de destino, ou a quantas páginas de distância ela está.",
	["Destination page"] = "Página de destino",
	["Distance in pages"] = "Distância em páginas",

	["Position hint"] = "Dica de posição",
	["Chooses what the text shown when you hold down a navigation button says."] = "Escolhe o que o texto exibido ao segurar um botão de navegação diz.",
	["Page number of the book"] = "Número da página do livro",
	["Page number in this chapter"] = "Número da página deste capítulo",
	["Percentage of the book"] = "Porcentagem do livro",
	["Percentage in this chapter"] = "Porcentagem deste capítulo",
	["Text only (chapter title)"] = "Somente texto (título do capítulo)",

	["Auto-dismiss"] = "Ocultar automaticamente",
	["Controls when the floating buttons disappear on their own, both from inactivity and after you've returned to the anchor."] = "Controla quando os botões flutuantes desaparecem sozinhos, tanto por inatividade quanto depois de você voltar à âncora.",
	["Timeout"] = "Tempo limite",
	["Hides the floating buttons after this much time without navigation activity. The anchor is kept: tap the anchor tab (or use the show/hide gesture action) to bring them back."] = "Oculta os botões flutuantes após esse tempo sem atividade de navegação. A âncora é mantida: toque na aba da âncora (ou use a ação de gesto mostrar/ocultar) para trazê-los de volta.",
	["15 seconds"] = "15 segundos",
	["30 seconds"] = "30 segundos",
	["1 minute"] = "1 minuto",
	["2 minutes"] = "2 minutos",
	["5 minutes"] = "5 minutos",

	["When hiding"] = "Ao ocultar",
	["What the timeout (or the show/hide gesture action) leaves on screen: a small anchor tab that brings the buttons back with one tap, or nothing."] = "O que o tempo limite (ou a ação de gesto mostrar/ocultar) deixa na tela: uma pequena aba de âncora que traz os botões de volta com um toque, ou nada.",
	["Minimize to an anchor tab"] = "Minimizar em uma aba de âncora",
	["Hide completely"] = "Ocultar totalmente",

	["Discard when hidden for"] = "Descartar após oculto por",
	["If the buttons stay hidden (or parked as a tab) this long, the anchor is discarded and the current page becomes your reading position, as if you had tapped the anchor button. Never keeps them waiting until you dismiss them yourself."] = "Se os botões ficarem ocultos (ou na aba) por esse tempo, a âncora é descartada e a página atual passa a ser sua posição de leitura, como se você tivesse tocado no botão da âncora. Nunca os mantém à espera até você mesmo dispensá-los.",
	["Never (until dismissed)"] = "Nunca (até dispensar)",
	["15 minutes"] = "15 minutos",
	["30 minutes"] = "30 minutos",
	["1 hour"] = "1 hora",

	["After returning to anchor"] = "Depois de voltar à âncora",
	["Auto-dismisses the floating button once you've read this many pages past the anchor. Off keeps it until you dismiss it yourself."] = "Oculta o botão flutuante automaticamente depois que você ler essa quantidade de páginas além da âncora. Desativado mantém até você mesmo dispensá-lo.",
	["Auto-dismiss after:"] = "Ocultar automaticamente após:",
	["1 page"] = "1 página",
	["2 pages"] = "2 páginas",
	["3 pages"] = "3 páginas",
	["5 pages"] = "5 páginas",

	["Show floating buttons"] = "Mostrar botões flutuantes",
	["Brings back floating buttons hidden by the inactivity timeout, with the anchor and the way back still in place."] = "Traz de volta os botões flutuantes ocultados pelo tempo limite, com a âncora e o caminho de volta preservados.",

	["Discard anchor and return point"] = "Descartar âncora e retorno",
	["Forgets the anchor and the return point and keeps reading from the current position. KOReader's own location history is not affected."] = "Esquece a âncora e o ponto de retorno e continua a leitura a partir da posição atual. O histórico de posições do próprio KOReader não é afetado.",
	["Discard anchor and return point?"] = "Descartar a âncora e o ponto de retorno?",

	["Anchor kept · tap to show the buttons"] = "Âncora mantida · toque para mostrar os botões",

	-- Gesture actions (Dispatcher) and their confirmations.
	["Page Anchor: show/hide buttons"] = "Page Anchor: mostrar/ocultar botões",
	["Page Anchor: go to anchor / return point"] = "Page Anchor: ir para a âncora / ponto de retorno",
	["Page Anchor: discard anchor"] = "Page Anchor: descartar âncora",
	["No anchor to show"] = "Nenhuma âncora para mostrar",
	["Anchor discarded"] = "Âncora descartada",

	["Page Anchor: pin anchor here"] = "Page Anchor: fixar âncora aqui",
	["Page Anchor: restore discarded anchor"] = "Page Anchor: restaurar âncora descartada",
	["Anchor pinned here"] = "Âncora fixada aqui",
	["Nothing to restore"] = "Nada para restaurar",
	["Anchor set here"] = "Âncora definida aqui",
	["Buttons dismissed"] = "Botões dispensados",

	["Pin anchor here"] = "Fixar âncora aqui",
	["Marks the current position as the anchor before you go exploring. A pinned anchor stays, through any number of trips away and back, until you discard it."] = "Marca a posição atual como âncora antes de você sair explorando. Uma âncora fixada permanece, por quantas idas e voltas forem, até você descartá-la.",
	["Restore discarded anchor"] = "Restaurar âncora descartada",
	["Brings back the anchor and return point you last discarded, as long as no new anchor has been set since."] = "Traz de volta a última âncora e ponto de retorno descartados, desde que nenhuma âncora nova tenha sido criada depois.",
	["This is the pinned anchor"] = "Esta é a âncora fixada",
	["Discard the pinned anchor and continue here"] = "Descartar a âncora fixada e continuar aqui",

	["This is the starting position"] = "Esta é a posição inicial",
	["Continue here"] = "Continuar aqui",
	["Go to %1"] = "Ir para %1",
	["Back to %1"] = "Voltar para %1",

	-- Built by PageAnchor:getDestinationLabel and fed into "Go to %1"/"Back to %1" above.
	["page %1"] = "página %1",
	["%1 (page %2 of %3)"] = "%1 (página %2 de %3)",
	["%1 (page %2)"] = "%1 (página %2)",
	["%1 (page %2 of this chapter)"] = "%1 (página %2 deste capítulo)",
	["%1 (%2 of the book)"] = "%1 (%2 do livro)",
	["%1 (%2 into this chapter)"] = "%1 (%2 dentro deste capítulo)",
}

return setmetatable({
	ngettext = gettext.ngettext,
	pgettext = gettext.pgettext,
}, {
	__call = function(_, msgid)
		return pt[msgid] or gettext(msgid)
	end,
})
