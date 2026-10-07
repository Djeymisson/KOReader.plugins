local datetime = require("datetime")
local Device = require("device")
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

-- Helpers shared by the information panel's data, covers and rendering.
local Util = {}

function Util.safeCall(callback, fallback)
    local ok, result = pcall(callback)
    if ok and result ~= nil then
        return result
    end
    return fallback
end

function Util.clamp(value, minimum, maximum)
    return math_max(minimum, math_min(maximum, tonumber(value) or minimum))
end

function Util.freeBlitBuffer(bb)
    if bb and bb.free then
        pcall(bb.free, bb)
    end
end

-- Fits an image within width x height, keeping its proportions; it is only
-- enlarged with enlarge. Takes ownership of bb: returns it unchanged, or
-- frees it and returns a scaled copy. Returns nil when the image cannot be
-- read or scaled.
function Util.fitImage(bb, width, height, enlarge)
    local image_width = tonumber(Util.safeCall(function() return bb:getWidth() end, nil))
    local image_height = tonumber(Util.safeCall(function() return bb:getHeight() end, nil))
    if not image_width or not image_height or image_width <= 0 or image_height <= 0 then
        Util.freeBlitBuffer(bb)
        return nil
    end
    local scale = math_min(width / image_width, height / image_height)
    if not enlarge then
        scale = math_min(1, scale)
    end
    local target_width = math_max(1, math_floor(image_width * scale + 0.5))
    local target_height = math_max(1, math_floor(image_height * scale + 0.5))
    if scale == 1 then
        return bb, target_width, target_height
    end
    local ok, scaled_bb = pcall(
        RenderImage.scaleBlitBuffer,
        RenderImage,
        bb,
        target_width,
        target_height,
        false
    )
    Util.freeBlitBuffer(bb)
    if not ok or not scaled_bb then
        return nil
    end
    return scaled_bb, target_width, target_height
end

function Util.scaleFactor(metrics)
    return tonumber(metrics and metrics.scale_factor) or 1
end

-- A length in screen-independent units, scaled with the dock size.
function Util.scaled(metrics, size)
    return math_floor(Screen:scaleBySize(size) * Util.scaleFactor(metrics) + 0.5)
end

-- Padding inside a panel's frame.
function Util.panelPadding(metrics)
    return math_max(Size.padding.small, Util.scaled(metrics, 8))
end

function Util.screenMargin(screen_margin)
    return math_max(0, tonumber(screen_margin) or Size.padding.large)
end

function Util.maximumPanelWidth(screen_margin)
    return math_max(
        Screen:scaleBySize(110),
        math_floor(Screen:getWidth() / 2) - 2 * Util.screenMargin(screen_margin)
    )
end

-- Width of the text inside a side panel.
function Util.panelContentWidth(metrics, maximum_outer_width)
    local padding = Util.panelPadding(metrics)
    local screen_short_side = math_min(Screen:getWidth(), Screen:getHeight())
    local width = math_max(
        math_floor((metrics and metrics.button_width or Screen:scaleBySize(54)) * 2.5),
        math_min(math_floor(screen_short_side * 0.34), math_floor(Screen:getWidth() * 0.38))
    )
    local outer_horizontal_space = 2 * (padding + Size.border.button)
    local maximum_content_width = math_max(
        Screen:scaleBySize(90),
        math_floor(tonumber(maximum_outer_width) or Screen:getWidth()) - outer_horizontal_space
    )
    return math_min(width, maximum_content_width)
end

function Util.fileTitle(file)
    local name = tostring(file or ""):match("([^/]+)$") or tostring(file or "")
    return (name:gsub("%.[^.]+$", ""))
end

function Util.compactDuration(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then
        return nil
    end
    local duration_format = G_reader_settings:readSetting("duration_format", "classic")
    return datetime.secondsToClockDuration(duration_format, seconds, true, false, true)
end

return Util
