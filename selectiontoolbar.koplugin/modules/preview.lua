-- Live preview of the settings: ToolbarPreview, a sheet docked at the bottom of the screen
-- while a settings page that changes the toolbar or the marks is shown in the menu.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Geom = require("ui/geometry")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("selectiontoolbar_l10n")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_sqrt = math.sqrt

local C, lib = ...
local applyToolbarButtonMetrics = lib.applyToolbarButtonMetrics
local getToolbarMetrics = lib.getToolbarMetrics
local SHADOW_BAYER8 = lib.SHADOW_BAYER8
local ShadowedPopup = lib.ShadowedPopup

local SelectionToolbar = {}

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

-- Sample text of the given width and number of lines, kept while they do not change:
-- it is laid out and rendered when created, which is the costly part.
function ToolbarPreview:getSample(width, lines, face)
    local key = width .. ":" .. lines
    if self.sample_key ~= key then
        if self.sample then
            self.sample:free()
        end
        -- TextBoxWidget splits all of its text into lines: give it just enough to fill
        -- them. 0.3 em per byte is generous for Latin text (~0.5 em per character) and
        -- still enough for wide CJK glyphs (1 em for 3 bytes).
        local repeats = math.ceil(lines * width / (0.3 * face.size) / #PREVIEW_SAMPLE_TEXT) + 1
        self.sample = TextBoxWidget:new({
            text = PREVIEW_SAMPLE_TEXT:rep(repeats),
            face = face,
            width = width,
            height = lines * math_floor(1.3 * face.size + 0.5),
        })
        self.sample_key = key
    end
    return self.sample
end

-- The toolbar over the sample text, with up to PREVIEW_MAX_EXTRA_LINES lines above and
-- below it when there is room.
-- The toolbar frame (nil without visible actions), rebuilt only when settings changed.
function ToolbarPreview:getToolbar(settings_changed, inner_w)
    if settings_changed or not self.toolbar_built then
        if self.toolbar then
            self.toolbar:free()
        end
        local dialog = self.plugin:buildPreviewDialog(inner_w)
        self.toolbar = dialog and dialog.movable[1]
        self.toolbar_built = true
    end
    return self.toolbar
end

function ToolbarPreview:buildToolbarStage(settings_changed, inner_w, face, line_h, room)
    local toolbar = self:getToolbar(settings_changed, inner_w)
    local toolbar_size = toolbar and toolbar:getSize() or Geom:new({ w = 0, h = 0 })

    local toolbar_lines = math.ceil(toolbar_size.h / line_h)
    local lines
    for extra = PREVIEW_MAX_EXTRA_LINES, 0, -1 do
        lines = toolbar_lines + 2 * extra
        if lines * line_h <= room then
            break
        end
    end
    lines = math_max(lines, 1)
    local text_h = lines * line_h

    local stage = OverlapGroup:new({
        dimen = Geom:new({ w = inner_w, h = text_h }),
        self:getSample(inner_w, lines, face),
    })
    if toolbar then
        toolbar.overlap_offset = {
            math_floor((inner_w - toolbar_size.w) / 2),
            math_floor((text_h - toolbar_size.h) / 2),
        }
        stage[2] = toolbar
    end
    return stage
end

-- Lays the preview out again. Its parts are only rebuilt when settings_changed (rather
-- than only the room left by the menu). Returns whether the preview looks different.
function ToolbarPreview:update(settings_changed)
    local plugin = self.plugin
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    -- Space kept between the menu and the shadow.
    local gap = Size.padding.large
    local padding = Size.padding.large
    local side = SHEET_BORDER + padding
    local inner_w = screen_w - 2 * side
    local menu_bottom = plugin:getMenuBottom()

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
    -- Height left for the stage below the menu.
    local room = screen_h - menu_bottom - gap - fixed_h

    local stage
    if self.mode == C.PREVIEW_MARKS then
        stage = plugin:buildMarksPreview(self, inner_w, face, line_h, room)
    elseif self.mode == C.PREVIEW_FULL then
        local toolbar = self:getToolbar(settings_changed, inner_w)
        stage = plugin:buildMarksPreview(self, inner_w, face, line_h, room, toolbar)
    else
        stage = self:buildToolbarStage(settings_changed, inner_w, face, line_h, room)
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
    return settings_changed or not old_dimen or old_dimen.y ~= self.dimen.y or old_dimen.h ~= self.dimen.h
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

-- A toolbar with every visible action, as it would show for a selection.
function SelectionToolbar:buildPreviewDialog(available_width)
    local metrics = getToolbarMetrics()
    local function noop() end
    local row = self:buildActionRow(function(action)
        return applyToolbarButtonMetrics({
            id = "selectiontoolbar_preview_" .. action.id,
            icon = self:getIconPath(action),
            callback = noop,
        }, metrics)
    end)
    if #row == 0 then
        return nil
    end
    -- As it first shows for a selection: with the More button, not expanded.
    local rows = self:splitToolbarRows(row, false, self:makeMoreButton(metrics, false, noop))
    return self:buildToolbarDialog(rows, metrics, {}, available_width)
end

-- Menu pages that show the preview, and what it shows there (PREVIEW_TOOLBAR or
-- PREVIEW_MARKS): entering one of them opens it, and it closes itself once the menu
-- shows any other page.
function SelectionToolbar:trackPreviewPage(item_table, mode)
    self.preview_pages = self.preview_pages or {}
    self.preview_pages[item_table] = mode
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

-- The preview mode of the menu page being shown, or false.
function SelectionToolbar:isOnPreviewPage()
    local _, touch_menu = self:getReaderMenu()
    return touch_menu and touch_menu.item_table and self.preview_pages and self.preview_pages[touch_menu.item_table]
        or false
end

-- "closed" when the menu left the preview's pages, "hidden" when a dialog (e.g. an item's
-- help) is over the menu or the preview would cover the menu, else "visible".
function SelectionToolbar:getPreviewState(preview)
    if self:isOnPreviewPage() ~= preview.mode then
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
        local mode = self:isOnPreviewPage()
        if not mode or (self.preview and self.preview.mode == mode) then
            return
        end
        if self.preview then
            self:closePreview(self.preview)
        end
        local preview = ToolbarPreview:new({ plugin = self, mode = mode })
        preview:update()
        self.preview = preview
        UIManager:show(preview, "ui", preview.dimen)
    end)
end

-- settings_changed: a setting changed (default), rather than only the room for the preview.
function SelectionToolbar:refreshPreview(settings_changed)
    local preview = self.preview
    if not preview then
        return
    end
    local old_dimen = preview.dimen
    if not preview:update(settings_changed ~= false) then
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

return SelectionToolbar
