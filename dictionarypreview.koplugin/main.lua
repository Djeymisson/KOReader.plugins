local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local ButtonTable = require("ui/widget/buttontable")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Size = require("ui/size")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Event = require("ui/event")
local util = require("util")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Screen = Device.screen

-- O texto HTML do preview deve parecer parte da interface, não do livro.
-- Button/ButtonTable usam a fonte de UI "cfont" com tamanho base 20;
-- no HTML/MuPDF usamos Noto Sans, que é a fonte padrão equivalente na UI.
local UI_FONT_FACE = "Noto Sans"
local UI_FONT_SIZE = 20
local ICON_BUTTON_FONT_SIZE = 30
local KOREADER_ICON_SIZE = Screen:scaleBySize(28)

local DictionaryPreview = WidgetContainer:extend({
	name = "dictionarypreview",
	is_doc_only = true,
})

local function htmlEscape(text)
	text = tostring(text or "")
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	text = text:gsub('"', "&quot;")
	return text
end

local function looksLikeHtml(text)
	text = tostring(text or "")
	return text:find("<%s*[%a/][^>]*>") ~= nil
end

local function plainTextToHtml(text)
	text = tostring(text or "")
	text = htmlEscape(text)

	text = text:gsub("\r\n", "\n")
	text = text:gsub("\r", "\n")
	text = text:gsub("\n\n+", "</p><p>")
	text = text:gsub("\n", "<br/>")

	return "<p>" .. text .. "</p>"
end

local function normalizeDictionaryHtml(definition)
	definition = tostring(definition or "")

	if definition == "" then
		return "<p>" .. htmlEscape(_("No definition.")) .. "</p>"
	end

	-- Alguns dicionários já retornam HTML.
	-- Nesse caso, preservamos a formatação original:
	-- negrito, itálico, listas, exemplos, quebras etc.
	if looksLikeHtml(definition) then
		return definition
	end

	-- Caso venha texto puro, convertemos apenas quebras de linha.
	return plainTextToHtml(definition)
end

local function appendStyleAttr(attrs, style)
	attrs = attrs or ""

	if attrs:find("style%s*=") then
		attrs = attrs:gsub('style%s*=%s*"([^"]*)"', 'style="%1; ' .. style .. '"', 1)
		return attrs
	end

	return attrs .. ' style="' .. style .. '"'
end

local dictionary_class_styles = {
	hw = "font-size:1.15em; font-weight:bold;",
	ctx = "font-size:0.85em; font-style:italic;",
	pron = "font-size:0.9em;",
	gr = "font-size:0.85em; font-style:italic;",
	use = "font-size:0.85em; font-style:italic;",
	ge = "font-size:0.85em; font-style:italic;",
	la = "font-size:0.85em; font-style:italic;",
	d = "font-size:0.85em;",
	num = "font-size:0.95em; font-weight:bold;",
	rm = "font-size:1em; font-weight:bold;",
	s1 = "display:block; margin:0.15em 0 0.35em 0;",
	ib = "display:block; margin:0.25em 0 0.45em 0.8em; font-size:0.92em;",
	ql = "display:inline;",
	q = "display:inline;",
	a = "font-size:0.9em; font-weight:bold;",
	w = "font-size:0.9em; font-style:italic;",
	phg = "display:block; margin-top:0.6em; font-size:0.95em;",
	sub = "display:block; margin-left:0.8em; margin-top:0.15em;",
	et = "display:block; margin-top:0.5em; font-size:0.92em;",
	xr = "font-style:italic;",
}

local function buildStyleFromClassList(classes)
	local style_parts = {}

	for class_name in tostring(classes or ""):gmatch("%S+") do
		local style = dictionary_class_styles[class_name]
		if style then
			table.insert(style_parts, style)
		end
	end

	if #style_parts == 0 then
		return nil
	end

	return table.concat(style_parts, " ")
end

