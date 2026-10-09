-- The saved settings, as methods of the plugin: getters with validation and defaults,
-- setters, style presets, visible actions, action order and resets.

local Device = require("device")
local Size = require("ui/size")

local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sqrt = math.sqrt

local C, lib = ...
local findChoice = lib.findChoice
local readChoice = lib.readChoice
local clearToolbarShadowCache = lib.clearToolbarShadowCache

local SelectionToolbar = {}

function SelectionToolbar:isEnabled()
    return G_reader_settings:readSetting(C.SETTING_ENABLED) ~= false
end

function SelectionToolbar:setEnabled(enabled)
    G_reader_settings:saveSetting(C.SETTING_ENABLED, enabled and true or false)
end

-- Up to v1.8.0 the shadow could only be turned on or off: an unset style reads the
-- old on/off setting.
function SelectionToolbar:getShadowStyle()
    local style = findChoice(C.SHADOW_STYLES, G_reader_settings:readSetting(C.SETTING_SHADOW_STYLE))
    if style then
        return style.id
    end
    return G_reader_settings:isFalse(C.SETTING_SHADOWS) and C.SHADOW_NONE or C.DEFAULT_SHADOW_STYLE
end

function SelectionToolbar:setShadowStyle(style)
    G_reader_settings:saveSetting(C.SETTING_SHADOW_STYLE, style)
    -- Free the cached shadow: it does not match the new style.
    clearToolbarShadowCache()
end

-- The chosen shadow finish, or nil without a shadow.
function SelectionToolbar:getShadowFinish()
    return findChoice(C.SHADOW_STYLES, self:getShadowStyle()).finish
end

function SelectionToolbar:getToolbarPosition()
    return readChoice(C.SETTING_POSITION, C.POSITIONS, C.POSITION_NEAR).id
end

function SelectionToolbar:setToolbarPosition(position)
    G_reader_settings:saveSetting(C.SETTING_POSITION, position)
end

function SelectionToolbar:getDensity()
    return readChoice(C.SETTING_DENSITY, C.DENSITIES, C.DEFAULT_DENSITY).id
end

function SelectionToolbar:setDensity(density)
    G_reader_settings:saveSetting(C.SETTING_DENSITY, density)
end

function SelectionToolbar:getShape()
    return readChoice(C.SETTING_SHAPE, C.SHAPES, C.DEFAULT_SHAPE).id
end

function SelectionToolbar:setShape(shape)
    G_reader_settings:saveSetting(C.SETTING_SHAPE, shape)
end

function SelectionToolbar:getBorder()
    return readChoice(C.SETTING_BORDER, C.BORDERS, C.DEFAULT_BORDER).id
end

function SelectionToolbar:setBorder(border)
    G_reader_settings:saveSetting(C.SETTING_BORDER, border)
end

function SelectionToolbar:getSeparators()
    return readChoice(C.SETTING_SEPARATORS, C.SEPARATOR_STYLES, C.DEFAULT_SEPARATORS).id
end

function SelectionToolbar:setSeparators(separators)
    G_reader_settings:saveSetting(C.SETTING_SEPARATORS, separators)
end

-- Border, corner radius and side padding of the toolbar frame for the chosen shape and
-- border. Known before the toolbar is built, as its width depends on them.
-- row_count: the number of button rows (two with the More row shown).
function SelectionToolbar:getFrameStyle(metrics, row_count)
    local border = readChoice(C.SETTING_BORDER, C.BORDERS, C.DEFAULT_BORDER).width
    local shape = self:getShape()
    local style = { border = border, radius = 0, padding_h = Size.padding.button }
    if shape == C.SHAPE_CAPSULE then
        -- ButtonTable: a span above and below each row of buttons, which have their own
        -- vertical padding, and a separator line between rows; ButtonDialog's frame adds
        -- no padding at the top or bottom. The ends stay fully round with several rows.
        local span = Size.span.vertical_default
        local row_h = metrics.button_height + 2 * Size.padding.buttontable + 2 * span
        local height = row_count * row_h + (row_count - 1) * Size.line.medium + 2 * border
        local radius = math_floor(height / 2)
        -- Keep each button's corners inside the curve's inner edge: the buttons paint
        -- their own background (and invert it when tapped), which would cover the border.
        local inner_r = radius - border
        local dy = radius - (border + span)
        local inset = radius - math_sqrt(math_max(0, inner_r * inner_r - dy * dy))
        style.radius = radius
        style.padding_h = math_max(Size.padding.button, math.ceil(inset))
    elseif shape == C.DEFAULT_SHAPE then
        style.radius = Size.radius.window
    end
    return style
