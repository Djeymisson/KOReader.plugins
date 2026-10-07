local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local time = require("ui/time")

local Screen = Device.screen
local math_ceil = math.ceil
local math_cos = math.cos
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sin = math.sin
local math_sqrt = math.sqrt

local QUARTER_TURN = math.pi / 2
-- Minimum travel along the ring, as a fraction of the quarter turn, for a
-- swipe or a released drag to change the page (about 11 degrees).
local PAGE_SWIPE_THRESHOLD = 0.12

-- Paints a filled disc one scanline at a time. paintRect is a single C fill
-- per row, which is much cheaper than Blitbuffer.paintCircle's per-pixel Lua
-- loop for the discs this widget paints on every repaint.
local function fillDisc(bb, center_x, center_y, radius, color)
    radius = math_floor(radius + 0.5)
    if radius <= 0 then
        return
    end
    local radius_squared = radius * radius
    for dy = -radius, radius do
        local half_width = math_floor(math_sqrt(radius_squared - dy * dy) + 0.5)
        bb:paintRect(center_x - half_width, center_y + dy, 2 * half_width + 1, 1, color)
    end
end

-- One item on a ring: an action, a navigation arrow or a lighting control.
-- It keeps the setIcon() interface of Button, so the in-place refresh of the
-- Wi-Fi and night-mode actions works unchanged on both dock shapes.
local ArcItem = {}
ArcItem.__index = ArcItem

function ArcItem.new(config)
    return setmetatable(config, ArcItem)
end

function ArcItem:setIcon(icon)
    self.icon = icon
end

function ArcItem:getLabel()
    if self.display_provider then
        return self.display_provider()
    elseif self.icon_provider then
        local icon = self.icon_provider()
        return icon, icon == nil and self.text or nil
    end
    return self.icon, self.icon == nil and self.text or nil
end

function ArcItem:freeLabel()
    if self.label_widget then
        self.label_widget:free()
        self.label_widget = nil
    end
    self.label_key = nil
end

function ArcItem:getLabelWidget(icon_size, font_size)
    local icon, text = self:getLabel()
    local key = (icon and ("icon:" .. icon) or ("text:" .. tostring(text or "?")))
        .. "@" .. icon_size .. "/" .. font_size
    if key ~= self.label_key then
        self:freeLabel()
        if icon then
            self.label_widget = IconWidget:new({
                icon = icon,
                width = icon_size,
                height = icon_size,
            })
        else
            self.label_widget = TextWidget:new({
                text = tostring(text or "?"),
                face = Font:getFace("cfont", font_size),
                bold = true,
            })
        end
        self.label_key = key
    end
    return self.label_widget
end

local ArcDock = InputContainer:extend({
    side = "right",
    page = 1,
    mode = "actions",
    -- Whether the ring buttons sit on an opaque band or float on the page.
    show_band = true,
    -- Whether a page's buttons are spread along the whole arc (true) or keep
    -- the spacing of a full page, leaving the rest of the arc empty at its
    -- "end" (next to the side edge) or its "start" (next to the bottom edge).
    fill = false,
    empty_space = "end",
})

-- A curve parallel to the quarter ellipse with semi-axes rx (along the
-- bottom edge) and ry (along the side edge), offset along its normal
-- (negative offsets move toward the corner), sampled by arc length.
-- Points are relative to the corner center: dx grows toward the middle of
-- the screen and dy grows upward, so both sides of the screen share it.
local CURVE_SAMPLES = 360

local function buildCurve(rx, ry, offset)
    local samples = {}
    local length = 0
    local previous_x, previous_y
    for index = 0, CURVE_SAMPLES do
        local angle = index / CURVE_SAMPLES * QUARTER_TURN
        local cosine, sine = math_cos(angle), math_sin(angle)
        local normal_x, normal_y = cosine / rx, sine / ry
        local normal_length = math_sqrt(normal_x * normal_x + normal_y * normal_y)
        local x = rx * cosine + offset * normal_x / normal_length
        local y = ry * sine + offset * normal_y / normal_length
        if previous_x then
            local step_x, step_y = x - previous_x, y - previous_y
            length = length + math_sqrt(step_x * step_x + step_y * step_y)
        end
        samples[index + 1] = { x = x, y = y, s = length }
        previous_x, previous_y = x, y
    end
    return { samples = samples, length = length }
end

