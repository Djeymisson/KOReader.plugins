-- Toolbar button and handle sizes in screen pixels, computed once for each combination
-- of the settings they depend on.

local Device = require("device")
local Size = require("ui/size")

local Screen = Device.screen
local math_max = math.max
local math_min = math.min

local C, lib = ...
local readChoice = lib.readChoice

-- Toolbar sizes for the chosen density and icon size, in screen pixels.
local toolbar_metrics_cache = {}

local function getToolbarMetrics()
    local density = readChoice(C.SETTING_DENSITY, C.DENSITIES, C.DEFAULT_DENSITY)
    local icon_size = readChoice(C.SETTING_ICON_SIZE, C.ICON_SIZES, C.DEFAULT_ICON_SIZE)
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

-- Handle shape sizes for the chosen handle size, in screen pixels.
local handle_metrics_cache = {}

local function getHandleMetrics()
    local size = readChoice(C.SETTING_HANDLE_SIZE, C.HANDLE_SIZES, C.DEFAULT_HANDLE_SIZE)
    local m = handle_metrics_cache[size.id]
    if m then
        return m
    end
    local function px(value, min)
        return math_max(min, Screen:scaleBySize(value * size.scale))
    end
    m = {
        bar_width = px(2, 2),
        -- An outlined knob must keep some white inside its ring.
        knob_radius = math_max(px(7, 3), C.HANDLE_RING_WIDTH + 2),
        -- Flag tab: a trapezoid grab area beyond the line.
        tab_height = px(22, 8),
        tab_width = px(16, 6),
        tab_slant = px(10, 3),
        bracket_width = px(3, 2),
        bracket_serif = px(7, 4),
    }
    -- Every handle style stays within this distance beyond its line (toolbar gap and
    -- drag refresh band rely on it).
    m.extent = math_max(2 * m.knob_radius, m.tab_height)
    -- How far a handle's touch area can reach beyond its line (knob plus centered touch padding).
    m.touch_extent = math_max(m.extent + 1, math.ceil(C.HANDLE_TOUCH_SIZE / 2) + m.knob_radius + 1)
    handle_metrics_cache[size.id] = m
    return m
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

return {
    getToolbarMetrics = getToolbarMetrics,
    getHandleMetrics = getHandleMetrics,
    applyToolbarButtonMetrics = applyToolbarButtonMetrics,
}
