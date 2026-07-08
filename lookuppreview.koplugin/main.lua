local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Notification = require("ui/widget/notification")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local Translator = require("ui/translator")
local util = require("util")
local logger = require("logger")
local _ = require("gettext")

local Screen = Device.screen
local IS_TOUCH_DEVICE = Device:isTouchDevice()
local HAS_KEYS = Device:hasKeys()

local LookupPreview = WidgetContainer:extend({
    name = "lookuppreview",
    is_doc_only = true,
})

local PLUGIN_VERSION = "v0.1.0"

local UI_FONT_FACE = "Noto Sans"
local UI_FONT_SIZE = 20
local TITLE_FONT_SIZE = math.max(12, UI_FONT_SIZE - 3)
local SUBTITLE_FONT_SIZE = math.max(10, UI_FONT_SIZE - 6)
local BODY_FONT_SIZE = Screen:scaleBySize(18)
local TITLE_FACE = Font:getFace("cfont", TITLE_FONT_SIZE)
local SUBTITLE_FACE = Font:getFace("cfont", SUBTITLE_FONT_SIZE)

local CARD_WIDTH_RATIO = 0.92
local CARD_HEIGHT_RATIO = 0.38
local CARD_MIN_WIDTH = Screen:scaleBySize(220)
local CARD_GAP = Screen:scaleBySize(8)
local CARD_EDGE_MARGIN = Screen:scaleBySize(10)
local CARD_BORDER_SIZE = Size.border.thin
local CARD_RADIUS = nil
local CARD_PADDING_H = Screen:scaleBySize(14)
local CARD_PADDING_TOP = Screen:scaleBySize(10)
local CARD_PADDING_BOTTOM = Screen:scaleBySize(8)
local HEADER_GAP = Screen:scaleBySize(2)
local HEADER_SEPARATOR_GAP = Screen:scaleBySize(5)
local SCROLL_BAR_WIDTH = Screen:scaleBySize(6)
local TEXT_SCROLL_SPAN = Screen:scaleBySize(8)
local FLOATING_SELECTION_GAP = Screen:scaleBySize(8)
local MIN_HTML_HEIGHT = Screen:scaleBySize(72)
local EMPTY_TEXT = "—"

local SETTING_ENABLED = "lookuppreview_enabled"
local SETTING_WIKI_LANG = "lookuppreview_wikipedia_lang"

local PAGE_DICTIONARY = 1
local PAGE_TRANSLATION = 2
local PAGE_WIKIPEDIA = 3

local PAGE_TITLES = {
    [PAGE_DICTIONARY] = _("Dictionary"),
    [PAGE_TRANSLATION] = _("Translation"),
    [PAGE_WIKIPEDIA] = _("Wikipedia"),
}

