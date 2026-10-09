-- Preview of the selection marks in the settings menu: sample text with a selection across
-- two of its lines, drawn in the reader's selection style with the handles and the line
-- marker as on the page.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local util = require("util")

local math_floor = math.floor
local math_max = math.max

local C, lib = ...
local handleGeometry = lib.handleGeometry
local paintShape = lib.paintShape
local getHandleMetrics = lib.getHandleMetrics

local SelectionToolbar = {}

-- Selection marks preview: sample text with a selection across two of its lines, drawn
-- in the reader's selection style, with the handles and the line marker as on the page.
local MarksSample = WidgetContainer:extend({})

function MarksSample:getSize()
    return Geom:new({ w = self.width, h = self.height })
end

function MarksSample:paintTo(bb, x, y)
    self.dimen = Geom:new({ x = x, y = y, w = self.width, h = self.height })
    self.sample:paintTo(bb, x + self.text_x, y + self.text_y)
    for _, box in ipairs(self.boxes) do
        self:paintSelection(bb, Geom:new({ x = x + box.x, y = y + box.y, w = box.w, h = box.h }))
    end
    for _, rect in ipairs(self.lines) do
        bb:paintRect(x + rect.x, y + rect.y, rect.w, rect.h, Blitbuffer.COLOR_BLACK)
    end
    for _, side in ipairs(C.HANDLE_SIDES) do
        local handle = self.handles[side]
        if handle then
            for _, shape in ipairs(handle.shapes) do
                paintShape(bb, x, y, shape)
            end
        end
    end
    if self.toolbar then
        self.toolbar:paintTo(bb, x + self.toolbar_x, y + self.toolbar_y)
    end
end

-- Paints a selection box (in screen coordinates) as ReaderView:drawTempHighlight() does
-- for a live selection: same drawer, color and height, through the same function.
function MarksSample:paintSelection(bb, rect)
    local view = self.view
    if not (view and view.drawHighlightRect and view.highlight) then
        bb:darkenRect(rect.x, rect.y, rect.w, rect.h, 0.2)
        return
    end
    -- drawHighlightRect() only uses the selection's lighten factor (rather than the saved
    -- highlights' one) while a selection is shown: pretend there is one.
    local highlight = view.highlight
    local temp = highlight.temp
    if not (temp and next(temp)) then
        highlight.temp = { selectiontoolbar_preview = {} }
    end
    local ok = pcall(view.drawHighlightRect, view, bb, rect.x, rect.y, rect, highlight.temp_drawer, self.color)
    highlight.temp = temp
    if not ok then
        bb:darkenRect(rect.x, rect.y, rect.w, rect.h, 0.2)
    end
end

-- Where the sample selection starts on first_line and ends on the next one, snapped to
-- word boundaries when the text box can tell where its characters are.
local function sampleSelectionRange(sample, first_line, width)
    local start_x, end_x
    local chars = util.splitToChars(sample.text or "")
    local line_h = sample.line_height_px
    if sample._getXYForCharPos and line_h then
        pcall(function()
            for pos = 2, #chars do
                local word_start = chars[pos - 1] == " " and chars[pos] ~= " "
                local word_end = chars[pos] == " " and chars[pos - 1] ~= " "
                if word_start or word_end then
                    local x, y = sample:_getXYForCharPos(pos)
                    local line = math_floor(y / line_h + 0.5)
                    if line > first_line + 1 then
                        break
                    elseif word_start and line == first_line and not start_x and x >= width * 0.25 then
                        start_x = x
                    elseif word_end and line == first_line + 1 and x <= width * 0.65 then
                        end_x = x
                    end
                end
            end
        end)
    end
    if not (start_x and end_x) then
        start_x, end_x = math_floor(width * 0.3), math_floor(width * 0.6)
    end
    return start_x, end_x
end

-- The stage of a PREVIEW_MARKS preview: four lines with the selection on the middle two,
-- or only those two when the menu leaves less room than that. With a toolbar (frame from
-- ToolbarPreview:getToolbar(), PREVIEW_FULL), the selection is on the first two lines and
-- the toolbar lies over the next ones, below it as on the page.
function SelectionToolbar:buildMarksPreview(preview, inner_w, face, line_h, room, toolbar)
    local metrics = getHandleMetrics()
    -- Page margins wide enough for the line marker at its farthest and thickest.
    local margin = C.LINE_MARKER_GAPS[#C.LINE_MARKER_GAPS].gap
        + C.LINE_MARKER_WIDTHS[#C.LINE_MARKER_WIDTHS].width
        + Size.padding.default
    local text_w = inner_w - 2 * margin

    -- Room for the handles beyond the selected lines, where they reach past the lines
    -- around them.
    local lines, first_line = 4, 1
    local text_y = math_max(0, metrics.extent - line_h)
    local toolbar_size, toolbar_gap
    if toolbar then
        toolbar_size = toolbar:getSize()
        -- Clear of the end handle. (On the page the gap also covers its touch area, which
        -- would only take room here.)
        toolbar_gap = metrics.extent + Size.padding.large
        lines, first_line, text_y = 2 + math.ceil((toolbar_gap + toolbar_size.h) / line_h), 0, metrics.extent
    elseif 4 * line_h + 2 * text_y > room then
        lines, first_line, text_y = 2, 0, metrics.extent
    end
    local height = lines * line_h + (toolbar and text_y or 2 * text_y)

    local sample = preview:getSample(text_w, lines, face)
    local start_x, end_x = sampleSelectionRange(sample, first_line, text_w)
    local row = sample.vertical_string_list and sample.vertical_string_list[first_line + 1]
    local line_end = row and row.width or text_w
    local top = text_y + first_line * line_h
    local first_box = Geom:new({ x = margin + start_x, y = top, w = math_max(1, line_end - start_x), h = line_h })
    local last_box = Geom:new({ x = margin, y = top + line_h, w = math_max(1, end_x), h = line_h })

    local marker = {}
    if self:showLineMarker() then
        local on_right = self:lineMarkerOnRight()
        if BD.mirroredUILayout() then
            on_right = not on_right
        end
        local width, gap = self:getLineMarkerSize(margin)
        marker[1] = width and Geom:new({
            x = on_right and (margin + text_w + gap) or (margin - gap - width),
            y = top,
            w = width,
            h = 2 * line_h,
        })
    end

    local handles = {}
    if self:showHandles() then
        local style, outline = self:getHandleStyle(), self:handleOutline()
        handles.start = handleGeometry(first_box, true, style, outline, metrics)
        handles["end"] = handleGeometry(last_box, false, style, outline, metrics)
    end

    -- The color ReaderView:drawTempHighlight() gives a live selection.
    local view = self.ui and self.ui.view
    local highlight = view and view.highlight
    local color = highlight
        and highlight.saved_drawer ~= "invert"
        and G_reader_settings:isTrue("highlight_selection_use_highlight_color")
        and Blitbuffer.colorFromName(highlight.saved_color)
        or nil
    return MarksSample:new({
        width = inner_w,
        height = height,
        sample = sample,
        text_x = margin,
        text_y = text_y,
        boxes = { first_box, last_box },
        lines = marker,
        handles = handles,
        view = view,
        color = color,
        toolbar = toolbar,
        toolbar_x = toolbar and math_floor((inner_w - toolbar_size.w) / 2),
        toolbar_y = toolbar and (top + 2 * line_h + toolbar_gap),
    })
end

return SelectionToolbar
