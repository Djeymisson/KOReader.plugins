local Button = require("ui/widget/button")
local Device = require("device")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("quickdock_l10n")
local T = require("ffi/util").template

local math_max = math.max

local function applyButtonMetrics(button, metrics)
    button.icon_width = metrics.button_icon_size
    button.icon_height = metrics.button_icon_size
    button.height = metrics.button_height
    button.width = metrics.button_width
    button.padding = metrics.button_side_padding
    button.margin = 0
    return button
end

-- Keep every detached/highlighted control on the same geometry. The close,
-- side-switch, information-panel, and frontlight buttons all share these
-- dimensions instead of duplicating them independently.
local function applyHighlightedButtonMetrics(button, width, metrics)
    button.width = width
    button.height = metrics.side_button_height
    button.padding = metrics.side_button_padding
    button.margin = 0
    button.bordersize = Size.border.button
    button.radius = Size.radius.button
    button.icon_width = metrics.side_button_icon_size
    button.icon_height = metrics.side_button_icon_size
    return button
end

-- Gives a button its icon or, without one, a text label. ButtonTable rows
-- (the dock's actions) and standalone Buttons name the font fields
-- differently, hence the prefix.
local function setLabel(button, icon, text, font_size, bold, font_prefix)
    if icon then
        button.icon = icon
    else
        font_prefix = font_prefix or ""
        button.text = text
        button[font_prefix .. "font_size"] = font_size
        button[font_prefix .. "font_bold"] = bold
    end
    return button
end

-- Button and lighting-control factories. Keeping these out of main.lua makes
-- the plugin lifecycle and dock orchestration easier to audit independently
-- from widget construction details.
return function(QuickDock, C, lib)
    local Prefs = lib.Prefs
    local makeFallbackLabel = lib.widgets.makeFallbackLabel
    local LightSlider = lib.widgets.LightSlider
    local DynamicLabelButton = lib.widgets.DynamicLabelButton

    function QuickDock:toggleFrontlight(slider)
        local powerd = slider.powerd
        local toggled = pcall(function()
            powerd:toggleFrontlight()
            powerd:updateResumeFrontlightState()
        end)
        if toggled then
            slider:syncFromPower(true)
        end
    end

    function QuickDock:showFrontlightToggleHelp(slider)
        local message = slider.enabled and _("Turn frontlight off") or _("Turn frontlight on")
        self:showButtonHelp(message)
    end

    function QuickDock:makeFrontlightToggleButton(width, dialog, slider, metrics)
        local function getDisplay()
            slider:syncFromPower()
            return self:getIcon(slider.enabled and "light_on" or "light_off"),
                slider.enabled and _("On") or _("Off")
        end

        local icon, text = getDisplay()
        local config = applyHighlightedButtonMetrics({
            id = "quickdock_toggle_frontlight",
            enabled = true,
            show_parent = dialog,
            display_provider = getDisplay,
            callback = function()
                self:toggleFrontlight(slider)
            end,
            hold_callback = function()
                self:showFrontlightToggleHelp(slider)
            end,
        }, width, metrics)
        return DynamicLabelButton:new(setLabel(config, icon, text))
    end

    function QuickDock:showWarmthLevel(slider)
        slider:syncFromPower()
        self:showButtonHelp(T(_("Warmth: %1"), slider.value))
    end

    function QuickDock:makeWarmthInfoButton(width, dialog, slider, metrics)
        local function showWarmthLevel()
            self:showWarmthLevel(slider)
        end
        local config = applyHighlightedButtonMetrics({
            id = "quickdock_frontlight_warmth",
            enabled = true,
            show_parent = dialog,
            callback = showWarmthLevel,
            hold_callback = showWarmthLevel,
        }, width, metrics)
        return Button:new(setLabel(config, self:getIcon("warmth"), makeFallbackLabel(_("Warmth"), "warmth")))
    end

    -- Brightness and warmth models shared by the column sliders and the arc
    -- dock, which only replaces how a position maps to a level and repaints.
    function QuickDock:newFrontlightModel(config)
        config.powerd = Device:getPowerDevice()
        return LightSlider:new(config)
    end

    function QuickDock:newWarmthModel(config)
        local powerd = Device:getPowerDevice()
        config.powerd = powerd
        config.minimum = tonumber(powerd.fl_warmth_min) or 0
        config.maximum = tonumber(powerd.fl_warmth_max) or 100
        config.value_reader = function(active_powerd)
            return active_powerd:toNativeWarmth(active_powerd:frontlightWarmth())
        end
        config.value_writer = function(active_powerd, native_warmth)
            active_powerd:setWarmth(active_powerd:fromNativeWarmth(native_warmth))
        end
        return LightSlider:new(config)
    end

    -- A lighting column beside the column dock: the slider over its button,
    -- together as tall as the dock. newModel and makeButton are the QuickDock
    -- methods creating the slider and the button below it.
    function QuickDock:makeLightColumn(dock_height, dialog, metrics, newModel, makeButton)
        local column_height = math_max(1, tonumber(dock_height) or 1)
        local slider = newModel(self, {
            width = metrics.button_width,
            height = math_max(1, column_height - metrics.side_button_outer_height - metrics.side_button_gap),
            slider_padding = metrics.frontlight_slider_padding,
            track_width = metrics.frontlight_track_width,
            knob_radius = metrics.frontlight_knob_radius,
            show_parent = dialog,
        })
        local button = makeButton(self, metrics.button_width, dialog, slider, metrics)
        local column = VerticalGroup:new({
            slider,
            VerticalSpan:new({ width = metrics.side_button_gap }),
            button,
        })
        column.button = button
        return column, slider
    end

    function QuickDock:makeFrontlightSlider(dock_height, dialog, metrics)
        local column, slider = self:makeLightColumn(
            dock_height, dialog, metrics, self.newFrontlightModel, self.makeFrontlightToggleButton
        )
        -- The toggle button's icon follows the light's state.
        slider.state_changed_callback = function()
            UIManager:setDirty(dialog, "ui")
        end
        return column
    end

    function QuickDock:makeWarmthSlider(dock_height, dialog, metrics)
        return (self:makeLightColumn(
            dock_height, dialog, metrics, self.newWarmthModel, self.makeWarmthInfoButton
        ))
    end

    function QuickDock:refreshStatefulActionButton(action_id)
        if not C.STATEFUL_ACTIONS[action_id] or not self.dialog then
            return
        end
        local dialog = self.dialog
        local button = dialog:getButtonById("quickdock_" .. action_id)
        if not button then
            return
        end

        local icon = self:getIcon(action_id)
        if icon and icon ~= button.icon then
            button:setIcon(icon, button.width)
            UIManager:setDirty(dialog, "ui")
        end
    end

    function QuickDock:makeActionButton(item, metrics)
        local button = {
            id = "quickdock_" .. item.key,
            enabled = true,
            callback = function()
                self:executeAction(item.key)
            end,
            hold_callback = function()
                self:showButtonHelp(item.text)
            end,
        }
        setLabel(button, self:getIcon(item.key), makeFallbackLabel(item.text, item.key),
            metrics.fallback_font_size, true)
        return applyButtonMetrics(button, metrics)
    end

    function QuickDock:makeContextButton(metrics)
        local text
        if self:getParkedBookshelfContext() then
            text = _("Return to reader")
        elseif self:isReaderContext() then
            text = _("File browser")
        else
            text = _("Open last document")
        end
        local button = {
            id = "quickdock_context_home",
            enabled = true,
            callback = function()
                self:closeDock()
                UIManager:scheduleIn(C.DISPATCH_DELAY, function()
                    self:onQuickDockContextHome()
                end)
            end,
            hold_callback = function()
                self:showButtonHelp(text)
            end,
        }
        setLabel(button, self:getIcon(C.ACTION_HOME), makeFallbackLabel(text, C.ACTION_HOME),
            metrics.fallback_font_size, true)
        return applyButtonMetrics(button, metrics)
    end

    function QuickDock:showPageHelp(direction)
        self:showButtonHelp(
            direction == "next" and _("Show next dock page") or _("Show previous dock page")
        )
    end

    function QuickDock:makePageButton(direction, target_page, metrics)
        local is_next = direction == "next"
        local button = {
            id = is_next and "quickdock_next" or "quickdock_previous",
            enabled = true,
            callback = function()
                self:showColumnDockPage(target_page)
            end,
            hold_callback = function()
                self:showPageHelp(direction)
            end,
        }
        setLabel(button, self:getIcon(is_next and "chevron-up" or "chevron-down"),
            is_next and "↑" or "↓", metrics.page_font_size)
        return applyButtonMetrics(button, metrics)
    end

    function QuickDock:moveDockToSide(target_side)
        local page = self.current_page
        local info_panel_data = self.info_panel_data
        Prefs.setSide(target_side)
        UIManager:scheduleIn(C.DISPATCH_DELAY, function()
            self:showDock(page, target_side, info_panel_data)
        end)
    end

    function QuickDock:showMoveDockHelp(target_side)
        local message = target_side == "left"
            and _("Move dock to the left")
            or _("Move dock to the right")
        self:showButtonHelp(message)
    end

    function QuickDock:makeSideButton(width, dialog, metrics)
        local current_side = self.current_dock_side or Prefs.getSide()
        local target_side = current_side == "left" and "right" or "left"
        local button = applyHighlightedButtonMetrics({
            id = "quickdock_switch_side",
            enabled = true,
            show_parent = dialog,
            callback = function()
                self:moveDockToSide(target_side)
            end,
            hold_callback = function()
                self:showMoveDockHelp(target_side)
            end,
        }, width, metrics)
        setLabel(button, self:getIcon("chevron-" .. target_side), target_side == "left" and "←" or "→",
            metrics.side_font_size, true, "text_")
        return Button:new(button)
    end

    function QuickDock:makeCloseButton(width, dialog, metrics)
        local button = applyHighlightedButtonMetrics({
            id = "quickdock_close",
            enabled = true,
            show_parent = dialog,
            callback = function()
                self:closeDock()
            end,
            hold_callback = function()
                self:showButtonHelp(_("Close Quick Dock"))
            end,
        }, width, metrics)
        setLabel(button, self:getIcon("close"), _("Close"), metrics.fallback_font_size, true, "text_")
        return Button:new(button)
    end

    function QuickDock:getInfoPanelToggleDisplay()
        local mode = self:getInfoPanelMode(self.current_info_panel_kind)
            or self:getInfoPanelMode("reading")
        return self:getIcon(mode.icon), makeFallbackLabel(mode.title, mode.icon)
    end

    function QuickDock:showInfoPanelSwitchHelp()
        local current = self:getInfoPanelMode(self.current_info_panel_kind)
            or self:getInfoPanelMode("reading")
        local next_mode = self:getInfoPanelMode(self:getNextInfoPanelKind()) or current
        self:showButtonHelp(T(_("Showing %1. Tap to show %2."), current.name, next_mode.name))
    end

    function QuickDock:makeInfoPanelToggleButton(width, dialog, metrics)
        local icon, fallback = self:getInfoPanelToggleDisplay()
        local button = applyHighlightedButtonMetrics({
            id = "quickdock_switch_info_panel",
            enabled = true,
            show_parent = dialog,
            display_provider = function()
                return self:getInfoPanelToggleDisplay()
            end,
            callback = function()
                self:switchInfoPanel(self:getNextInfoPanelKind())
            end,
            hold_callback = function()
                self:showInfoPanelSwitchHelp()
            end,
        }, width, metrics)
        setLabel(button, icon, fallback, metrics.side_font_size, true, "text_")
        return DynamicLabelButton:new(button)
    end

end