-- Point at fraction a of the curve's length, relative to the corner center.
local function curvePoint(curve, a)
    local samples = curve.samples
    local target = math_max(0, math_min(1, a)) * curve.length
    local low, high = 1, #samples
    while high - low > 1 do
        local middle = math_floor((low + high) / 2)
        if samples[middle].s < target then
            low = middle
        else
            high = middle
        end
    end
    local first, second = samples[low], samples[high]
    local span = second.s - first.s
    local t = span > 0 and (target - first.s) / span or 0
    return first.x + (second.x - first.x) * t, first.y + (second.y - first.y) * t
end

-- Nearest sample to a point given relative to the corner center: its
-- fraction of the curve's length and its distance. Past either end, the
-- nearest sample is that end, so the distance rounds the band's caps.
local function curveLocate(curve, dx, dy)
    local best_distance, best_s
    for _index, sample in ipairs(curve.samples) do
        local ex, ey = dx - sample.x, dy - sample.y
        local distance = ex * ex + ey * ey
        if not best_distance or distance < best_distance then
            best_distance, best_s = distance, sample.s
        end
    end
    return best_s / math_max(1, curve.length), math_sqrt(best_distance)
end

-- Geometry shared by the dock and by the pagination done before the dock is
-- created: the corner the arc turns around, its curves and how many items
-- fit on it. Positions along the arc are a fraction a of its length, from 0
-- at the end near the bottom edge to 1 at the end near the side edge.
--
-- The arc is a quarter ellipse whose tilt is set by options.angle: the angle
-- between the bottom edge and the line joining both ends. At 45 degrees it
-- is a quarter circle; steeper angles bring the bottom end closer to the
-- side and make the arc taller, shallower ones make it wider and lower. The
-- semi-axes keep the circle's area, so the arc keeps about the same size.
--
-- The arc holds a single row with the actions and their page arrows. The
-- fixed controls (side switch, lighting, panel switch, close) float apart,
-- inside it, on a parallel curve starting at the bottom end.
-- How much the ring buttons may grow to fill an arc with room to spare.
local MAX_BUTTON_GROWTH = 1.5

local function buildGeometry(side, metrics, options, button_scale)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local margin = options.margin
    local clearance = math_max(0, options.bottom_clearance or 0)
    local diameter = math_floor(metrics.button_width * button_scale + 0.5)
    local pad = metrics.side_button_gap
    local floating_count = options.floating_count or 0
    local minimum_rows = options.minimum_rows or 3

    local band_width = diameter + 2 * pad
    local half_band = math_floor(band_width / 2)
    local slot = diameter + pad

    -- Floating buttons: smaller discs, a gap away from the band's inner edge.
    local floating_radius = math_floor(metrics.arc_utility_diameter / 2) + pad
    local floating_slot = 2 * floating_radius + pad
    local floating_inset = half_band + 2 * pad + floating_radius

    local tilt = math.tan(math.rad(math_max(10, math_min(80, options.angle or 45))))
    local ratio = math_sqrt(tilt)
    local radius = metrics.arc_radius
    local rx, ry = radius / ratio, radius * ratio

    -- Room left by the screen and by the maximum dock height, measured from
    -- the corner center, which sits half a band away from both edges.
    local corner_inset = margin + half_band
    local maximum_x = screen_width - margin - corner_inset - half_band
    local maximum_y = math_floor(screen_height * options.max_height_factor)
        - corner_inset - clearance - half_band
    local fit = math_min(1, maximum_x / rx, maximum_y / ry)
    rx, ry = rx * fit, ry * fit

    local curve, floating_curve, capacity
    for _attempt = 1, 40 do
        curve = buildCurve(rx, ry, 0)
        capacity = math_max(2, math_floor(curve.length / slot) + 1)
        floating_curve = floating_count > 0 and buildCurve(rx, ry, -floating_inset) or nil
        local floating_fits = not floating_curve
            or floating_curve.length >= (floating_count - 1) * floating_slot
        if capacity >= minimum_rows and floating_fits then
            break
        end
        -- Too small for the minimum: grow past the limits, as the column does.
        rx, ry = rx * 1.05, ry * 1.05
    end

    local floating_step = 0
    if floating_count > 1 then
        floating_step = math_min(
            floating_slot / math_max(1, floating_curve.length),
            1 / (floating_count - 1)
        )
    end

    local center_x
    if side == "left" then
        center_x = corner_inset
    else
        center_x = screen_width - corner_inset
    end

    return {
        side = side,
        center_x = center_x,
        center_y = screen_height - corner_inset - clearance,
        radius = math_floor(math_sqrt(rx * ry) + 0.5),
        rx = rx,
        ry = ry,
        curve = curve,
        floating_curve = floating_curve,
        diameter = diameter,
        pad = pad,
        band_width = band_width,
        half_band = half_band,
        capacity = capacity,
        step = 1 / math_max(1, capacity - 1),
        floating_radius = floating_radius,
        floating_step = floating_step,
        button_scale = button_scale,
    }
