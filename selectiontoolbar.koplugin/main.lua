local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local Font = require("ui/font")
local IconWidget = require("ui/widget/iconwidget")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")

local Screen = Device.screen
local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sqrt = math.sqrt

local PLUGIN_VERSION = "v1.7.0"
local QR_MESSAGE_MODULE = "ui/widget/qrmessage"

local HANDLE_BAR_WIDTH = math_max(2, Screen:scaleBySize(2))
local HANDLE_KNOB_RADIUS = math_max(3, Screen:scaleBySize(7))
-- Flag tab: a trapezoid grab area beyond the line.
local HANDLE_TAB_HEIGHT = math_max(8, Screen:scaleBySize(22))
local HANDLE_TAB_WIDTH = math_max(6, Screen:scaleBySize(16))
local HANDLE_TAB_SLANT = math_max(3, Screen:scaleBySize(10))
-- Every handle style stays within this distance beyond its line (toolbar gap and drag
-- refresh band rely on it).
local HANDLE_EXTENT = math_max(2 * HANDLE_KNOB_RADIUS, HANDLE_TAB_HEIGHT)
local HANDLE_BRACKET_WIDTH = math_max(2, Screen:scaleBySize(3))
local HANDLE_BRACKET_SERIF = math_max(4, Screen:scaleBySize(7))
local HANDLE_OUTLINE = math_max(1, Screen:scaleBySize(1))
local HANDLE_RING_WIDTH = math_max(2, Screen:scaleBySize(2))
local HANDLE_TOUCH_SIZE = Screen:scaleBySize(48)
-- How far a handle's touch area can reach beyond its line (knob plus centered touch padding).
local HANDLE_TOUCH_EXTENT = math_max(HANDLE_EXTENT + 1, math.ceil(HANDLE_TOUCH_SIZE / 2) + HANDLE_KNOB_RADIUS + 1)
local LINE_MARKER_WIDTH = math_max(2, Screen:scaleBySize(3))
local LINE_MARKER_GAP = Screen:scaleBySize(6)
-- Finger moves smaller than this are not sent to crengine: selection snaps to words,
-- so they would only recompute the same text range.
local DRAG_MIN_MOVE = math_max(2, Screen:scaleBySize(4))
local MARKS_VIEW_MODULE = "selectiontoolbar_selection_marks"
local HANDLE_SIDES = { "start", "end" }

local SHADOW_WIDTH = math_max(2, Screen:scaleBySize(12))
local SHADOW_OVERLAP = math_min(SHADOW_WIDTH - 1, math_max(1, Screen:scaleBySize(6)))
local SHADOW_EXTENT = math_max(0, SHADOW_WIDTH - SHADOW_OVERLAP)
local SHADOW_BAYER8 = {
    { 0, 32, 8, 40, 2, 34, 10, 42 },
    { 48, 16, 56, 24, 50, 18, 58, 26 },
    { 12, 44, 4, 36, 14, 46, 6, 38 },
    { 60, 28, 52, 20, 62, 30, 54, 22 },
    { 3, 35, 11, 43, 1, 33, 9, 41 },
    { 51, 19, 59, 27, 49, 17, 57, 25 },
    { 15, 47, 7, 39, 13, 45, 5, 37 },
    { 63, 31, 55, 23, 61, 29, 53, 21 },
}

local SETTING_ENABLED = "selectiontoolbar_enabled"
local SETTING_ACTIONS = "selectiontoolbar_actions"
local SETTING_SHADOWS = "selectiontoolbar_shadows"
local SETTING_HANDLES = "selectiontoolbar_handles"
local SETTING_LINE_MARKER = "selectiontoolbar_line_marker"
local SETTING_LINE_MARKER_RIGHT = "selectiontoolbar_line_marker_right"
local SETTING_HANDLE_STYLE = "selectiontoolbar_handle_style"
local SETTING_HANDLE_OUTLINE = "selectiontoolbar_handle_outline"
local SETTING_POSITION = "selectiontoolbar_position"
local SETTING_DENSITY = "selectiontoolbar_density"
local SETTING_ICON_SIZE = "selectiontoolbar_icon_size"
-- v1.3.0 had the outline as a separate "wireframe" style: read it as lollipop + outline.
local LEGACY_WIREFRAME_STYLE = "wireframe"

local POSITION_NEAR = "near"
local POSITION_EDGE = "edge"
local POSITIONS = {
    {
        id = POSITION_NEAR,
        text = _("Near the selection"),
        help_text = _("Show the toolbar right below the selection, or above it when there is no room."),
    },
    {
        id = POSITION_EDGE,
        text = _("Fixed at screen edge"),
        help_text = _(
            "Show the toolbar centered at the bottom of the screen, or at the top when the selection is in the lower part."
        ),
    },
}

-- Button height (the icon area; ButtonTable adds its own vertical padding) and the side
-- padding that, added on both sides, gives the button width.
local DEFAULT_DENSITY = "normal"
local DENSITIES = {
    {
        id = "compact",
        text = _("Compact"),
        help_text = _("Smaller, tighter buttons: the toolbar covers less of the page."),
        height = 34,
        side_padding = 4,
    },
    {
        id = "normal",
        text = _("Normal"),
        help_text = _("The default button size and spacing."),
        height = 42,
        side_padding = 6,
    },
    {
        id = "comfortable",
        text = _("Comfortable"),
        help_text = _("Taller, more spaced buttons: easier to tap."),
        height = 50,
        side_padding = 10,
    },
}

local DEFAULT_ICON_SIZE = "normal"
local ICON_SIZES = {
    { id = "small", text = _("Small"), size = 18 },
    { id = "normal", text = _("Normal"), size = 22 },
    { id = "large", text = _("Large"), size = 28 },
}

local ACTIONS = {
    { id = "select", key = "01_select", icon = "select", text = _("Select") },
    { id = "highlight", key = "02_highlight", icon = "highlight", text = _("Highlight") },
    { id = "copy", key = "03_copy", icon = "copy", text = _("Copy") },
    { id = "add_note", key = "04_add_note", icon = "add_note", text = _("Add note") },
    { id = "wikipedia", key = "05_wikipedia", icon = "wikipedia", text = _("Wikipedia") },
    { id = "dictionary", key = "06_dictionary", icon = "dictionary", text = _("Dictionary") },
    { id = "translate", key = "07_translate", icon = "translate", text = _("Translate") },
    { id = "view_html", key = "09_view_html", icon = "view_html", text = _("View HTML") },
    { id = "qr_code", key = nil, icon = "qr_code", text = _("Generate QR code") },
    { id = "search", key = "12_search", icon = "search", text = _("Search") },
}
local QR_ICON_ACTION = { icon = "qr_code" }

local DEFAULT_HANDLE_STYLE = "lollipop"
-- Styles drawn with solid shapes large enough to get a high-contrast outline.
local OUTLINE_STYLES = { lollipop = true, teardrop = true, flag = true }
local HANDLE_STYLES = {
    {
        id = "lollipop",
        text = _("Lollipop"),
        help_text = _("A bar at the selection edge with a round knob above the start and below the end."),
    },
    {
        id = "teardrop",
        text = _("Teardrop"),
        help_text = _("A drop below the line, pointing at the selection edge, as on Android."),
    },
    {
        id = "bracket",
        text = _("Brackets"),
        help_text = _("A [ at the start and a ] at the end of the selection. The most discreet style."),
    },
    {
        id = "flag",
        text = _("Flag tabs"),
        help_text = _(
            "A pole with a grab tab pointing outwards, above the start and below the end, slanted toward the text."
        ),
    },
}

local TOOLBAR_SHADOW_CACHE = {}

local function clearToolbarShadowCache()
    if TOOLBAR_SHADOW_CACHE.right then
        TOOLBAR_SHADOW_CACHE.right:free()
    end
    if TOOLBAR_SHADOW_CACHE.bottom then
        TOOLBAR_SHADOW_CACHE.bottom:free()
    end
    TOOLBAR_SHADOW_CACHE = {}
end

local function roundedRectDistance(x, y, width, height, radius)
    local half_width = width / 2
    local half_height = height / 2
    radius = math_max(0, math_min(radius or 0, half_width, half_height))
    local qx = math_abs(x - half_width) - (half_width - radius)
    local qy = math_abs(y - half_height) - (half_height - radius)
    local outside_x = math_max(qx, 0)
    local outside_y = math_max(qy, 0)
    return math_sqrt(outside_x * outside_x + outside_y * outside_y)
        + math_min(math_max(qx, qy), 0)
        - radius
end

local ShadowedPopup = WidgetContainer:extend({})

function ShadowedPopup:getSize()
    local size = self[1]:getSize()
    return Geom:new({
        w = size.w + SHADOW_EXTENT,
        h = size.h + SHADOW_EXTENT,
    })
end

function ShadowedPopup:_ensureShadowBuffers(bb, width, height)
    local radius = math_max(0, math_min(self.shadow_radius or 0, width / 2, height / 2))
    local night = Screen.night_mode
    local inv = bb.getInverse and bb:getInverse() == 1
    local render_inv = inv and not (night and Device.isAndroid and Device:isAndroid())
    local cache_key = table.concat({
        tostring(width),
        tostring(height),
        tostring(radius),
        tostring(night),
        tostring(render_inv),
    }, ":")
    if TOOLBAR_SHADOW_CACHE.key == cache_key then
        return
    end

    clearToolbarShadowCache()
    TOOLBAR_SHADOW_CACHE.key = cache_key

    local shadow_value = render_inv and 0x00 or (night and 0xFF or 0x00)
    local shadow_on = Blitbuffer.ColorRGB32(shadow_value, shadow_value, shadow_value, 255)
    local shadow_off = Blitbuffer.ColorRGB32(shadow_value, shadow_value, shadow_value, 0)
    local base_strength = night and 1.0 or 0.5
    local peak_level = night and 1.0 or 0.62
    local bump_width = 0.18

    local function baseFraction(t)
        if night then
            return t < 0.5 and (1 - 0.8 * t) or 0.6 * (1 - (t - 0.5) * 2) ^ 2
        end
        return 1 - t
    end

    local function shadowLevel(pos)
        local t = (pos + 0.5) / SHADOW_WIDTH
        local original_level = base_strength * baseFraction(t)
        local visible_start = SHADOW_OVERLAP / SHADOW_WIDTH
        local bump
        if t <= visible_start then
            bump = 1
        else
            local distance = (t - visible_start) / bump_width
            bump = distance < 1 and 0.5 * (1 + math.cos(math.pi * distance)) or 0
        end
        return (original_level + bump * (peak_level - original_level)) * 255
    end

    TOOLBAR_SHADOW_CACHE.right = Blitbuffer.new(SHADOW_WIDTH, height, Blitbuffer.TYPE_BBRGB32)
    for x = 0, SHADOW_WIDTH - 1 do
        local column = (x % 8) + 1
        for y = 0, height - 1 do
            local level
            if radius > 0 then
                local distance = roundedRectDistance(width - SHADOW_OVERLAP + x, y, width, height, radius)
                local shadow_pos = SHADOW_OVERLAP + distance
                level = shadow_pos >= 0 and shadow_pos < SHADOW_WIDTH and shadowLevel(shadow_pos) or 0
            else
                level = shadowLevel(x)
            end
            local threshold = (SHADOW_BAYER8[column][(y % 8) + 1] + 0.5) * 4
            local color = level > threshold and shadow_on or shadow_off
            TOOLBAR_SHADOW_CACHE.right:setPixel(x, y, color)
        end
    end
    TOOLBAR_SHADOW_CACHE.right:setInverse(render_inv and 1 or 0)

    local bottom_width = width + SHADOW_EXTENT
    TOOLBAR_SHADOW_CACHE.bottom = Blitbuffer.new(bottom_width, SHADOW_WIDTH, Blitbuffer.TYPE_BBRGB32)
    for y = 0, SHADOW_WIDTH - 1 do
        local bottom_level = shadowLevel(y)
        local row = (y % 8) + 1
        for x = 0, bottom_width - 1 do
            local level
            if radius > 0 then
                if y < SHADOW_OVERLAP and x >= width - SHADOW_OVERLAP then
                    level = 0
                else
                    local distance = roundedRectDistance(x, height - SHADOW_OVERLAP + y, width, height, radius)
                    local shadow_pos = SHADOW_OVERLAP + distance
                    level = shadow_pos >= 0 and shadow_pos < SHADOW_WIDTH and shadowLevel(shadow_pos) or 0
                end
            else
                level = bottom_level
                if y < SHADOW_OVERLAP and x >= width - SHADOW_OVERLAP then
                    level = 0
                elseif x >= width then
                    level = math_min(level, shadowLevel(SHADOW_OVERLAP + x - width))
                end
            end
            local threshold = (SHADOW_BAYER8[(x % 8) + 1][row] + 0.5) * 4
            local color = level > threshold and shadow_on or shadow_off
            TOOLBAR_SHADOW_CACHE.bottom:setPixel(x, y, color)
        end
    end
    TOOLBAR_SHADOW_CACHE.bottom:setInverse(render_inv and 1 or 0)
