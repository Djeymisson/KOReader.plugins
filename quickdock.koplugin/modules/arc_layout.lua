local UIManager = require("ui/uimanager")
local _ = require("quickdock_l10n")

-- Builds the arc-shaped dock: the actions in one row on a quarter ring around
-- the lower corner, and the side-switch, lighting, information-panel and
-- close buttons floating inside the ring. The action buttons and their
-- callbacks are the same as in the column dock; only their placement differs.
return function(QuickDock, C, lib)
    local ArcDock = lib.ArcDock
    local Prefs = lib.Prefs
    local makeFallbackLabel = lib.widgets.makeFallbackLabel

    function QuickDock:getArcFloatingCount()
        return (Prefs.showSideButton() and 1 or 0)
            + (Prefs.showFrontlightSlider() and 1 or 0)
            + (Prefs.showWarmthSlider() and 1 or 0)
            + (Prefs.showInfoPanelToggleButton() and 1 or 0)
            + (Prefs.showCloseButton() and 1 or 0)
    end

    function QuickDock:getArcGeometry(side, metrics, item_count)
        return ArcDock.computeGeometry(side, metrics, {
            -- Items on a single page: the reader/browser button and the actions.
            item_count = item_count,
            fill = Prefs.fillArc(),
            margin = C.DOCK_MARGIN,
            bottom_clearance = self:getSiblingOverlayClearance(side),
            max_height_factor = Prefs.getMaxActionDockHeightFactor(),
            floating_count = self:getArcFloatingCount(),
            -- Without filling, the floating buttons start from the same end of
            -- the arc as the actions: the side end when the empty space is at
            -- the start, the bottom end otherwise.
            floating_from_end = not Prefs.fillArc()
                and Prefs.getArcEmptySpace() == C.ARC_EMPTY_SPACE_START,
            angle = Prefs.getArcAngle(),
            -- Room for one action between the two page arrows (or the
            -- reader/browser button and the next arrow on the first page).
            minimum_rows = 3,
        })
    end

    -- Attaches a brightness or warmth model to the arc dock: positions map to
    -- levels along the ring, and repaints go to the whole dock.
    local function bindSliderToDock(slider, get_dock)
        slider.getLevelFromPosition = function(model, pos)
            return get_dock():getSliderLevel(model, pos)
        end
        slider.refreshSlider = function(_model, force)
            get_dock():refreshSlider(force)
        end
        slider.state_changed_callback = function()
            get_dock():refresh()
        end
        return slider
    end

    -- The same up and down arrows as the column dock: a sideways arrow at the
    -- bottom end would look like the side-switch button beside it.
    function QuickDock:makeArcPageItem(direction, target_page, metrics, get_dock)
        local is_next = direction == "next"
        return {
            id = is_next and "quickdock_next" or "quickdock_previous",
            icon = self:getIcon(is_next and "chevron-up" or "chevron-down"),
            text = is_next and "↑" or "↓",
            font_size = metrics.page_font_size,
            callback = function()
                get_dock():setPage(target_page)
            end,
            hold_callback = function()
                self:showPageHelp(direction)
            end,
        }
    end

    -- The floating buttons in order from the bottom end, and the lighting
    -- slider models. The side switch comes first, at the start of the dock.
    function QuickDock:makeArcFloatingItems(side, metrics, get_dock)
        local items = {}
        local sliders = {}
        local function add(item)
            item.font_size = item.font_size or metrics.side_font_size
            items[#items + 1] = item
        end

        if Prefs.showSideButton() then
            local target_side = side == "left" and "right" or "left"
            add({
                id = "quickdock_switch_side",
                icon = self:getIcon("chevron-" .. target_side),
                text = target_side == "left" and "←" or "→",
                callback = function()
                    self:moveDockToSide(target_side)
                end,
                hold_callback = function()
                    self:showMoveDockHelp(target_side)
                end,
            })
        end

        if Prefs.showFrontlightSlider() then
            local model = bindSliderToDock(self:newFrontlightModel({}), get_dock)
            local function getStateIcon()
                return self:getIcon(model.enabled and "light_on" or "light_off")
            end
            model.leading_item = {
                id = "quickdock_toggle_frontlight",
                icon_provider = getStateIcon,
                text = makeFallbackLabel(_("Frontlight toggle"), "frontlight"),
                font_size = metrics.fallback_font_size,
                callback = function()
                    self:toggleFrontlight(model)
                end,
                hold_callback = function()
                    self:showFrontlightToggleHelp(model)
                end,
            }
            sliders.frontlight = model
            add({
                id = "quickdock_frontlight_slider",
                slider_kind = "frontlight",
                icon_provider = getStateIcon,
                text = makeFallbackLabel(_("Brightness"), "frontlight"),
                callback = function()
                    get_dock():toggleSlider("frontlight")
                end,
                hold_callback = function()
                    self:showButtonHelp(_("Show or hide the brightness slider"))
                end,
            })
        end

        if Prefs.showWarmthSlider() then
            local model = bindSliderToDock(self:newWarmthModel({}), get_dock)
            local icon = self:getIcon("warmth")
            local fallback = makeFallbackLabel(_("Warmth"), "warmth")
            model.leading_item = {
                id = "quickdock_frontlight_warmth",
                icon = icon,
                text = fallback,
                font_size = metrics.fallback_font_size,
                callback = function()
                    self:showWarmthLevel(model)
                end,
                hold_callback = function()
                    self:showWarmthLevel(model)
                end,
            }
            sliders.warmth = model
            add({
                id = "quickdock_warmth_slider",
                slider_kind = "warmth",
                icon = icon,
                text = fallback,
                callback = function()
                    get_dock():toggleSlider("warmth")
                end,
                hold_callback = function()
                    self:showButtonHelp(_("Show or hide the warmth slider"))
                end,
            })
        end

        if Prefs.showInfoPanelToggleButton() then
            add({
                id = "quickdock_switch_info_panel",
                display_provider = function()
                    return self:getInfoPanelToggleDisplay()
                end,
                callback = function()
                    self:switchInfoPanel(self:getNextInfoPanelKind())
                end,
                hold_callback = function()
                    self:showInfoPanelSwitchHelp()
                end,
            })
        end

        if Prefs.showCloseButton() then
            add({
                id = "quickdock_close",
                icon = self:getIcon("close"),
                text = "×",
                callback = function()
                    self:closeDock()
                end,
                hold_callback = function()
                    self:showButtonHelp(_("Close Quick Dock"))
                end,
            })
        end

        return items, sliders
    end

    -- The arc dock for the given actions, showing the given page. Sets
    -- current_page; the caller shows it.
    function QuickDock:buildArcDock(actions, metrics, page, side)
        local dock
        local function get_dock()
            return dock
        end

        local geometry = self:getArcGeometry(
            side,
            metrics,
            #actions + (Prefs.showContextButton() and 1 or 0)
        )
        local ranges = self:getPages(#actions, metrics, geometry.capacity)
        local pages = {}
        for page_index, range in ipairs(ranges) do
            -- From the bottom end of the ring to the side end, in the same order
            -- the column dock shows from bottom to top.
            local items = {}
            if page_index > 1 then
                items[#items + 1] = self:makeArcPageItem("previous", page_index - 1, metrics, get_dock)
            elseif Prefs.showContextButton() then
                items[#items + 1] = self:makeContextButton(metrics)
            end
            for index = range.first, range.last do
                items[#items + 1] = self:makeActionButton(actions[index], metrics)
            end
            if page_index < #ranges then
                items[#items + 1] = self:makeArcPageItem("next", page_index + 1, metrics, get_dock)
            end
            pages[page_index] = items
        end
        local floating_items, sliders = self:makeArcFloatingItems(side, metrics, get_dock)

        dock = ArcDock:new({
            geometry = geometry,
            metrics = metrics,
            pages = pages,
            page = page or 1,
            floating_items = floating_items,
            show_band = Prefs.showArcBand(),
            fill = Prefs.fillArc(),
            empty_space = Prefs.getArcEmptySpace(),
            sliders = sliders,
            page_changed_callback = function(new_page)
                self.current_page = new_page
            end,
            close_callback = function()
                if self.dialog == dock then
                    self:closeDock()
                else
                    UIManager:close(dock)
                end
            end,
        })
        dock.info_panel_toggle_button = dock:getButtonById("quickdock_switch_info_panel")
        self.current_page = dock.page
        return dock
    end

end