end

function SelectionToolbar:getIconSize()
    return readChoice(C.SETTING_ICON_SIZE, C.ICON_SIZES, C.DEFAULT_ICON_SIZE).id
end

function SelectionToolbar:setIconSize(icon_size)
    G_reader_settings:saveSetting(C.SETTING_ICON_SIZE, icon_size)
end

function SelectionToolbar:showHandles()
    return Device:isTouchDevice() and G_reader_settings:nilOrTrue(C.SETTING_HANDLES)
end

function SelectionToolbar:showLineMarker()
    return G_reader_settings:nilOrTrue(C.SETTING_LINE_MARKER)
end

function SelectionToolbar:getHandleStyle()
    -- A legacy "wireframe" style is not a known choice: it reads as the default one.
    return readChoice(C.SETTING_HANDLE_STYLE, C.HANDLE_STYLES, C.DEFAULT_HANDLE_STYLE).id
end

function SelectionToolbar:handleOutline()
    return G_reader_settings:isTrue(C.SETTING_HANDLE_OUTLINE)
        or G_reader_settings:readSetting(C.SETTING_HANDLE_STYLE) == C.LEGACY_WIREFRAME_STYLE
end

-- Saving either setting also resolves a legacy "wireframe" style into its two parts.
function SelectionToolbar:setHandleStyle(style, outline)
    G_reader_settings:saveSetting(C.SETTING_HANDLE_STYLE, style)
    G_reader_settings:saveSetting(C.SETTING_HANDLE_OUTLINE, outline and true or false)
end

function SelectionToolbar:canOutlineHandles()
    return C.OUTLINE_STYLES[self:getHandleStyle()] or false
end

function SelectionToolbar:getHandleSize()
    return readChoice(C.SETTING_HANDLE_SIZE, C.HANDLE_SIZES, C.DEFAULT_HANDLE_SIZE).id
end

function SelectionToolbar:setHandleSize(size)
    G_reader_settings:saveSetting(C.SETTING_HANDLE_SIZE, size)
end

-- The current look, in the form of a preset's look. The outline counts only where the
-- handle style can have one.
function SelectionToolbar:getLook()
    return {
        density = self:getDensity(),
        icon_size = self:getIconSize(),
        shape = self:getShape(),
        border = self:getBorder(),
        separators = self:getSeparators(),
        shadow = self:getShadowStyle(),
        handle_style = self:getHandleStyle(),
        handle_outline = self:canOutlineHandles() and self:handleOutline() or false,
        handle_size = self:getHandleSize(),
        marker_width = self:getLineMarkerWidth(),
    }
end

-- The id of the preset matching the current look, or nil for a custom look.
function SelectionToolbar:getStylePreset()
    local look = self:getLook()
    for _, preset in ipairs(C.STYLE_PRESETS) do
        local matches = true
        for key, value in pairs(preset.look) do
            if look[key] ~= value then
                matches = false
                break
            end
        end
        if matches then
            return preset.id
        end
    end
end

function SelectionToolbar:applyStylePreset(id)
    local look = findChoice(C.STYLE_PRESETS, id).look
    self:setDensity(look.density)
    self:setIconSize(look.icon_size)
    self:setShape(look.shape)
    self:setBorder(look.border)
    self:setSeparators(look.separators)
    self:setShadowStyle(look.shadow)
    self:setHandleStyle(look.handle_style, look.handle_outline)
    self:setHandleSize(look.handle_size)
    self:setLineMarkerWidth(look.marker_width)
end

function SelectionToolbar:getMainActions()
    return readChoice(C.SETTING_MAIN_ACTIONS, C.MAIN_ACTION_COUNTS, C.DEFAULT_MAIN_ACTIONS).id
end

function SelectionToolbar:setMainActions(main_actions)
    G_reader_settings:saveSetting(C.SETTING_MAIN_ACTIONS, main_actions)
end

function SelectionToolbar:getLineMarkerWidth()
    return readChoice(C.SETTING_LINE_MARKER_WIDTH, C.LINE_MARKER_WIDTHS, C.DEFAULT_LINE_MARKER_WIDTH).id
end

function SelectionToolbar:setLineMarkerWidth(width)
    G_reader_settings:saveSetting(C.SETTING_LINE_MARKER_WIDTH, width)
end

function SelectionToolbar:getLineMarkerGap()
    return readChoice(C.SETTING_LINE_MARKER_GAP, C.LINE_MARKER_GAPS, C.DEFAULT_LINE_MARKER_GAP).id
