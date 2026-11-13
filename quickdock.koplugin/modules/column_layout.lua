local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

-- Builds the column dock: the actions stacked beside the screen edge in a
-- ButtonDialog, the side-switch, information-panel and close buttons (and
-- the panel picker, while open) above it, and the lighting sliders beside it.
return function(QuickDock, C, lib)
    local FloatingControlButtonDialog = lib.widgets.FloatingControlButtonDialog
    local markSelectedButton = lib.widgets.markSelectedButton
    local Layout = lib.Layout
    local Prefs = lib.Prefs

    function QuickDock:getMaxPageRows(metrics)
        return Layout.maxColumnRows(metrics or self:getDockMetrics(), {
            screen_height = Screen:getHeight(),
            height_factor = Prefs.getMaxActionDockHeightFactor(),
            stacked_buttons = (Prefs.showSideButton() and 1 or 0)
                + (Prefs.showCloseButton() and 1 or 0)
                + (Prefs.showInfoPanelToggleButton() and 1 or 0),
            minimum_rows = Prefs.showContextButton() and 4 or 3,
        })
    end

    function QuickDock:makeColumnActionRows(actions, metrics, page)
        local pages = self:getPages(#actions, metrics)
        local page_count = #pages
        self.current_page = math_max(1, math_min(page or 1, page_count))
        local page_range = pages[self.current_page]
        local rows = {}

        for index = page_range.last, page_range.first, -1 do
            rows[#rows + 1] = { self:makeActionButton(actions[index], metrics) }
        end

        if self.current_page < page_count then
            table.insert(rows, 1, { self:makePageButton("next", self.current_page + 1, metrics) })
        end
        if self.current_page == 1 and Prefs.showContextButton() then
            rows[#rows + 1] = { self:makeContextButton(metrics) }
        end
        if self.current_page > 1 then
            rows[#rows + 1] = { self:makePageButton("previous", self.current_page - 1, metrics) }
        end
        return rows
    end

    -- The panel picker rows, the first panel at the bottom like the first
    -- action.
    function QuickDock:makeColumnPanelPickerRows(metrics)
        local rows = {}
        local items = self:makePanelPickerItems(metrics)
        for index = #items, 1, -1 do
            rows[#rows + 1] = { items[index] }
        end
        return rows, items
    end

    -- The shown panel is marked across the whole width of its frame.
    local function markSelectedPanel(frame, button_table, rows, items)
        for _index, item in ipairs(items) do
            if item.selected then
                markSelectedButton(frame, button_table, rows, item.id)
            end
        end
    end

    -- The panel picker stacked above the panel-switch button: its own block,
    -- framed and sized like the action dock.
    function QuickDock:makeColumnPanelPickerBlock(width, dialog, metrics)
        local rows, items = self:makeColumnPanelPickerRows(metrics)
        local button_table = ButtonTable:new({
            buttons = rows,
            width = width - 2 * Size.border.window - 2 * Size.padding.button,
            shrink_unneeded_width = true,
            shrink_min_width = metrics.button_width,
            show_parent = dialog,
        })
        local block = FrameContainer:new({
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            radius = Size.radius.window,
            padding = Size.padding.button,
            padding_top = 0,
            padding_bottom = 0,
            button_table,
        })
        block.button_table = button_table
        markSelectedPanel(block, button_table, rows, items)
        return block
    end

    -- Whether the whole dock, bottom margin included, fits on the screen.
    local function fitsScreen(dialog, bottom_margin)
        return dialog.movable[1]:getSize().h + bottom_margin + C.DOCK_MARGIN <= Screen:getHeight()
    end

    -- The column dock for one page of actions. Sets current_page; the caller
    -- shows it, either as a new dock or in place of the current one.
    --
    -- With the panel picker open, its block is stacked above the panel-switch
    -- button; when that does not fit on the screen, the picker takes the
    -- actions' place instead (current_page is then kept for their return),
    -- with the lighting columns kept at the actions' height.
    function QuickDock:buildColumnDialog(actions, metrics, page, side)
        local bottom_margin = C.DOCK_MARGIN + self:getSiblingOverlayClearance(side)

        -- The optional controls around the dock, each built by the dialog once
        -- it knows the dock's size: factory(size, dialog) with the dock's width
        -- for the buttons above it, its height for the sliders beside it.
        local function factory(enabled, make)
            if not enabled then
                return nil
            end
            return function(size, parent)
                return make(self, size, parent, metrics)
            end
        end

        local function build(rows, options)
            local dialog
            dialog = FloatingControlButtonDialog:new({
                buttons = rows,
                width = metrics.button_width + 2 * Size.border.window + 2 * Size.padding.button,
                shrink_unneeded_width = true,
                shrink_min_width = metrics.button_width,
                dismissable = true,
                side_button_factory = factory(Prefs.showSideButton(), self.makeSideButton),
                close_button_factory = factory(Prefs.showCloseButton(), self.makeCloseButton),
                info_panel_toggle_button_factory = factory(
                    Prefs.showInfoPanelToggleButton(), self.makeInfoPanelToggleButton
                ),
                panel_picker_factory = options.stacked_picker
                    and factory(true, self.makeColumnPanelPickerBlock) or nil,
                frontlight_slider_factory = factory(Prefs.showFrontlightSlider(), self.makeFrontlightSlider),
                warmth_slider_factory = factory(Prefs.showWarmthSlider(), self.makeWarmthSlider),
                slider_height = options.slider_height,
                side_button_gap = metrics.side_button_gap,
                frontlight_slider_gap = metrics.frontlight_slider_gap,
                dock_side = side,
                anchor = function()
                    local dialog_size = dialog:getContentSize()
                    local left
                    if side == "left" then
                        left = C.DOCK_MARGIN
                    else
                        left = Screen:getWidth() - C.DOCK_MARGIN - dialog_size.w
                    end
                    return Geom:new({
                        x = math_floor(left),
                        y = Screen:getHeight() - bottom_margin,
                        -- Giving the anchor the dialog width keeps x as the physical
                        -- left edge in both regular and mirrored UI layouts.
                        w = dialog_size.w,
                        h = 0,
                    }), false
                end,
                close_all_callback = function()
                    if self.dialog == dialog then
                        self:closeDock()
                        return true
                    end
                    return false
                end,
            })
            return dialog
        end

        local action_rows = self:makeColumnActionRows(actions, metrics, page)
        if not self.panel_picker_open then
            return build(action_rows, {})
        end

        local stacked = build(action_rows, { stacked_picker = true })
        if fitsScreen(stacked, bottom_margin) then
            return stacked
        end
        local rows, items = self:makeColumnPanelPickerRows(metrics)
        local dialog = build(rows, { slider_height = stacked.dock_height })
        markSelectedPanel(dialog.dock_frame, dialog.buttontable, rows, items)
        return dialog
    end

    -- Turns the column dock's page in place, as the arc dock does: only the dock
    -- is replaced, while the information and status panels stay untouched. The
    -- old dock closes without its own (flashing) refresh, and its area is
    -- refreshed together with the new dock's, which overlaps it at the bottom,
    -- so the page change is one non-flashing update.
    function QuickDock:showColumnDockPage(page)
        local previous = self.dialog
        local side = self.current_dock_side
        local actions = self:getDockActions()
        if not previous or not side or Prefs.isArcLayout() or not actions then
            return self:showDock(page, side, self.info_panel_data)
        end

        local dialog = self:buildColumnDialog(actions, self:getDockMetrics(), page, side)
        local previous_dimen = previous.movable and previous.movable.dimen
        local previous_region = previous_dimen and Geom:new({
            x = previous_dimen.x,
            y = previous_dimen.y,
            w = previous_dimen.w,
            h = previous_dimen.h,
        })
        self.dialog = dialog
        self:attachDockCallbacks(dialog)
        previous._quickdock_suppress_close_refresh = true
        UIManager:close(previous)
        UIManager:show(dialog, "[ui]")
        if previous_region then
            -- A shorter last page leaves part of the old dock to clear.
            UIManager:setDirty(nil, "ui", previous_region)
        end
    end

end