end

-- When every item fits on one page with room to spare, the buttons grow
-- (up to MAX_BUTTON_GROWTH) so that, spread along the whole arc, they are
-- not separated by wide gaps. Larger buttons widen the band, which can
-- shorten the arc within the screen limits, so the growth is checked.
function ArcDock.computeGeometry(side, metrics, options)
    local geometry = buildGeometry(side, metrics, options, 1)
    local count = options.item_count or 0
    if not options.fill or count < 2 or count >= geometry.capacity then
        return geometry
    end
    local spacing = geometry.curve.length / (count - 1) - geometry.pad
    local scale = math_min(MAX_BUTTON_GROWTH, spacing / metrics.button_width)
    while scale > 1.01 do
        local grown = buildGeometry(side, metrics, options, scale)
        if grown.capacity >= count then
            return grown
        end
        scale = scale * 0.95
    end
    return geometry
end

function ArcDock:init()
    local geometry = self.geometry
    self.items_by_id = {}
    local function register(item)
        item = ArcItem.new(item)
        if item.id then
            self.items_by_id[item.id] = item
        end
        return item
    end
    for page_index = 1, #self.pages do
        local page_items = self.pages[page_index]
        for index = 1, #page_items do
            page_items[index] = register(page_items[index])
        end
    end
    self.floating_items = self.floating_items or {}
    for index = 1, #self.floating_items do
        self.floating_items[index] = register(self.floating_items[index])
        self.floating_items[index].detached = true
    end
    self.sliders = self.sliders or {}
    for _kind, slider in pairs(self.sliders) do
        if slider.leading_item then
            slider.leading_item = ArcItem.new(slider.leading_item)
        end
    end
    self.page = math_max(1, math_min(self.page or 1, #self.pages))
    self.last_refresh_time = 0

    -- Bounding box of the band and of the floating buttons.
    local left, top, right, bottom
    local function include(curve, margin_size)
        if not curve then
            return
        end
        for _index, sample in ipairs(curve.samples) do
            local x, y = self:toScreen(sample.x, sample.y)
            left = math_min(left or x, x - margin_size)
            right = math_max(right or x, x + margin_size)
            top = math_min(top or y, y - margin_size)
            bottom = math_max(bottom or y, y + margin_size)
        end
    end
    include(geometry.curve, geometry.half_band)
    if #self.floating_items > 0 then
        include(geometry.floating_curve, geometry.floating_radius)
    end
    left, top = math_floor(left), math_floor(top)
    self.dimen = Geom:new({
        x = left,
        y = top,
        w = math_ceil(right) - left + 1,
        h = math_ceil(bottom) - top + 1,
    })

    local screen = Geom:new({ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
    if Device:isTouchDevice() then
        self.ges_events = {
            TapArcDock = { GestureRange:new({ ges = "tap", range = screen }) },
            HoldArcDock = { GestureRange:new({ ges = "hold", range = screen }) },
            PanArcDock = { GestureRange:new({ ges = "pan", range = screen }) },
            PanReleaseArcDock = { GestureRange:new({ ges = "pan_release", range = screen }) },
            SwipeArcDock = { GestureRange:new({ ges = "swipe", range = screen }) },
        }
    end
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
        }
    end
end

function ArcDock:getSize()
    return self.dimen
end

-- Prefers what is on screen: every page has its own navigation arrows with
-- the same ids, and the lighting toggles only exist while their slider shows.
function ArcDock:getButtonById(id)
    for _slot, item in pairs(self:getMainSlots()) do
        if item.id == id then
            return item
        end
    end
    return self.items_by_id[id]
end

function ArcDock:toScreen(dx, dy)
    local geometry = self.geometry
    if geometry.side == "left" then
        return geometry.center_x + dx, geometry.center_y - dy
    end
    return geometry.center_x - dx, geometry.center_y - dy
end

-- Screen point at fraction a of a curve's length (the arc by default).
function ArcDock:pointAt(a, curve)
    local dx, dy = curvePoint(curve or self.geometry.curve, a)
    local x, y = self:toScreen(dx, dy)
    return math_floor(x + 0.5), math_floor(y + 0.5)
end

-- Where a screen point falls along the arc: its fraction a of the arc's
-- length and its distance from the arc.
function ArcDock:locate(pos)
    local geometry = self.geometry
    local dx = pos.x - geometry.center_x
    if geometry.side ~= "left" then
        dx = -dx
    end
    return curveLocate(geometry.curve, dx, geometry.center_y - pos.y)
end

function ArcDock:isInsideBand(pos)
    if self:findFloatingItem(pos) then
        return true
    end
    local _, distance = self:locate(pos)
    return distance <= self.geometry.half_band
end

-- Items on the arc, from the bottom end to the side end. The page arrows
-- are the first and last items of their pages.
function ArcDock:getMainSlots()
    if self.mode ~= "actions" then
        local slider = self.sliders[self.mode]
        return { slider and slider.leading_item or nil }
    end
    return self.pages[self.page] or {}
end

-- Fraction of the arc's length for the index-th of count items. Filling
-- spreads a page along the whole arc, the first item at the bottom end and
-- the last at the side end; otherwise items keep a full page's spacing and
-- the unused slots stay empty at the chosen end. The slider's leading item
-- always sits at the bottom end.
function ArcDock:itemPosition(index, count)
    if self.mode ~= "actions" then
        return 0
    end
    if self.fill then
        if count < 2 then
            return 0
        end
        return (index - 1) / (count - 1)
    end
    local geometry = self.geometry
    local offset = 0
    if self.empty_space == "start" then
        offset = math_max(0, geometry.capacity - count)
    end
    return math_min(1, (offset + index - 1) * geometry.step)
end

function ArcDock:forEachVisibleItem(callback)
    local geometry = self.geometry
    local items = self:getMainSlots()
    for index = 1, #items do
        local x, y = self:pointAt(self:itemPosition(index, #items))
        callback(items[index], x, y, math_floor(geometry.diameter / 2))
    end
    self:forEachFloatingItem(callback)
end

function ArcDock:forEachFloatingItem(callback)
    local geometry = self.geometry
    for index = 1, #self.floating_items do
        local x, y = self:pointAt((index - 1) * geometry.floating_step, geometry.floating_curve)
        callback(self.floating_items[index], x, y, geometry.floating_radius)
    end
end

function ArcDock:findFloatingItem(pos)
    local found
    self:forEachFloatingItem(function(item, x, y, radius)
        local dx, dy = pos.x - x, pos.y - y
        if not found and dx * dx + dy * dy <= radius * radius then
            found = item
        end
    end)
    return found
end

function ArcDock:findItem(pos)
    local found
    local tolerance = math_floor(self.geometry.pad / 2)
    self:forEachVisibleItem(function(item, x, y, radius)
        local dx, dy = pos.x - x, pos.y - y
        local reach = radius + tolerance
        if not found and dx * dx + dy * dy <= reach * reach then
            found = item
        end
    end)
    return found
end

-- Lighting track: from the slot after the leading item to the side end.
function ArcDock:getTrackRange()
    return self.geometry.step, 1
end

function ArcDock:isOnTrack(pos)
    local geometry = self.geometry
    local u, distance = self:locate(pos)
    local track_start, track_end = self:getTrackRange()
    return distance <= geometry.half_band
        and u >= track_start - geometry.step / 2
        and u <= track_end + geometry.step / 2
end

function ArcDock:getSliderLevel(slider, pos)
    if not pos then
        return nil
    end
    local u = self:locate(pos)
    local track_start, track_end = self:getTrackRange()
    local fraction = (u - track_start) / (track_end - track_start)
    fraction = math_max(0, math_min(1, fraction))
    return math_floor(slider.minimum + fraction * (slider.maximum - slider.minimum) + 0.5)
end

function ArcDock:refreshSlider(force)
    local now = time.now()
    if Screen.low_pan_rate and not force then
        if now - self.last_refresh_time < time.s(1 / 3) then
            return
        end
    end
    self.last_refresh_time = now
    self:repaint("fast")
end

-- With the band, the dock covers everything it ever painted, so repainting
-- it alone erases a previous page or slider position. Floating buttons
-- leave the page visible between them, so the page must be repainted too.
function ArcDock:repaint(refresh_type)
    if self.show_band then
        UIManager:setDirty(self, refresh_type, self.dimen)
    else
        UIManager:setDirty("all", refresh_type, self.dimen)
    end
end

function ArcDock:refresh()
    self:repaint("ui")
end

function ArcDock:setPage(page)
    page = math_max(1, math_min(page, #self.pages))
    if page == self.page and self.mode == "actions" then
        return
    end
    self.page = page
    self.mode = "actions"
    if self.page_changed_callback then
        self.page_changed_callback(page)
    end
    self:refresh()
end

-- Shows the lighting slider of the given kind in place of the main ring, or
-- brings the actions back when that slider is already shown.
function ArcDock:toggleSlider(kind)
    if self.mode == kind or not self.sliders[kind] then
        self.mode = "actions"
    else
        self.mode = kind
        self.sliders[kind]:syncFromPower()
    end
    self:refresh()
end

function ArcDock:isItemSelected(item)
    return item.slider_kind ~= nil and item.slider_kind == self.mode
end

-- Paints a stroke along a curve, from fraction a_start to a_end of its
-- length, by stamping discs. Stamps sqrt(2r) apart leave edges within a
-- quarter pixel of the true outline, so wide strokes need few of them.
function ArcDock:strokeCurve(bb, curve, a_start, a_end, thickness, color)
    if a_end < a_start then
        return
    end
    local stamp_radius = thickness / 2
    local spacing = math_max(1, math_sqrt(2 * stamp_radius))
    local length = (a_end - a_start) * curve.length
    local stamps = math_max(1, math_ceil(length / spacing))
    for index = 0, stamps do
        local x, y = self:pointAt(a_start + (a_end - a_start) * index / stamps, curve)
        fillDisc(bb, x, y, stamp_radius, color)
    end
end

function ArcDock:paintItem(bb, item, x, y, radius)
    local border = Size.border.button
    if self:isItemSelected(item) then
        fillDisc(bb, x, y, radius, Blitbuffer.COLOR_BLACK)
        fillDisc(bb, x, y, radius - 3 * border, Blitbuffer.COLOR_WHITE)
    elseif item.detached or not self.show_band then
        -- A floating button of its own, with the band's outline.
        fillDisc(bb, x, y, radius, Blitbuffer.COLOR_BLACK)
        fillDisc(bb, x, y, radius - Size.border.window, Blitbuffer.COLOR_WHITE)
    else
        fillDisc(bb, x, y, radius, Blitbuffer.COLOR_GRAY)
        fillDisc(bb, x, y, radius - border, Blitbuffer.COLOR_WHITE)
    end
    local metrics = self.metrics
    local icon_size, font_size
    if item.detached then
        icon_size = metrics.side_button_icon_size
        font_size = item.font_size or metrics.side_font_size
    else
        -- Ring buttons may have grown to fill the arc; their labels follow.
        local scale = self.geometry.button_scale
        icon_size = math_floor(metrics.button_icon_size * scale + 0.5)
        font_size = math_floor((item.font_size or metrics.fallback_font_size) * scale + 0.5)
    end
    local label = item:getLabelWidget(icon_size, font_size)
    local size = label:getSize()
    label:paintTo(bb, x - math_floor(size.w / 2), y - math_floor(size.h / 2))
    item.dimen = Geom:new({ x = x - radius, y = y - radius, w = 2 * radius, h = 2 * radius })
end

function ArcDock:paintSlider(bb, slider)
    local geometry = self.geometry
    local metrics = self.metrics
    slider:syncFromPower()
    local track_start, track_end = self:getTrackRange()
    local range = math_max(1, slider.maximum - slider.minimum)
    local fraction = math_max(0, math_min(1, (slider.value - slider.minimum) / range))
    local knob_u = track_start + fraction * (track_end - track_start)
    local track_color = slider.enabled and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_LIGHT_GRAY
    local active_color = slider.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    if not self.show_band then
        -- Without the band, an outlined lane keeps the track readable over text.
        local lane = 2 * metrics.arc_knob_radius + 2 * geometry.pad
        self:strokeCurve(bb, geometry.curve, track_start, track_end, lane, Blitbuffer.COLOR_BLACK)
        self:strokeCurve(
            bb, geometry.curve, track_start, track_end,
            lane - 2 * Size.border.window, Blitbuffer.COLOR_WHITE
        )
    end
    self:strokeCurve(bb, geometry.curve, track_start, track_end, metrics.arc_track_width, track_color)
    self:strokeCurve(bb, geometry.curve, track_start, knob_u, metrics.arc_track_width, active_color)
    local knob_x, knob_y = self:pointAt(knob_u)
    fillDisc(bb, knob_x, knob_y, metrics.arc_knob_radius, active_color)
end

function ArcDock:paintTo(bb, x, y)
    local geometry = self.geometry
    local border = Size.border.window
    if self.show_band then
        -- The band is the arc stroked a button wide; stamping rounds its ends.
        self:strokeCurve(bb, geometry.curve, 0, 1, geometry.band_width, Blitbuffer.COLOR_BLACK)
        self:strokeCurve(
            bb, geometry.curve, 0, 1,
            geometry.band_width - 2 * border, Blitbuffer.COLOR_WHITE
        )
    end
    local slider = self.sliders[self.mode]
    if slider then
        self:paintSlider(bb, slider)
    end
    self:forEachVisibleItem(function(item, item_x, item_y, radius)
        self:paintItem(bb, item, item_x, item_y, radius)
    end)
end

function ArcDock:onShow()
    self:refresh()
    return true
end

function ArcDock:onCloseWidget()
    for page_index = 1, #self.pages do
        for _index, item in ipairs(self.pages[page_index]) do
            item:freeLabel()
        end
    end
    for _index, item in ipairs(self.floating_items) do
        item:freeLabel()
    end
    for _kind, slider in pairs(self.sliders) do
        if slider.leading_item then
            slider.leading_item:freeLabel()
        end
    end
    if self._quickdock_suppress_close_refresh then
        return
    end
    UIManager:setDirty(nil, "ui", self.dimen)
end

function ArcDock:onClose()
    if self.close_callback then
        self.close_callback()
    else
        UIManager:close(self)
    end
    return true
end

function ArcDock:onTapArcDock(_arg, ges)
    local item = self:findItem(ges.pos)
    if item then
        if item.callback then
            item.callback()
        end
        return true
    end
    local slider = self.sliders[self.mode]
    if slider and self:isOnTrack(ges.pos) then
        return slider:setLevelFromPosition(ges.pos, true)
    end
    if not self:isInsideBand(ges.pos) then
        return self:onClose()
    end
    return true
end

function ArcDock:onHoldArcDock(_arg, ges)
    local item = self:findItem(ges.pos)
    if item and item.hold_callback then
        item.hold_callback()
    end
    return true
end

function ArcDock:changePageBy(u_start, u_end)
    local delta = u_end - u_start
    if math.abs(delta) < PAGE_SWIPE_THRESHOLD then
        return
    end
    -- Turning the ring toward the bottom end brings in the items that sit
    -- past the side end, the same direction as the next-page arrow.
    if delta < 0 then
        self:setPage(self.page + 1)
    else
        self:setPage(self.page - 1)
    end
end

function ArcDock:onPanArcDock(_arg, ges)
    if not self.pan_state then
        local start = ges.start_pos or ges.pos
        local slider = self.sliders[self.mode]
        if slider and self:isOnTrack(start) then
            self.pan_state = { kind = "slider" }
        elseif self.mode == "actions" and self:isInsideBand(start) then
            local u = self:locate(start)
            self.pan_state = { kind = "page", start_u = u }
        else
            self.pan_state = { kind = "none" }
        end
    end
    if self.pan_state.kind == "slider" then
        local slider = self.sliders[self.mode]
        if slider then
            slider:setLevelFromPosition(ges.pos, false)
        end
    end
    return true
end

function ArcDock:onPanReleaseArcDock(_arg, ges)
    local state = self.pan_state
    self.pan_state = nil
    if not state then
        return true
    end
    if state.kind == "slider" then
        local slider = self.sliders[self.mode]
        if slider then
            slider:setLevelFromPosition(ges.pos, true)
        end
        self:refresh()
    elseif state.kind == "page" and ges.pos then
        local u = self:locate(ges.pos)
        self:changePageBy(state.start_u, u)
    end
    return true
end

function ArcDock:onSwipeArcDock(_arg, ges)
    local start = ges.pos
    local finish = ges.end_pos
    if not start or not finish then
        return true
    end
    local slider = self.sliders[self.mode]
    if slider then
        if self:isOnTrack(start) then
            slider:setLevelFromPosition(finish, true)
        end
        return true
    end
    if self:isInsideBand(start) then
        local start_u = self:locate(start)
        local end_u = self:locate(finish)
        self:changePageBy(start_u, end_u)
    end
    return true
end

return ArcDock