end

function SelectionToolbar:setLineMarkerGap(gap)
    G_reader_settings:saveSetting(C.SETTING_LINE_MARKER_GAP, gap)
end

-- Line marker width and its distance from the text, in screen pixels, for a page margin
-- of the given width. The marker must stay in the margin: when it is too narrow, the
-- distance is reduced first, then the width. Without any margin there is no marker (nil).
function SelectionToolbar:getLineMarkerSize(margin)
    margin = math_floor(margin or 0)
    if margin <= 0 then
        return nil
    end
    local width = readChoice(C.SETTING_LINE_MARKER_WIDTH, C.LINE_MARKER_WIDTHS, C.DEFAULT_LINE_MARKER_WIDTH).width
    local gap = readChoice(C.SETTING_LINE_MARKER_GAP, C.LINE_MARKER_GAPS, C.DEFAULT_LINE_MARKER_GAP).gap
    width = math_min(width, margin)
    return width, math_max(0, math_min(gap, margin - width))
end

function SelectionToolbar:lineMarkerOnRight()
    return G_reader_settings:isTrue(C.SETTING_LINE_MARKER_RIGHT)
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
    local settings = G_reader_settings:readSetting(C.SETTING_ACTIONS)
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
    G_reader_settings:saveSetting(C.SETTING_ACTIONS, settings)
end

local function deleteSetting(setting, empty_value)
    if G_reader_settings.delSetting then
        G_reader_settings:delSetting(setting)
    else
        G_reader_settings:saveSetting(setting, empty_value)
    end
end

function SelectionToolbar:resetActions()
    deleteSetting(C.SETTING_ACTIONS, {})
end

-- The saved toolbar order, made valid: each known action once (actions added in a later
-- version go at the end) and exactly GROUP_SEPARATOR_COUNT group separators.
function SelectionToolbar:getActionOrder()
    local saved = G_reader_settings:readSetting(C.SETTING_ACTION_ORDER)
    local order, seen, separators = {}, {}, 0
    for _, id in ipairs(type(saved) == "table" and saved or C.DEFAULT_ACTION_ORDER) do
        if id == C.GROUP_SEPARATOR then
            if separators < C.GROUP_SEPARATOR_COUNT then
                separators = separators + 1
                order[#order + 1] = id
            end
        elseif C.ACTIONS_BY_ID[id] and not seen[id] then
            seen[id] = true
            order[#order + 1] = id
        end
    end
    for _, action in ipairs(C.ACTIONS) do
        if not seen[action.id] then
            order[#order + 1] = action.id
        end
    end
    for _ = separators + 1, C.GROUP_SEPARATOR_COUNT do
        order[#order + 1] = C.GROUP_SEPARATOR
    end
    return order
end

function SelectionToolbar:setActionOrder(order)
    G_reader_settings:saveSetting(C.SETTING_ACTION_ORDER, order)
end

function SelectionToolbar:resetActionOrder()
    -- An empty list would read as an order without any action: delete it instead.
    deleteSetting(C.SETTING_ACTION_ORDER, C.DEFAULT_ACTION_ORDER)
end

-- Every setting but the one turning the plugin on, including the legacy shadow switch.
local RESETTABLE_SETTINGS = {
    C.SETTING_SHADOWS,
    C.SETTING_HANDLES,
    C.SETTING_LINE_MARKER,
    C.SETTING_LINE_MARKER_RIGHT,
    C.SETTING_HANDLE_STYLE,
    C.SETTING_HANDLE_OUTLINE,
    C.SETTING_POSITION,
    C.SETTING_DENSITY,
    C.SETTING_ICON_SIZE,
    C.SETTING_SHAPE,
    C.SETTING_BORDER,
    C.SETTING_SEPARATORS,
    C.SETTING_SHADOW_STYLE,
    C.SETTING_MAIN_ACTIONS,
    C.SETTING_HANDLE_SIZE,
    C.SETTING_LINE_MARKER_WIDTH,
    C.SETTING_LINE_MARKER_GAP,
}

function SelectionToolbar:resetAllSettings()
    for _, setting in ipairs(RESETTABLE_SETTINGS) do
        deleteSetting(setting, nil)
    end
    self:resetActions()
    self:resetActionOrder()
    clearToolbarShadowCache()
end

function SelectionToolbar:countEnabledActions()
    local count = 0
    for _, action in ipairs(C.ACTIONS) do
        if self:isActionEnabled(action.id) then
            count = count + 1
        end
    end
    return count
end

return SelectionToolbar
