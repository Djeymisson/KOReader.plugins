-- Dragging the selection handles: which gestures belong to a drag, moving the selection
-- end in crengine, and refreshing only the screen band that changed.

local UIManager = require("ui/uimanager")
local Device = require("device")
local Geom = require("ui/geometry")

local Screen = Device.screen
local math_abs = math.abs
local math_max = math.max
local math_min = math.min

local C, lib = ...
local isLiveSelection = lib.isLiveSelection
local getHandleMetrics = lib.getHandleMetrics

local SelectionToolbar = {}

function SelectionToolbar:getHandlePanRate()
    local rate = G_reader_settings:readSetting("hold_pan_rate")
    if not rate then
        rate = Screen.low_pan_rate and 5.0 or 30.0
    end
    return rate
end

function SelectionToolbar:handleAt(pos)
    local handles = self.marks and self.marks.handles
    if not (handles and pos) then
        return nil
    end

    -- Short selections may have overlapping touch areas: pick the nearest knob.
    local nearest, nearest_distance
    for _, side in ipairs(C.HANDLE_SIDES) do
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

-- Runs fn while holding back the full-screen "ui" refreshes of the reader it requests,
-- and returns whether one was requested, so the caller can refresh a smaller region.
local function withReaderRefreshHeld(reader_dialog, fn)
    local own_set_dirty = rawget(UIManager, "setDirty")
    local set_dirty = UIManager.setDirty
    local requested = false
    UIManager.setDirty = function(uimanager, widget, refreshtype, refreshregion, ...)
        if widget == reader_dialog and refreshtype == "ui" and refreshregion == nil then
            requested = true
            return
        end
        return set_dirty(uimanager, widget, refreshtype, refreshregion, ...)
    end
    local ok, err = pcall(fn)
    UIManager.setDirty = own_set_dirty
    if not ok then
        error(err, 0)
    end
    return requested
end

-- The boundary box at the moving end of a selection: the one not holding the anchor.
local function movingEndBox(boxes, anchor)
    if not (boxes and anchor) or #boxes == 0 then
        return nil
    end
    local first, last = boxes[1], boxes[#boxes]
    if #boxes == 1 then
        return first
    end
    local function holdsAnchor(box)
        return anchor.x >= box.x and anchor.x <= box.x + box.w and anchor.y >= box.y and anchor.y <= box.y + box.h
    end
    if holdsAnchor(first) then
        return last
    elseif holdsAnchor(last) then
        return first
    end
end

-- Moving one end of the selection only changes the lines between its old and new
-- position: the highlight there, both handles' knobs (the anchor one too when the
-- ends cross) and the ends of the margin line. All of it fits in a full-width band.
local function dragRefreshBand(old_box, new_box)
    local pad = getHandleMetrics().extent + 2
    local top = math_max(0, math_min(old_box.y, new_box.y) - pad)
    local bottom = math_min(Screen:getHeight(), math_max(old_box.y + old_box.h, new_box.y + new_box.h) + pad)
    return Geom:new({ x = 0, y = top, w = Screen:getWidth(), h = bottom - top })
end

-- Screen boxes of a selection in the current view. selected_text.sboxes can be stale:
-- when ReaderHighlight scrolls from a page corner it returns before recomputing the
-- selection, so its boxes still have the coordinates from before the scroll.
function SelectionToolbar:getCurrentScreenBoxes(reader_highlight, selected_text)
    local marks = self.marks
    if
        marks
        and marks.boxes
        and marks.selected_text == selected_text
        and marks.view_key == self:getMarksViewKey(reader_highlight)
    then
        return marks.boxes
    end
    local document = reader_highlight.ui.document
    local ok, boxes =
        pcall(document.getScreenBoxesFromPositions, document, selected_text.pos0, selected_text.pos1, true)
    return ok and boxes or nil
end

-- is_final: the finger was lifted, so its last position must be applied even if it
-- moved less than DRAG_MIN_MOVE (a couple of pixels can cross a word boundary).
function SelectionToolbar:updateHandleDrag(pos, is_final)
    local drag = self.drag
    if not (drag and pos) then
        return false
    end

    local reader_highlight = drag.highlight
    local x = math_max(0, math_min(Screen:getWidth() - 1, pos.x - drag.offset_x))
    local y = math_max(0, math_min(Screen:getHeight() - 1, pos.y - drag.offset_y))
    local small_move = drag.last_x
        and math_abs(x - drag.last_x) < C.DRAG_MIN_MOVE
        and math_abs(y - drag.last_y) < C.DRAG_MIN_MOVE
    if small_move and not is_final then
        return true
    end
    drag.last_x, drag.last_y = x, y

    local document = reader_highlight.ui.document
    local view = reader_highlight.view
    local previous = reader_highlight.selected_text
    local old_box = isLiveSelection(previous)
        and movingEndBox(self:getCurrentScreenBoxes(reader_highlight, previous), reader_highlight.hold_pos)
    local view_pos, view_mode = document:getCurrentPos(), view.view_mode

    -- ReaderHighlight refreshes the whole screen on each selection change, as it cannot
    -- tell what changed. Here we can: refresh only the band of lines the moving end
    -- swept over, which saves most of the e-ink refresh work while dragging.
    local refresh_requested = withReaderRefreshHeld(reader_highlight.dialog, function()
        reader_highlight:onHoldPan(nil, { ges = "hold_pan", pos = Geom:new({ x = x, y = y, w = 0, h = 0 }) })
    end)

    if not reader_highlight.selected_text and isLiveSelection(previous) then
        -- No text at this point: keep the last valid selection instead of losing it.
        reader_highlight.selected_text = previous
        pcall(document.getTextFromXPointers, document, previous.pos0, previous.pos1, true)
        UIManager:setDirty(reader_highlight.dialog, "ui")
        return true
    end

    if refresh_requested then
        local band
        -- Fresh boxes: the view did not move during this call (checked below).
        local new_box = movingEndBox(reader_highlight.selected_text.sboxes, reader_highlight.hold_pos)
        -- Full screen when the view moved (corner scroll) or in two-page mode, where
        -- the lines between both ends are not a single vertical band.
        local single_view = view.view_mode ~= "page" or document:getVisiblePageCount() == 1
        local view_moved = view.view_mode ~= view_mode or document:getCurrentPos() ~= view_pos
        if old_box and new_box and single_view and not view_moved then
            band = dragRefreshBand(old_box, new_box)
        end
        UIManager:setDirty(reader_highlight.dialog, "ui", band)
    end
    return true
end

function SelectionToolbar:endHandleDrag(pos)
    local drag = self.drag
    if not drag then
        return false
    end

    self:updateHandleDrag(pos, true)
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
        self:reopenToolbar(reader_highlight, nil, dialog.toolbar_expanded)
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

return SelectionToolbar
