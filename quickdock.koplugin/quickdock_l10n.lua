-- KOReader's gettext catalog does not contain strings from external plugins.
-- Keep plugin-specific translations here and fall back to KOReader's catalog
-- for languages without a Quick Dock translation (and for native UI terms).
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

local pt_BR = {
    ["Quick Dock"] = "Quick Dock",
    ["Quick Dock %1"] = "Quick Dock %1",
    ["A configurable floating dock for quick access to actions, controls, and information."] = "Uma dock flutuante configurável para acessar rapidamente ações, controles e informações.",
    ["Search current context"] = "Pesquisar no contexto atual",
    ["Show Quick Dock"] = "Mostrar Quick Dock",
    ["No Quick Dock actions are configured."] = "Nenhuma ação do Quick Dock está configurada.",
    ["Could not return to the reader."] = "Não foi possível voltar ao leitor.",
    ["Turn frontlight off"] = "Desligar iluminação frontal",
    ["Turn frontlight on"] = "Ligar iluminação frontal",
    ["Warmth: %1"] = "Temperatura de cor: %1",
    ["Return to reader"] = "Voltar ao leitor",
    ["Show next dock page"] = "Mostrar próxima página da dock",
    ["Show previous dock page"] = "Mostrar página anterior da dock",
    ["Move dock to the left"] = "Mover dock para a esquerda",
    ["Move dock to the right"] = "Mover dock para a direita",
    ["Close Quick Dock"] = "Fechar Quick Dock",
    ["Network information"] = "Informações da rede",
    ["Reading information"] = "Informações de leitura",
    ["Book statistics"] = "Estatísticas do livro",
    ["reading information"] = "informações de leitura",
    ["book statistics"] = "estatísticas do livro",
    ["network information"] = "informações da rede",
    ["Showing %1. Tap to show %2."] = "Exibindo %1. Toque para mostrar %2.",
    ["Connected"] = "Conectado",
    ["Wi-Fi on, not connected"] = "Wi-Fi ligado, sem conexão",
    ["Wi-Fi off"] = "Wi-Fi desligado",
    ["SSID: %1"] = "SSID: %1",
    ["Book: %1 / %2  ·  %3%"] = "Livro: %1 / %2  ·  %3%",
    ["Remaining: %1"] = "Restante: %1",
    ["Page: %1 / %2  ·  %3%"] = "Página: %1 / %2  ·  %3%",
    ["Reading today"] = "Leitura de hoje",
    ["No document is currently open."] = "Nenhum documento está aberto.",
    ["Today: %1"] = "Hoje: %1",
    ["Today: %1  ·  %2"] = "Hoje: %1  ·  %2",
    ["Progress"] = "Progresso",
    ["Time read"] = "Tempo de leitura",
    ["Time left"] = "Tempo restante",
    ["Daily average"] = "Média diária",
    ["Pages/min"] = "Págs/min",
    ["Started"] = "Iniciado",
    ["Started on %1"] = "Iniciado em %1",
    ["Today"] = "Hoje",
    ["1 day ago"] = "Há 1 dia",
    ["%1 days ago"] = "Há %1 dias",
    ["Estimated end"] = "Término estimado",
    ["Enable KOReader's Statistics plugin to collect reading data."] = "Ative o plugin Estatísticas do KOReader para registrar os dados de leitura.",

    ["Reset the Quick Dock actions and their order to the defaults?"] = "Restaurar as ações do Quick Dock e sua ordem padrão?",
    ["Reset Quick Dock behavior to its defaults? Your actions and their order will be kept."] = "Restaurar o comportamento padrão do Quick Dock? As ações e sua ordem serão mantidas.",
    ["Reset Quick Dock behavior and actions to their defaults? Appearance settings will be kept."] = "Restaurar o comportamento e as ações padrão do Quick Dock? As configurações de aparência serão mantidas.",
    ["Reset all"] = "Redefinir tudo",
    ["Automatic"] = "Automático",
    ["Automatic (%1)"] = "Automático (%1)",
    ["Reader only"] = "Somente no leitor",
    ["File browser and Bookshelf only"] = "Somente no explorador de arquivos e no Bookshelf",
    ["Everywhere"] = "Em todos os contextos",
    ["Use automatic visibility for all actions"] = "Usar visibilidade automática em todas as ações",
    ["Show all actions everywhere"] = "Mostrar todas as ações em todos os contextos",

    ["Close button"] = "Botão de fechar",
    ["Icon shown in the separate button that closes the dock."] = "Ícone do botão separado que fecha a dock.",
    ["Frontlight toggle"] = "Alternar iluminação frontal",
    ["Uses a different icon for the active and inactive frontlight states."] = "Usa ícones diferentes quando a iluminação frontal está ligada ou desligada.",
    ["Frontlight on"] = "Iluminação frontal ligada",
    ["Frontlight off"] = "Iluminação frontal desligada",
    ["Warmth control"] = "Controle de temperatura de cor",
    ["Icon of the warmth control: below its slider in the column dock, or on its button inside the arc."] = "Ícone do controle de temperatura de cor: abaixo do controle deslizante na dock em coluna ou no seu botão dentro do arco.",
    ["Information panel switch"] = "Alternar painel de informações",
    ["File browser / return to reader / open last document"] = "Explorador de arquivos / voltar ao leitor / abrir último documento",
    ["Alternative PNG filename"] = "Nome alternativo do arquivo PNG",
    ["Uses a different icon for day and night modes."] = "Usa ícones diferentes nos modos diurno e noturno.",
    ["Day mode"] = "Modo diurno",
    ["Uses a different icon for the active and inactive Wi-Fi states."] = "Usa ícones diferentes quando o Wi-Fi está ligado ou desligado.",
    ["Wi-Fi on"] = "Wi-Fi ligado",
    ["Uses a different icon inside and outside the reader."] = "Usa ícones diferentes dentro e fora do leitor.",
    ["While reading"] = "Durante a leitura",
    ["In the file browser"] = "No explorador de arquivos",
    ["In Bookshelf with a parked reader"] = "No Bookshelf com o leitor em segundo plano",

    ["Follow gesture"] = "Seguir gesto",
    ["Dock side: %1"] = "Lado da dock: %1",
    ["Choose a fixed side or place the dock on the side where its gesture started."] = "Escolha um lado fixo ou abra a dock no lado em que o gesto começou.",
    ["Follow gesture side"] = "Seguir o lado do gesto",
    ["Places the dock on the half of the screen where the gesture started. Uses the fixed side when no gesture position is available."] = "Abre a dock na metade da tela em que o gesto começou. Usa o lado fixo quando a posição do gesto não está disponível.",
    ["All blocks at once"] = "Todos os blocos de uma vez",
    ["One block at a time"] = "Um bloco por vez",
    ["Dock and panel closing: %1"] = "Fechamento da dock e dos painéis: %1",
    ["Choose whether the dock and its panels disappear in the same repaint cycle or close separately."] = "Escolha se a dock e os painéis desaparecem na mesma atualização da tela ou separadamente.",
    ["Closes each visible block separately, using the original sequential behavior."] = "Fecha cada bloco visível separadamente, em sequência.",
    ["Closes all blocks with one non-flashing update over the smallest rectangle that contains them."] = "Fecha todos os blocos com uma única atualização sem flash na menor área retangular que os contém.",
    ["Show reader/browser button"] = "Mostrar botão leitor/navegador",
    ["Shows the first dock button: it opens the file browser while reading, returns from Bookshelf to the reader, or opens the last document from the file browser."] = "Mostra o primeiro botão da dock: abre o explorador de arquivos durante a leitura, volta do Bookshelf ao leitor ou abre o último documento no explorador.",
    ["Show side-switch button"] = "Mostrar botão de troca de lado",
    ["Shows a button that moves the dock to the other side without opening the settings: above the column dock, or inside the arc next to its start."] = "Mostra um botão que move a dock para o outro lado sem abrir as configurações: acima da dock em coluna ou dentro do arco, junto ao seu começo.",
    ["Show close button"] = "Mostrar botão de fechar",
    ["Shows a button that closes the dock, using close.svg: above the column dock, or inside the arc."] = "Mostra um botão que fecha a dock, usando close.svg: acima da dock em coluna ou dentro do arco.",
    ["Configured actions: %1"] = "Ações configuradas: %1",
    ["Choose the actions shown in the dock and arrange their order."] = "Escolha as ações mostradas na dock e organize sua ordem.",
    ["Extra buttons"] = "Botões extras",
    ["Show or hide the reader/browser, side-switch, and close buttons around the dock. These are not configurable actions."] = "Mostre ou oculte os botões de leitor/navegador, troca de lado e fechamento ao redor da dock. Eles não são ações configuráveis.",
    ["Action visibility"] = "Visibilidade das ações",
    ["Control which actions appear in the reader, file browser, and Bookshelf."] = "Controle quais ações aparecem no leitor, no explorador de arquivos e no Bookshelf.",
    ["Automatic visibility"] = "Visibilidade automática",
    ["Automatically shows native reader and file-browser actions only in their relevant context. Manual choices override the automatic result."] = "Mostra automaticamente as ações nativas do leitor e do navegador apenas nos contextos relevantes. As escolhas manuais têm prioridade.",
    ["Per-action visibility"] = "Visibilidade por ação",
    ["Review automatic results or override each action for all screens, the reader, or the file browser and Bookshelf."] = "Confira o resultado automático ou defina onde cada ação aparece: em todas as telas, no leitor ou no explorador de arquivos e Bookshelf.",

    ["Small"] = "Pequena",
    ["Large"] = "Grande",
    ["Dock scale: %1"] = "Escala da dock: %1",
    ["Sets the size of the buttons, icons, and lighting controls. With the arc's Fill the arc option enabled, its buttons may grow beyond this size."] = "Define o tamanho dos botões, ícones e controles de iluminação. Com a opção Preencher o arco ativada, os botões do arco podem ficar maiores que esse tamanho.",
    ["Uses the base dock dimensions."] = "Usa as dimensões básicas da dock.",
    ["Increases the dock dimensions by 20 percent."] = "Aumenta as dimensões da dock em 20%.",
    ["Increases the dock dimensions by 40 percent."] = "Aumenta as dimensões da dock em 40%.",
    ["Maximum dock height: %1%"] = "Altura máxima da dock: %1%",
    ["Limits the dock's height (the column with its lighting sliders, or the arc) to the selected percentage of the screen, and paginates the actions when they do not fit."] = "Limita a altura da dock (a coluna com os controles de iluminação ou o arco) à porcentagem selecionada da tela e pagina as ações quando não couberem.",
    ["Nearest screen edge"] = "Borda da tela mais próxima",
    ["Shows book, chapter, daily reading, clock, and battery information in the information panel."] = "Mostra informações do livro, capítulo, leitura diária, relógio e bateria no painel de informações.",
    ["Shows Wi-Fi state and the network details reported by KOReader in the information panel."] = "Mostra o estado do Wi-Fi e os detalhes de rede fornecidos pelo KOReader no painel de informações.",
    ["Recent documents"] = "Documentos recentes",
    ["Show this panel"] = "Mostrar este painel",
    ["Documents to show: %1"] = "Documentos exibidos: %1",
    ["Uses a dedicated icon for each information panel mode, showing which one is visible."] = "Usa um ícone específico para cada modo do painel de informações, indicando qual está visível.",
    ["recent documents"] = "documentos recentes",
    ["No recent documents."] = "Nenhum documento recente.",
    ["This document is no longer available."] = "Este documento não está mais disponível.",
    ["Shows the covers of the most recently opened documents in the information panel. Tap a cover to open its document; when they do not fit, arrows above the covers turn the page. Covers come from the Cover browser plugin; documents it has not indexed yet show their title instead."] = "Mostra no painel de informações as capas dos documentos abertos mais recentemente. Toque em uma capa para abrir o documento; quando não couberem, as setas acima das capas mudam de página. As capas vêm do plugin Navegador de capas; documentos que ele ainda não indexou mostram o título no lugar.",
    ["The maximum number of recent documents in the recent documents panel. The document open in the reader is not listed. Documents that do not fit the panel are split into pages."] = "Quantidade máxima de documentos no painel de documentos recentes. O documento aberto no leitor não é listado. Os documentos que não couberem no painel são divididos em páginas.",
    ["Shows the open book's reading time, remaining time, progress, daily average, reading speed, start date, and estimated end date, as recorded by KOReader's Statistics plugin."] = "Mostra o tempo de leitura, tempo restante, progresso, média diária, velocidade de leitura, data de início e data estimada de término do livro aberto, conforme registrado pelo plugin Estatísticas do KOReader.",
    ["Show book cover"] = "Mostrar capa do livro",
    ["Shows the open book's cover in the reading information and book statistics: above the text beside the column dock, or to its left in the arc dock's top panel. The thumbnail is loaded once and reused while the document remains open. This option applies to both panels."] = "Mostra a capa do livro aberto nas informações de leitura e nas estatísticas do livro: acima do texto, ao lado da dock em coluna, ou à esquerda no painel superior da dock em arco. A miniatura é carregada uma vez e reutilizada enquanto o documento permanece aberto. Esta opção vale para os dois painéis.",
    ["Panel text alignment: %1"] = "Alinhamento do texto do painel: %1",
    ["Aligns every line in the selected information panel, including the clock and battery."] = "Alinha todas as linhas do painel de informações, inclusive relógio e bateria.",
    ["Aligns left on the left edge and right on the right edge. The arc dock's top panel aligns left."] = "Alinha à esquerda na borda esquerda e à direita na borda direita. O painel superior da dock em arco alinha à esquerda.",
    ["Show frontlight control"] = "Mostrar controle de iluminação frontal",
    ["On devices with a frontlight, shows the brightness slider and light toggle: a column beside the column dock, or a button inside the arc that shows the slider along it."] = "Em dispositivos com iluminação frontal, mostra o controle de brilho e o botão de ligar e desligar a luz: uma coluna ao lado da dock em coluna ou um botão dentro do arco que mostra o controle ao longo dele.",
    ["Show warmth control"] = "Mostrar controle de temperatura de cor",
    ["On supported devices, shows the frontlight warmth slider: a second column beside the column dock, or a second button inside the arc."] = "Em dispositivos compatíveis, mostra o controle de temperatura de cor: uma segunda coluna ao lado da dock em coluna ou um segundo botão dentro do arco.",
    ["Dock layout"] = "Layout da dock",
    ["Adjust the scale and maximum height of the dock."] = "Ajuste a escala e a altura máxima da dock.",
    ["Choose the dock shape, its scale and maximum height, and the arc's options."] = "Escolha o formato da dock, sua escala e altura máxima e as opções do arco.",
    ["Dock shape: %1"] = "Formato da dock: %1",
    ["Column"] = "Coluna",
    ["Arc"] = "Arco",
    ["Choose a column beside the screen edge or a quarter ring around the lower corner for one-handed use."] = "Escolha uma coluna junto à borda da tela ou um quarto de anel em volta do canto inferior, para uso com uma mão.",
    ["Stacks the buttons in a column, with the lighting sliders beside it and the information panel on the opposite edge."] = "Empilha os botões em uma coluna, com os controles de iluminação ao lado e o painel de informações na borda oposta.",
    ["Places the actions in a single row on a quarter ring around the lower corner, within reach of the thumb, with the other buttons floating inside it. Tapping the brightness or warmth button shows its slider in place of the actions; pages turn by swiping along the ring or with its arrows. The information panel moves to the top of the screen."] = "Coloca as ações em uma única fileira, em um quarto de anel em volta do canto inferior, ao alcance do polegar, com os demais botões flutuando por dentro. Tocar no botão de brilho ou de temperatura de cor mostra o controle deslizante no lugar das ações; as páginas mudam deslizando ao longo do anel ou pelas setas. O painel de informações passa para o topo da tela.",
    ["Brightness"] = "Brilho",
    ["Arc options"] = "Opções do arco",
    ["The arc's angle, its background band, and how its buttons use its length. Available with the Arc shape."] = "O ângulo do arco, a faixa de fundo e como os botões ocupam o seu comprimento. Disponível com o formato Arco.",
    ["Fill the arc when there are few actions"] = "Preencher o arco quando houver poucas ações",
    ["Spreads each page's buttons along the whole arc and, when every action fits on one page, enlarges them up to 1.5 times to close the gaps. Button size then varies with the number of actions, and Dock scale only sets the smallest size. When disabled, the buttons keep the Dock scale size and the spacing of a full page, and the unused part of the arc stays empty."] = "Distribui os botões de cada página ao longo de todo o arco e, quando todas as ações cabem em uma página, aumenta-os em até 1,5 vez para reduzir os espaços. Assim, o tamanho dos botões varia com o número de ações, e a Escala da dock define apenas o tamanho mínimo. Desativado, os botões mantêm o tamanho da Escala da dock e o espaçamento de uma página cheia, e a parte não usada do arco fica vazia.",
    ["At the end, near the side edge"] = "No final, perto da borda lateral",
    ["At the start, near the bottom edge"] = "No começo, perto da borda inferior",
    ["Empty space: %1"] = "Espaço vazio: %1",
    ["Where the unused part of the arc stays when a page has fewer buttons than the arc holds. Available when Fill the arc is disabled."] = "Onde fica a parte não usada do arco quando uma página tem menos botões do que o arco comporta. Disponível quando Preencher o arco está desativado.",
    ["The buttons, including the floating ones inside the arc, start at its bottom end."] = "Os botões, inclusive os flutuantes dentro do arco, começam na sua ponta inferior.",
    ["The buttons end at the side end of the arc, and the floating ones inside it start there too."] = "Os botões terminam na ponta lateral do arco, e os flutuantes dentro dele também começam ali.",
    ["%1°"] = "%1°",
    ["%1° (quarter circle)"] = "%1° (quarto de círculo)",
    ["%1° (widest and lowest)"] = "%1° (mais largo e baixo)",
    ["%1° (tallest and narrowest)"] = "%1° (mais alto e estreito)",
    ["Arc angle: %1°"] = "Ângulo do arco: %1°",
    ["Tilts the arc: the angle between the bottom edge and the line joining its two ends. Higher angles bring the bottom end closer to the side and make the arc taller; lower angles spread it along the bottom and make it lower. The arc keeps about the same size."] = "Inclina o arco: é o ângulo entre a borda inferior e a linha que liga as duas pontas. Ângulos maiores aproximam a ponta de baixo da lateral e deixam o arco mais alto; ângulos menores o espalham pela parte de baixo e o deixam mais baixo. O tamanho do arco se mantém aproximadamente.",
    ["Show band behind buttons"] = "Mostrar faixa atrás dos botões",
    ["Draws the arc's buttons on a white band. Without it, each button floats on the page with its own outline."] = "Desenha os botões do arco sobre uma faixa branca. Sem ela, cada botão flutua sobre a página com o próprio contorno.",
    ["Show or hide the brightness slider"] = "Mostrar ou ocultar o controle de brilho",
    ["Show or hide the warmth slider"] = "Mostrar ou ocultar o controle de temperatura de cor",
    ["Information panel"] = "Painel de informações",
    ["Choose the content and text alignment of the information panel: on the edge opposite the column dock, or along the top of the screen with the arc dock."] = "Escolha o conteúdo e o alinhamento do texto do painel de informações: na borda oposta à dock em coluna ou no topo da tela com a dock em arco.",
    ["Lighting controls"] = "Controles de iluminação",
    ["Show or hide the frontlight brightness and warmth controls."] = "Mostre ou oculte os controles de brilho e temperatura de cor.",
    ["Custom icon filenames"] = "Nomes de arquivo de ícones personalizados",
    ["Reference list of the SVG/PNG filenames Quick Dock looks for when you want to replace an icon."] = "Lista de referência dos nomes de arquivo SVG/PNG que o Quick Dock procura quando você quer substituir um ícone.",

    ["Reset behavior to defaults"] = "Redefinir comportamento para o padrão",
    ["Restores gesture-following placement, right-side fallback, and one-block-at-a-time closing without changing actions, extra buttons, or appearance."] = "Restaura a posição pelo gesto, o lado direito padrão e o fechamento de um bloco por vez sem alterar ações, botões extras ou aparência.",
    ["Reset actions to defaults"] = "Redefinir ações para o padrão",
    ["Restores the initial actions and their order without changing other Quick Dock settings."] = "Restaura as ações iniciais e sua ordem sem alterar outras configurações do Quick Dock.",
    ["Reset behavior and actions"] = "Redefinir comportamento e ações",
    ["Restores behavior, extra buttons, default actions, order, and action visibility while keeping appearance settings."] = "Restaura comportamento, botões extras, ações padrão, ordem e visibilidade, mantendo as configurações de aparência.",
    ["Behavior"] = "Comportamento",
    ["Controls where the dock opens and how its visible blocks close."] = "Define onde a dock abre e como seus blocos visíveis são fechados.",
    ["Actions"] = "Ações",
    ["Configure actions, extra buttons, ordering, and contextual visibility."] = "Configure ações, botões extras, ordem e visibilidade por contexto.",
    ["Appearance"] = "Aparência",
    ["Controls dock layout, information panels, lighting controls, and custom icons."] = "Define o layout da dock, os painéis de informações, os controles de iluminação e os ícones personalizados.",
    ["Restore default behavior, with or without resetting actions."] = "Restaure o comportamento padrão, com ou sem redefinir as ações.",
    ["Gesture setup"] = "Configuração de gestos",
    ["Assign 'Show Quick Dock' to any gesture in KOReader's gesture manager."] = "Atribua 'Mostrar Quick Dock' a qualquer gesto no gerenciador de gestos do KOReader.",
    ["Open Settings > Taps and gestures > Gesture manager, choose a gesture, then select Show Quick Dock."] = "Abra Configurações > Toques e gestos > Gerenciador de gestos, escolha um gesto e selecione Mostrar Quick Dock.",
}

