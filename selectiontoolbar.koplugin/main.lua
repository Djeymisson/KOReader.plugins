local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local IconWidget = require("ui/widget/iconwidget")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Size = require("ui/size")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")

local Screen = Device.screen
local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sqrt = math.sqrt

local PLUGIN_VERSION = "v1.2.0"
local QR_MESSAGE_MODULE = "ui/widget/qrmessage"

local BUTTON_ICON_SIZE = Screen:scaleBySize(22)
local BUTTON_HEIGHT = Screen:scaleBySize(42)
local BUTTON_SIDE_PADDING = Screen:scaleBySize(6)
local BUTTON_WIDTH = BUTTON_HEIGHT + 2 * BUTTON_SIDE_PADDING

local HANDLE_BAR_WIDTH = math_max(2, Screen:scaleBySize(2))
local HANDLE_KNOB_RADIUS = math_max(3, Screen:scaleBySize(7))
local HANDLE_EXTENT = 2 * HANDLE_KNOB_RADIUS
local HANDLE_TOUCH_SIZE = Screen:scaleBySize(48)
-- How far a handle's touch area can reach beyond its line (knob plus centered touch padding).
local HANDLE_TOUCH_EXTENT = math_max(HANDLE_EXTENT + 1, math.ceil(HANDLE_TOUCH_SIZE / 2) + HANDLE_KNOB_RADIUS + 1)
local LINE_MARKER_WIDTH = math_max(2, Screen:scaleBySize(3))
local LINE_MARKER_GAP = Screen:scaleBySize(6)
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
    ButtonDialog.onCloseWidget(self)
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

local function pluginDir()
    local source = debug.getinfo(1, "S").source or ""
    local path = source:match("^@(.*/)") or source:match("^(.*/)")
    return path or "plugins/selectiontoolbar.koplugin/"
end

local function applyToolbarButtonMetrics(button)
    button.icon_width = BUTTON_ICON_SIZE
    button.icon_height = BUTTON_ICON_SIZE
    button.height = BUTTON_HEIGHT
    button.width = BUTTON_WIDTH
    button.padding = BUTTON_SIDE_PADDING
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

function SelectionToolbar:showHandles()
    return Device:isTouchDevice() and G_reader_settings:nilOrTrue(SETTING_HANDLES)
end

function SelectionToolbar:showLineMarker()
    return G_reader_settings:nilOrTrue(SETTING_LINE_MARKER)
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

    local patched_init = function(icon_widget)
        local explicit_icon = rawget(icon_widget, "icon")
        if
            type(explicit_icon) == "string"
            and explicit_icon:match("%.%a+$")
            and lfs.attributes(explicit_icon, "mode") == "file"
        then
            icon_widget.file = explicit_icon
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
            end,
            keep_menu_open = true,
        })
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
                help_text = _("Show or hide the toolbar's drop shadow."),
                sub_item_table = {
                    {
                        text = _("Show toolbar shadow"),
                        help_text = _(
                            "Show a small dithered shadow along the right and bottom edges of the selection toolbar."
                        ),
                        checked_func = function()
                            return self:showToolbarShadows()
                        end,
                        callback = function()
                            self:setToolbarShadows(not self:showToolbarShadows())
                        end,
                        keep_menu_open = true,
                    },
                },
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
                        callback = function()
                            self:toggleSetting(SETTING_HANDLES, true)
                        end,
                        keep_menu_open = true,
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
                sub_item_table = action_items,
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

function SelectionToolbar:makeQRButton(reader_highlight)
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
    })
end

function SelectionToolbar:makeButton(reader_highlight, action, index)
    if action.id == "qr_code" then
        return self:makeQRButton(reader_highlight)
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
    local button = applyToolbarButtonMetrics(original)
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