end

function ShadowedPopup:_alphaBlitClipped(bb, source, x, y)
    local source_x, source_y = 0, 0
    local width, height = source:getWidth(), source:getHeight()
    if x < 0 then
        source_x = -x
        width = width - source_x
        x = 0
    end
    if y < 0 then
        source_y = -y
        height = height - source_y
        y = 0
    end
    width = math_min(width, bb:getWidth() - x)
    height = math_min(height, bb:getHeight() - y)
    if width > 0 and height > 0 then
        bb:alphablitFrom(source, x, y, source_x, source_y, width, height)
    end
end

function ShadowedPopup:paintTo(bb, x, y)
    local content_size = self[1]:getSize()
    local width, height = content_size.w, content_size.h
    self:_ensureShadowBuffers(bb, width, height)
    self.dimen = Geom:new({
        x = x,
        y = y,
        w = width + SHADOW_EXTENT,
        h = height + SHADOW_EXTENT,
    })
    self:_alphaBlitClipped(bb, TOOLBAR_SHADOW_CACHE.bottom, x, y + height - SHADOW_OVERLAP)
    self:_alphaBlitClipped(bb, TOOLBAR_SHADOW_CACHE.right, x + width - SHADOW_OVERLAP, y)
    self[1]:paintTo(bb, x, y)
end

local ShadowedButtonDialog = ButtonDialog:extend({})