local function normalizeHeadingTags(html)
	-- Alguns dicionários usam <h2> para blocos longos de pronúncia/flexão.
	-- No FootnoteWidget, o tamanho padrão de h1-h6 pode ficar exagerado.
	-- Por isso, convertemos h1-h6 em div, preservando atributos e conteúdo.
	html = html:gsub("<%s*[hH][1-6]([^>]*)>", function(attrs)
		return "<div"
			.. appendStyleAttr(
				attrs,
				"font-size:1em; line-height:1.25; margin:0.35em 0 0.25em 0; font-weight:normal;"
			)
			.. ">"
	end)

	html = html:gsub("</%s*[hH][1-6]%s*>", "</div>")

	return html
end

local function normalizeDictionaryClasses(html)
	-- Versão otimizada: em vez de fazer um gsub para cada classe,
	-- percorremos as tags com class="..." uma única vez.
	return html:gsub('(<%w+)([^>]-class%s*=%s*"([^"]*)"[^>]*)(>)', function(tag, attrs, classes, close)
		local style = buildStyleFromClassList(classes)

		if style then
			return tag .. appendStyleAttr(attrs, style) .. close
		end

		return tag .. attrs .. close
	end)
end

local function normalizeDictionaryLists(html)
	html = html:gsub("<%s*[uU][lL]([^>]*)>", function(attrs)
		return "<ul" .. appendStyleAttr(attrs, "margin:0.25em 0 0.35em 1.1em; padding:0;") .. ">"
	end)

	html = html:gsub("<%s*[oO][lL]([^>]*)>", function(attrs)
		return "<ol" .. appendStyleAttr(attrs, "margin:0.25em 0 0.35em 1.1em; padding:0;") .. ">"
	end)

	html = html:gsub("<%s*[lL][iI]([^>]*)>", function(attrs)
		return "<li" .. appendStyleAttr(attrs, "margin:0.18em 0;") .. ">"
	end)

	return html
end

local function shouldNormalizeDictionaryPreviewHtml(html)
	-- Evita processamento desnecessário em dicionários simples.
	-- A normalização mais custosa só roda quando há sinais dos padrões problemáticos.
	return html:find("<%s*[hH][1-6]")
		or html:find('class%s*=%s*"hw"')
		or html:find('class%s*=%s*"pron"')
		or html:find('class%s*=%s*"ctx"')
		or html:find('class%s*=%s*"ib"')
		or html:find('class%s*=%s*"ql"')
		or html:find('class%s*=%s*"phg"')
end

local function normalizeDictionaryPreviewHtml(definition)
	local html = normalizeDictionaryHtml(definition)

	if not shouldNormalizeDictionaryPreviewHtml(html) then
		return html
	end

	html = normalizeHeadingTags(html)
	html = normalizeDictionaryClasses(html)
	html = normalizeDictionaryLists(html)

	return html
end


local FALLBACK_CSS = [[
@page {
    margin: 0;
    font-family: 'Noto Sans';
}
body {
    margin: 0;
    padding: 0;
    line-height: 1.3;
    font-family: 'Noto Sans';
}
p, h1, h2, h3, h4, h5, h6, ol, ul, dl, dd {
    margin: 0;
}
ul, ol {
    padding-left: 1.1em;
}
a {
    color: black;
}
.dictionarypreview-header {
    margin-bottom: 0.45em;
    font-size: 0.92em;
    font-weight: bold;
}
.dictionarypreview-separator {
    border-top: 1px solid #888;
    margin: 0.3em 0 0.45em 0;
}
]]

local function hasDictionaryCss(result)
    return result
        and result.css
        and result.css ~= ""
        and looksLikeHtml(result.definition)
end

local function getDictionaryPanelCss(result)
    local css_justify = G_reader_settings:nilOrTrue("dict_justify")
        and "text-align: justify;"
        or ""

    -- Base inspirado no painel original do dicionário: mantém margens zeradas,
    -- listas compactas e depois acrescenta o CSS que o próprio KOReader já
    -- anexou ao resultado do dicionário em result.css.
    local css = [[
@page {
    margin: 0;
    font-family: 'Noto Sans';
}
body {
    margin: 0;
    padding: 0;
    line-height: 1.3;
    font-family: 'Noto Sans';
]] .. css_justify .. [[
}
blockquote, dd {
    margin: 0 1em;
}
ol, ul, menu {
    margin: 0;
    padding: 0 1.7em;
}
a {
    color: black;
}
.dictionarypreview-header {
    margin-bottom: 0.45em;
    font-size: 0.92em;
    font-weight: bold;
}
.dictionarypreview-separator {
    border-top: 1px solid #888;
    margin: 0.3em 0 0.45em 0;
}
]]

    if result and result.css and result.css ~= "" then
        css = css .. "\n" .. result.css
    end

    return css
