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
    ["Icon shown below the frontlight warmth slider."] = "Ícone mostrado abaixo do controle deslizante de temperatura de cor.",
    ["Information panel switch"] = "Alternar painel de informações",
    ["Uses a dedicated icon for the visible reading, book statistics, or network information panel."] = "Usa um ícone específico para o painel de leitura, de estatísticas do livro ou de rede exibido.",
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
    ["Shows a separate chevron button above the dock for changing sides without opening the settings."] = "Mostra um botão de seta acima da dock para trocar de lado sem abrir as configurações.",
    ["Show close button"] = "Mostrar botão de fechar",
    ["Shows a separate close button above the dock using close.svg."] = "Mostra um botão de fechar separado acima da dock usando close.svg.",
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
    ["Change the size of buttons, icons, pagination controls, and lighting columns."] = "Altere o tamanho dos botões, ícones, controles de paginação e colunas de iluminação.",
    ["Uses the base dock dimensions."] = "Usa as dimensões básicas da dock.",
    ["Increases the dock dimensions by 20 percent."] = "Aumenta as dimensões da dock em 20%.",
    ["Increases the dock dimensions by 40 percent."] = "Aumenta as dimensões da dock em 40%.",
    ["Maximum dock height: %1%"] = "Altura máxima da dock: %1%",
    ["Limits the action and lighting columns to the selected percentage of the screen and paginates buttons when necessary."] = "Limita as colunas de ações e iluminação à porcentagem selecionada da tela e pagina os botões quando necessário.",
    ["Nearest screen edge"] = "Borda da tela mais próxima",
    ["Show reading information"] = "Mostrar informações de leitura",
    ["Shows book, chapter, daily reading, clock, and battery information on the screen edge opposite the dock."] = "Mostra informações do livro, capítulo, leitura diária, relógio e bateria na borda oposta à dock.",
    ["Show network information"] = "Mostrar informações da rede",
    ["Shows Wi-Fi state and the network details reported by KOReader in the information panel."] = "Mostra o estado do Wi-Fi e os detalhes de rede fornecidos pelo KOReader no painel de informações.",
    ["Show book statistics"] = "Mostrar estatísticas do livro",
    ["Shows the open book's reading time, remaining time, progress, daily average, reading speed, start date, and estimated end date, as recorded by KOReader's Statistics plugin."] = "Mostra o tempo de leitura, tempo restante, progresso, média diária, velocidade de leitura, data de início e data estimada de término do livro aberto, conforme registrado pelo plugin Estatísticas do KOReader.",
    ["Show book cover at the top"] = "Mostrar capa do livro no topo",
    ["Shows the open book's cover above the reading information and book statistics. The thumbnail is loaded once and reused while the document remains open."] = "Mostra a capa do livro aberto acima das informações de leitura e das estatísticas do livro. A miniatura é carregada uma vez e reutilizada enquanto o documento permanece aberto.",
    ["Panel text alignment: %1"] = "Alinhamento do texto do painel: %1",
    ["Aligns every line in the selected information panel, including the clock and battery."] = "Alinha todas as linhas do painel de informações, inclusive relógio e bateria.",
    ["Aligns left on the left edge and right on the right edge."] = "Alinha à esquerda na borda esquerda e à direita na borda direita.",
    ["Show frontlight control"] = "Mostrar controle de iluminação frontal",
    ["Shows the brightness slider and its light toggle button beside the dock on devices with a frontlight."] = "Mostra o controle deslizante de brilho e o botão de ligar/desligar a luz ao lado da dock em dispositivos com iluminação frontal.",
    ["Show warmth control"] = "Mostrar controle de temperatura de cor",
    ["Shows a second slider for frontlight warmth on supported devices."] = "Mostra um segundo controle deslizante para a temperatura de cor em dispositivos compatíveis.",
    ["Dock layout"] = "Layout da dock",
    ["Adjust the scale and maximum height of the dock."] = "Ajuste a escala e a altura máxima da dock.",
    ["Information panel"] = "Painel de informações",
    ["Choose the content and text alignment of the opposite-edge panel."] = "Escolha o conteúdo e o alinhamento do texto do painel na borda oposta.",
    ["Lighting controls"] = "Controles de iluminação",
    ["Show or hide the frontlight brightness and warmth columns."] = "Mostre ou oculte as colunas de brilho e temperatura de cor da iluminação frontal.",
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
    ["Controls dock layout, information panels, lighting columns, and custom icons."] = "Define o layout da dock, os painéis de informações, as colunas de iluminação e os ícones personalizados.",
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
    ["Shows book, chapter, daily reading, clock, and battery information on the screen edge opposite the dock."] = "Mostra informações do livro, capítulo, leitura diária, relógio e bateria na margem do ecrã oposta à dock.",
    ["Shows Wi-Fi state and the network details reported by KOReader in the information panel."] = "Mostra o estado do Wi-Fi e os detalhes da rede fornecidos pelo KOReader no painel de informações.",
    ["Nearest screen edge"] = "Margem do ecrã mais próxima",
    ["Warmth control"] = "Controlo de temperatura de cor",
    ["Show warmth control"] = "Mostrar controlo de temperatura de cor",
    ["Icon shown below the frontlight warmth slider."] = "Ícone mostrado abaixo do controlo deslizante de temperatura de cor.",
    ["Shows a second slider for frontlight warmth on supported devices."] = "Mostra um segundo controlo deslizante para a temperatura de cor em dispositivos compatíveis.",
    ["Show or hide the frontlight brightness and warmth columns."] = "Mostre ou oculte as colunas de brilho e temperatura de cor da iluminação frontal.",
    ["Shows a separate chevron button above the dock for changing sides without opening the settings."] = "Mostra um botão de seta acima da dock para trocar de lado sem abrir as definições.",
    ["Shows the open book's cover above the reading information and book statistics. The thumbnail is loaded once and reused while the document remains open."] = "Mostra a capa do livro aberto acima das informações de leitura e das estatísticas do livro. A miniatura é carregada uma vez e reutilizada enquanto o documento permanece aberto.",
    ["Restores the initial actions and their order without changing other Quick Dock settings."] = "Restaura as ações iniciais e a sua ordem sem alterar outras definições do Quick Dock.",
    ["Reset Quick Dock behavior to its defaults? Your actions and their order will be kept."] = "Restaurar o comportamento padrão do Quick Dock? As ações e a sua ordem serão mantidas.",
    ["Reset Quick Dock behavior and actions to their defaults? Appearance settings will be kept."] = "Restaurar o comportamento e as ações padrão do Quick Dock? As definições de aparência serão mantidas.",
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