local function handleGeometry(box, is_start)
    local edge_x = is_start and box.x or (box.x + box.w)
    local knob_y = is_start and (box.y - HANDLE_KNOB_RADIUS) or (box.y + box.h + HANDLE_KNOB_RADIUS)
    local bar = Geom:new({
        x = math_floor(edge_x - HANDLE_BAR_WIDTH / 2),
        y = box.y,
        w = HANDLE_BAR_WIDTH,
        h = box.h,
    })
    local knob = Geom:new({
        x = edge_x - HANDLE_KNOB_RADIUS,
        y = knob_y - HANDLE_KNOB_RADIUS,
        w = 2 * HANDLE_KNOB_RADIUS + 1,
        h = 2 * HANDLE_KNOB_RADIUS + 1,
    })
    local visual = bar:combine(knob)
    local touch_w = math_max(HANDLE_TOUCH_SIZE, visual.w)
    local touch_h = math_max(HANDLE_TOUCH_SIZE, visual.h)

    return {
        bar = bar,
        knob_x = edge_x,
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
        local first_box, last_box = boxes[1], boxes[#boxes]
        if isBoundaryVisible(document, selected_text.pos0, first_box) then
            marks.handles.start = handleGeometry(first_box, true)
        end
        if isBoundaryVisible(document, selected_text.pos1, last_box) then
            marks.handles["end"] = handleGeometry(last_box, false)
        end
    end

    local region
    for _, rect in ipairs(marks.lines) do
        region = region and region:combine(rect) or rect
    end
    for _, handle in pairs(marks.handles) do
        region = region and region:combine(handle.visual) or handle.visual
    end
    if not region then
        return nil
    end

    marks.region = region
    return marks
end

function SelectionToolbar:paintSelectionMarks(bb, x, y)
    local reader_highlight = self.marks_highlight
    local marks = self.marks_dialog and reader_highlight and self:computeSelectionMarks(reader_highlight) or nil
    self.marks = marks
    if not marks then
        return
    end

    for _, rect in ipairs(marks.lines) do
        bb:paintRect(x + rect.x, y + rect.y, rect.w, rect.h, Blitbuffer.COLOR_BLACK)
    end
    for _, handle in pairs(marks.handles) do
        local bar = handle.bar
        bb:paintRect(x + bar.x, y + bar.y, bar.w, bar.h, Blitbuffer.COLOR_BLACK)
        bb:paintCircle(x + handle.knob_x, y + handle.knob_y, HANDLE_KNOB_RADIUS, Blitbuffer.COLOR_BLACK)
    end
end

function SelectionToolbar:onToolbarClosed(dialog)
    if self.marks_dialog ~= dialog then
        return
    end

    local region = self.marks and self.marks.region
    local reader_highlight = self.marks_highlight
    self.marks_dialog = nil
    self.marks_highlight = nil
    self.marks = nil
    if self.drag and self.drag.dialog == dialog then
        self.drag = nil
    end

    -- Repaint the page under the marks, which were drawn on the page itself.
    if region and reader_highlight and reader_highlight.dialog then
        UIManager:setDirty(reader_highlight.dialog, "ui", region)
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

function SelectionToolbar:updateHandleDrag(pos)
    local drag = self.drag
    if not (drag and pos) then
        return false
    end

    local reader_highlight = drag.highlight
    local x = math_max(0, math_min(Screen:getWidth() - 1, pos.x - drag.offset_x))
    local y = math_max(0, math_min(Screen:getHeight() - 1, pos.y - drag.offset_y))
    local previous = reader_highlight.selected_text

    reader_highlight:onHoldPan(nil, { ges = "hold_pan", pos = Geom:new({ x = x, y = y, w = 0, h = 0 }) })

    if not reader_highlight.selected_text and isLiveSelection(previous) then
        -- No text at this point: keep the last valid selection instead of losing it.
        reader_highlight.selected_text = previous
        local document = reader_highlight.ui.document
        pcall(document.getTextFromXPointers, document, previous.pos0, previous.pos1, true)
        UIManager:setDirty(reader_highlight.dialog, "ui")
    end
    return true
end

function SelectionToolbar:endHandleDrag(pos)
    local drag = self.drag
    if not drag then
        return false
    end

    self:updateHandleDrag(pos)
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
        -- Re-open the toolbar so it is anchored to the adjusted selection.
        self:showToolbar(reader_highlight)
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

    local action_settings = self:getActionSettings()
    for _, action in ipairs(ACTIONS) do
        if action_settings[action.id] ~= false then
            local button = self:makeButton(reader_highlight, action, index)
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

    local button_size = BUTTON_WIDTH
    local show_shadow = self:showToolbarShadows()
    local shadow_extent = show_shadow and SHADOW_EXTENT or 0
    local width = math_min(
        Screen:getWidth() - 2 * Size.padding.large - shadow_extent,
        #row * button_size + 2 * Size.border.window + 2 * Size.padding.button
    )
    local with_marks = self:canShowMarks(reader_highlight, index)

    reader_highlight.highlight_dialog = ShadowedButtonDialog:new({
        buttons = { row },
        width = width,
        show_shadow = show_shadow,
        shrink_unneeded_width = true,
        shrink_min_width = button_size,
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
        if marks then
            UIManager:setDirty(reader_highlight.dialog, "ui", marks.region)
        end
    end

    UIManager:show(reader_highlight.highlight_dialog, "[ui]")
    return true
end

return SelectionToolbar