local FALLBACK_CSS = [[
@page {
    margin: 0;
    font-family: ']] .. UI_FONT_FACE .. [[';
}
body {
    margin: 0;
    padding: 0;
    line-height: 1.32;
    font-family: ']] .. UI_FONT_FACE .. [[';
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
.lp-muted {
    color: #666666;
    font-size: 0.88em;
}
.lp-title {
    font-weight: bold;
    font-size: 1.05em;
    margin-bottom: 0.25em;
}
.lp-source {
    margin-top: 0.5em;
    color: #555555;
    font-size: 0.86em;
}
]]

local CLASS_STYLE_CACHE = {}
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

local function trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function htmlEscape(text)
    text = tostring(text or "")
    text = text:gsub("&", "&amp;")
    text = text:gsub("<", "&lt;")
    text = text:gsub(">", "&gt;")
    text = text:gsub('"', "&quot;")
    return text
end

local function looksLikeHtml(text)
    return tostring(text or ""):find("<%s*[%a/][^>]*>") ~= nil
end

local function plainTextToHtml(text)
    text = htmlEscape(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("\n\n+", "</p><p>"):gsub("\n", "<br/>")
    return "<p>" .. text .. "</p>"
end

local function copyTable(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[copyTable(key, seen)] = copyTable(item, seen)
    end
    return copy
end

local function appendStyleAttr(attrs, style)
    attrs = attrs or ""
    if attrs:find("style%s*=") then
        return attrs:gsub('style%s*=%s*"([^"]*)"', 'style="%1; ' .. style .. '"', 1)
    end
    return attrs .. ' style="' .. style .. '"'
end

local function normalizeDictionaryHtml(definition)
    definition = tostring(definition or "")
    if definition == "" then
        return "<p>" .. htmlEscape(_("No definition.")) .. "</p>"
    end
    if looksLikeHtml(definition) then
        return definition
    end
    return plainTextToHtml(definition)
end

local function buildStyleFromClassList(classes)
    classes = tostring(classes or "")
    local cached = CLASS_STYLE_CACHE[classes]
    if cached ~= nil then
        return cached or nil
    end
    local style_parts = {}
    for class_name in classes:gmatch("%S+") do
        local style = dictionary_class_styles[class_name]
        if style then
            style_parts[#style_parts + 1] = style
        end
    end
    local result = #style_parts > 0 and table.concat(style_parts, " ") or false
    CLASS_STYLE_CACHE[classes] = result
    return result or nil
end

local function normalizeHeadingTags(html)
    html = html:gsub("<%s*[hH][1-6]([^>]*)>", function(attrs)
        return "<div" .. appendStyleAttr(attrs, "font-size:1em; line-height:1.25; margin:0.35em 0 0.25em 0; font-weight:normal;") .. ">"
    end)
    return html:gsub("</%s*[hH][1-6]%s*>", "</div>")
end

local function normalizeDictionaryClasses(html)
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
    return html:gsub("<%s*[lL][iI]([^>]*)>", function(attrs)
        return "<li" .. appendStyleAttr(attrs, "margin:0.18em 0;") .. ">"
    end)
end

local function shouldNormalizeDictionaryPreviewHtml(html)
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
    return normalizeDictionaryLists(html)
end

local function getDictionaryPanelCss(result)
    local css_justify = G_reader_settings:nilOrTrue("dict_justify") and "text-align: justify;" or ""
    local css = [[
@page {
    margin: 0;
    font-family: ']] .. UI_FONT_FACE .. [[';
}
body {
    margin: 0;
    padding: 0;
    line-height: 1.3;
    font-family: ']] .. UI_FONT_FACE .. [[';
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
]]
    if result and result.css and result.css ~= "" then
        css = css .. "\n" .. result.css
    end
    return css
end

local function hasDictionaryCss(result)
    return result and result.css and result.css ~= "" and looksLikeHtml(result.definition)
end

local function stripHtmlForLineEstimate(html)
    html = tostring(html or "")
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

local function estimateHtmlHeight(html, content_width, font_size, max_height)
    local text = stripHtmlForLineEstimate(html)
    local average_char_width = math.max(1, font_size * 0.50)
    local chars_per_line = math.max(12, math.floor(content_width / average_char_width))
    local lines = 0
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"
    for raw_line in text:gmatch("(.-)\n") do
        local line = trim(raw_line)
        if line ~= "" then
            lines = lines + math.max(1, math.ceil(#line / chars_per_line))
        end
    end
    lines = math.max(1, lines)
    local line_height = math.ceil(font_size * 1.30)
    local safety = lines <= 2 and Screen:scaleBySize(8) or Screen:scaleBySize(18)
    local estimated_height = math.ceil(lines * line_height + safety)
    local height = math.max(MIN_HTML_HEIGHT, estimated_height)
    if max_height and max_height > 0 then
        height = math.max(1, math.min(max_height, height))
    end
    return height
end

local function getSelectionBounds(boxes)
    if type(boxes) ~= "table" or #boxes == 0 then
        return nil
    end
    local top
    local bottom
    for _, box in ipairs(boxes) do
        if type(box) == "table" and box.y and box.h then
            local box_top = tonumber(box.y)
            local box_height = tonumber(box.h)
            local box_bottom = box_top and box_height and (box_top + box_height)
            if box_top and box_bottom then
                top = top and math.min(top, box_top) or box_top
                bottom = bottom and math.max(bottom, box_bottom) or box_bottom
            end
        end
    end
    if not top or not bottom then
        return nil
    end
    return { top = top, bottom = bottom }
end

local function extractMainTranslation(result)
    if not (result and type(result) == "table" and type(result[1]) == "table") then
        return ""
    end
    local translated = {}
    for _, r in ipairs(result[1]) do
        if type(r) == "table" and type(r[1]) == "string" and r[1] ~= "" then
            translated[#translated + 1] = r[1]
        end
    end
    return trim(table.concat(translated, " "))
end

local function getWidgetSize(widget)
    local ok, size = pcall(function()
        return widget:getSize()
    end)
    if ok and size then
        return size
    end
    return Geom:new({ w = 0, h = 0 })
end

local CarouselRow = InputContainer:extend({
    popup = nil,
    active_index = PAGE_DICTIONARY,
    screen_width = nil,
    card_width = nil,
    card_height = nil,
    cards = nil,
    active_card = nil,
    active_container = nil,
    positions = nil,
})

function CarouselRow:init()
    self.screen_width = self.screen_width or Screen:getWidth()
    self.card_width = self.card_width or math.floor(self.screen_width * CARD_WIDTH_RATIO)
    self.card_height = self.card_height or math.floor(Screen:getHeight() * CARD_HEIGHT_RATIO)
    self.active_index = self.active_index or PAGE_DICTIONARY
    self.dimen = Geom:new({ x = 0, y = 0, w = self.screen_width, h = self.card_height })
    self.cards = {}

    local popup = self.popup
    if popup then
        for index = PAGE_DICTIONARY, PAGE_WIKIPEDIA do
            if math.abs(index - self.active_index) <= 1 then
                local payload = popup.plugin:getPagePayload(popup.state, index, index == self.active_index)
                local card = popup:makeCard(payload, self.card_width, self.card_height)
                self.cards[index] = card

                if index == self.active_index then
                    self.active_card = card
                end
            end
        end
    end

    local active_x = math.floor((self.screen_width - self.card_width) / 2)
    self.positions = {
        [self.active_index - 1] = active_x - self.card_width - CARD_GAP,
        [self.active_index] = active_x,
        [self.active_index + 1] = active_x + self.card_width + CARD_GAP,
    }

    -- The centered card must also be part of the widget tree, otherwise
    -- widgets inside it (notably ScrollHtmlWidget) are painted but don't
    -- reliably receive touch/pan events.
    if self.active_card then
        self.active_container = CenterContainer:new({
            dimen = self.dimen,
            self.active_card,
        })
        self[1] = self.active_container
    end
end
function CarouselRow:getSize()
    return self.dimen
end

function CarouselRow:paintCard(bb, base_x, base_y, index)
    local card = self.cards and self.cards[index]
    local card_x = self.positions and self.positions[index]
    if not card or not card_x then
        return
    end

    local x = (base_x or 0) + card_x
    local y = base_y or 0

    if card.dimen then
        card.dimen.x = x
        card.dimen.y = y
        card.dimen.w = self.card_width
        card.dimen.h = self.card_height
    end

    card:paintTo(bb, x, y)
end

function CarouselRow:paintTo(bb, x, y)
    x = x or (self.dimen and self.dimen.x) or 0
    y = y or (self.dimen and self.dimen.y) or 0

    -- Draw side cards first. They keep their full size and are simply clipped
    -- by the screen edge. The active card is painted through active_container
    -- so it remains a real child widget and can handle scrolling.
    self:paintCard(bb, x, y, self.active_index - 1)
    self:paintCard(bb, x, y, self.active_index + 1)

    if self.active_container then
        self.active_container:paintTo(bb, x, y)
    else
        self:paintCard(bb, x, y, self.active_index)
    end
end
local LookupPreviewPopup = InputContainer:extend({
    plugin = nil,
    state = nil,
    active_index = PAGE_DICTIONARY,
    selection_bounds = nil,
    dialog = nil,
    anchor_top = false,
    card_container = nil,
    visible_dimen = nil,
})

function LookupPreviewPopup:shouldAnchorTop(row_height)
    local bounds = self.selection_bounds
    if type(bounds) ~= "table" or not bounds.top or not bounds.bottom then
        return false
    end

    local screen_height = Screen:getHeight()
    local top_card_bottom = CARD_EDGE_MARGIN + row_height
    local bottom_card_top = screen_height - CARD_EDGE_MARGIN - row_height

    if bottom_card_top > bounds.bottom + FLOATING_SELECTION_GAP then
        return false
    end
    if top_card_bottom < bounds.top - FLOATING_SELECTION_GAP then
        return true
    end

    local space_above = math.max(0, bounds.top - CARD_EDGE_MARGIN - FLOATING_SELECTION_GAP)
    local space_below = math.max(0, screen_height - bounds.bottom - CARD_EDGE_MARGIN - FLOATING_SELECTION_GAP)
    return space_above > space_below
end

function LookupPreviewPopup:makeHeader(payload, content_width)
    local title = TextWidget:new({
        text = payload.title or EMPTY_TEXT,
        face = TITLE_FACE,
        bold = true,
        max_width = content_width,
    })

    local items = { title }
    if payload.subtitle and payload.subtitle ~= "" then
        items[#items + 1] = VerticalSpan:new({ width = HEADER_GAP })
        items[#items + 1] = TextWidget:new({
            text = payload.subtitle,
            face = SUBTITLE_FACE,
            max_width = content_width,
        })
    end

    items[#items + 1] = VerticalSpan:new({ width = HEADER_SEPARATOR_GAP })
    items[#items + 1] = LineWidget:new({
        background = Blitbuffer.COLOR_GRAY,
        dimen = Geom:new({ w = content_width, h = math.max(1, Screen:scaleBySize(1)) }),
    })
    items[#items + 1] = VerticalSpan:new({ width = HEADER_SEPARATOR_GAP })

    return VerticalGroup:new(items)
end

function LookupPreviewPopup:makeCard(payload, card_width, card_height)
    local content_width = math.max(1, card_width - 2 * CARD_PADDING_H - 2 * CARD_BORDER_SIZE)
    local header = self:makeHeader(payload, content_width)
    local header_height = getWidgetSize(header).h or Screen:scaleBySize(46)
    local html_height = math.max(
        MIN_HTML_HEIGHT,
        card_height - header_height - CARD_PADDING_TOP - CARD_PADDING_BOTTOM - 2 * CARD_BORDER_SIZE
    )

    local html_widget = ScrollHtmlWidget:new({
        html_body = payload.html_body or "",
        is_xhtml = true,
        css = payload.css or FALLBACK_CSS,
        html_resource_directory = payload.html_resource_directory,
        default_font_size = BODY_FONT_SIZE,
        width = content_width,
        height = html_height,
        scroll_bar_width = SCROLL_BAR_WIDTH,
        text_scroll_span = TEXT_SCROLL_SPAN,
        dialog = self.dialog,
        highlight_text_selection = false,
    })

    local content = VerticalGroup:new({
        VerticalSpan:new({ width = CARD_PADDING_TOP }),
        HorizontalGroup:new({
            HorizontalSpan:new({ width = CARD_PADDING_H }),
            header,
            HorizontalSpan:new({ width = CARD_PADDING_H }),
        }),
        HorizontalGroup:new({
            HorizontalSpan:new({ width = CARD_PADDING_H }),
            html_widget,
            HorizontalSpan:new({ width = CARD_PADDING_H }),
        }),
        VerticalSpan:new({ width = CARD_PADDING_BOTTOM }),
    })

    local card = FrameContainer:new({
        background = Blitbuffer.COLOR_WHITE,
        bordersize = CARD_BORDER_SIZE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        radius = CARD_RADIUS,
        margin = 0,
        padding = 0,
        content,
    })

    return card, Geom:new({ w = card_width, h = card_height })
end

function LookupPreviewPopup:makeRow(card_width, card_height)
    local row = CarouselRow:new({
        popup = self,
        active_index = self.active_index or PAGE_DICTIONARY,
        screen_width = Screen:getWidth(),
        card_width = card_width,
        card_height = card_height,
    })

    return row, card_height
end

function LookupPreviewPopup:init()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local card_height = math.floor(screen_height * CARD_HEIGHT_RATIO)
    local card_width = math.max(CARD_MIN_WIDTH, math.floor(screen_width * CARD_WIDTH_RATIO))
    card_width = math.min(card_width, screen_width - 2 * CARD_EDGE_MARGIN)

    if IS_TOUCH_DEVICE then
        local range = Geom:new({ x = 0, y = 0, w = screen_width, h = screen_height })
        self.ges_events = {
            TapClose = { GestureRange:new({ ges = "tap", range = range }) },
            SwipePage = { GestureRange:new({ ges = "swipe", range = range }) },
        }
    end

    if HAS_KEYS then
        self.key_events = {
            Close = { { Device.input.group.Back } },
        }
    end

    local row, row_height = self:makeRow(card_width, card_height)
    self.card_container = row
    self.anchor_top = self:shouldAnchorTop(row_height)

    local y
    if self.anchor_top then
        y = CARD_EDGE_MARGIN
        self[1] = TopContainer:new({
            dimen = Screen:getSize(),
            VerticalGroup:new({
                VerticalSpan:new({ width = CARD_EDGE_MARGIN }),
                row,
            }),
        })
    else
        y = screen_height - CARD_EDGE_MARGIN - row_height
        self[1] = BottomContainer:new({
            dimen = Screen:getSize(),
            VerticalGroup:new({
                row,
                VerticalSpan:new({ width = CARD_EDGE_MARGIN }),
            }),
        })
    end

    self.visible_dimen = Geom:new({ x = 0, y = y, w = screen_width, h = row_height })
end

function LookupPreviewPopup:onShow()
    UIManager:setDirty(self.dialog or self, function()
        return "ui", self.visible_dimen or Screen:getSize()
    end)
end

function LookupPreviewPopup:onCloseWidget()
    UIManager:setDirty(self.dialog or self, function()
        return "partial", self.visible_dimen or Screen:getSize()
    end)
end

function LookupPreviewPopup:onClose()
    UIManager:close(self)
    if not self.skip_close_callback and self.plugin then
        return self.plugin:closePreview(false)
    end
    return true
end

function LookupPreviewPopup:onTapClose(_arg, ges)
    if ges and ges.pos and self.visible_dimen and ges.pos:notIntersectWith(self.visible_dimen) then
        return self:onClose()
    end
    return false
end

function LookupPreviewPopup:onSwipePage(_arg, ges)
    if not ges or not ges.direction then
        return false
    end

    if ges.direction == "west" then
        return self.plugin:switchToPage(math.min(PAGE_WIKIPEDIA, self.active_index + 1))
    elseif ges.direction == "east" then
        return self.plugin:switchToPage(math.max(PAGE_DICTIONARY, self.active_index - 1))
    end

    -- Do not close on vertical swipes. Vertical movement must remain available
    -- to ScrollHtmlWidget so dictionary/translation/Wikipedia content can scroll.
    return false
end

function LookupPreviewPopup:onNextPage()
    return self.plugin:switchToPage(math.min(PAGE_WIKIPEDIA, self.active_index + 1))
end

function LookupPreviewPopup:onPrevPage()
    return self.plugin:switchToPage(math.max(PAGE_DICTIONARY, self.active_index - 1))
end

function LookupPreview:init()
    self.current_popup = nil
    self.current_state = nil
    self.original_showDict = nil
    self.patched_dictionary = nil
    self.opening_original_popup = false
    self.native_dict_popup_active = false
    self.native_dict_popup_count = 0
    self.selection_snapshot = nil

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    self:patchDictionary()
end

function LookupPreview:addToMainMenu(menu_items)
    menu_items.lookuppreview = {
        text = _("Lookup preview"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Enable lookup preview"),
                checked_func = function()
                    return self:isPreviewEnabled()
                end,
                callback = function()
                    self:setPreviewEnabled(not self:isPreviewEnabled())
                end,
            },
            {
                text = string.format("%s: %s", _("Wikipedia language"), self:getWikipediaLang()),
                callback = function()
                    self:notify(string.format("%s: %s", _("Wikipedia language"), self:getWikipediaLang()))
                end,
            },
            {
                text = string.format("%s: %s", _("Version"), PLUGIN_VERSION),
                callback = function()
                    self:notify(string.format("%s %s", _("Lookup Preview"), PLUGIN_VERSION))
                end,
                separator = true,
            },
        },
    }
end

function LookupPreview:isPreviewEnabled()
    return G_reader_settings:nilOrTrue(SETTING_ENABLED)
end

function LookupPreview:setPreviewEnabled(enabled)
    G_reader_settings:saveSetting(SETTING_ENABLED, enabled and true or false)
end

function LookupPreview:getWikipediaLang()
    local lang = G_reader_settings:readSetting(SETTING_WIKI_LANG)
        or G_reader_settings:readSetting("wikipedia_language")
        or G_reader_settings:readSetting("wikipedia_lang")
        or G_reader_settings:readSetting("translator_to_language")
        or "en"
    lang = tostring(lang or "en"):lower()
    if lang == "" then
        lang = "en"
    end
    return lang
end

function LookupPreview:notify(message)
    UIManager:show(Notification:new({ text = message }))
    return true
end

function LookupPreview:destroy()
    self:closeCurrentPopup(true)

    if self.patched_dictionary and self.original_showDict and self.patched_dictionary._lookuppreview_patched then
        self.patched_dictionary.showDict = self.original_showDict
        self.patched_dictionary._lookuppreview_patched = nil
    end

    self.original_showDict = nil
    self.patched_dictionary = nil
    self.selection_snapshot = nil
    self.current_state = nil
    self:resetNativeDictionaryPopupGuard()

    if WidgetContainer.destroy then
        WidgetContainer.destroy(self)
    end
end

function LookupPreview:patchDictionary()
    local dictionary = self.ui and self.ui.dictionary
    if not dictionary then
        logger.warn("LookupPreview: ReaderDictionary not available.")
        return
    end
    if dictionary._lookuppreview_patched then
        return
    end

    self.original_showDict = dictionary.showDict
    self.patched_dictionary = dictionary
    local plugin = self

    dictionary.showDict = function(dict_self, word, results, boxes, link, dict_close_callback)
        if not plugin:isPreviewEnabled() or plugin.opening_original_popup or not results or not results[1] then
            return plugin.original_showDict(dict_self, word, results, boxes, link, dict_close_callback)
        end

        if plugin.native_dict_popup_active then
            local wrapped_close_callback = plugin:beginNativeDictionaryPopup(dict_close_callback)
            return plugin.original_showDict(dict_self, word, results, boxes, link, wrapped_close_callback)
        end

        plugin:rememberSelection(dict_self)
        if dict_self.dismissLookupInfo then
            pcall(function()
                dict_self:dismissLookupInfo()
            end)
        end

        return plugin:showPreview(dict_self, word, results, boxes, link, dict_close_callback)
    end

    dictionary._lookuppreview_patched = true
end

function LookupPreview:beginNativeDictionaryPopup(dict_close_callback)
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

function LookupPreview:resetNativeDictionaryPopupGuard()
    self.native_dict_popup_count = 0
    self.native_dict_popup_active = false
end

function LookupPreview:showOriginalDictionaryPopup(dict_self, word, results, boxes, link, dict_close_callback)
    if not self.original_showDict then
        return true
    end

    self.opening_original_popup = true
    local wrapped_close_callback = self:beginNativeDictionaryPopup(dict_close_callback)
    local ok, err = pcall(function()
        self.original_showDict(dict_self, word, results, boxes, link, wrapped_close_callback)
    end)
    self.opening_original_popup = false

    if not ok then
        self:resetNativeDictionaryPopupGuard()
        logger.warn("LookupPreview: failed to open original dictionary popup:", err)
    end

    return true
end

function LookupPreview:closeCurrentPopup(preserve_state)
    if self.current_popup then
        self.current_popup.skip_close_callback = true
        pcall(function()
            UIManager:close(self.current_popup)
        end)
        self.current_popup = nil
    end
    if not preserve_state then
        self.current_state = nil
    end
end

function LookupPreview:clearOriginalHighlight(dict_self)
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

function LookupPreview:clearSelection()
    if self.ui and self.ui.handleEvent then
        pcall(function()
            self.ui:handleEvent(Event:new("ClearSelection"))
        end)
    end
end

function LookupPreview:getActiveHighlight(dict_self)
    local candidates = {}
    if dict_self and dict_self.highlight then
        candidates[#candidates + 1] = dict_self.highlight
    end
    if self.ui and self.ui.highlight then
        candidates[#candidates + 1] = self.ui.highlight
    end
    if dict_self and dict_self.ui and dict_self.ui.highlight then
        candidates[#candidates + 1] = dict_self.ui.highlight
    end

    local fallback
    for _, highlight in ipairs(candidates) do
        if highlight then
            if highlight.selected_text or highlight.hold_pos then
                return highlight
            end
            if not fallback and (type(highlight.lookupWikipedia) == "function" or type(highlight.clear) == "function") then
                fallback = highlight
            end
        end
    end
    return fallback
end

function LookupPreview:rememberSelection(dict_self)
    local highlight = self:getActiveHighlight(dict_self)
    if not highlight then
        self.selection_snapshot = nil
        return nil
    end

    if not highlight.selected_text and highlight.hold_pos and type(highlight.highlightFromHoldPos) == "function" then
        pcall(function()
            highlight:highlightFromHoldPos()
        end)
    end

    self.selection_snapshot = {
        highlight = highlight,
        selected_text = copyTable(highlight.selected_text),
        hold_pos = copyTable(highlight.hold_pos),
        selected_link = copyTable(highlight.selected_link),
        is_word_selection = highlight.is_word_selection,
    }

    return self.selection_snapshot
end

function LookupPreview:restoreSelection(dict_self)
    local snapshot = self.selection_snapshot
    local highlight = snapshot and snapshot.highlight or self:getActiveHighlight(dict_self)
    if not highlight then
        return nil
    end

    if snapshot then
        if snapshot.selected_text then
            highlight.selected_text = copyTable(snapshot.selected_text)
        end
        if snapshot.hold_pos then
            highlight.hold_pos = copyTable(snapshot.hold_pos)
        end
        if snapshot.selected_link then
            highlight.selected_link = copyTable(snapshot.selected_link)
        end
        highlight.is_word_selection = false
    end

    if not highlight.selected_text and highlight.hold_pos and type(highlight.highlightFromHoldPos) == "function" then
        pcall(function()
            highlight:highlightFromHoldPos()
        end)
    end

    return highlight
end

function LookupPreview:getSearchText(word, result)
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
    return trim(text)
end

local function buildPreviewResults(results)
    local preview_results = {}
    if type(results) ~= "table" then
        return preview_results
    end
    for index, result in ipairs(results) do
        if result and not result.no_result then
            preview_results[#preview_results + 1] = {
                result = result,
                source_index = index,
            }
        end
    end
    if #preview_results == 0 and results[1] then
        preview_results[#preview_results + 1] = {
            result = results[1],
            source_index = 1,
        }
    end
    return preview_results
end

function LookupPreview:buildDictionaryPayload(word, result, result_index, result_count)
    result = result or {}
    local shown_word = result.word or word or _("Dictionary")
    local dict_name = result.dict or _("Dictionary")
    local definition_html
    local css

    if result.no_result then
        dict_name = _("Dictionary")
        definition_html = "<p>" .. htmlEscape(_("No definition found.")) .. "</p>"
        css = FALLBACK_CSS
    elseif hasDictionaryCss(result) then
        definition_html = normalizeDictionaryHtml(result.definition)
        css = getDictionaryPanelCss(result)
    else
        definition_html = normalizeDictionaryPreviewHtml(result.definition)
        css = FALLBACK_CSS
    end

    local count_label = ""
    if not result.no_result and result_count and result_count > 1 then
        count_label = string.format("%d/%d", result_index or 1, result_count)
    end

    local subtitle = dict_name
    if count_label ~= "" then
        subtitle = string.format("%s · %s", dict_name, count_label)
    end

    return {
        title = tostring(shown_word or _("Dictionary")),
        subtitle = subtitle,
        html_body = definition_html,
        css = css,
        html_resource_directory = result.dictionary_resource_directory,
    }
end

function LookupPreview:makeLoadingPayload(title, message)
    return {
        title = title,
        subtitle = self.current_state and self.current_state.search_text or "",
        html_body = '<p class="lp-muted">' .. htmlEscape(message or _("Loading…")) .. '</p>',
        css = FALLBACK_CSS,
    }
end

function LookupPreview:getPagePayload(state, index, is_active)
    state = state or self.current_state or {}
    if is_active == nil then
        is_active = true
    end

    if index == PAGE_DICTIONARY then
        return state.dictionary_payload or self:makeLoadingPayload(_("Dictionary"), _("No definition found."))
    end

    if index == PAGE_TRANSLATION then
        if state.translation_payload then
            return state.translation_payload
        end
        if state.translation_error then
            return {
                title = _("Translation"),
                subtitle = state.search_text or "",
                html_body = plainTextToHtml(state.translation_error),
                css = FALLBACK_CSS,
            }
        end
        if is_active then
            return self:makeLoadingPayload(_("Translation"), _("Querying translation service…"))
        end
        return self:makeLoadingPayload(_("Translation"), _("Swipe to open translation."))
    end

    if index == PAGE_WIKIPEDIA then
        if state.wikipedia_payload then
            return state.wikipedia_payload
        end
        if state.wikipedia_error then
            return {
                title = _("Wikipedia"),
                subtitle = state.search_text or "",
                html_body = plainTextToHtml(state.wikipedia_error),
                css = FALLBACK_CSS,
            }
        end
        if is_active then
            return self:makeLoadingPayload(_("Wikipedia"), _("Querying Wikipedia…"))
        end
        return self:makeLoadingPayload(_("Wikipedia"), _("Swipe to open Wikipedia."))
    end

    return self:makeLoadingPayload(_("Lookup"), _("No content."))
end

function LookupPreview:getTranslatorLanguageLabel(translator, lang)
    if translator and type(translator.getLanguageName) == "function" then
        local ok, name = pcall(function()
            return translator:getLanguageName(lang, lang and lang:upper() or "?")
        end)
        if ok and name then
            return name
        end
    end
    return tostring(lang or "?")
end

function LookupPreview:loadTranslation(state)
    if state ~= self.current_state then
        return true
    end
    if not state or state.translation_loading or state.translation_payload or state.translation_error then
        return true
    end

    state.translation_loading = true
    local text = state.search_text or ""
    local translator = Translator

    if text == "" then
        state.translation_error = _("No text to translate.")
        state.translation_loading = false
        return self:refreshCurrentPage(PAGE_TRANSLATION)
    end

    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:willRerunWhenOnline(function()
        state.translation_loading = false
        self:loadTranslation(state)
    end) then
        state.translation_error = _("Waiting for network connection.")
        state.translation_loading = false
        return self:refreshCurrentPage(PAGE_TRANSLATION)
    end

    local ok, err = pcall(function()
        local target_lang = translator.getTargetLanguage and translator:getTargetLanguage() or G_reader_settings:readSetting("translator_to_language") or "en"
        local source_lang = translator.getSourceLanguage and translator:getSourceLanguage() or G_reader_settings:readSetting("translator_from_language") or "auto"
        local Trapper = require("ui/trapper")
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            return translator:loadPage(text, target_lang, source_lang)
        end, _("Querying translation service…"))

        if not completed then
            state.translation_error = _("Translation interrupted.")
            return
        end
        if not result or type(result) ~= "table" then
            state.translation_error = _("Translation failed.")
            return
        end
        if result[3] then
            source_lang = result[3]
        end

        local text_main = extractMainTranslation(result)
        if text_main == "" then
            text_main = _("No translation found.")
        end

        local source_name = self:getTranslatorLanguageLabel(translator, source_lang)
        local target_name = self:getTranslatorLanguageLabel(translator, target_lang)
        state.translation_payload = {
            title = _("Translation"),
            subtitle = string.format("%s → %s", source_name, target_name),
            html_body = '<div class="lp-title">' .. plainTextToHtml(text_main) .. '</div><div class="lp-source">' .. plainTextToHtml(text) .. '</div>',
            css = FALLBACK_CSS,
        }
    end)

    if not ok then
        logger.warn("LookupPreview: translation failed:", err)
        state.translation_error = tostring(err or _("Translation failed."))
    end

    state.translation_loading = false
    return self:refreshCurrentPage(PAGE_TRANSLATION)
end

function LookupPreview:pickBestWikipediaPage(pages)
    local best
    if type(pages) ~= "table" then
        return nil
    end
    for _, page in pairs(pages) do
        if type(page) == "table" then
            if not best or tonumber(page.index or 999999) < tonumber(best.index or 999999) then
                best = page
            end
        end
    end
    return best
end

function LookupPreview:loadWikipedia(state)
    if state ~= self.current_state then
        return true
    end
    if not state or state.wikipedia_loading or state.wikipedia_payload or state.wikipedia_error then
        return true
    end

    state.wikipedia_loading = true
    local text = state.search_text or ""
    if text == "" then
        state.wikipedia_error = _("No text to search on Wikipedia.")
        state.wikipedia_loading = false
        return self:refreshCurrentPage(PAGE_WIKIPEDIA)
    end

    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:willRerunWhenOnline(function()
        state.wikipedia_loading = false
        self:loadWikipedia(state)
    end) then
        state.wikipedia_error = _("Waiting for network connection.")
        state.wikipedia_loading = false
        return self:refreshCurrentPage(PAGE_WIKIPEDIA)
    end

    local ok, err = pcall(function()
        local Wikipedia = require("ui/wikipedia")
        local lang = self:getWikipediaLang()
        if type(Wikipedia.setTrapWidget) == "function" then
            Wikipedia:setTrapWidget(_("Querying Wikipedia…"))
        end
        local pages = Wikipedia:searchAndGetIntros(text, lang)
        if type(Wikipedia.resetTrapWidget) == "function" then
            Wikipedia:resetTrapWidget()
        end

        local page = self:pickBestWikipediaPage(pages)
        if not page then
            state.wikipedia_error = _("No Wikipedia article found.")
            return
        end

        local title = trim(page.title or text)
        local extract = trim(page.extract or "")
        if extract == "" then
            extract = _("No introduction found.")
        end

        state.wikipedia_payload = {
            title = _("Wikipedia"),
            subtitle = title .. " · " .. lang,
            html_body = '<div class="lp-title">' .. plainTextToHtml(title) .. '</div>' .. plainTextToHtml(extract),
            css = FALLBACK_CSS,
        }
    end)

    if not ok then
        logger.warn("LookupPreview: Wikipedia lookup failed:", err)
        pcall(function()
            local Wikipedia = require("ui/wikipedia")
            if type(Wikipedia.resetTrapWidget) == "function" then
                Wikipedia:resetTrapWidget()
            end
        end)
        state.wikipedia_error = tostring(err or _("Wikipedia lookup failed."))
    end

    state.wikipedia_loading = false
    return self:refreshCurrentPage(PAGE_WIKIPEDIA)
end

function LookupPreview:refreshCurrentPage(index)
    if not self.current_state then
        return true
    end

    local active_index = self.current_state.active_index or PAGE_DICTIONARY
    if index and index ~= active_index then
        return true
    end

    return self:showCarousel(self.current_state, active_index, true)
end

function LookupPreview:switchToPage(index)
    if not self.current_state then
        return true
    end
    index = math.max(PAGE_DICTIONARY, math.min(PAGE_WIKIPEDIA, index or PAGE_DICTIONARY))
    if index == self.current_state.active_index then
        return true
    end

    self:showCarousel(self.current_state, index, true)

    local state = self.current_state
    if index == PAGE_TRANSLATION then
        UIManager:scheduleIn(0.05, function()
            self:loadTranslation(state)
        end)
    elseif index == PAGE_WIKIPEDIA then
        UIManager:scheduleIn(0.05, function()
            self:loadWikipedia(state)
        end)
    end

    return true
end

function LookupPreview:showCarousel(state, active_index, preserve_state)
    self:closeCurrentPopup(true)
    state.active_index = active_index or PAGE_DICTIONARY
    self.current_state = state

    local popup = LookupPreviewPopup:new({
        plugin = self,
        state = state,
        active_index = state.active_index,
        selection_bounds = state.selection_bounds,
        dialog = state.dialog,
    })

    self.current_popup = popup
    UIManager:show(popup)
    return true
end

function LookupPreview:closePreview(skip_clear)
    local state = self.current_state
    self.current_popup = nil

    if state and not skip_clear then
        self.selection_snapshot = nil
        self:clearOriginalHighlight(state.dict_self)
        self:clearSelection()
        if state.dict_close_callback then
            pcall(state.dict_close_callback)
        end
    end

    self.current_state = nil
    return true
end

function LookupPreview:showPreview(dict_self, word, results, boxes, link, dict_close_callback)
    local preview_results = buildPreviewResults(results)
    if #preview_results <= 0 then
        return true
    end

    local first_entry = preview_results[1] or {}
    local first_result = first_entry.result or results[1] or {}
    local search_text = self:getSearchText(word, first_result)
    local state = {
        dict_self = dict_self,
        word = word,
        results = results,
        boxes = boxes,
        link = link,
        dict_close_callback = dict_close_callback,
        preview_count = #preview_results,
        search_text = search_text,
        selection_bounds = getSelectionBounds(boxes),
        dialog = dict_self and dict_self.dialog,
        dictionary_payload = self:buildDictionaryPayload(word, first_result, 1, #preview_results),
    }

    return self:showCarousel(state, PAGE_DICTIONARY, false)
end

LookupPreview.showFootnotePreview = LookupPreview.showPreview

return LookupPreview
