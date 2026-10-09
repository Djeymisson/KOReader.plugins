-- The dithered shadow drawn around the toolbar, and ShadowedPopup, the widget that paints
-- a popup with it. The shadow buffers are cached and shared between toolbar openings.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")

local Screen = Device.screen
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local math_sqrt = math.sqrt

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
    local shadow = self.shadow
    local size = self[1]:getSize()
    return Geom:new({
        w = size.w + shadow.extent,
        h = size.h + shadow.extent,
    })
end

function ShadowedPopup:_ensureShadowBuffers(bb, width, height)
    local shadow = self.shadow
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
        shadow.id,
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
        local t = (pos + 0.5) / shadow.width
        local original_level = base_strength * baseFraction(t)
        local visible_start = shadow.overlap / shadow.width
        local bump
        if t <= visible_start then
            bump = 1
        else
            local distance = (t - visible_start) / bump_width
            bump = distance < 1 and 0.5 * (1 + math.cos(math.pi * distance)) or 0
        end
        return (original_level + bump * (peak_level - original_level)) * shadow.strength * 255
    end

    TOOLBAR_SHADOW_CACHE.right = Blitbuffer.new(shadow.width, height, Blitbuffer.TYPE_BBRGB32)
    for x = 0, shadow.width - 1 do
        local column = (x % 8) + 1
        for y = 0, height - 1 do
            local level
            if radius > 0 then
                local distance = roundedRectDistance(width - shadow.overlap + x, y, width, height, radius)
                local shadow_pos = shadow.overlap + distance
                level = shadow_pos >= 0 and shadow_pos < shadow.width and shadowLevel(shadow_pos) or 0
            else
                level = shadowLevel(x)
            end
            local threshold = (SHADOW_BAYER8[column][(y % 8) + 1] + 0.5) * 4
            local color = level > threshold and shadow_on or shadow_off
            TOOLBAR_SHADOW_CACHE.right:setPixel(x, y, color)
        end
    end
    TOOLBAR_SHADOW_CACHE.right:setInverse(render_inv and 1 or 0)

    local bottom_width = width + shadow.extent
    TOOLBAR_SHADOW_CACHE.bottom = Blitbuffer.new(bottom_width, shadow.width, Blitbuffer.TYPE_BBRGB32)
    for y = 0, shadow.width - 1 do
        local bottom_level = shadowLevel(y)
        local row = (y % 8) + 1
        for x = 0, bottom_width - 1 do
            local level
            if radius > 0 then
                if y < shadow.overlap and x >= width - shadow.overlap then
                    level = 0
                else
                    local distance = roundedRectDistance(x, height - shadow.overlap + y, width, height, radius)
                    local shadow_pos = shadow.overlap + distance
                    level = shadow_pos >= 0 and shadow_pos < shadow.width and shadowLevel(shadow_pos) or 0
                end
            else
                level = bottom_level
                if y < shadow.overlap and x >= width - shadow.overlap then
                    level = 0
                elseif x >= width then
                    level = math_min(level, shadowLevel(shadow.overlap + x - width))
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
    local shadow = self.shadow
    local content_size = self[1]:getSize()
    local width, height = content_size.w, content_size.h
    self:_ensureShadowBuffers(bb, width, height)
    self.dimen = Geom:new({
        x = x,
        y = y,
        w = width + shadow.extent,
        h = height + shadow.extent,
    })
    self:_alphaBlitClipped(bb, TOOLBAR_SHADOW_CACHE.bottom, x, y + height - shadow.overlap)
    self:_alphaBlitClipped(bb, TOOLBAR_SHADOW_CACHE.right, x + width - shadow.overlap, y)
    self[1]:paintTo(bb, x, y)
end

return {
    SHADOW_BAYER8 = SHADOW_BAYER8,
    ShadowedPopup = ShadowedPopup,
    clearToolbarShadowCache = clearToolbarShadowCache,
}
