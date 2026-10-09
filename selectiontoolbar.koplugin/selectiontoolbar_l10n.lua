-- KOReader's gettext catalog does not contain strings from external plugins.
-- Keep plugin-specific translations here and fall back to KOReader's catalog
-- for languages without a Selection Toolbar translation (and for native UI terms).
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

-- Only strings with no fitting translation in KOReader's own catalog belong here.
-- Left out, so they come from KOReader in every language it supports: the action
-- names (Select, Highlight, Copy, Add note, Wikipedia, Dictionary, Translate,
-- View HTML, Generate QR code, Search), "Thin", "Medium", "Thick", "None",
-- "Default", "Arrange actions", "Restore", "About", "Version: %1" and "%1: %2".
-- "Selection Toolbar" is the plugin's name and stays untranslated.
local pt_BR = {
    -- Menu
    ["Selection toolbar"] = "Barra de ferramentas de seleção",
    ["Use compact selection toolbar"] = "Usar barra de ferramentas de seleção compacta",
    ["Replaces KOReader's default centered selection menu with a compact icon toolbar near the selection."] = "Substitui o menu de seleção centralizado do KOReader por uma barra compacta de ícones perto da seleção.",
    ["Style preset"] = "Estilo predefinido",
    ["Ready-made looks for the toolbar, the handles and the line marker. You can still adjust each setting afterwards."] = "Visuais prontos para a barra, as alças e o marcador de linha. Cada configuração ainda pode ser ajustada depois.",
    ["Actions: %1 of %2"] = "Ações: %1 de %2",
    ["Choose which actions appear in the toolbar, their order, and whether the toolbar is shortened."] = "Escolha quais ações aparecem na barra, a ordem delas e se a barra é encurtada.",
    ["Toolbar appearance"] = "Aparência da barra",
    ["Choose where the toolbar is shown, its size, shape, border, shadow and separators."] = "Escolha onde a barra aparece, seu tamanho, formato, borda, sombra e separadores.",
    ["Handles and line marker"] = "Alças e marcador de linha",
    ["Handles to adjust the selection and a margin line beside the selected lines."] = "Alças para ajustar a seleção e uma linha na margem ao lado das linhas selecionadas.",
    ["Restore all defaults"] = "Restaurar todos os padrões",
    ["Restores every selection toolbar setting, the visible actions and their order. The toolbar stays turned on or off as it is."] = "Restaura todas as configurações da barra de ferramentas de seleção, as ações visíveis e a ordem delas. A barra continua ligada ou desligada, como está.",
    ["Restore all selection toolbar settings to their defaults?"] = "Restaurar todas as configurações da barra de ferramentas de seleção para o padrão?",
    ["Shows a compact icon toolbar near selected text instead of the default centered selection menu."] = "Mostra uma barra compacta de ícones perto do texto selecionado, no lugar do menu de seleção centralizado.",

    -- Style presets
    ["The plugin's original look."] = "O visual original do plugin.",
    ["Discreet"] = "Discreto",
    ["A light toolbar: thin border, rounded corners, no shadow and lines only between groups of actions. Bracket handles and a thin line marker."] = "Uma barra leve: borda fina, cantos arredondados, sem sombra e linhas só entre grupos de ações. Alças em colchetes e marcador de linha fino.",
    ["Classic"] = "Clássico",
    ["A rectangular toolbar with a medium border, a shadow and separators between the buttons. Round (lollipop) handles."] = "Uma barra retangular com borda média, sombra e separadores entre os botões. Alças redondas (pirulito).",
    -- Also a button density.
    ["Comfortable"] = "Confortável",
    ["More spaced buttons with larger icons and a thick border. Lollipop handles with the high-contrast outline."] = "Botões mais espaçados, ícones maiores e borda grossa. Alças pirulito com o contorno de alto contraste.",
    ["Custom"] = "Personalizado",
    ["Your own combination: shown when the current look matches none of the styles above."] = "Sua própria combinação: marcada quando o visual atual não corresponde a nenhum dos estilos acima.",

    -- Actions
    ["Arrange actions and groups"] = "Organizar ações e grupos",
    ["Change the order of the actions and move the group separators between them. A separator moved to the start or the end of the list is not used."] = "Muda a ordem das ações e move os separadores de grupo entre elas. Um separador movido para o início ou o fim da lista não é usado.",
    ["Groups are shown as lines: Toolbar appearance > Separators is set to Between groups."] = "Os grupos aparecem como linhas: Aparência da barra > Separadores está em Entre grupos.",
    ["Groups are not shown now: set Toolbar appearance > Separators to Between groups to show them as lines."] = "Os grupos não aparecem agora: escolha Entre grupos em Aparência da barra > Separadores para mostrá-los como linhas.",
    ["Groups are shown as lines with Toolbar appearance > Separators set to Between groups."] = "Os grupos aparecem como linhas quando Aparência da barra > Separadores está em Entre grupos.",
    ["Group separator"] = "Separador de grupo",
    ["Shorten the toolbar"] = "Encurtar a barra",
    ["Show only the first actions of the order, and a More button (…) that shows the others in a second row. Useful with many actions enabled, so the toolbar covers less of the text."] = "Mostra só as primeiras ações da ordem e um botão Mais (…) que mostra as outras em uma segunda linha. Útil com muitas ações ativadas, para a barra cobrir menos o texto.",
    ["Show every visible action in a single row."] = "Mostra todas as ações visíveis em uma única linha.",
    ["To 4 actions"] = "Para 4 ações",
    ["To 5 actions"] = "Para 5 ações",
    ["To 6 actions"] = "Para 6 ações",
    ["Show all actions"] = "Mostrar todas as ações",
    ["Re-enables every selection toolbar action at once."] = "Reativa de uma vez todas as ações da barra de ferramentas de seleção.",
    ["All selection toolbar actions are enabled."] = "Todas as ações da barra de ferramentas de seleção estão ativadas.",
    ["Restore default order"] = "Restaurar ordem padrão",
    ["Annotation, lookup and tools groups, in the plugin's original order."] = "Grupos de anotação, consulta e ferramentas, na ordem original do plugin.",
    ["The default order of the actions is restored."] = "A ordem padrão das ações foi restaurada.",

    -- Toolbar
    ["Position"] = "Posição",
    ["Choose where the toolbar is shown on screen."] = "Escolha onde a barra aparece na tela.",
    ["Near the selection"] = "Perto da seleção",
    ["Show the toolbar right below the selection, or above it when there is no room."] = "Mostra a barra logo abaixo da seleção, ou acima dela quando não há espaço.",
    ["Fixed at screen edge"] = "Fixa na borda da tela",
    ["Show the toolbar centered at the bottom of the screen, or at the top when the selection is in the lower part."] = "Mostra a barra centralizada na parte de baixo da tela, ou no topo quando a seleção está na parte de baixo.",
    ["Button density"] = "Densidade dos botões",
    ["Choose the size and spacing of the toolbar buttons."] = "Escolha o tamanho e o espaçamento dos botões da barra.",
    ["Compact"] = "Compacta",
    ["Smaller, tighter buttons: the toolbar covers less of the page."] = "Botões menores e mais juntos: a barra cobre menos a página.",
    ["Normal"] = "Normal",
    ["The default button size and spacing."] = "O tamanho e o espaçamento padrão dos botões.",
    ["Taller, more spaced buttons: easier to tap."] = "Botões mais altos e espaçados: mais fáceis de tocar.",
    ["Icon size"] = "Tamanho dos ícones",
    ["Choose the size of the icons, independently of the button size."] = "Escolha o tamanho dos ícones, independente do tamanho dos botões.",
    -- Also handle sizes.
    ["Small"] = "Pequeno",
    ["Large"] = "Grande",
    ["Shape"] = "Formato",
    ["Choose how rounded the toolbar corners are."] = "Escolha o quanto os cantos da barra são arredondados.",
    ["Rectangle"] = "Retângulo",
    ["Square corners: the most sober look."] = "Cantos retos: o visual mais sóbrio.",
    ["Rounded corners"] = "Cantos arredondados",
    ["Slightly rounded corners, as KOReader's own dialogs."] = "Cantos levemente arredondados, como nos diálogos do próprio KOReader.",
    ["Capsule"] = "Cápsula",
    ["Fully rounded ends. The toolbar gets a little wider, to keep the buttons inside the curves."] = "Pontas totalmente arredondadas. A barra fica um pouco mais larga, para manter os botões dentro das curvas.",
    ["Border"] = "Borda",
    ["Choose how strong the toolbar outline is."] = "Escolha a força do contorno da barra.",
    ["A discreet outline."] = "Um contorno discreto.",
    ["The default outline, as KOReader's own dialogs."] = "O contorno padrão, como nos diálogos do próprio KOReader.",
    ["A strong outline that stands out over the text, useful without the shadow."] = "Um contorno forte, que se destaca sobre o texto; útil sem a sombra.",
    ["Shadow"] = "Sombra",
    ["Choose the shadow along the right and bottom edges of the toolbar."] = "Escolha a sombra ao longo das bordas direita e inferior da barra.",
    ["No shadow"] = "Sem sombra",
    ["A flat toolbar. A stronger border helps it stand out over the text."] = "Uma barra plana. Uma borda mais forte ajuda a destacá-la sobre o texto.",
    ["Subtle"] = "Sutil",
    ["A shorter, lighter shadow."] = "Uma sombra mais curta e mais clara.",
    ["Standard"] = "Padrão",
    ["A dithered shadow along the right and bottom edges."] = "Uma sombra pontilhada ao longo das bordas direita e inferior.",
    ["Separators"] = "Separadores",
    ["Choose whether lines are drawn between the buttons."] = "Escolha se são desenhadas linhas entre os botões.",
    ["Between all buttons"] = "Entre todos os botões",
    ["A thin line between each pair of buttons."] = "Uma linha fina entre cada par de botões.",
    ["Between groups"] = "Entre grupos",
    ["A line only between groups of actions, such as annotation, lookup and tools. Arrange the groups in Actions."] = "Uma linha só entre grupos de ações, como anotação, consulta e ferramentas. Organize os grupos em Ações.",
    ["No lines between buttons, for a lighter look."] = "Sem linhas entre os botões, para um visual mais leve.",

    -- Handles and line marker
    ["Show selection handles"] = "Mostrar alças de seleção",
    ["Drag the selection handles to adjust it, or into a page corner to continue."] = "Arraste as alças para ajustar a seleção, ou até um canto da página para continuar.",
    ["Handle style"] = "Estilo das alças",
    ["Choose how the selection handles are drawn."] = "Escolha como as alças de seleção são desenhadas.",
    ["Lollipop"] = "Pirulito",
    ["A bar at the selection edge with a round knob above the start and below the end."] = "Uma barra na borda da seleção, com uma bolinha acima do início e abaixo do fim.",
    ["Teardrop"] = "Gota",
    ["A drop below the line, pointing at the selection edge, as on Android."] = "Uma gota abaixo da linha, apontando para a borda da seleção, como no Android.",
    ["Brackets"] = "Colchetes",
    ["A [ at the start and a ] at the end of the selection. The most discreet style."] = "Um [ no início e um ] no fim da seleção. O estilo mais discreto.",
    ["Flag tabs"] = "Bandeirolas",
    ["A pole with a grab tab pointing outwards, above the start and below the end, slanted toward the text."] = "Um mastro com uma aba de arrastar apontando para fora, acima do início e abaixo do fim, inclinada em direção ao texto.",
    ["High-contrast outline"] = "Contorno de alto contraste",
    ["Black outline over white, readable over dark or highlighted text. Not for brackets."] = "Contorno preto sobre branco, legível sobre texto escuro ou destacado. Não vale para colchetes.",
    ["Handle size"] = "Tamanho das alças",
    ["Choose how large the handles are drawn. Their touch area stays the same."] = "Escolha o tamanho com que as alças são desenhadas. A área de toque continua a mesma.",
    ["Discreet handles. They are as easy to grab as normal ones."] = "Alças discretas. São tão fáceis de arrastar quanto as normais.",
    ["The default handle size."] = "O tamanho padrão das alças.",
    ["Handles that are easier to see."] = "Alças mais fáceis de ver.",
    ["Show line marker"] = "Mostrar marcador de linha",
    ["Show a vertical line in the page margin beside the selected lines."] = "Mostra uma linha vertical na margem da página, ao lado das linhas selecionadas.",
    ["Line marker in right margin"] = "Marcador de linha na margem direita",
    ["Draw the line marker in the right margin. Mirrored for right-to-left languages."] = "Desenha o marcador de linha na margem direita. Espelhado em idiomas da direita para a esquerda.",
    ["Line marker thickness"] = "Espessura do marcador de linha",
    ["Choose how thick the line marker is."] = "Escolha a espessura do marcador de linha.",
    ["Line marker distance"] = "Distância do marcador de linha",
    ["Choose how far from the text the line marker is drawn. It stays in the page margin, closer to the text when the margin is narrow."] = "Escolha a que distância do texto o marcador de linha é desenhado. Ele fica na margem da página, mais perto do texto quando a margem é estreita.",
    ["Close to the text"] = "Perto do texto",
    ["Far from the text"] = "Longe do texto",

    -- Settings preview
    ["Preview"] = "Prévia",
    -- Repeated to fill the preview's lines: keep the trailing space.
    ["This is a short sample of text, shown so you can see how the selection toolbar looks over the page. "] = "Este é um pequeno trecho de texto, mostrado para você ver como a barra de ferramentas de seleção fica sobre a página. ",

    -- Toolbar and messages
    ["More actions"] = "Mais ações",
    ["Fewer actions"] = "Menos ações",
    ["No selected text."] = "Nenhum texto selecionado.",
    ["QR code widget is not available in this KOReader build."] = "O widget de código QR não está disponível nesta versão do KOReader.",
    ["No selection toolbar actions are enabled."] = "Nenhuma ação da barra de ferramentas de seleção está ativada.",
}

