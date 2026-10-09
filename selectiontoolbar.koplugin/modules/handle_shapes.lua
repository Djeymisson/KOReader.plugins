-- Selection handle shapes. Every handle style is drawn from a few simple shapes (bars,
-- circles, flag tabs), so all of them share the same painting, touch area and refresh
-- logic. Used by the marks on the page and by their preview.

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")

local math_floor = math.floor
local math_max = math.max
local math_sqrt = math.sqrt

local C = ...

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
local function barShapes(shapes, edge_x, y, h, outline, m)
    local bar_x = edge_x - m.bar_width / 2
    if outline then
        shapes[#shapes + 1] =
            rectShape(bar_x - C.HANDLE_OUTLINE, y, m.bar_width + 2 * C.HANDLE_OUTLINE, h, Blitbuffer.COLOR_WHITE)
    end
    shapes[#shapes + 1] = rectShape(bar_x, y, m.bar_width, h)
end

-- Each style returns its shapes and the knob center (the point a finger aims at, used
-- to pick the nearest handle when touch areas overlap). Shapes must stay within
-- m.extent above/below the line (m: getHandleMetrics()). With outline, the solid knob is drawn black and
-- its inside, inset by HANDLE_RING_WIDTH, white: a black outline over white.
local HANDLE_STYLE_BUILDERS = {
    lollipop = function(box, is_start, edge_x, outline, m)
        local r, ring = m.knob_radius, C.HANDLE_RING_WIDTH
        local knob_y = is_start and (box.y - r) or (box.y + box.h + r)
        local shapes = {}
        barShapes(shapes, edge_x, box.y, box.h, outline, m)
        shapes[#shapes + 1] = circleShape(edge_x, knob_y, r, Blitbuffer.COLOR_BLACK)
        if outline then
            shapes[#shapes + 1] = circleShape(edge_x, knob_y, r - ring, Blitbuffer.COLOR_WHITE)
        end
        return shapes, edge_x, knob_y
    end,
    teardrop = function(box, is_start, edge_x, outline, m)
        -- Both drops hang below the line; a squared corner turns the disc into a drop
        -- whose point touches the selection edge.
        local r, ring = m.knob_radius, C.HANDLE_RING_WIDTH
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
    bracket = function(box, is_start, edge_x, _, m)
        local t, serif = m.bracket_width, m.bracket_serif
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
    flag = function(box, is_start, edge_x, outline, m)
        -- A pole along the selection edge with a grab tab beyond the line: above and
        -- outward (left) at the start, below and outward (right) at the end.
        local w, h, slant, ring = m.tab_width, m.tab_height, m.tab_slant, C.HANDLE_RING_WIDTH
        local pole_top = is_start and (box.y - h) or box.y
        local tab_y = is_start and (box.y - h) or (box.y + box.h)
        local shapes = {}
        barShapes(shapes, edge_x, pole_top, box.h + h, outline, m)
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

local function handleGeometry(box, is_start, style, outline, m)
    local edge_x = is_start and box.x or (box.x + box.w)
    local build = HANDLE_STYLE_BUILDERS[style] or HANDLE_STYLE_BUILDERS[C.DEFAULT_HANDLE_STYLE]
    local shapes, knob_x, knob_y = build(box, is_start, edge_x, outline and C.OUTLINE_STYLES[style] or false, m)
    local visual
    for _, shape in ipairs(shapes) do
        local bounds = shapeBounds(shape)
        visual = visual and visual:combine(bounds) or bounds
    end
    local touch_w = math_max(C.HANDLE_TOUCH_SIZE, visual.w)
    local touch_h = math_max(C.HANDLE_TOUCH_SIZE, visual.h)

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

return {
    paintShape = paintShape,
    handleGeometry = handleGeometry,
}
