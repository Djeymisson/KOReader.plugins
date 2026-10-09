-- Selection marks: drag handles at both ends of the selection and a line marker in the
-- page margin, where they go on the page, and their painting by a ReaderView module while
-- the toolbar opened for a live (not yet saved) selection is shown.

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")

local Screen = Device.screen
local math_max = math.max
local math_min = math.min

local C, lib = ...
local handleGeometry = lib.handleGeometry
local paintShape = lib.paintShape
local isLiveSelection = lib.isLiveSelection
local refreshRects = lib.refreshRects
local getHandleMetrics = lib.getHandleMetrics

local SelectionToolbar = {}

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
    local width, gap = self:getLineMarkerSize(on_right and margins.right or margins.left)
    if not width then
        return {}
    end

    local rects = {}
    for column = 1, 2 do
        local range = columns[column]
        if range then
            local x
            if on_right then
                x = screen_w - margins.right + gap
                if page2_x and column == 1 then
                    x = x - page2_x
                end
            else
                x = margins.left - gap - width
                if page2_x and column == 2 then
                    x = x + page2_x
                end
            end
            x = math_max(0, math_min(x, screen_w - width))
            rects[#rects + 1] = Geom:new({
                x = x,
                y = range.top,
                w = width,
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
        local style, outline, metrics = self:getHandleStyle(), self:handleOutline(), getHandleMetrics()
        local first_box, last_box = boxes[1], boxes[#boxes]
        if isBoundaryVisible(document, selected_text.pos0, first_box) then
            marks.handles.start = handleGeometry(first_box, true, style, outline, metrics)
        end
        if isBoundaryVisible(document, selected_text.pos1, last_box) then
            marks.handles["end"] = handleGeometry(last_box, false, style, outline, metrics)
        end
    end

    -- Painted areas, kept separate: refreshing the thin margin line and the two handles
    -- is much cheaper on e-ink than refreshing their bounding box, which for a long
    -- selection covers most of the screen.
    local rects = {}
    for _, rect in ipairs(marks.lines) do
        rects[#rects + 1] = rect
    end
    for _, side in ipairs(C.HANDLE_SIDES) do
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
    if rects and reader_highlight and reader_highlight.dialog and not self.reopening_toolbar then
        refreshRects(reader_highlight.dialog, rects)
    end
end

return SelectionToolbar