-- European Portuguese: only the strings whose wording differs. A word swap would get
-- the gender wrong ("a tela" is "o ecrã"), so each one is written out.
local pt_PT = setmetatable({
    ["Replaces KOReader's default centered selection menu with a compact icon toolbar near the selection."] = "Substitui o menu de seleção centrado do KOReader por uma barra compacta de ícones perto da seleção.",
    ["Ready-made looks for the toolbar, the handles and the line marker. You can still adjust each setting afterwards."] = "Visuais prontos para a barra, as pegas e o marcador de linha. Cada definição pode ainda ser ajustada depois.",
    ["Choose where the toolbar is shown, its size, shape, border, shadow and separators."] = "Escolha onde a barra aparece, o seu tamanho, forma, contorno, sombra e separadores.",
    ["Handles to adjust the selection and a margin line beside the selected lines."] = "Pegas para ajustar a seleção e uma linha na margem ao lado das linhas selecionadas.",
    ["Restores every selection toolbar setting, the visible actions and their order. The toolbar stays turned on or off as it is."] = "Repõe todas as definições da barra de ferramentas de seleção, as ações visíveis e a sua ordem. A barra continua ligada ou desligada, como está.",
    ["Restore all defaults"] = "Repor todas as predefinições",
    -- KOReader has "Restaurar": the confirmation button would not match its question.
    ["Restore"] = "Repor",
    ["Restore all selection toolbar settings to their defaults?"] = "Repor todas as definições da barra de ferramentas de seleção para as predefinições?",
    ["Shows a compact icon toolbar near selected text instead of the default centered selection menu."] = "Mostra uma barra compacta de ícones perto do texto selecionado, em vez do menu de seleção centrado.",
    ["A light toolbar: thin border, rounded corners, no shadow and lines only between groups of actions. Bracket handles and a thin line marker."] = "Uma barra leve: contorno fino, cantos arredondados, sem sombra e linhas só entre grupos de ações. Pegas em parênteses retos e marcador de linha fino.",
    ["A rectangular toolbar with a medium border, a shadow and separators between the buttons. Round (lollipop) handles."] = "Uma barra retangular com contorno médio, sombra e separadores entre os botões. Pegas redondas (chupa-chupa).",
    ["More spaced buttons with larger icons and a thick border. Lollipop handles with the high-contrast outline."] = "Botões mais espaçados, ícones maiores e contorno grosso. Pegas chupa-chupa com o contorno de alto contraste.",
    ["Your own combination: shown when the current look matches none of the styles above."] = "A sua própria combinação: marcada quando o visual atual não corresponde a nenhum dos estilos acima.",
    ["Groups are shown as lines: Toolbar appearance > Separators is set to Between groups."] = "Os grupos aparecem como linhas: Aparência da barra > Separadores está em Entre grupos.",
    ["Show only the first actions of the order, and a More button (…) that shows the others in a second row. Useful with many actions enabled, so the toolbar covers less of the text."] = "Mostra só as primeiras ações da ordem e um botão Mais (…) que mostra as outras numa segunda linha. Útil com muitas ações ativadas, para a barra cobrir menos o texto.",
    ["Show every visible action in a single row."] = "Mostra todas as ações visíveis numa única linha.",
    ["Restore default order"] = "Repor ordem predefinida",
    ["The default order of the actions is restored."] = "A ordem predefinida das ações foi reposta.",
    ["Choose where the toolbar is shown on screen."] = "Escolha onde a barra aparece no ecrã.",
    ["Fixed at screen edge"] = "Fixa no limite do ecrã",
    ["Show the toolbar centered at the bottom of the screen, or at the top when the selection is in the lower part."] = "Mostra a barra centrada na parte de baixo do ecrã, ou no topo quando a seleção está na parte de baixo.",
    ["The default button size and spacing."] = "O tamanho e o espaçamento predefinidos dos botões.",
    ["Choose the size of the icons, independently of the button size."] = "Escolha o tamanho dos ícones, independentemente do tamanho dos botões.",
    ["Shape"] = "Forma",
    ["Rectangle"] = "Retângulo",
    ["Border"] = "Contorno",
    ["The default outline, as KOReader's own dialogs."] = "O contorno predefinido, como nos diálogos do próprio KOReader.",
    ["Choose the shadow along the right and bottom edges of the toolbar."] = "Escolha a sombra ao longo dos limites direito e inferior da barra.",
    ["A flat toolbar. A stronger border helps it stand out over the text."] = "Uma barra plana. Um contorno mais forte ajuda a destacá-la sobre o texto.",
    ["Subtle"] = "Subtil",
    ["Standard"] = "Normal",
    ["A dithered shadow along the right and bottom edges."] = "Uma sombra pontilhada ao longo dos limites direito e inferior.",
    ["Handles and line marker"] = "Pegas e marcador de linha",
    ["Show selection handles"] = "Mostrar pegas de seleção",
    ["Drag the selection handles to adjust it, or into a page corner to continue."] = "Arraste as pegas para ajustar a seleção, ou até um canto da página para continuar.",
    ["Handle style"] = "Estilo das pegas",
    ["Choose how the selection handles are drawn."] = "Escolha como as pegas de seleção são desenhadas.",
    ["Lollipop"] = "Chupa-chupa",
    ["A bar at the selection edge with a round knob above the start and below the end."] = "Uma barra no limite da seleção, com uma bolinha acima do início e abaixo do fim.",
    ["A drop below the line, pointing at the selection edge, as on Android."] = "Uma gota abaixo da linha, a apontar para o limite da seleção, como no Android.",
    ["Brackets"] = "Parênteses retos",
    ["A pole with a grab tab pointing outwards, above the start and below the end, slanted toward the text."] = "Um mastro com uma aba de arrastar a apontar para fora, acima do início e abaixo do fim, inclinada em direção ao texto.",
    ["Black outline over white, readable over dark or highlighted text. Not for brackets."] = "Contorno preto sobre branco, legível sobre texto escuro ou destacado. Não se aplica aos parênteses retos.",
    ["Handle size"] = "Tamanho das pegas",
    ["Choose how large the handles are drawn. Their touch area stays the same."] = "Escolha o tamanho com que as pegas são desenhadas. A área de toque mantém-se.",
    ["Discreet handles. They are as easy to grab as normal ones."] = "Pegas discretas. São tão fáceis de arrastar como as normais.",
    ["The default handle size."] = "O tamanho predefinido das pegas.",
    ["Handles that are easier to see."] = "Pegas mais fáceis de ver.",
    ["Preview"] = "Pré-visualização",
    ["This is a short sample of text, shown so you can see how the selection toolbar looks over the page. "] = "Este é um pequeno excerto de texto, mostrado para ver como a barra de ferramentas de seleção fica sobre a página. ",
    ["QR code widget is not available in this KOReader build."] = "O widget de código QR não está disponível nesta compilação do KOReader.",
}, { __index = pt_BR })

local translations = locale:match("^pt_PT") and pt_PT or pt_BR

return setmetatable({
    ngettext = gettext.ngettext,
    pgettext = gettext.pgettext,
}, {
    __call = function(_, msgid)
        return translations[msgid] or gettext(msgid)
    end,
})