function ShadowedButtonDialog:init()
    ButtonDialog.init(self)
    if self.show_shadow then
        local frame = self.movable[1]
        self.movable[1] = ShadowedPopup:new({
            shadow_radius = frame.radius,
            frame,
        })
    end
    -- While the toolbar is shown it is the top widget and swallows every gesture, so the
    -- selection handles must be dragged through it. Ranges cover the whole screen; the
    -- controller only consumes gestures that start on a handle.
    if self.handle_controller and Device:isTouchDevice() then
        local screen_range = Geom:new({ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
        local rate = self.handle_pan_rate
        self.ges_events.SelectionHandleHold = { GestureRange:new({ ges = "hold", range = screen_range }) }
        self.ges_events.SelectionHandlePan = { GestureRange:new({ ges = "pan", range = screen_range, rate = rate }) }
        self.ges_events.SelectionHandleHoldPan = {
            GestureRange:new({ ges = "hold_pan", range = screen_range, rate = rate }),
        }
        -- A quick flick on a handle is a swipe, or a multiswipe if it changed direction.
        self.ges_events.SelectionHandleSwipe = {
            GestureRange:new({ ges = "swipe", range = screen_range }),
            GestureRange:new({ ges = "multiswipe", range = screen_range }),
        }
    end
end

-- WidgetContainer hands gestures to the children before our own ges_events, and the
-- MovableContainer child grabs any pan passing over the toolbar (even while it is hidden),
-- which would move the toolbar instead of the handle. Gestures that belong to a handle
-- are therefore dispatched to our own ges_events first, without reaching the children.
function ShadowedButtonDialog:handleEvent(event)
    if self.handle_controller and event.handler == "onGesture" then
        local ges = event.args and event.args[1]
        if ges and self.handle_controller:endsDrag(self, ges) then
            return true
        end
        if ges and self.handle_controller:claimsGesture(self, ges) then
            self:onGesture(ges)
            return true
        end
    end
    return ButtonDialog.handleEvent(self, event)
end

function ShadowedButtonDialog:paintTo(...)
    if self.content_hidden then
        return
    end
    return ButtonDialog.paintTo(self, ...)
end

function ShadowedButtonDialog:onTapClose(arg, ges)
    if self.handle_controller and self.handle_controller:handleAt(ges.pos) then
        return true
    end
    return ButtonDialog.onTapClose(self, arg, ges)
end

function ShadowedButtonDialog:onCloseWidget()
    -- ButtonDialog flashes its area on close. A hidden toolbar left nothing there
    -- (its area was repainted when it was hidden), so skip that flash refresh.
    if not self.content_hidden then
        ButtonDialog.onCloseWidget(self)
    end
    if self.handle_controller then
        self.handle_controller:onToolbarClosed(self)
    end
end

function ShadowedButtonDialog:onSelectionHandleHold(_, ges)
    return self.handle_controller:onHandleHold(self, ges)
end

function ShadowedButtonDialog:onSelectionHandlePan(_, ges)
    return self.handle_controller:onHandlePan(self, ges)
end

function ShadowedButtonDialog:onSelectionHandleHoldPan(_, ges)
    return self.handle_controller:onHandleHoldPan(ges)
end

function ShadowedButtonDialog:onSelectionHandleSwipe(_, ges)
    return self.handle_controller:onHandleSwipe(self, ges)
end

-- Live preview of the toolbar, docked at the bottom of the screen while its settings are
-- open in the menu: a sheet with rounded top corners and a dithered shadow cast upwards,
-- where the toolbar lies over a few lines of sample text as it would over the page. As a
-- toast it stays above the menu without taking its gestures, and it holds the toolbar
-- frame only to paint it, so its buttons never get events.
local ToolbarPreview = WidgetContainer:extend({
    name = "selectiontoolbar_preview",
    toast = true,
})

local PREVIEW_SAMPLE_TEXT = _(
    "This is a short sample of text, shown so you can see how the selection toolbar looks over the page. "
)
-- Sample lines shown above and below the toolbar, when the menu leaves room for them.
local PREVIEW_MAX_EXTRA_LINES = 2
local SHEET_RADIUS = Screen:scaleBySize(16)
local SHEET_BORDER = Size.border.thick
local SHEET_SHADOW = math_max(2, Screen:scaleBySize(10))
-- Peak darkness of the shadow, right above the sheet (0..1).
local SHEET_SHADOW_STRENGTH = 0.6
local SHEET_GRIP_WIDTH = Screen:scaleBySize(36)
local SHEET_GRIP_HEIGHT = math_max(2, Screen:scaleBySize(4))
local SHEET_GRIP_MARGIN = Size.padding.default

-- Lays the preview out again. The toolbar is only rebuilt when toolbar_changed (a setting
-- changed) and the sample text only when its size changed: it is laid out and rendered
-- when created, which is the costly part. Returns whether the preview looks different.
function ToolbarPreview:update(toolbar_changed)
    local plugin = self.plugin
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    -- Space kept between the menu and the shadow.
    local gap = Size.padding.large
    local padding = Size.padding.large
    local side = SHEET_BORDER + padding
    local inner_w = screen_w - 2 * side
    local menu_bottom = plugin:getMenuBottom()

    if toolbar_changed or not self.toolbar_built then
        if self.toolbar then
            self.toolbar:free()
        end
        local dialog = plugin:buildPreviewDialog(inner_w)
        self.toolbar = dialog and dialog.movable[1]
        self.toolbar_built = true
    end
    local toolbar = self.toolbar
    local toolbar_size = toolbar and toolbar:getSize() or Geom:new({ w = 0, h = 0 })

    if not self.title then
        self.title = TextWidget:new({
            text = _("Preview"),
            face = Font:getFace("smallinfofontbold"),
        })
    end
    local title_span = Size.span.vertical_default
    local face = Font:getFace("infofont")
    -- TextBoxWidget's default line height: 1.3 em.
    local line_h = math_floor(1.3 * face.size + 0.5)
    -- Above the body: the shadow, the top border and the grip with its margins.
    local body_top = SHEET_BORDER + 2 * SHEET_GRIP_MARGIN + SHEET_GRIP_HEIGHT
    local fixed_h = SHEET_SHADOW + body_top + self.title:getSize().h + title_span + padding
    local room = screen_h - menu_bottom - gap
    local toolbar_lines = math.ceil(toolbar_size.h / line_h)
    local lines
    for extra = PREVIEW_MAX_EXTRA_LINES, 0, -1 do
        lines = toolbar_lines + 2 * extra
        if fixed_h + lines * line_h <= room then
            break
        end
    end
    lines = math_max(lines, 1)
    local text_h = lines * line_h

    local sample_key = inner_w .. ":" .. lines
    if self.sample_key ~= sample_key then
        if self.sample then
            self.sample:free()
        end
        -- TextBoxWidget splits all of its text into lines: give it just enough to fill
        -- them. 0.3 em per byte is generous for Latin text (~0.5 em per character) and
        -- still enough for wide CJK glyphs (1 em for 3 bytes).
        local repeats = math.ceil(lines * inner_w / (0.3 * face.size) / #PREVIEW_SAMPLE_TEXT) + 1
        self.sample = TextBoxWidget:new({
            text = PREVIEW_SAMPLE_TEXT:rep(repeats),
            face = face,
            width = inner_w,
            height = text_h,
        })
        self.sample_key = sample_key
    end

    local stage = OverlapGroup:new({
        dimen = Geom:new({ w = inner_w, h = text_h }),
        self.sample,
    })
    if toolbar then
        toolbar.overlap_offset = {
            math_floor((inner_w - toolbar_size.w) / 2),
            math_floor((text_h - toolbar_size.h) / 2),
        }
        stage[2] = toolbar
    end

    -- Only layout containers: the widgets they hold are kept and freed in freeContent().
    self.content = VerticalGroup:new({
        align = "left",
        self.title,
        VerticalSpan:new({ width = title_span }),
        stage,
    })
    self.menu_bottom = menu_bottom
    self.content_x = side
    self.content_dy = body_top

    local old_dimen = self.dimen
    local sheet_h = body_top + self.content:getSize().h + padding
    -- The shadow is part of the preview area, so it is refreshed and erased with it.
    self.dimen = Geom:new({
        x = 0,
        y = math_max(0, screen_h - sheet_h - SHEET_SHADOW),
        w = screen_w,
        h = sheet_h + SHEET_SHADOW,
    })
    return toolbar_changed or not old_dimen or old_dimen.y ~= self.dimen.y or old_dimen.h ~= self.dimen.h
end

function ToolbarPreview:freeContent()
    for _, name in ipairs({ "toolbar", "sample", "title" }) do
        if self[name] then
            self[name]:free()
            self[name] = nil
        end
    end
    self.content = nil
    self.toolbar_built = nil
    self.sample_key = nil
end

function ToolbarPreview:freeShadow()
    if self.shadow_bb then
        self.shadow_bb:free()
        self.shadow_bb = nil
        self.shadow_key = nil
    end
end

function ToolbarPreview:onCloseWidget()
    self:freeContent()
    self:freeShadow()
end

-- Dithered shadow above a sheet of the given width, following its rounded top corners:
-- SHEET_SHADOW rows above its top edge, plus the corner areas beside its top rows.
-- Same colors and night mode handling as the toolbar shadow.
function ToolbarPreview:getShadow(bb, width)
    local night = Screen.night_mode
    local inv = bb.getInverse and bb:getInverse() == 1
    local render_inv = inv and not (night and Device.isAndroid and Device:isAndroid())
    local key = table.concat({ width, tostring(night), tostring(render_inv) }, ":")
    if self.shadow_key == key then
        return self.shadow_bb
    end
    self:freeShadow()

    local shadow_value = render_inv and 0x00 or (night and 0xFF or 0x00)
    local shadow_on = Blitbuffer.ColorRGB32(shadow_value, shadow_value, shadow_value, 255)
    local shadow_off = Blitbuffer.ColorRGB32(shadow_value, shadow_value, shadow_value, 0)
    local r, s = SHEET_RADIUS, SHEET_SHADOW
    local height = s + r
    local shadow = Blitbuffer.new(width, height, Blitbuffer.TYPE_BBRGB32)
    for py = 0, height - 1 do
        -- Relative to the sheet's top edge (negative above it).
        local sy = py + 0.5 - s
        for px = 0, width - 1 do
            local sx = px + 0.5
            local distance
            if sx < r or sx > width - r then
                local cx = sx < r and r or (width - r)
                distance = math_sqrt((sx - cx) ^ 2 + (sy - r) ^ 2) - r
                if sy >= r then
                    distance = -1
                end
            else
                distance = -sy
            end
            local color = shadow_off
            if distance >= 0 and distance < s then
                local level = SHEET_SHADOW_STRENGTH * (1 - distance / s) * 255
                local threshold = (SHADOW_BAYER8[(px % 8) + 1][(py % 8) + 1] + 0.5) * 4
                if level > threshold then
                    color = shadow_on
                end
            end
            shadow:setPixel(px, py, color)
        end
    end
    shadow:setInverse(render_inv and 1 or 0)
    self.shadow_bb, self.shadow_key = shadow, key
    return shadow
end

-- The sheet: white with a black border along its top and sides, rounded top corners
-- and square bottom corners (it sits on the screen's bottom edge).
local function paintSheet(bb, top, width, height)
    local r, b = SHEET_RADIUS, SHEET_BORDER
    local white, black = Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK
    bb:paintRect(r, top, width - 2 * r, r, white)
    bb:paintRect(r, top, width - 2 * r, b, black)
    bb:paintRect(0, top + r, width, height - r, white)
    bb:paintRect(0, top + r, b, height - r, black)
    bb:paintRect(width - b, top + r, b, height - r, black)
    -- Corners row by row: a black arc b thick around a white inside.
    local inner_r = r - b
    for row = 0, r - 1 do
        local dy = r - row - 0.5
        local outer = math_floor(math_sqrt(math_max(0, r * r - dy * dy)) + 0.5)
        local inner = dy < inner_r and math_floor(math_sqrt(inner_r * inner_r - dy * dy) + 0.5) or 0
        local y = top + row
        if outer > 0 then
            bb:paintRect(r - outer, y, outer - inner, 1, black)
            bb:paintRect(width - r + inner, y, outer - inner, 1, black)
            if inner > 0 then
                bb:paintRect(r - inner, y, inner, 1, white)
                bb:paintRect(width - r, y, inner, 1, white)
            end
        end
    end
end

function ToolbarPreview:paintTo(bb)
    local state = self.plugin:getPreviewState(self)
    -- Not from within a repaint: closing or rebuilding changes what is being painted.
    if state == "closed" then
        UIManager:nextTick(function()
            self.plugin:closePreview(self)
        end)
        return
    end
    if self.plugin:getMenuBottom() ~= self.menu_bottom then
        -- The menu changed height: fit the sample text to the room left below it.
        UIManager:nextTick(function()
            if self.plugin.preview == self then
                self.plugin:refreshPreview(false)
            end
        end)
    end
    local visible = state == "visible" and self.content ~= nil
    if self.shown ~= nil and visible ~= self.shown then
        -- The repaint that changed it only refreshes its own area (e.g. a help dialog
        -- opening or closing): the preview's area must be refreshed as well.
        local was_shown = self.shown
        UIManager:nextTick(function()
            if self.plugin.preview ~= self then
                return
            end
            if was_shown then
                -- Erase it: repaint the page (and what lies above it) under its area.
                local ui = self.plugin.ui
                UIManager:setDirty(ui and (ui.dialog or ui), "ui", self.dimen)
            else
                UIManager:setDirty(self, "ui", self.dimen)
            end
        end)
    end
    self.shown = visible
    if not visible then
        return
    end

    local dimen = self.dimen
    local sheet_top = dimen.y + SHEET_SHADOW
    ShadowedPopup._alphaBlitClipped(nil, bb, self:getShadow(bb, dimen.w), dimen.x, dimen.y)
    paintSheet(bb, sheet_top, dimen.w, dimen.h - SHEET_SHADOW)
    -- A grip, as on bottom sheets: it only tells the panel apart, it cannot be dragged.
    bb:paintRoundedRect(
        math_floor((dimen.w - SHEET_GRIP_WIDTH) / 2),
        sheet_top + SHEET_BORDER + SHEET_GRIP_MARGIN,
        SHEET_GRIP_WIDTH,
        SHEET_GRIP_HEIGHT,
        Blitbuffer.COLOR_DARK_GRAY,
        math_floor(SHEET_GRIP_HEIGHT / 2)
    )
    self.content:paintTo(bb, dimen.x + self.content_x, sheet_top + self.content_dy)
end

local function pluginDir()
    local source = debug.getinfo(1, "S").source or ""
    local path = source:match("^@(.*/)") or source:match("^(.*/)")
    return path or "plugins/selectiontoolbar.koplugin/"
end

local function findChoice(choices, id)
    for _, choice in ipairs(choices) do
        if choice.id == id then
            return choice
        end
    end
end

-- The saved choice of a multiple-choice setting, or the default one if it is unset or
-- no longer exists.
local function readChoice(setting, choices, default_id)
    return findChoice(choices, G_reader_settings:readSetting(setting)) or findChoice(choices, default_id)
end

-- Toolbar sizes for the chosen density and icon size, in screen pixels.
local toolbar_metrics_cache = {}

local function getToolbarMetrics()
    local density = readChoice(SETTING_DENSITY, DENSITIES, DEFAULT_DENSITY)
    local icon_size = readChoice(SETTING_ICON_SIZE, ICON_SIZES, DEFAULT_ICON_SIZE)
    local key = density.id .. ":" .. icon_size.id
    local metrics = toolbar_metrics_cache[key]
    if not metrics then
        local height = Screen:scaleBySize(density.height)
        local side_padding = Screen:scaleBySize(density.side_padding)
        local width = height + 2 * side_padding
        metrics = {
            button_height = height,
            button_width = width,
            side_padding = side_padding,
            -- The icon must fit inside the button, past ButtonTable's side padding.
            icon_size = math_min(Screen:scaleBySize(icon_size.size), height, width - 2 * Size.padding.button),
        }
        toolbar_metrics_cache[key] = metrics
    end
    return metrics
end

local function applyToolbarButtonMetrics(button, metrics)
    button.icon_width = metrics.icon_size
    button.icon_height = metrics.icon_size
    button.height = metrics.button_height
    button.width = metrics.button_width
    button.padding = metrics.side_padding
    button.margin = 0
    return button
end

local SelectionToolbar = WidgetContainer:extend({
    name = "selectiontoolbar",
    is_doc_only = true,
})

function SelectionToolbar:init()
    -- The plugin is developed for EPUB (crengine) documents only. In PDF, DjVu and other
    -- paged documents it stays inactive and KOReader's native selection menu is used.
    if not (self.ui and self.ui.rolling) then
        return
    end

    self.plugin_path = pluginDir()
    self.icons_path = self.plugin_path .. "icons/"
    self.icon_cache = {}
    self.qr_message_checked = false
    self.qr_message_class = nil

    self:patchIconWidget()
    if self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    if self.ui.highlight then
        self:patchHighlight(self.ui.highlight)
    end
    if self.ui.view and self.ui.view.registerViewModule then
        local plugin = self
        self.ui.view:registerViewModule(MARKS_VIEW_MODULE, {
            paintTo = function(_, bb, x, y)
                plugin:paintSelectionMarks(bb, x, y)
            end,
        })
    end
end

function SelectionToolbar:onClose()
    if self.ui and self.ui.highlight and self.ui.highlight._selectiontoolbar_original_onShowHighlightMenu then
        self.ui.highlight.onShowHighlightMenu = self.ui.highlight._selectiontoolbar_original_onShowHighlightMenu
        self.ui.highlight._selectiontoolbar_original_onShowHighlightMenu = nil
        self.ui.highlight._selectiontoolbar_patched = nil
    end
    if self.ui and self.ui.view and self.ui.view.view_modules then
        self.ui.view.view_modules[MARKS_VIEW_MODULE] = nil
    end
    self.marks_dialog = nil
    self.marks_highlight = nil
    self.marks = nil
    self.drag = nil

    if self.preview then
        self:closePreview(self.preview)
    end
    self:unpatchIconWidget()
    clearToolbarShadowCache()
end

function SelectionToolbar:isEnabled()
    return G_reader_settings:readSetting(SETTING_ENABLED) ~= false
end

function SelectionToolbar:setEnabled(enabled)
    G_reader_settings:saveSetting(SETTING_ENABLED, enabled and true or false)
end

function SelectionToolbar:showToolbarShadows()
    return G_reader_settings:nilOrTrue(SETTING_SHADOWS)
end

function SelectionToolbar:setToolbarShadows(enabled)
    G_reader_settings:saveSetting(SETTING_SHADOWS, enabled and true or false)
    if not enabled then
        clearToolbarShadowCache()
    end
end

function SelectionToolbar:getToolbarPosition()
    return readChoice(SETTING_POSITION, POSITIONS, POSITION_NEAR).id
end

function SelectionToolbar:setToolbarPosition(position)
    G_reader_settings:saveSetting(SETTING_POSITION, position)
end

function SelectionToolbar:getDensity()
    return readChoice(SETTING_DENSITY, DENSITIES, DEFAULT_DENSITY).id
end

function SelectionToolbar:setDensity(density)
    G_reader_settings:saveSetting(SETTING_DENSITY, density)
end

function SelectionToolbar:getIconSize()
    return readChoice(SETTING_ICON_SIZE, ICON_SIZES, DEFAULT_ICON_SIZE).id
end

function SelectionToolbar:setIconSize(icon_size)
    G_reader_settings:saveSetting(SETTING_ICON_SIZE, icon_size)
end

function SelectionToolbar:showHandles()
    return Device:isTouchDevice() and G_reader_settings:nilOrTrue(SETTING_HANDLES)
end

function SelectionToolbar:showLineMarker()
    return G_reader_settings:nilOrTrue(SETTING_LINE_MARKER)
end

function SelectionToolbar:getHandleStyle()
    -- A legacy "wireframe" style is not a known choice: it reads as the default one.
    return readChoice(SETTING_HANDLE_STYLE, HANDLE_STYLES, DEFAULT_HANDLE_STYLE).id
end

function SelectionToolbar:handleOutline()
    return G_reader_settings:isTrue(SETTING_HANDLE_OUTLINE)
        or G_reader_settings:readSetting(SETTING_HANDLE_STYLE) == LEGACY_WIREFRAME_STYLE
end

-- Saving either setting also resolves a legacy "wireframe" style into its two parts.
function SelectionToolbar:setHandleStyle(style, outline)
    G_reader_settings:saveSetting(SETTING_HANDLE_STYLE, style)
    G_reader_settings:saveSetting(SETTING_HANDLE_OUTLINE, outline and true or false)
end

function SelectionToolbar:canOutlineHandles()
    return OUTLINE_STYLES[self:getHandleStyle()] or false
end

function SelectionToolbar:lineMarkerOnRight()
    return G_reader_settings:isTrue(SETTING_LINE_MARKER_RIGHT)
end

function SelectionToolbar:toggleSetting(setting, default_on)
    local enabled
    if default_on then
        enabled = G_reader_settings:nilOrTrue(setting)
    else
        enabled = G_reader_settings:isTrue(setting)
    end
    G_reader_settings:saveSetting(setting, not enabled)
end

function SelectionToolbar:getActionSettings()
    local settings = G_reader_settings:readSetting(SETTING_ACTIONS)
    if type(settings) ~= "table" then
        settings = {}
    end
    return settings
end

function SelectionToolbar:isActionEnabled(action_id)
    local settings = self:getActionSettings()
    return settings[action_id] ~= false
end

function SelectionToolbar:setActionEnabled(action_id, enabled)
    local settings = self:getActionSettings()
    settings[action_id] = enabled and true or false
    G_reader_settings:saveSetting(SETTING_ACTIONS, settings)
end

function SelectionToolbar:resetActions()
    if G_reader_settings.delSetting then
        G_reader_settings:delSetting(SETTING_ACTIONS)
    else
        G_reader_settings:saveSetting(SETTING_ACTIONS, {})
    end
end

function SelectionToolbar:patchIconWidget()
    if IconWidget._selectiontoolbar_original_init then
        return
    end

    IconWidget._selectiontoolbar_original_init = IconWidget.init

    -- File existence per path, so showing the toolbar does not stat each icon every time.
    local is_file = {}
    local patched_init = function(icon_widget)
        local explicit_icon = rawget(icon_widget, "icon")
        if type(explicit_icon) == "string" and explicit_icon:match("%.%a+$") then
            local exists = is_file[explicit_icon]
            if exists == nil then
                exists = lfs.attributes(explicit_icon, "mode") == "file"
                is_file[explicit_icon] = exists
            end
            if exists then
                icon_widget.file = explicit_icon
            end
        end

        return IconWidget._selectiontoolbar_original_init(icon_widget)
    end

    IconWidget._selectiontoolbar_patched_init = patched_init
    IconWidget.init = patched_init
end

function SelectionToolbar:unpatchIconWidget()
    if
        IconWidget._selectiontoolbar_original_init
        and IconWidget._selectiontoolbar_patched_init
        and IconWidget.init == IconWidget._selectiontoolbar_patched_init
    then
        IconWidget.init = IconWidget._selectiontoolbar_original_init
        IconWidget._selectiontoolbar_original_init = nil
        IconWidget._selectiontoolbar_patched_init = nil
    end
end

function SelectionToolbar:getIconPath(action)
    local icon = action and action.icon
    if not icon then
        return nil
    end

    self.icon_cache = self.icon_cache or {}
    self.icons_path = self.icons_path or ((self.plugin_path or pluginDir()) .. "icons/")

    local cached = self.icon_cache[icon]
    if cached then
        return cached
    end

    local path = self.icons_path .. icon .. ".svg"
    self.icon_cache[icon] = path
    return path
end

function SelectionToolbar:getQRMessage()
    if self.qr_message_checked then
        return self.qr_message_class
    end

    self.qr_message_checked = true
    local ok_qr, QRMessage = pcall(require, QR_MESSAGE_MODULE)
    if ok_qr and QRMessage then
        self.qr_message_class = QRMessage
    end

    return self.qr_message_class
end

function SelectionToolbar:closeHighlightDialog(reader_highlight)
    if reader_highlight.highlight_dialog then
        UIManager:close(reader_highlight.highlight_dialog)
        reader_highlight.highlight_dialog = nil
    end
end

-- The toolbar dialog for a row of buttons, with the current appearance settings. Used
-- for both the real toolbar and its preview, so that they always look the same.
-- available_width: the room for the toolbar and its shadow (default: the screen width
-- less a margin on both sides).
function SelectionToolbar:buildToolbarDialog(row, metrics, options, available_width)
    local show_shadow = self:showToolbarShadows()
    local shadow_extent = show_shadow and SHADOW_EXTENT or 0
    local count = #row
    -- ButtonTable puts a separator line between buttons; the frame adds border and padding.
    local separators = (count - 1) * Size.line.medium
    local frame_extra = 2 * Size.border.window + 2 * Size.padding.button
    local max_width = (available_width or (Screen:getWidth() - 2 * Size.padding.large)) - shadow_extent

    -- ButtonTable never shrinks buttons with a given width, so a row wider than the
    -- screen would run off it: narrow the buttons (and icons, if needed) to fit.
    local button_width = metrics.button_width
    local fit_width = math_floor((max_width - frame_extra - separators) / count)
    if fit_width < button_width then
        button_width = fit_width
        local icon_size = math_min(metrics.icon_size, button_width - 2 * Size.padding.button)
        for _, button in ipairs(row) do
            button.width = button_width
            button.icon_width = icon_size
            button.icon_height = icon_size
        end
    end

    options.buttons = { row }
    options.width = count * button_width + separators + frame_extra
    options.show_shadow = show_shadow
    options.shrink_unneeded_width = true
    options.shrink_min_width = button_width
    return ShadowedButtonDialog:new(options)
end

-- A toolbar with every visible action, as it would show for a selection.
function SelectionToolbar:buildPreviewDialog(available_width)
    local metrics = getToolbarMetrics()
    local action_settings = self:getActionSettings()
    local row = {}
    for _, action in ipairs(ACTIONS) do
        if action_settings[action.id] ~= false then
            row[#row + 1] = applyToolbarButtonMetrics({
                id = "selectiontoolbar_preview_" .. action.id,
                icon = self:getIconPath(action),
                callback = function() end,
            }, metrics)
        end
    end
    if #row == 0 then
        return nil
    end
    return self:buildToolbarDialog(row, metrics, {}, available_width)
end

-- Menu pages that show the preview: entering one of them opens it, and it closes itself
-- once the menu shows any other page.
function SelectionToolbar:trackPreviewPage(item_table)
    self.preview_pages = self.preview_pages or {}
    self.preview_pages[item_table] = true
    return item_table
end

function SelectionToolbar:getReaderMenu()
    local menu_container = self.ui and self.ui.menu and self.ui.menu.menu_container
    return menu_container, menu_container and menu_container[1]
end

-- Bottom of the reader menu on screen (0 when it is not shown).
function SelectionToolbar:getMenuBottom()
    local _, touch_menu = self:getReaderMenu()
    local menu_dimen = touch_menu and touch_menu.dimen
    if not menu_dimen then
        return 0
    end
    return (menu_dimen.y or 0) + (menu_dimen.h or 0)
end

-- "closed" when the menu left the preview pages, "hidden" when a dialog (e.g. an item's
-- help) is over the menu or the preview would cover the menu, else "visible".
function SelectionToolbar:isOnPreviewPage()
    local _, touch_menu = self:getReaderMenu()
    return touch_menu and touch_menu.item_table and self.preview_pages and self.preview_pages[touch_menu.item_table]
        or false
end

function SelectionToolbar:getPreviewState(preview)
    if not self:isOnPreviewPage() then
        return "closed"
    end
    local menu_container = self:getReaderMenu()
    local stack = UIManager._window_stack or {}
    for i = #stack, 1, -1 do
        local widget = stack[i].widget
        if not widget.toast then
            if widget ~= menu_container then
                return "hidden"
            end
            break
        end
    end
    if preview.dimen.y < self:getMenuBottom() + Size.padding.large then
        return "hidden"
    end
    return "visible"
end

-- Called while entering a preview page, before the menu switches to it.
function SelectionToolbar:schedulePreview()
    UIManager:nextTick(function()
        -- Also called while the menu is searched: only show it on an actual preview page.
        if self.preview or not self:isOnPreviewPage() then
            return
        end
        local preview = ToolbarPreview:new({ plugin = self })
        preview:update()
        self.preview = preview
        UIManager:show(preview, "ui", preview.dimen)
    end)
end

-- toolbar_changed: a setting changed (default), rather than only the room for the preview.
function SelectionToolbar:refreshPreview(toolbar_changed)
    local preview = self.preview
    if not preview then
        return
    end
    local old_dimen = preview.dimen
    if not preview:update(toolbar_changed ~= false) then
        return
    end
    if preview.dimen.y == old_dimen.y then
        -- Same area: the opaque sheet covers its old content, and the shadow is the same.
        UIManager:setDirty(preview, "ui", preview.dimen)
    else
        -- It moved: the page must be repainted under its old area, including the old
        -- shadow dots, which the new shadow would only add to.
        local reader = self.ui and (self.ui.dialog or self.ui)
        UIManager:setDirty(reader, "ui", old_dimen:combine(preview.dimen))
    end
end

function SelectionToolbar:closePreview(preview)
    if not preview or self.preview ~= preview then
        return
    end
    self.preview = nil
    UIManager:close(preview, "ui", preview.dimen)
end

-- Radio items for a multiple-choice setting. get and set are methods of the plugin.
-- Other items may depend on the choice, so the menu is updated after each change.
function SelectionToolbar:choiceMenuItems(choices, get, set)
    local items = {}
    for _, choice in ipairs(choices) do
        items[#items + 1] = {
            text = choice.text,
            help_text = choice.help_text,
            radio = true,
            checked_func = function()
                return get(self) == choice.id
            end,
            callback = function(touchmenu_instance)
                set(self, choice.id)
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
                self:refreshPreview()
            end,
            keep_menu_open = true,
        }
    end
    return items
end

function SelectionToolbar:addToMainMenu(menu_items)
    local action_items = {
        {
            text = _("Show all actions"),
            help_text = _("Re-enables every selection toolbar action at once."),
            callback = function()
                self:resetActions()
                UIManager:show(InfoMessage:new({ text = _("All selection toolbar actions are enabled.") }))
            end,
            separator = true,
        },
    }

    for _, action in ipairs(ACTIONS) do
        table.insert(action_items, {
            text = action.text,
            checked_func = function()
                return self:isActionEnabled(action.id)
            end,
            callback = function(touchmenu_instance)
                self:setActionEnabled(action.id, not self:isActionEnabled(action.id))
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
                self:refreshPreview()
            end,
            keep_menu_open = true,
        })
    end

    local handle_style_items = self:choiceMenuItems(HANDLE_STYLES, self.getHandleStyle, function(_, style)
        self:setHandleStyle(style, self:handleOutline())
    end)
    handle_style_items[#handle_style_items].separator = true
    table.insert(handle_style_items, {
        text = _("High-contrast outline"),
        help_text = _(
            "Black outline over white, readable over dark or highlighted text. Not for brackets."
        ),
        enabled_func = function()
            return self:canOutlineHandles()
        end,
        checked_func = function()
            return self:canOutlineHandles() and self:handleOutline()
        end,
        callback = function()
            self:setHandleStyle(self:getHandleStyle(), not self:handleOutline())
        end,
        keep_menu_open = true,
    })

    local position_items = self:choiceMenuItems(POSITIONS, self.getToolbarPosition, self.setToolbarPosition)
    local density_items = self:choiceMenuItems(DENSITIES, self.getDensity, self.setDensity)
    local icon_size_items = self:choiceMenuItems(ICON_SIZES, self.getIconSize, self.setIconSize)

    local appearance_items = {
        {
            text = _("Toolbar position"),
            help_text = _("Choose where the toolbar is shown on screen."),
            sub_item_table = position_items,
        },
        {
            text = _("Button density"),
            help_text = _("Choose the size and spacing of the toolbar buttons."),
            sub_item_table = density_items,
        },
        {
            text = _("Icon size"),
            help_text = _("Choose the size of the icons, independently of the button size."),
            sub_item_table = icon_size_items,
        },
        {
            text = _("Show toolbar shadow"),
            help_text = _("Show a small dithered shadow along the right and bottom edges of the selection toolbar."),
            checked_func = function()
                return self:showToolbarShadows()
            end,
            callback = function()
                self:setToolbarShadows(not self:showToolbarShadows())
                self:refreshPreview()
            end,
            keep_menu_open = true,
        },
    }
    for _, page in ipairs({ appearance_items, position_items, density_items, icon_size_items, action_items }) do
        self:trackPreviewPage(page)
    end

    menu_items.selectiontoolbar = {
        text = _("Selection toolbar"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Use compact selection toolbar"),
                help_text = _("Replaces KOReader's default centered selection menu with a compact icon toolbar near the selection."),
                checked_func = function()
                    return self:isEnabled()
                end,
                callback = function(touchmenu_instance)
                    self:setEnabled(not self:isEnabled())
                    if touchmenu_instance and touchmenu_instance.updateItems then
                        touchmenu_instance:updateItems()
                    end
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text = _("Appearance"),
                help_text = _("Choose where the toolbar is shown, its button and icon sizes, and whether it has a drop shadow."),
                sub_item_table_func = function()
                    self:schedulePreview()
                    return appearance_items
                end,
            },
            {
                text = _("Selection marks"),
                help_text = _("Handles to adjust the selection and a margin line beside the selected lines."),
                sub_item_table = {
                    {
                        text = _("Show selection handles"),
                        help_text = _(
                            "Drag the selection handles to adjust it, or into a page corner to continue."
                        ),
                        enabled_func = function()
                            return Device:isTouchDevice()
                        end,
                        checked_func = function()
                            return self:showHandles()
                        end,
                        callback = function(touchmenu_instance)
                            self:toggleSetting(SETTING_HANDLES, true)
                            if touchmenu_instance and touchmenu_instance.updateItems then
                                touchmenu_instance:updateItems()
                            end
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Handle style"),
                        help_text = _("Choose how the selection handles are drawn."),
                        enabled_func = function()
                            return self:showHandles()
                        end,
                        sub_item_table = handle_style_items,
                    },
                    {
                        text = _("Show line marker"),
                        help_text = _("Show a vertical line in the page margin beside the selected lines."),
                        checked_func = function()
                            return self:showLineMarker()
                        end,
                        callback = function(touchmenu_instance)
                            self:toggleSetting(SETTING_LINE_MARKER, true)
                            if touchmenu_instance and touchmenu_instance.updateItems then
                                touchmenu_instance:updateItems()
                            end
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Line marker in right margin"),
                        help_text = _(
                            "Draw the line marker in the right margin. Mirrored for right-to-left languages."
                        ),
                        enabled_func = function()
                            return self:showLineMarker()
                        end,
                        checked_func = function()
                            return self:lineMarkerOnRight()
                        end,
                        callback = function()
                            self:toggleSetting(SETTING_LINE_MARKER_RIGHT, false)
                        end,
                        keep_menu_open = true,
                    },
                },
            },
            {
                text = _("Visible actions"),
                help_text = _("Choose which actions appear in the selection toolbar."),
                sub_item_table_func = function()
                    self:schedulePreview()
                    return action_items
                end,
                separator = true,
            },
            {
                text = _("Version") .. ": " .. PLUGIN_VERSION,
                callback = function()
                    UIManager:show(InfoMessage:new({ text = _("Selection Toolbar Plugin") .. " " .. PLUGIN_VERSION }))
                end,
            },
        },
    }
end

function SelectionToolbar:patchHighlight(highlight)
    if highlight._selectiontoolbar_patched then
        return
    end

    highlight._selectiontoolbar_original_onShowHighlightMenu = highlight.onShowHighlightMenu
    local plugin = self

    highlight.onShowHighlightMenu = function(reader_highlight, index)
        if not plugin:isEnabled() then
            return reader_highlight:_selectiontoolbar_original_onShowHighlightMenu(index)
        end
        return plugin:showToolbar(reader_highlight, index)
    end

    highlight._selectiontoolbar_patched = true
end

function SelectionToolbar:getSelectedText(reader_highlight)
    if reader_highlight.selected_text then
        if reader_highlight.selected_text.text then
            return util.cleanupSelectedText(reader_highlight.selected_text.text)
        end
        if type(reader_highlight.selected_text) == "string" then
            return util.cleanupSelectedText(reader_highlight.selected_text)
        end
    end
    return ""
end

function SelectionToolbar:showQRCode(reader_highlight)
    local text = self:getSelectedText(reader_highlight)
    if text == "" then
        UIManager:show(InfoMessage:new({ text = _("No selected text.") }))
        return
    end

    self:closeHighlightDialog(reader_highlight)

    local QRMessage = self:getQRMessage()
    if not QRMessage then
        UIManager:show(InfoMessage:new({ text = _("QR code widget is not available in this KOReader build.") }))
        return
    end

    local qr_size = math_floor(math_min(Screen:getWidth(), Screen:getHeight()) * 0.85)
    UIManager:show(QRMessage:new({
        text = text,
        width = qr_size,
        height = qr_size,
    }))
end

function SelectionToolbar:makeQRButton(reader_highlight, metrics)
    return applyToolbarButtonMetrics({
        id = "selectiontoolbar_qr_code",
        icon = self:getIconPath(QR_ICON_ACTION),
        enabled = true,
        callback = function()
            self:showQRCode(reader_highlight)
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new({ text = _("Generate QR code") }))
        end,
    }, metrics)
end

function SelectionToolbar:makeButton(reader_highlight, action, index, metrics)
    if action.id == "qr_code" then
        return self:makeQRButton(reader_highlight, metrics)
    end

    local make_original = reader_highlight._highlight_buttons and reader_highlight._highlight_buttons[action.key]
    if not make_original then
        return nil
    end

    local original = make_original(reader_highlight, index)
    if not original then
        return nil
    end

    if original.show_in_highlight_dialog_func and not original.show_in_highlight_dialog_func(reader_highlight) then
        return nil
    end

    local original_callback = original.callback
    local button = applyToolbarButtonMetrics(original, metrics)
    button.id = "selectiontoolbar_" .. action.id
    button.text = nil
    button.icon = self:getIconPath(action)
    button.show_in_highlight_dialog_func = nil

    button.callback = function()
        if original_callback then
            return original_callback()
        end
    end
    button.hold_callback = function()
        UIManager:show(InfoMessage:new({ text = action.text }))
    end

    return button
end

function SelectionToolbar:getSelectionBoxes(reader_highlight, index)
    local boxes

    if index and reader_highlight.getHighlightVisibleBoxes then
        boxes = reader_highlight:getHighlightVisibleBoxes(index)
    elseif reader_highlight.selected_text then
        boxes = reader_highlight.selected_text.sboxes
    end

    if not boxes or #boxes == 0 then
        return nil
    end

    return boxes
end

function SelectionToolbar:selectionBoundingBox(reader_highlight, index)
    local boxes = self:getSelectionBoxes(reader_highlight, index)
    if not boxes then
        return nil
    end

    local min_x, min_y, max_x, max_y
    for _, box in ipairs(boxes) do
        min_x = min_x and math_min(min_x, box.x) or box.x
        min_y = min_y and math_min(min_y, box.y) or box.y
        max_x = max_x and math_max(max_x, box.x + box.w) or (box.x + box.w)
        max_y = max_y and math_max(max_y, box.y + box.h) or (box.y + box.h)
    end

    if not min_x then
        return nil
    end

    return Geom:new({ x = min_x, y = min_y, w = max_x - min_x, h = max_y - min_y })
end

function SelectionToolbar:getToolbarAnchor(reader_highlight, dialog, index)
    local selection_box = self:selectionBoundingBox(reader_highlight, index)
    if not selection_box then
        if reader_highlight._getDialogAnchor then
            return reader_highlight:_getDialogAnchor(dialog, index)
        end
        return nil
    end

    local dialog_size = dialog:getContentSize()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local gap = Size.padding.large
    -- Keep the toolbar clear of the handles' touch areas above the first and below the last line.
    local vertical_gap = gap
    if self.marks_dialog == dialog and self:showHandles() then
        vertical_gap = gap + HANDLE_TOUCH_EXTENT
    end

    if self:getToolbarPosition() == POSITION_EDGE then
        return self:getEdgeToolbarAnchor(reader_highlight, dialog, dialog_size, selection_box, vertical_gap)
    end

    local anchor_x = math_floor(selection_box.x + selection_box.w / 2 - dialog_size.w / 2)
    if anchor_x < gap then
        anchor_x = gap
    elseif anchor_x + dialog_size.w > screen_w - gap then
        anchor_x = screen_w - dialog_size.w - gap
    end

    local space_above = selection_box.y
    local space_below = screen_h - (selection_box.y + selection_box.h)
    local needed_h = dialog_size.h + vertical_gap
    if space_below < needed_h and space_above < needed_h and self.marks_dialog == dialog then
        -- The selection fills the screen: MovableContainer would squeeze the toolbar
        -- onto the text, right over a handle. Pin it to a screen edge instead.
        return self:getPinnedToolbarAnchor(reader_highlight, dialog_size, anchor_x), true
    end
    local prefer_below = space_below >= needed_h or space_below >= space_above

    if prefer_below then
        return Geom:new({ x = anchor_x, y = selection_box.y + selection_box.h + vertical_gap, w = 0, h = 0 }), true
    end

    return Geom:new({ x = anchor_x, y = selection_box.y - vertical_gap, w = 0, h = 0 }), false
end

local function overlapsHandles(rect, handles)
    for _, side in ipairs(HANDLE_SIDES) do
        local handle = handles[side]
        if handle and rect:intersectWith(handle.touch) then
            return true
        end
    end
    return false
end

-- Fixed position: centered on a screen edge, the bottom one unless the selection is in
-- the lower half of the screen (or only the top edge keeps it clear).
function SelectionToolbar:getEdgeToolbarAnchor(reader_highlight, dialog, dialog_size, selection_box, vertical_gap)
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local gap = Size.padding.large
    local centered_x = math_max(gap, math_floor((screen_w - dialog_size.w) / 2))
    local top_y = gap
    local bottom_y = math_max(top_y, screen_h - dialog_size.h - gap)

    local top_clear = top_y + dialog_size.h + vertical_gap <= selection_box.y
    local bottom_clear = bottom_y >= selection_box.y + selection_box.h + vertical_gap
    if not top_clear and not bottom_clear and self.marks_dialog == dialog then
        -- The selection fills the screen: same placement as near the selection.
        return self:getPinnedToolbarAnchor(reader_highlight, dialog_size, centered_x), true
    end

    local y
    if top_clear ~= bottom_clear then
        y = bottom_clear and bottom_y or top_y
    elseif selection_box.y + selection_box.h / 2 >= screen_h / 2 then
        y = top_y
    else
        y = bottom_y
    end
    -- w = content width keeps x as the left edge in mirrored (RTL) layouts too.
    return Geom:new({ x = centered_x, y = y, w = dialog_size.w, h = 0 }), true
end

function SelectionToolbar:getPinnedToolbarAnchor(reader_highlight, dialog_size, centered_x)
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local gap = Size.padding.large
    local top_y = gap
    local bottom_y = math_max(top_y, screen_h - dialog_size.h - gap)

    -- Prefer the edge opposite to the last selection point (handle drag or long-press
    -- pan): the user is working there and likely to adjust that end again.
    local last_pos = reader_highlight.holdpan_pos or reader_highlight.hold_pos
    local edges
    if last_pos and last_pos.y >= screen_h / 2 then
        edges = { top_y, bottom_y }
    else
        edges = { bottom_y, top_y }
    end

    -- Then slide it sideways so it covers neither handle, if the width allows it.
    -- The other edge is only used if it is the one that keeps both handles free.
    local handles = self.marks and self.marks.handles
    if handles then
        local right_x = math_max(gap, screen_w - dialog_size.w - gap)
        local xs = { centered_x, gap, right_x }
        for _, y in ipairs(edges) do
            for _, x in ipairs(xs) do
                if not overlapsHandles(Geom:new({ x = x, y = y, w = dialog_size.w, h = dialog_size.h }), handles) then
                    -- w = content width keeps x as the left edge in mirrored (RTL) layouts too.
                    return Geom:new({ x = x, y = y, w = dialog_size.w, h = 0 })
                end
            end
        end
    end

    return Geom:new({ x = centered_x, y = edges[1], w = dialog_size.w, h = 0 })
end

-- Selection marks: drag handles at both ends of the selection and a line marker in the
-- page margin. They are painted by a ReaderView module and only while the toolbar opened
-- for a live (not yet saved) selection is shown.

local function isLiveSelection(selected_text)
    return selected_text and type(selected_text.pos0) == "string" and type(selected_text.pos1) == "string"
end

-- Handles are drawn from a few simple shapes, so every style shares the same painting,
-- touch area and refresh logic.
local function rectShape(x, y, w, h, color)
    return {
        kind = "rect",
        x = math_floor(x),
        y = math_floor(y),
        w = w,
        h = h,
        color = color or Blitbuffer.COLOR_BLACK,
    }
end

-- Filled disc, or a ring when width is given.
local function circleShape(cx, cy, r, color, width)
    return { kind = "circle", cx = math_floor(cx), cy = math_floor(cy), r = r, width = width, color = color }
end

-- Grab tab hanging from the pole at pole_x and extending left or right. It is a right
-- trapezoid: straight on the pole side, the outer side and the side away from the text;
-- only the side facing the text line is slanted (slant_top: the top side, else the bottom),
-- so the tab narrows toward the text instead of covering it.
local function tabShape(pole_x, y, w, h, slant, to_left, slant_top, color)
    return {
        kind = "tab",
        pole_x = math_floor(pole_x),
        y = math_floor(y),
        w = w,
        h = h,
        slant = math_max(1, slant),
        to_left = to_left,
        slant_top = slant_top,
        color = color or Blitbuffer.COLOR_BLACK,
    }
end

local function shapeBounds(shape)
    if shape.kind == "circle" then
        return Geom:new({ x = shape.cx - shape.r, y = shape.cy - shape.r, w = 2 * shape.r + 1, h = 2 * shape.r + 1 })
    elseif shape.kind == "tab" then
        local x = shape.to_left and (shape.pole_x - shape.w) or shape.pole_x
        return Geom:new({ x = x, y = shape.y, w = shape.w, h = shape.h })
    end
    return Geom:new({ x = shape.x, y = shape.y, w = shape.w, h = shape.h })
end

local function paintShape(bb, x, y, shape)
    if shape.kind == "rect" then
        bb:paintRect(x + shape.x, y + shape.y, shape.w, shape.h, shape.color)
    elseif shape.kind == "circle" then
        bb:paintCircle(x + shape.cx, y + shape.cy, shape.r, shape.color or Blitbuffer.COLOR_BLACK, shape.width)
    elseif shape.kind == "tab" then
        -- Row by row: full width, except along the slanted side where it narrows to the pole.
        local w, h, slant = shape.w, shape.h, shape.slant
        for row = 0, h - 1 do
            local len = w
            if shape.slant_top and row < slant then
                len = math_floor(w * (row + 1) / slant + 0.5)
            elseif not shape.slant_top and row >= h - slant then
                len = math_floor(w * (h - row) / slant + 0.5)
            end
            if len > 0 then
                local px = shape.to_left and (shape.pole_x - len) or shape.pole_x
                bb:paintRect(x + px, y + shape.y + row, len, 1, shape.color)
            end
        end
    end
end

-- The vertical bar along the selection edge; in outline mode it gets a white halo so it
-- stays visible against black text.
local function barShapes(shapes, edge_x, y, h, outline)
    local bar_x = edge_x - HANDLE_BAR_WIDTH / 2
    if outline then
        shapes[#shapes + 1] =
            rectShape(bar_x - HANDLE_OUTLINE, y, HANDLE_BAR_WIDTH + 2 * HANDLE_OUTLINE, h, Blitbuffer.COLOR_WHITE)
    end
    shapes[#shapes + 1] = rectShape(bar_x, y, HANDLE_BAR_WIDTH, h)
end

-- Each style returns its shapes and the knob center (the point a finger aims at, used
-- to pick the nearest handle when touch areas overlap). Shapes must stay within
-- HANDLE_EXTENT above/below the line. With outline, the solid knob is drawn black and
-- its inside, inset by HANDLE_RING_WIDTH, white: a black outline over white.
local HANDLE_STYLE_BUILDERS = {
    lollipop = function(box, is_start, edge_x, outline)
        local r, ring = HANDLE_KNOB_RADIUS, HANDLE_RING_WIDTH
        local knob_y = is_start and (box.y - r) or (box.y + box.h + r)
        local shapes = {}
        barShapes(shapes, edge_x, box.y, box.h, outline)
        shapes[#shapes + 1] = circleShape(edge_x, knob_y, r, Blitbuffer.COLOR_BLACK)
        if outline then
            shapes[#shapes + 1] = circleShape(edge_x, knob_y, r - ring, Blitbuffer.COLOR_WHITE)
        end
        return shapes, edge_x, knob_y
    end,
    teardrop = function(box, is_start, edge_x, outline)
        -- Both drops hang below the line; a squared corner turns the disc into a drop
        -- whose point touches the selection edge.
        local r, ring = HANDLE_KNOB_RADIUS, HANDLE_RING_WIDTH
        local bottom = box.y + box.h
        local cx = is_start and (edge_x - r) or (edge_x + r)
        local cy = bottom + r
        local corner_x = is_start and (edge_x - r) or edge_x
        local shapes = {
            circleShape(cx, cy, r, Blitbuffer.COLOR_BLACK),
            rectShape(corner_x, bottom, r + 1, r + 1),
        }
        if outline then
            -- The corner inset only from its two outer sides (the point side and the top).
            local inner_corner_x = is_start and (edge_x - r) or (edge_x + ring)
            shapes[#shapes + 1] = circleShape(cx, cy, r - ring, Blitbuffer.COLOR_WHITE)
            shapes[#shapes + 1] =
                rectShape(inner_corner_x, bottom + ring, r + 1 - ring, r + 1 - ring, Blitbuffer.COLOR_WHITE)
        end
        return shapes, cx, cy
    end,
    bracket = function(box, is_start, edge_x)
        local t, serif = HANDLE_BRACKET_WIDTH, HANDLE_BRACKET_SERIF
        local top, height = box.y - t, box.h + 2 * t
        local stem_x = is_start and (edge_x - t) or edge_x
        -- Serifs point into the selection: right for "[", left for "]".
        local serif_x = is_start and stem_x or (edge_x + t - serif)
        return {
            rectShape(stem_x, top, t, height),
            rectShape(serif_x, top, serif, t),
            rectShape(serif_x, top + height - t, serif, t),
        }, stem_x + math_floor(t / 2), box.y + math_floor(box.h / 2)
    end,
    flag = function(box, is_start, edge_x, outline)
        -- A pole along the selection edge with a grab tab beyond the line: above and
        -- outward (left) at the start, below and outward (right) at the end.
        local w, h, slant, ring = HANDLE_TAB_WIDTH, HANDLE_TAB_HEIGHT, HANDLE_TAB_SLANT, HANDLE_RING_WIDTH
        local pole_top = is_start and (box.y - h) or box.y
        local tab_y = is_start and (box.y - h) or (box.y + box.h)
        local shapes = {}
        barShapes(shapes, edge_x, pole_top, box.h + h, outline)
        -- The slanted side is the one facing the text: bottom at the start, top at the end.
        shapes[#shapes + 1] = tabShape(edge_x, tab_y, w, h, slant, is_start, not is_start)
        if outline then
            -- Inset the white tab by the ring width on every side. Along the slanted side
            -- the inset must be measured perpendicular to it, so the inner diagonal is the
            -- outer one shifted by ring / cos(angle) and keeps the same slope; otherwise the
            -- black border thins out to a broken line there.
            local slope = slant / w
            local diagonal_shift = ring * math_sqrt(1 + slope * slope)
            local inner_w = w - 2 * ring
            local inner_h = math_floor(h - ring - slope * ring - diagonal_shift + 0.5)
            local inner_y = is_start and (tab_y + ring) or math_floor(tab_y + slope * ring + diagonal_shift + 0.5)
            shapes[#shapes + 1] = tabShape(
                edge_x + (is_start and -ring or ring),
                inner_y,
                inner_w,
                inner_h,
                math_floor(slope * inner_w + 0.5),
                is_start,
                not is_start,
                Blitbuffer.COLOR_WHITE
            )
        end
        return shapes, edge_x + (is_start and -1 or 1) * math_floor(w / 2), tab_y + math_floor(h / 2)
    end,
}

local function handleGeometry(box, is_start, style, outline)
    local edge_x = is_start and box.x or (box.x + box.w)
    local build = HANDLE_STYLE_BUILDERS[style] or HANDLE_STYLE_BUILDERS[DEFAULT_HANDLE_STYLE]
    local shapes, knob_x, knob_y = build(box, is_start, edge_x, outline and OUTLINE_STYLES[style] or false)
    local visual
    for _, shape in ipairs(shapes) do
        local bounds = shapeBounds(shape)
        visual = visual and visual:combine(bounds) or bounds
    end
    local touch_w = math_max(HANDLE_TOUCH_SIZE, visual.w)
    local touch_h = math_max(HANDLE_TOUCH_SIZE, visual.h)

    return {
        shapes = shapes,
        knob_x = knob_x,
        knob_y = knob_y,
        visual = visual,
        touch = Geom:new({
            x = math_floor(visual.x + visual.w / 2 - touch_w / 2),
            y = math_floor(visual.y + visual.h / 2 - touch_h / 2),
            w = touch_w,
            h = touch_h,
        }),
        -- A point inside the boundary character: where the selection end is taken from.
        tip_x = is_start and (box.x + 1) or (box.x + box.w - 1),
        tip_y = box.y + math_floor(box.h / 2),
    }
end

local function isBoundaryVisible(document, xpointer, box)
    if not box or box.y < 0 or box.y + box.h > Screen:getHeight() then
        return false
    end
    local ok, visible = pcall(document.isXPointerInCurrentPage, document, xpointer)
    return ok and visible and true or false
end

function SelectionToolbar:canShowMarks(reader_highlight, index)
    if index or not reader_highlight.hold_pos or not isLiveSelection(reader_highlight.selected_text) then
        return false
    end
    return self:showHandles() or self:showLineMarker()
end

function SelectionToolbar:getHandlePanRate()
    local rate = G_reader_settings:readSetting("hold_pan_rate")
    if not rate then
        rate = Screen.low_pan_rate and 5.0 or 30.0
    end
    return rate
end

function SelectionToolbar:computeLineMarkers(reader_highlight, boxes)
    local document = reader_highlight.ui.document
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()

    -- In two-page mode, each visible page gets its own marker.
    local page2_x
    if reader_highlight.view.view_mode == "page" and document:getVisiblePageCount() > 1 then
        page2_x = document:getPageOffsetX(document:getCurrentPage(true) + 1)
    end

    local columns = {}
    for _, box in ipairs(boxes) do
        local top = math_max(0, box.y)
        local bottom = math_min(screen_h, box.y + box.h)
        if bottom > top then
            local column = (page2_x and box.x >= page2_x) and 2 or 1
            local range = columns[column]
            if range then
                range.top = math_min(range.top, top)
                range.bottom = math_max(range.bottom, bottom)
            else
                columns[column] = { top = top, bottom = bottom }
            end
        end
    end

    -- Same margin math as ReaderView's note marks.
    local margins = document:getPageMargins()
    local on_right = self:lineMarkerOnRight()
    if BD.mirroredUILayout() then
        on_right = not on_right
    end

    local rects = {}
    for column = 1, 2 do
        local range = columns[column]
        if range then
            local x
            if on_right then
                x = screen_w - margins.right + LINE_MARKER_GAP
                if page2_x and column == 1 then
                    x = x - page2_x
                end
            else
                x = margins.left - LINE_MARKER_GAP - LINE_MARKER_WIDTH
                if page2_x and column == 2 then
                    x = x + page2_x
                end
            end
            x = math_max(0, math_min(x, screen_w - LINE_MARKER_WIDTH))
            rects[#rects + 1] = Geom:new({
                x = x,
                y = range.top,
                w = LINE_MARKER_WIDTH,
                h = range.bottom - range.top,
            })
        end
    end
    return rects
end

function SelectionToolbar:computeSelectionMarks(reader_highlight)
    local selected_text = reader_highlight.selected_text
    if not isLiveSelection(selected_text) then
        return nil
    end

    local document = reader_highlight.ui.document
    local ok, boxes =
        pcall(document.getScreenBoxesFromPositions, document, selected_text.pos0, selected_text.pos1, true)
    if not ok or not boxes or #boxes == 0 then
        return nil
    end

    local marks = { lines = {}, handles = {} }
    if self:showLineMarker() then
        marks.lines = self:computeLineMarkers(reader_highlight, boxes)
    end
    if self:showHandles() then
        local style, outline = self:getHandleStyle(), self:handleOutline()
        local first_box, last_box = boxes[1], boxes[#boxes]
        if isBoundaryVisible(document, selected_text.pos0, first_box) then
            marks.handles.start = handleGeometry(first_box, true, style, outline)
        end
        if isBoundaryVisible(document, selected_text.pos1, last_box) then
            marks.handles["end"] = handleGeometry(last_box, false, style, outline)
        end
    end

    -- Painted areas, kept separate: refreshing the thin margin line and the two handles
    -- is much cheaper on e-ink than refreshing their bounding box, which for a long
    -- selection covers most of the screen.
    local rects = {}
    for _, rect in ipairs(marks.lines) do
        rects[#rects + 1] = rect
    end
    for _, side in ipairs(HANDLE_SIDES) do
        local handle = marks.handles[side]
        if handle then
            rects[#rects + 1] = handle.visual
        end
    end
    if #rects == 0 then
        return nil
    end

    marks.rects = rects
    marks.selected_text = selected_text
    marks.boxes = boxes
    marks.view_key = self:getMarksViewKey(reader_highlight)
    return marks
end

-- What the marks' screen positions depend on besides the selection itself.
function SelectionToolbar:getMarksViewKey(reader_highlight)
    local document = reader_highlight.ui.document
    return table.concat({
        tostring(document:getCurrentPos()),
        tostring(reader_highlight.view.view_mode),
        tostring(Screen:getWidth()),
        tostring(Screen:getHeight()),
    }, ":")
end

-- The reader repaints for many reasons while the toolbar is open; only ask crengine
-- for the selection boxes again when the selection or the view actually changed.
function SelectionToolbar:getSelectionMarks(reader_highlight)
    local marks = self.marks
    if
        marks
        and marks.selected_text == reader_highlight.selected_text
        and marks.view_key == self:getMarksViewKey(reader_highlight)
    then
        return marks
    end
    return self:computeSelectionMarks(reader_highlight)
end

local function refreshRects(widget, rects)
    for _, rect in ipairs(rects) do
        UIManager:setDirty(widget, "ui", rect)
    end
end

function SelectionToolbar:paintSelectionMarks(bb, x, y)
    local reader_highlight = self.marks_highlight
    local marks = self.marks_dialog and reader_highlight and self:getSelectionMarks(reader_highlight) or nil
    self.marks = marks
    if not marks then
        return
    end

    for _, rect in ipairs(marks.lines) do
        bb:paintRect(x + rect.x, y + rect.y, rect.w, rect.h, Blitbuffer.COLOR_BLACK)
    end
    for _, handle in pairs(marks.handles) do
        for _, shape in ipairs(handle.shapes) do
            paintShape(bb, x, y, shape)
        end
    end
end

function SelectionToolbar:onToolbarClosed(dialog)
    if self.marks_dialog ~= dialog then
        return
    end

    local rects = self.marks and self.marks.rects
    local reader_highlight = self.marks_highlight
    self.marks_dialog = nil
    self.marks_highlight = nil
    self.marks = nil
    if self.drag and self.drag.dialog == dialog then
        self.drag = nil
    end

    -- Repaint the page under the marks, which were drawn on the page itself. Not needed
    -- when the toolbar is re-opened after a drag: the same marks stay on screen.
    if rects and reader_highlight and reader_highlight.dialog and not self.reopening_after_drag then
        refreshRects(reader_highlight.dialog, rects)
    end
end

function SelectionToolbar:handleAt(pos)
    local handles = self.marks and self.marks.handles
    if not (handles and pos) then
        return nil
    end

    -- Short selections may have overlapping touch areas: pick the nearest knob.
    local nearest, nearest_distance
    for _, side in ipairs(HANDLE_SIDES) do
        local handle = handles[side]
        if handle and handle.touch:contains(pos) then
            local dx, dy = pos.x - handle.knob_x, pos.y - handle.knob_y
            local distance = dx * dx + dy * dy
            if not nearest_distance or distance < nearest_distance then
                nearest, nearest_distance = side, distance
            end
        end
    end
    return nearest
end

-- Gestures that keep a handle drag going. Anything else ends it: which event
-- closes a contact depends on its timing and path (pan_release, hold_release,
-- swipe, or multiswipe when the finger changed direction within the swipe
-- interval), so the drag must not wait for one specific event or the toolbar
-- would stay hidden.
local DRAG_MOVE_GESTURES = { pan = true, hold_pan = true }
-- Lifts of the dragging contact, whose last point is applied before ending.
local DRAG_LIFT_GESTURES = { pan_release = true, hold_release = true, swipe = true, multiswipe = true }

function SelectionToolbar:endsDrag(dialog, ges)
    local drag = self.drag
    if not (drag and drag.dialog == dialog) or DRAG_MOVE_GESTURES[ges.ges] then
        return false
    end
    local lift_pos
    if DRAG_LIFT_GESTURES[ges.ges] then
        -- Swipes report the touch-down point as pos and the lift point as end_pos.
        lift_pos = ges.end_pos or ges.pos
    end
    -- Otherwise (e.g. a new "touch") the lift was never seen: just finish the drag.
    self:endHandleDrag(lift_pos)
    return true
end

function SelectionToolbar:claimsGesture(dialog, ges)
    if dialog ~= self.marks_dialog then
        return false
    end
    -- During a drag the moves belong to the handle, wherever the finger goes.
    if self.drag then
        return self.drag.dialog == dialog
    end

    -- "pan" reports the current point: hit-test where the finger went down.
    local pos = ges.start_pos or ges.pos
    if not pos then
        return false
    end
    -- Toolbar buttons keep priority where they are actually shown.
    local toolbar = not dialog.content_hidden and dialog.movable and dialog.movable.dimen
    if toolbar and toolbar:contains(pos) then
        return false
    end
    return self:handleAt(pos) ~= nil
end

function SelectionToolbar:beginHandleDrag(dialog, side, touch_pos)
    local reader_highlight = self.marks_highlight
    local handles = self.marks and self.marks.handles
    local handle = handles and handles[side]
    local selected_text = reader_highlight and reader_highlight.selected_text
    if not (handle and dialog == self.marks_dialog and isLiveSelection(selected_text)) then
        return false
    end

    -- The opposite end stays fixed: it becomes the hold position ReaderHighlight:onHoldPan()
    -- selects from, exactly as if the user had long-pressed there.
    local anchor_xpointer = side == "start" and selected_text.pos1 or selected_text.pos0
    local anchor_handle = handles[side == "start" and "end" or "start"]
    local anchor_x, anchor_y
    if anchor_handle then
        anchor_x, anchor_y = anchor_handle.tip_x, anchor_handle.tip_y
    else
        -- The opposite end is off-screen (selection scrolled across pages): crengine accepts
        -- out-of-screen coordinates, as ReaderHighlight does when scrolling from a corner.
        local document = reader_highlight.ui.document
        local ok, screen_y, screen_x = pcall(document.getScreenPositionFromXPointer, document, anchor_xpointer)
        if not (ok and screen_y and screen_x) then
            return false
        end
        anchor_x = side == "start" and (screen_x - 1) or (screen_x + 1)
        anchor_y = screen_y + 1
    end

    reader_highlight.hold_pos =
        reader_highlight.view:screenToPageTransform(Geom:new({ x = anchor_x, y = anchor_y, w = 0, h = 0 }))
    -- Lets ReaderHighlight keep the anchor in place when it scrolls from a page corner.
    reader_highlight.selected_text_start_xpointer = anchor_xpointer
    reader_highlight.allow_hold_pan_corner_scroll = false
    reader_highlight.was_in_some_corner = nil

    self.drag = {
        dialog = dialog,
        highlight = reader_highlight,
        initial_text = selected_text.text,
        -- Keep the grabbed point of the handle under the finger, so the text being
        -- selected is not hidden by it.
        offset_x = touch_pos.x - handle.tip_x,
        offset_y = touch_pos.y - handle.tip_y,
    }

    -- Hide the toolbar while dragging; it is re-anchored when the handle is released.
    dialog.content_hidden = true
    local dimen = dialog.movable and dialog.movable.dimen
    if dimen then
        UIManager:setDirty(reader_highlight.dialog, "ui", dimen)
    end
    return true
end

-- Runs fn while holding back the full-screen "ui" refreshes of the reader it requests,
-- and returns whether one was requested, so the caller can refresh a smaller region.
local function withReaderRefreshHeld(reader_dialog, fn)
    local own_set_dirty = rawget(UIManager, "setDirty")
    local set_dirty = UIManager.setDirty
    local requested = false
    UIManager.setDirty = function(uimanager, widget, refreshtype, refreshregion, ...)
        if widget == reader_dialog and refreshtype == "ui" and refreshregion == nil then
            requested = true
            return
        end
        return set_dirty(uimanager, widget, refreshtype, refreshregion, ...)
    end
    local ok, err = pcall(fn)
    UIManager.setDirty = own_set_dirty
    if not ok then
        error(err, 0)
    end
    return requested
end

-- The boundary box at the moving end of a selection: the one not holding the anchor.
local function movingEndBox(boxes, anchor)
    if not (boxes and anchor) or #boxes == 0 then
        return nil
    end
    local first, last = boxes[1], boxes[#boxes]
    if #boxes == 1 then
        return first
    end
    local function holdsAnchor(box)
        return anchor.x >= box.x and anchor.x <= box.x + box.w and anchor.y >= box.y and anchor.y <= box.y + box.h
    end
    if holdsAnchor(first) then
        return last
    elseif holdsAnchor(last) then
        return first
    end
end

-- Moving one end of the selection only changes the lines between its old and new
-- position: the highlight there, both handles' knobs (the anchor one too when the
-- ends cross) and the ends of the margin line. All of it fits in a full-width band.
local function dragRefreshBand(old_box, new_box)
    local pad = HANDLE_EXTENT + 2
    local top = math_max(0, math_min(old_box.y, new_box.y) - pad)
    local bottom = math_min(Screen:getHeight(), math_max(old_box.y + old_box.h, new_box.y + new_box.h) + pad)
    return Geom:new({ x = 0, y = top, w = Screen:getWidth(), h = bottom - top })
end

-- Screen boxes of a selection in the current view. selected_text.sboxes can be stale:
-- when ReaderHighlight scrolls from a page corner it returns before recomputing the
-- selection, so its boxes still have the coordinates from before the scroll.
function SelectionToolbar:getCurrentScreenBoxes(reader_highlight, selected_text)
    local marks = self.marks
    if
        marks
        and marks.boxes
        and marks.selected_text == selected_text
        and marks.view_key == self:getMarksViewKey(reader_highlight)
    then
        return marks.boxes
    end
    local document = reader_highlight.ui.document
    local ok, boxes =
        pcall(document.getScreenBoxesFromPositions, document, selected_text.pos0, selected_text.pos1, true)
    return ok and boxes or nil
end

-- is_final: the finger was lifted, so its last position must be applied even if it
-- moved less than DRAG_MIN_MOVE (a couple of pixels can cross a word boundary).
function SelectionToolbar:updateHandleDrag(pos, is_final)
    local drag = self.drag
    if not (drag and pos) then
        return false
    end

    local reader_highlight = drag.highlight
    local x = math_max(0, math_min(Screen:getWidth() - 1, pos.x - drag.offset_x))
    local y = math_max(0, math_min(Screen:getHeight() - 1, pos.y - drag.offset_y))
    local small_move = drag.last_x
        and math_abs(x - drag.last_x) < DRAG_MIN_MOVE
        and math_abs(y - drag.last_y) < DRAG_MIN_MOVE
    if small_move and not is_final then
        return true
    end
    drag.last_x, drag.last_y = x, y

    local document = reader_highlight.ui.document
    local view = reader_highlight.view
    local previous = reader_highlight.selected_text
    local old_box = isLiveSelection(previous)
        and movingEndBox(self:getCurrentScreenBoxes(reader_highlight, previous), reader_highlight.hold_pos)
    local view_pos, view_mode = document:getCurrentPos(), view.view_mode

    -- ReaderHighlight refreshes the whole screen on each selection change, as it cannot
    -- tell what changed. Here we can: refresh only the band of lines the moving end
    -- swept over, which saves most of the e-ink refresh work while dragging.
    local refresh_requested = withReaderRefreshHeld(reader_highlight.dialog, function()
        reader_highlight:onHoldPan(nil, { ges = "hold_pan", pos = Geom:new({ x = x, y = y, w = 0, h = 0 }) })
    end)

    if not reader_highlight.selected_text and isLiveSelection(previous) then
        -- No text at this point: keep the last valid selection instead of losing it.
        reader_highlight.selected_text = previous
        pcall(document.getTextFromXPointers, document, previous.pos0, previous.pos1, true)
        UIManager:setDirty(reader_highlight.dialog, "ui")
        return true
    end

    if refresh_requested then
        local band
        -- Fresh boxes: the view did not move during this call (checked below).
        local new_box = movingEndBox(reader_highlight.selected_text.sboxes, reader_highlight.hold_pos)
        -- Full screen when the view moved (corner scroll) or in two-page mode, where
        -- the lines between both ends are not a single vertical band.
        local single_view = view.view_mode ~= "page" or document:getVisiblePageCount() == 1
        local view_moved = view.view_mode ~= view_mode or document:getCurrentPos() ~= view_pos
        if old_box and new_box and single_view and not view_moved then
            band = dragRefreshBand(old_box, new_box)
        end
        UIManager:setDirty(reader_highlight.dialog, "ui", band)
    end
    return true
end

function SelectionToolbar:endHandleDrag(pos)
    local drag = self.drag
    if not drag then
        return false
    end

    self:updateHandleDrag(pos, true)
    self.drag = nil

    local reader_highlight = drag.highlight
    local dialog = drag.dialog
    if reader_highlight._resetHoldTimer then
        reader_highlight:_resetHoldTimer(true)
    end

    local selected_text = reader_highlight.selected_text
    if not selected_text then
        self:closeHighlightDialog(reader_highlight)
        reader_highlight:clear()
    elseif selected_text.text == drag.initial_text and reader_highlight.highlight_dialog == dialog then
        -- Unchanged selection: just show the same toolbar again.
        dialog.content_hidden = nil
        UIManager:setDirty(dialog, "ui", dialog.movable and dialog.movable.dimen)
    else
        -- Re-open the toolbar so it is anchored to the adjusted selection. The marks on
        -- screen are already up to date, so it does not need to refresh them again.
        self.reopening_after_drag = true
        local ok, err = pcall(self.showToolbar, self, reader_highlight)
        self.reopening_after_drag = nil
        if not ok then
            error(err, 0)
        end
    end
    return true
end

function SelectionToolbar:onHandleHold(dialog, ges)
    local side = self:handleAt(ges.pos)
    return side ~= nil and self:beginHandleDrag(dialog, side, ges.pos)
end

function SelectionToolbar:onHandlePan(dialog, ges)
    if self.drag then
        return self:updateHandleDrag(ges.pos)
    end
    -- "pan" is only emitted once the finger has moved: hit-test where it went down.
    local side = self:handleAt(ges.start_pos)
    if side and self:beginHandleDrag(dialog, side, ges.start_pos) then
        return self:updateHandleDrag(ges.pos)
    end
    return false
end

function SelectionToolbar:onHandleHoldPan(ges)
    return self.drag ~= nil and self:updateHandleDrag(ges.pos)
end

function SelectionToolbar:onHandleSwipe(dialog, ges)
    -- A quick flick is reported as a single swipe: apply it as a one-step drag.
    local side = self:handleAt(ges.pos)
    if side and self:beginHandleDrag(dialog, side, ges.pos) then
        return self:endHandleDrag(ges.end_pos)
    end
    return false
end

function SelectionToolbar:showToolbar(reader_highlight, index)
    local row = {}
    local metrics = getToolbarMetrics()

    local action_settings = self:getActionSettings()
    for _, action in ipairs(ACTIONS) do
        if action_settings[action.id] ~= false then
            local button = self:makeButton(reader_highlight, action, index, metrics)
            if button then
                row[#row + 1] = button
            end
        end
    end

    if #row == 0 then
        UIManager:show(InfoMessage:new({ text = _("No selection toolbar actions are enabled.") }))
        return true
    end

    self:closeHighlightDialog(reader_highlight)

    local with_marks = self:canShowMarks(reader_highlight, index)

    reader_highlight.highlight_dialog = self:buildToolbarDialog(row, metrics, {
        dismissable = true,
        handle_controller = with_marks and self or nil,
        handle_pan_rate = with_marks and self:getHandlePanRate() or nil,
        anchor = function()
            return self:getToolbarAnchor(reader_highlight, reader_highlight.highlight_dialog, index)
        end,
        tap_close_callback = function()
            if reader_highlight.hold_pos and reader_highlight.clear then
                reader_highlight:clear()
            end
        end,
    })

    if with_marks then
        self.marks_dialog = reader_highlight.highlight_dialog
        self.marks_highlight = reader_highlight
        local marks = self:computeSelectionMarks(reader_highlight)
        -- Current handle positions, for the toolbar anchor computed at its first paint.
        self.marks = marks
        if marks and not self.reopening_after_drag then
            refreshRects(reader_highlight.dialog, marks.rects)
        end
    end

    UIManager:show(reader_highlight.highlight_dialog, "[ui]")
    return true
end

return SelectionToolbar
