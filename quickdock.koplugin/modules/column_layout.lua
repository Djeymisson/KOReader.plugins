local Device = require("device")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

-- Builds the column dock: the actions stacked beside the screen edge in a
-- ButtonDialog, the side-switch, information-panel and close buttons above
-- it, and the lighting sliders beside it.
return function(QuickDock, C, lib)
    local FloatingControlButtonDialog = lib.widgets.FloatingControlButtonDialog
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

    -- The column dock for one page of actions. Sets current_page; the caller
    -- shows it, either as a new dock or in place of the current one.
    function QuickDock:buildColumnDialog(actions, metrics, page, side)
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
            frontlight_slider_factory = factory(Prefs.showFrontlightSlider(), self.makeFrontlightSlider),
            warmth_slider_factory = factory(Prefs.showWarmthSlider(), self.makeWarmthSlider),
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
                local bottom_margin = C.DOCK_MARGIN + self:getSiblingOverlayClearance(side)
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