end


local function stripHtmlForLineEstimate(html)
    html = tostring(html or "")

    -- Transforma os principais blocos HTML em quebras de linha para estimar
    -- melhor quantas linhas visíveis o preview precisa mostrar.
    html = html:gsub("<%s*[bB][rR]%s*/?%s*>", "\n")
    html = html:gsub("</%s*[pP]%s*>", "\n")
    html = html:gsub("</%s*[dD][iI][vV]%s*>", "\n")
    html = html:gsub("</%s*[lL][iI]%s*>", "\n")
    html = html:gsub("</%s*[uU][lL]%s*>", "\n")
    html = html:gsub("</%s*[oO][lL]%s*>", "\n")
    html = html:gsub("</%s*[hH][1-6]%s*>", "\n")

    html = html:gsub("<[^>]+>", "")
    html = html:gsub("&nbsp;", " ")
    html = html:gsub("&amp;", "&")
    html = html:gsub("&lt;", "<")
    html = html:gsub("&gt;", ">")
    html = html:gsub("&quot;", '"')

    return html
end

local function estimateHtmlLineCount(html, content_width, font_size)
    local text = stripHtmlForLineEstimate(html)

    -- Estimativa conservadora para fontes proporcionais. O objetivo não é medir
    -- com precisão pixel a pixel, mas evitar que previews curtos de 2 ou 3 linhas
    -- acabem criando uma área rolável desnecessária.
    local average_char_width = math.max(1, font_size * 0.50)
    local chars_per_line = math.max(12, math.floor(content_width / average_char_width))

    local lines = 0
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"

    for raw_line in text:gmatch("(.-)\n") do
        local line = raw_line:gsub("^%s+", ""):gsub("%s+$", "")

        if line ~= "" then
            lines = lines + math.max(1, math.ceil(#line / chars_per_line))
        end
    end

    return math.max(1, lines)
end

local function getAdaptiveMinHtmlHeight(html, content_width, font_size, max_html_height)
    local estimated_lines = estimateHtmlLineCount(html, content_width, font_size)
    local line_height = math.ceil(font_size * 1.35)

    -- Para previews curtos, adicionamos uma folga maior. Isso evita o caso em que
    -- duas linhas de texto aparecem como uma linha visível + rolagem.
    local safety_lines = estimated_lines <= 3 and 1.25 or 0.75
    local estimated_height = math.ceil((estimated_lines + safety_lines) * line_height + Screen:scaleBySize(8))

    local base_height = math.max(Screen:scaleBySize(44), math.ceil(font_size * 2.2))
    local min_height = math.max(base_height, estimated_height)

    if max_html_height and max_html_height > 0 then
        min_height = math.min(max_html_height, min_height)
    end

    return min_height
end

local DictionaryPreviewPopup = InputContainer:extend({
    html_body = nil,
    css = nil,
    html_resource_directory = nil,
    dialog = nil,
    doc_font_size = Screen:scaleBySize(18),
    doc_margins = nil,
    open_callback = nil,
    search_callback = nil,
    prev_callback = nil,
    next_callback = nil,
    close_preview_callback = nil,
    result_index = 1,
    result_count = 1,
})

function DictionaryPreviewPopup:init()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    -- O painel ocupa toda a largura da tela, como o rodapé/footnote nativo.
    -- O afastamento lateral fica apenas no conteúdo interno, não na borda externa.
    self.width = screen_width

    local top_border_size = Size.line.thick
    local padding_top = Size.padding.default
    local padding_bottom = Size.padding.default
    local content_padding_left = Screen:scaleBySize(16)
    local content_padding_right = Screen:scaleBySize(12)
    local button_gap = Screen:scaleBySize(8)

    local max_popup_height = math.floor(screen_height * 0.38)

    self.doc_margins = self.doc_margins or {
        left = Screen:scaleBySize(20),
        right = Screen:scaleBySize(20),
        top = Screen:scaleBySize(10),
        bottom = Screen:scaleBySize(10),
    }

    if Device:isTouchDevice() then
        local range = Geom:new({
            x = 0,
            y = 0,
            w = screen_width,
            h = screen_height,
        })

        self.ges_events = {
            TapClose = {
                GestureRange:new({
                    ges = "tap",
                    range = range,
                }),
            },
            SwipeFollow = {
                GestureRange:new({
                    ges = "swipe",
                    range = range,
                }),
            },
        }
    end

    if Device:hasKeys() then
        self.key_events = {
            Close = {
                { Device.input.group.Back },
            },
            Follow = {
                { "Press" },
            },
        }
    end

    local content_width = self.width - content_padding_left - content_padding_right
    if content_width < Screen:scaleBySize(120) then
        content_width = Screen:scaleBySize(120)
    end

    local buttons = ButtonTable:new({
        width = content_width,
        show_parent = self,
        buttons = {
            {
                {
                    icon = "appbar.search",
                    icon_width = KOREADER_ICON_SIZE,
                    icon_height = KOREADER_ICON_SIZE,
                    callback = function()
                        return self:onSearchDocument()
                    end,
                },
                {
                    icon = "chevron.left",
                    icon_width = KOREADER_ICON_SIZE,
                    icon_height = KOREADER_ICON_SIZE,
                    callback = function()
                        return self:onPrevDictionary()
                    end,
                },
                {
                    icon = "chevron.right",
                    icon_width = KOREADER_ICON_SIZE,
                    icon_height = KOREADER_ICON_SIZE,
                    callback = function()
                        return self:onNextDictionary()
                    end,
                },
                {
                    icon = "chevron.up",
                    icon_width = KOREADER_ICON_SIZE,
                    icon_height = KOREADER_ICON_SIZE,
                    callback = function()
                        return self:onFollow()
                    end,
                },
            },
        },
    })

    local buttons_height = Screen:scaleBySize(48)
    local ok_buttons_size, buttons_size = pcall(function()
        return buttons:getSize()
    end)
    if ok_buttons_size and buttons_size and buttons_size.h then
        buttons_height = buttons_size.h
    end

    local fixed_height = top_border_size
        + padding_top
        + button_gap
        + buttons_height
        + padding_bottom

    local max_html_height = max_popup_height - fixed_height
    local min_html_height = getAdaptiveMinHtmlHeight(
        self.html_body,
        content_width,
        self.doc_font_size,
        max_html_height
    )

    if max_html_height < min_html_height then
        max_html_height = min_html_height
    end

    local scroll_bar_width = Screen:scaleBySize(6)
    local text_scroll_span = Screen:scaleBySize(8)

    local function makeHtmlWidget(height)
        return ScrollHtmlWidget:new({
            html_body = self.html_body,
            is_xhtml = true,
            css = self.css or FALLBACK_CSS,
            html_resource_directory = self.html_resource_directory,
            default_font_size = self.doc_font_size,
            width = content_width,
            height = height,
            scroll_bar_width = scroll_bar_width,
            text_scroll_span = text_scroll_span,
            dialog = self.dialog,
            highlight_text_selection = true,
        })
    end

    -- Primeiro renderizamos com a altura máxima para medir a altura real de uma página.
    -- Se a definição for curta, recriamos o widget com uma altura menor.
    local htmlwidget = makeHtmlWidget(max_html_height)
    local htmlwidget_height = max_html_height

    local ok_single_page_height, single_page_height = pcall(function()
        return htmlwidget:getSinglePageHeight()
    end)

    if ok_single_page_height and type(single_page_height) == "number" and single_page_height > 0 then
        local measurement_safety = math.ceil(self.doc_font_size * 0.75)
        htmlwidget_height = math.ceil(single_page_height + measurement_safety)
        htmlwidget_height = math.max(min_html_height, htmlwidget_height)
        htmlwidget_height = math.min(max_html_height, htmlwidget_height)
    end

    if htmlwidget_height < max_html_height then
        htmlwidget = makeHtmlWidget(htmlwidget_height)
    end

    self.htmlwidget = htmlwidget
    self.height = fixed_height + htmlwidget_height

    local vgroup = VerticalGroup:new({
        LineWidget:new({
            dimen = Geom:new({
                w = self.width,
                h = top_border_size,
            }),
        }),
        VerticalSpan:new({ width = padding_top }),
        HorizontalGroup:new({
            HorizontalSpan:new({ width = content_padding_left }),
            self.htmlwidget,
            HorizontalSpan:new({ width = content_padding_right }),
        }),
        VerticalSpan:new({ width = button_gap }),
        HorizontalGroup:new({
            HorizontalSpan:new({ width = content_padding_left }),
            buttons,
            HorizontalSpan:new({ width = content_padding_right }),
        }),
        VerticalSpan:new({ width = padding_bottom }),
    })

    self.container = FrameContainer:new({
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        margin = 0,
        padding = 0,
        vgroup,
    })

    self[1] = BottomContainer:new({
        dimen = Screen:getSize(),
        self.container,
    })
end

function DictionaryPreviewPopup:onShow()
    UIManager:setDirty(self.dialog, function()
        return "ui", self.container.dimen
    end)
end

function DictionaryPreviewPopup:onCloseWidget()
    UIManager:setDirty(self.dialog, function()
        return "partial", self.container.dimen
    end)
end

function DictionaryPreviewPopup:onClose()
    UIManager:close(self)
    if self.close_preview_callback then
        return self.close_preview_callback()
    end
    return true
end

function DictionaryPreviewPopup:onClosePreview()
    UIManager:close(self)
    if self.close_preview_callback then
        return self.close_preview_callback()
    end
    return true
end

function DictionaryPreviewPopup:onSearchDocument()
    UIManager:close(self)
    if self.search_callback then
        return self.search_callback()
    end
    return true
end

function DictionaryPreviewPopup:onPrevDictionary()
    if not self.result_count or self.result_count <= 1 then
        return true
    end

    UIManager:close(self)

    if self.prev_callback then
        return self.prev_callback()
    end

    return true
end

function DictionaryPreviewPopup:onNextDictionary()
    if not self.result_count or self.result_count <= 1 then
        return true
    end

    UIManager:close(self)

    if self.next_callback then
        return self.next_callback()
    end

    return true
end

function DictionaryPreviewPopup:onFollow()
    UIManager:close(self)
    if self.open_callback then
        return self.open_callback()
    end
    return true
end

function DictionaryPreviewPopup:onTapClose(_arg, ges)
    if ges
        and ges.pos
        and self.container
        and self.container.dimen
        and ges.pos:notIntersectWith(self.container.dimen)
    then
        return self:onClosePreview()
    end

    -- Toques dentro do conteúdo não abrem automaticamente o popup completo.
    -- Assim o usuário pode rolar/selecionar texto e usar os botões do rodapé.
    return false
end

function DictionaryPreviewPopup:onSwipeFollow(_arg, ges)
    if not ges or not ges.direction then
        return false
    end

    -- Navegação por gesto:
    -- - deslizar para a esquerda: próximo dicionário
    -- - deslizar para a direita: dicionário anterior
    -- - deslizar para baixo: fechar preview
    if ges.direction == "west" then
        return self:onNextDictionary()
    elseif ges.direction == "east" then
        return self:onPrevDictionary()
    elseif ges.direction == "south" then
        return self:onClosePreview()
    end

    return false
end

function DictionaryPreview:init()
	self.enabled = G_reader_settings:nilOrTrue("dictionarypreview_enabled")
	self.current_popup = nil
	self.original_showDict = nil
	self.patched_dictionary = nil
	self.opening_original_popup = false
	-- Enquanto o popup nativo/original do dicionário estiver aberto,
	-- não abrimos previews. Isso evita que uma seleção feita dentro do
	-- DictQuickLookup original crie um segundo painel no rodapé.
	self.native_dict_popup_active = false
	self.native_dict_popup_count = 0

	if self.ui and self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end

	self:patchDictionary()
end

function DictionaryPreview:addToMainMenu(menu_items)
	menu_items.dictionarypreview = {
		text = _("Dictionary preview"),
		sorting_hint = "more_tools",

		checked_func = function()
			return self.enabled
		end,

		callback = function()
			self.enabled = not self.enabled
			G_reader_settings:saveSetting("dictionarypreview_enabled", self.enabled)
		end,
	}
end

function DictionaryPreview:patchDictionary()
	local dictionary = self.ui and self.ui.dictionary

	if not dictionary then
		logger.warn("DictionaryPreview: ReaderDictionary not available.")
		return
	end

	if dictionary._dictionarypreview_patched then
		return
	end

	self.original_showDict = dictionary.showDict
	self.patched_dictionary = dictionary

	local plugin = self

	dictionary.showDict = function(dict_self, word, results, boxes, link, dict_close_callback)
		if
			not plugin.enabled
			or plugin.opening_original_popup
			or not results
			or not results[1]
		then
			return plugin.original_showDict(dict_self, word, results, boxes, link, dict_close_callback)
		end

		-- Se o popup original do dicionário já estiver aberto, significa que
		-- o usuário pode estar selecionando texto dentro dele. Nesse cenário,
		-- mantemos o comportamento nativo do KOReader e não mostramos preview.
		if plugin.native_dict_popup_active then
			local wrapped_close_callback = plugin:beginNativeDictionaryPopup(dict_close_callback)
			return plugin.original_showDict(dict_self, word, results, boxes, link, wrapped_close_callback)
		end

		if dict_self.dismissLookupInfo then
			pcall(function()
				dict_self:dismissLookupInfo()
			end)
		end

		return plugin:showFootnotePreview(dict_self, word, results, boxes, link, dict_close_callback)
	end

	dictionary._dictionarypreview_patched = true
end

function DictionaryPreview:beginNativeDictionaryPopup(dict_close_callback)
	self.native_dict_popup_count = (self.native_dict_popup_count or 0) + 1
	self.native_dict_popup_active = true

	local plugin = self
	local closed = false

	return function(...)
		if not closed then
			closed = true
			plugin.native_dict_popup_count = math.max(0, (plugin.native_dict_popup_count or 1) - 1)
			plugin.native_dict_popup_active = plugin.native_dict_popup_count > 0
		end

		if dict_close_callback then
			return dict_close_callback(...)
		end
	end
end

function DictionaryPreview:resetNativeDictionaryPopupGuard()
	self.native_dict_popup_count = 0
	self.native_dict_popup_active = false
end

function DictionaryPreview:showOriginalDictionaryPopup(dict_self, word, results, boxes, link, dict_close_callback)
	if not self.original_showDict then
		return
	end

	self.opening_original_popup = true
	local wrapped_close_callback = self:beginNativeDictionaryPopup(dict_close_callback)

	local ok, err = pcall(function()
		self.original_showDict(dict_self, word, results, boxes, link, wrapped_close_callback)
	end)

	self.opening_original_popup = false

	if not ok then
		self:resetNativeDictionaryPopupGuard()
		logger.warn("DictionaryPreview: failed to open original dictionary popup:", err)
	end
end

function DictionaryPreview:clearOriginalHighlight(dict_self)
	local highlight = dict_self and dict_self.highlight

	if not highlight then
		return
	end

	local ok, clear_id = pcall(function()
		return highlight:getClearId()
	end)

	if ok and clear_id then
		pcall(function()
			highlight:clear(clear_id)
		end)
	else
		pcall(function()
			highlight:clear()
		end)
	end

	dict_self.highlight = nil
end

function DictionaryPreview:clearSelection()
	if self.ui and self.ui.handleEvent then
		pcall(function()
			self.ui:handleEvent(Event:new("ClearSelection"))
		end)
	end
end

function DictionaryPreview:getDocumentFontName(dict_self)
	if dict_self and dict_self.ui and dict_self.ui.font and dict_self.ui.font.font_face then
		return dict_self.ui.font.font_face
	end

	return "Noto Sans"
end

function DictionaryPreview:getInterfaceFontSize()
	return Screen:scaleBySize(UI_FONT_SIZE)
end

function DictionaryPreview:getDocumentMargins(dict_self)
	if dict_self and dict_self.ui and dict_self.ui.document and dict_self.ui.document.getPageMargins then
		local ok, margins = pcall(function()
			return dict_self.ui.document:getPageMargins()
		end)

		if ok and margins then
			return margins
		end
	end

	return {
		left = Screen:scaleBySize(20),
		right = Screen:scaleBySize(20),
		top = Screen:scaleBySize(10),
		bottom = Screen:scaleBySize(10),
	}
end

function DictionaryPreview:getSearchText(word, result)
    result = result or {}

    local text = word or result.word or ""

    if type(text) == "table" then
        text = text.text or text.word or ""
    end

    text = tostring(text or "")

    if util and util.stripPunctuation then
        local ok, stripped = pcall(function()
            return util.stripPunctuation(text)
        end)

        if ok and stripped and stripped ~= "" then
            text = stripped
        end
    end

    text = text:gsub("^%s+", ""):gsub("%s+$", "")

    return text
end

function DictionaryPreview:showSearchDialog(search_text)
    search_text = tostring(search_text or "")
    search_text = search_text:gsub("^%s+", ""):gsub("%s+$", "")

    if search_text == "" then
        return true
    end

    local function openSearchInput()
        -- Preferimos abrir a janela de entrada da busca já preenchida.
        -- ReaderSearch:onShowFulltextSearchInput(search_string) usa esse argumento
        -- diretamente como texto inicial do campo de busca.
        if self.ui
            and self.ui.search
            and type(self.ui.search.onShowFulltextSearchInput) == "function"
        then
            local ok, err = pcall(function()
                self.ui.search:onShowFulltextSearchInput(search_text)
            end)

            if ok then
                return true
            end

            logger.warn("DictionaryPreview: direct search input failed:", err)
        end

        -- Fallback: dispara o evento equivalente para o módulo ReaderSearch.
        if self.ui and self.ui.handleEvent then
            local ok, err = pcall(function()
                self.ui:handleEvent(Event:new("ShowFulltextSearchInput", search_text))
            end)

            if ok then
                return true
            end

            logger.warn("DictionaryPreview: search input event failed:", err)
        end

        -- Último fallback: executa a busca diretamente e mostra o painel de navegação
        -- dos resultados. Isso não abre o campo de texto, mas garante a busca.
        if self.ui
            and self.ui.search
            and type(self.ui.search.searchText) == "function"
        then
            local ok, err = pcall(function()
                self.ui.search:searchText(search_text)
            end)

            if ok then
                return true
            end

            logger.warn("DictionaryPreview: direct search execution failed:", err)
        end

        if self.ui and self.ui.handleEvent then
            local ok, err = pcall(function()
                self.ui:handleEvent(Event:new("ShowSearchDialog", search_text, 0, false, true))
            end)

            if not ok then
                logger.warn("DictionaryPreview: search dialog fallback failed:", err)
            end
        end

        return true
    end

    -- Abrir a busca no próximo ciclo evita conflito de foco entre o fechamento
    -- do preview e a abertura do InputDialog/teclado.
    local ok_schedule = pcall(function()
        UIManager:scheduleIn(0.05, openSearchInput)
    end)

    if not ok_schedule then
        openSearchInput()
    end

    return true
end

function DictionaryPreview:buildPreviewPayload(word, result, result_index, result_count)
	result = result or {}

	local shown_word = result.word or word or _("Dictionary")
	local dict_name = result.dict or _("Dictionary")

    if result.no_result then
        dict_name = _("Dictionary")
    elseif result_count and result_count > 1 then
        dict_name = string.format("%s (%d/%d)", dict_name, result_index or 1, result_count)
    end

	local use_dictionary_css = hasDictionaryCss(result)
	local definition_html
	local css

    if result.no_result then
        definition_html = "<p>" .. htmlEscape(_("No definition found.")) .. "</p>"
        css = FALLBACK_CSS
	elseif use_dictionary_css then
		-- Quando o resultado já traz CSS do dicionário, usamos o HTML cru,
		-- como o painel original do dicionário. Isso preserva tamanhos,
		-- espaçamentos, classes e recursos relativos do dicionário.
		definition_html = normalizeDictionaryHtml(result.definition)
		css = getDictionaryPanelCss(result)
	else
		-- Fallback para dicionários sem CSS próprio ou entradas de texto puro.
		-- Mantém a normalização que corrige <h2> grandes e classes comuns.
		definition_html = normalizeDictionaryPreviewHtml(result.definition)
		css = FALLBACK_CSS
	end

	local html_body = table.concat({
		'<div class="dictionarypreview-header">',
		htmlEscape(shown_word),
		" — ",
		htmlEscape(dict_name),
		"</div>",

		'<div class="dictionarypreview-separator"></div>',

		definition_html,
	}, "\n")

	return {
		html_body = html_body,
		css = css,
		html_resource_directory = result.dictionary_resource_directory,
	}
end

local function getResultCount(results)
    if type(results) ~= "table" then
        return 0
    end

    return #results
end

local function normalizeResultIndex(index, count)
    if not count or count <= 0 then
        return 1
    end

    index = tonumber(index) or 1

    if index < 1 then
        return count
    elseif index > count then
        return 1
    end

    return index
end

local function reorderResultsFromIndex(results, index)
    local count = getResultCount(results)

    if count <= 1 or index == 1 then
        return results
    end

    local reordered = {}

    for i = index, count do
        table.insert(reordered, results[i])
    end

    for i = 1, index - 1 do
        table.insert(reordered, results[i])
    end

    return reordered
end

function DictionaryPreview:showFootnotePreview(dict_self, word, results, boxes, link, dict_close_callback)
	local result_count = getResultCount(results)

    if result_count <= 0 then
        return true
    end

	if self.current_popup then
		UIManager:close(self.current_popup)
		self.current_popup = nil
	end

	local popup
	local opened_full_popup = false
    local current_index = 1

    local function closeCurrentPopup()
        if popup then
            pcall(function()
                UIManager:close(popup)
            end)
            popup = nil
        end

        self.current_popup = nil
    end

	local function openFullPopup(index)
		opened_full_popup = true

		closeCurrentPopup()

        local selected_results = reorderResultsFromIndex(results, normalizeResultIndex(index or current_index, result_count))
		self:showOriginalDictionaryPopup(dict_self, word, selected_results, boxes, link, dict_close_callback)

		return true
	end

    local function showResult(index)
        current_index = normalizeResultIndex(index, result_count)
        local result = results[current_index] or results[1] or {}
        local search_text = self:getSearchText(word, result)

        closeCurrentPopup()

        local preview_payload = self:buildPreviewPayload(word, result, current_index, result_count)

        popup = DictionaryPreviewPopup:new({
            html_body = preview_payload.html_body,
            css = preview_payload.css,
            html_resource_directory = preview_payload.html_resource_directory,
            doc_font_size = self:getInterfaceFontSize(),
            doc_margins = self:getDocumentMargins(dict_self),
            dialog = dict_self and dict_self.dialog,
            result_index = current_index,
            result_count = result_count,
            open_callback = function()
                return openFullPopup(current_index)
            end,
            search_callback = function()
                self.current_popup = nil
                self:clearOriginalHighlight(dict_self)
                self:clearSelection()

                if dict_close_callback then
                    pcall(dict_close_callback)
                end

                return self:showSearchDialog(search_text)
            end,
            prev_callback = function()
                return showResult(current_index - 1)
            end,
            next_callback = function()
                return showResult(current_index + 1)
            end,
            close_preview_callback = function()
                if not opened_full_popup then
                    self.current_popup = nil
                    self:clearOriginalHighlight(dict_self)
                    self:clearSelection()

                    if dict_close_callback then
                        pcall(dict_close_callback)
                    end
                end

                return true
            end,
        })

        self.current_popup = popup
        UIManager:show(popup)

        return true
    end

    return showResult(1)
end

function DictionaryPreview:destroy()
	if self.current_popup then
		UIManager:close(self.current_popup)
		self.current_popup = nil
	end

	if self.patched_dictionary and self.original_showDict and self.patched_dictionary._dictionarypreview_patched then
		self.patched_dictionary.showDict = self.original_showDict
		self.patched_dictionary._dictionarypreview_patched = nil
	end

	self.original_showDict = nil
	self.patched_dictionary = nil
	self:resetNativeDictionaryPopupGuard()

	if WidgetContainer.destroy then
		WidgetContainer.destroy(self)
	end
end

return DictionaryPreview
