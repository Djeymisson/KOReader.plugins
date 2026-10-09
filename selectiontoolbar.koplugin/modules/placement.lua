-- Where the toolbar goes on screen: near the selection, at a screen edge, or pinned when
-- the selection fills the screen, always clear of the selection handles.

local Device = require("device")
local Geom = require("ui/geometry")
local Size = require("ui/size")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local C, lib = ...
local getHandleMetrics = lib.getHandleMetrics

local SelectionToolbar = {}

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
        vertical_gap = gap + getHandleMetrics().touch_extent
    end

    if self:getToolbarPosition() == C.POSITION_EDGE then
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
    for _, side in ipairs(C.HANDLE_SIDES) do
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

return SelectionToolbar