local pt_PT = setmetatable({
    ["A configurable floating dock for quick access to actions, controls, and information."] = "Uma dock flutuante configurável para aceder rapidamente a ações, controlos e informações.",
    ["Connecting to Wi-Fi…"] = "A ligar ao Wi-Fi…",
    ["Connected"] = "Ligado",
    ["Turning off Wi-Fi…"] = "A desligar o Wi-Fi…",
    ["Error connecting to the network"] = "Erro ao ligar à rede",
    ["File browser and Bookshelf only"] = "Apenas no navegador de ficheiros e no Bookshelf",
    ["File browser / return to reader / open last document"] = "Navegador de ficheiros / voltar ao leitor / abrir o último documento",
    ["In the file browser"] = "No navegador de ficheiros",
    ["Show reader/browser button"] = "Mostrar botão leitor/navegador",
    ["Shows the first dock button: it opens the file browser while reading, returns from Bookshelf to the reader, or opens the last document from the file browser."] = "Mostra o primeiro botão da dock: abre o navegador de ficheiros durante a leitura, volta do Bookshelf ao leitor ou abre o último documento no navegador.",
    ["Control which actions appear in the reader, file browser, and Bookshelf."] = "Controle as ações que aparecem no leitor, no navegador de ficheiros e no Bookshelf.",
    ["Review automatic results or override each action for all screens, the reader, or the file browser and Bookshelf."] = "Confira o resultado automático ou defina onde cada ação aparece: em todos os ecrãs, no leitor ou no navegador de ficheiros e Bookshelf.",
    ["Automatically shows native reader and file-browser actions only in their relevant context. Manual choices override the automatic result."] = "Mostra automaticamente as ações nativas do leitor e do navegador apenas nos contextos relevantes. As escolhas manuais têm prioridade.",
    ["Shows Wi-Fi state and the network details reported by KOReader in the information panel."] = "Mostra o estado do Wi-Fi e os detalhes da rede fornecidos pelo KOReader no painel de informações.",
    ["Nearest screen edge"] = "Margem do ecrã mais próxima",
    ["Warmth control"] = "Controlo de temperatura de cor",
    ["Show warmth control"] = "Mostrar controlo de temperatura de cor",
    ["Icon of the warmth control: below its slider in the column dock, or on its button inside the arc."] = "Ícone do controlo de temperatura de cor: abaixo do controlo deslizante na dock em coluna ou no seu botão dentro do arco.",
    ["On supported devices, shows the frontlight warmth slider: a second column beside the column dock, or a second button inside the arc."] = "Em dispositivos compatíveis, mostra o controlo de temperatura de cor: uma segunda coluna ao lado da dock em coluna ou um segundo botão dentro do arco.",
    ["Show or hide the frontlight brightness and warmth controls."] = "Mostre ou oculte os controlos de brilho e temperatura de cor.",
    ["Shows a button that moves the dock to the other side without opening the settings: above the column dock, or inside the arc next to its start."] = "Mostra um botão que move a dock para o outro lado sem abrir as definições: acima da dock em coluna ou dentro do arco, junto ao seu começo.",
    ["Restores the initial actions and their order without changing other Quick Dock settings."] = "Restaura as ações iniciais e a sua ordem sem alterar outras definições do Quick Dock.",
    ["Reset Quick Dock behavior to its defaults? Your actions and their order will be kept."] = "Restaurar o comportamento padrão do Quick Dock? As ações e a sua ordem serão mantidas.",
    ["Reset Quick Dock behavior and actions to their defaults? Appearance settings will be kept."] = "Restaurar o comportamento e as ações padrão do Quick Dock? As definições de aparência serão mantidas.",
    ["This document is no longer available."] = "Este documento já não está disponível.",
    ["Shows the covers of the most recently opened documents in the information panel. Tap a cover to open its document; when they do not fit, arrows above the covers turn the page. Covers come from the Cover browser plugin; documents it has not indexed yet show their title instead."] = "Mostra no painel de informações as capas dos documentos abertos mais recentemente. Toque numa capa para abrir o documento; quando não couberem, as setas acima das capas mudam de página. As capas vêm do plugin Navegador de capas; os documentos que ele ainda não indexou mostram o título.",
    ["Gesture setup"] = "Configuração de gestos",
    ["Open Settings > Taps and gestures > Gesture manager, choose a gesture, then select Show Quick Dock."] = "Abra Definições > Toques e gestos > Gestor de gestos, escolha um gesto e selecione Mostrar Quick Dock.",
}, {
    __index = function(translations, msgid)
        local value = pt_BR[msgid]
        if not value then
            return nil
        end
        -- Keep shared phrases idiomatic in European Portuguese without
        -- repeating the entire catalog. Explicit entries above win.
        value = value:gsub("Explorador", "Navegador")
            :gsub("explorador", "navegador")
            :gsub("arquivos", "ficheiros")
            :gsub("arquivo", "ficheiro")
            :gsub("telas", "ecrãs")
            :gsub("tela", "ecrã")
            :gsub("controles", "controlos")
            :gsub("controle", "controlo")
            :gsub("Configurações", "Definições")
            :gsub("configurações", "definições")
            :gsub("porcentagem", "percentagem")
        rawset(translations, msgid, value)
        return value
    end,
})

local translations = locale:match("^pt_PT") and pt_PT or pt_BR

return setmetatable({
    ngettext = gettext.ngettext,
    pgettext = gettext.pgettext,
}, {
    __call = function(_, msgid)
        return translations[msgid] or gettext(msgid)
    end,
})
