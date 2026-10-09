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

	-- Masculine forms (agreeing with "tamanho"): kept separate from Quick
	-- Dock's own "Small"/"Large" entries, which are feminine there
	-- (agreeing with "escala da dock") -- same English source string, but
	-- these two plugins need it to agree with a different Portuguese noun.
	["Small"] = "Pequeno",
	["Medium"] = "Médio",
	["Large"] = "Grande",

	["Middle"] = "Meio",

	["Re-reading tolerance"] = "Tolerância de releitura",
	["1 page turn"] = "1 virada de página",
	["2 page turns"] = "2 viradas de página",
	["3 page turns"] = "3 viradas de página",
	["5 page turns"] = "5 viradas de página",

	["Destination page"] = "Página de destino",
	["Distance in pages"] = "Distância em páginas",

	["Page number of the book"] = "Número da página do livro",
	["Page number in this chapter"] = "Número da página deste capítulo",
	["Percentage of the book"] = "Porcentagem do livro",
	["Percentage in this chapter"] = "Porcentagem deste capítulo",
	["Text only (chapter title)"] = "Somente texto (título do capítulo)",

	["15 seconds"] = "15 segundos",
	["30 seconds"] = "30 segundos",
	["1 minute"] = "1 minuto",
	["2 minutes"] = "2 minutos",
	["5 minutes"] = "5 minutos",

	["Never (until dismissed)"] = "Nunca (até dispensar)",
	["15 minutes"] = "15 minutos",
	["30 minutes"] = "30 minutos",
	["1 hour"] = "1 hora",

	["1 page"] = "1 página",
	["2 pages"] = "2 páginas",
	["3 pages"] = "3 páginas",
	["5 pages"] = "5 páginas",

	["Show floating buttons"] = "Mostrar botões flutuantes",

	["Discard anchor and return point"] = "Descartar âncora e retorno",
	["Discard anchor and return point?"] = "Descartar a âncora e o ponto de retorno?",

	["Anchor kept · tap to show the buttons"] = "Âncora mantida · toque para mostrar os botões",

	-- Gesture actions (Dispatcher) and their confirmations.
	["Page Anchor: show/hide buttons"] = "Page Anchor: mostrar/ocultar botões",
	["Page Anchor: go to anchor / return point"] = "Page Anchor: ir para a âncora / ponto de retorno",
	["Page Anchor: discard anchor"] = "Page Anchor: descartar âncora",
	["No anchor to show"] = "Nenhuma âncora para mostrar",
	["Anchor discarded"] = "Âncora descartada",

	["Page Anchor: show trail"] = "Page Anchor: mostrar trilha",
	["Places visited on this trip"] = "Lugares visitados nesta ida",
	["No other places visited yet"] = "Nenhum outro lugar visitado ainda",
	["Page Anchor: pin anchor here"] = "Page Anchor: fixar âncora aqui",
	["Page Anchor: restore discarded anchor"] = "Page Anchor: restaurar âncora descartada",
	["Anchor pinned here"] = "Âncora fixada aqui",
	["Nothing to restore"] = "Nada para restaurar",
	["Anchor set here"] = "Âncora definida aqui",
	["Buttons dismissed"] = "Botões dispensados",

	["Pin anchor here"] = "Fixar âncora aqui",
	["Restore discarded anchor"] = "Restaurar âncora descartada",
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

	-- Menu (see modules/menu.lua).
	["Current anchor"] = "Âncora atual",
	["None"] = "Nenhuma",
	["Hidden"] = "Oculta",
	["Pinned"] = "Fixada",
	["Active"] = "Ativa",
	["Pin an anchor before exploring, bring back hidden buttons, or discard the anchor (and undo that)."] = "Fixe uma âncora antes de explorar, traga de volta os botões ocultos ou descarte a âncora (e desfaça isso).",
	["Marks this page as the anchor before you go exploring. A pinned anchor stays through any number of trips away and back, until you discard it."] = "Marca esta página como âncora antes de você sair explorando. Uma âncora fixada permanece por quantas idas e voltas forem, até você descartá-la.",
	["Brings back the buttons after auto-hide put them away. The anchor and the way back are still there."] = "Traz de volta os botões que a ocultação automática guardou. A âncora e o caminho de volta continuam lá.",
	["Forgets the anchor and the return point and keeps reading from this page. KOReader's own location history is not affected."] = "Esquece a âncora e o ponto de retorno e continua a leitura a partir desta página. O histórico de posições do próprio KOReader não é afetado.",
	["Brings back the anchor and return point you discarded last, as long as no new anchor has been set since."] = "Traz de volta a última âncora e ponto de retorno descartados, desde que nenhuma âncora nova tenha sido criada depois.",
	["Buttons"] = "Botões",
	["Choose the size and position of the floating buttons and what they show."] = "Escolha o tamanho e a posição dos botões flutuantes e o que eles mostram.",
	["Size"] = "Tamanho",
	["Choose how big the floating buttons are. Bigger buttons are easier to tap."] = "Escolha o tamanho dos botões flutuantes. Botões maiores são mais fáceis de tocar.",
	["Position"] = "Posição",
	["Choose where on the screen the buttons sit. They always stay on the side the arrow leads to."] = "Escolha onde os botões ficam na tela. Eles sempre ficam do lado para onde a seta leva.",
	["Destination on button"] = "Destino no botão",
	["Choose what is written next to the arrow: the page it leads to, how many pages away that is, or nothing."] = "Escolha o que aparece escrito ao lado da seta: a página para onde ela leva, a quantas páginas de distância ela está, ou nada.",
	["Hold hint"] = "Dica ao segurar",
	["Choose what the hint says when you hold the arrow: the chapter title with a page number or percentage, in the book or in the chapter."] = "Escolha o que a dica diz quando você segura a seta: o título do capítulo com um número de página ou uma porcentagem, no livro ou no capítulo.",
	["Auto-hide"] = "Ocultar automaticamente",
	["Choose when the buttons hide on their own, what stays on screen, and how long a hidden anchor is kept."] = "Escolha quando os botões se ocultam sozinhos, o que fica na tela e por quanto tempo uma âncora oculta é mantida.",
	["Hide after"] = "Ocultar após",
	["Choose how long the buttons stay up without navigating before they hide. Hiding never loses the anchor."] = "Escolha quanto tempo os botões ficam na tela sem navegação antes de se ocultarem. Ocultar nunca perde a âncora.",
	["When hidden"] = "Ao ocultar",
	["Choose what stays on screen while the buttons are hidden: a small anchor tab that brings them back with a tap, or nothing (bring them back from the menu or a gesture)."] = "Escolha o que fica na tela enquanto os botões estão ocultos: uma pequena aba de âncora que os traz de volta com um toque, ou nada (traga-os de volta pelo menu ou por um gesto).",
	["Leave an anchor tab"] = "Deixar uma aba de âncora",
	["Leave nothing"] = "Não deixar nada",
	["Discard after hidden for"] = "Descartar após oculto por",
	["Choose how long hidden buttons wait. After that the anchor is discarded and this page becomes your reading position. A pinned anchor never expires."] = "Escolha quanto tempo os botões ocultos esperam. Depois disso a âncora é descartada e esta página passa a ser sua posição de leitura. Uma âncora fixada nunca expira.",
	["Choose how long the way back out is kept after returning to the anchor, and what counts as a jump."] = "Escolha por quanto tempo o caminho de volta ao ponto de revisão é mantido depois de voltar à âncora, e o que conta como salto.",
	["Forget return point after"] = "Esquecer retorno após",
	["After going back to the anchor, the button can take you back out to where you were. Choose after how many pages of reading on that return point is forgotten."] = "Depois de voltar à âncora, o botão pode levar você de volta até onde estava. Escolha depois de quantas páginas lidas adiante esse ponto de retorno é esquecido.",
	["Choose how many page turns back still count as re-reading rather than a jump. Only matters for tools that move without telling KOReader: the table of contents, Go to page, links and other standard navigation always offer the way back."] = "Escolha quantas viradas de página para trás ainda contam como releitura e não como salto. Só importa para ferramentas que navegam sem avisar o KOReader: índice, ir para página, links e a navegação padrão sempre oferecem o caminho de volta.",
	["Shows floating buttons after a jump so you can go back to where you were reading. Turning it off keeps the anchor; the buttons come back when you turn it on again."] = "Mostra botões flutuantes depois de um salto para você voltar até onde estava lendo. Desativar mantém a âncora; os botões voltam quando você ativar de novo.",
	["Restore all defaults"] = "Restaurar todos os padrões",
	["Restores every Page Anchor setting. Page Anchor stays turned on or off as it is, and the current anchor is kept."] = "Restaura todas as configurações do Page Anchor. O Page Anchor continua ativado ou desativado como está, e a âncora atual é mantida.",
	["Restore all Page Anchor settings to their defaults?"] = "Restaurar todas as configurações do Page Anchor para os padrões?",
}

return setmetatable({
	ngettext = gettext.ngettext,
	pgettext = gettext.pgettext,
}, {
	__call = function(_, msgid)
		return pt[msgid] or gettext(msgid)
	end,
})
