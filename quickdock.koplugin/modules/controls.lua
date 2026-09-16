local Button = require("ui/widget/button")
local Device = require("device")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("quickdock_l10n")
local T = require("ffi/util").template

local math_max = math.max

-- Button and lighting-control factories. Keeping these out of main.lua makes
-- the plugin lifecycle and dock orchestration easier to audit independently
-- from widget construction details.
return function(QuickDock, options)
    local ACTION_HOME = options.action_home
    local STATEFUL_ACTIONS = options.stateful_actions
    local applyButtonMetrics = options.apply_button_metrics
    local applyHighlightedButtonMetrics = options.apply_highlighted_button_metrics
    local makeFallbackLabel = options.make_fallback_label
    local LightSlider = options.widgets.LightSlider
    local FrontlightToggleButton = options.widgets.FrontlightToggleButton
    local InfoPanelToggleButton = options.widgets.InfoPanelToggleButton

function QuickDock:getFrontlightSliderHeight(dock_height)
    return math_max(1, tonumber(dock_height) or 1)
end

function QuickDock:makeFrontlightToggleButton(width, dialog, slider, metrics)
    local powerd = slider.powerd
    local function getStateIcon()
        return self:getIcon(slider.enabled and "light_on" or "light_off")
    end

    local icon = getStateIcon()
    local config = applyHighlightedButtonMetrics({
        id = "quickdock_toggle_frontlight",
        enabled = true,
        show_parent = dialog,
        slider = slider,
        icon_provider = getStateIcon,
        callback = function()
            local toggled = pcall(function()
                powerd:toggleFrontlight()
                powerd:updateResumeFrontlightState()
            end)
            if toggled then
                slider:syncFromPower(true)
            end
        end,
        hold_callback = function()
            local message = slider.enabled and _("Turn frontlight off") or _("Turn frontlight on")
            self:showButtonHelp(message)
        end,
    }, width, metrics)
    if icon then
        config.icon = icon
    else
        config.text = slider.enabled and _("On") or _("Off")
    end
    return FrontlightToggleButton:new(config)
end

function QuickDock:makeFrontlightSlider(dock_height, dialog, metrics)
    local column_height = self:getFrontlightSliderHeight(dock_height)
    local slider_height = math_max(
        1,
        column_height - metrics.side_button_outer_height - metrics.side_button_gap
    )
    local slider = LightSlider:new({
        width = metrics.button_width,
        height = slider_height,
        slider_padding = metrics.frontlight_slider_padding,
        track_width = metrics.frontlight_track_width,
        knob_radius = metrics.frontlight_knob_radius,
        powerd = Device:getPowerDevice(),
        show_parent = dialog,
    })
    local toggle_button = self:makeFrontlightToggleButton(
        metrics.button_width,
        dialog,
        slider,
        metrics
    )
    slider.state_changed_callback = function()
        UIManager:setDirty(dialog, "ui")
    end
    local column = VerticalGroup:new({
        slider,
        VerticalSpan:new({ width = metrics.side_button_gap }),
        toggle_button,
    })
    column.toggle_button = toggle_button
    return column
end

function QuickDock:makeWarmthInfoButton(width, dialog, slider, metrics)
    local function showWarmthLevel()
        slider:syncFromPower()
        self:showButtonHelp(T(_("Warmth: %1"), slider.value))
    end
    local icon = self:getIcon("warmth")
    local config = applyHighlightedButtonMetrics({
        id = "quickdock_frontlight_warmth",
        enabled = true,
        show_parent = dialog,
        callback = showWarmthLevel,
        hold_callback = showWarmthLevel,
    }, width, metrics)
    if icon then
        config.icon = icon
    else
        config.text = makeFallbackLabel(_("Warmth"), "warmth")
    end
    return Button:new(config)
end

function QuickDock:makeWarmthSlider(dock_height, dialog, metrics)
    local powerd = Device:getPowerDevice()
    local column_height = self:getFrontlightSliderHeight(dock_height)
    local slider_height = math_max(
        1,
        column_height - metrics.side_button_outer_height - metrics.side_button_gap
    )
    local slider = LightSlider:new({
        width = metrics.button_width,
        height = slider_height,
        slider_padding = metrics.frontlight_slider_padding,
        track_width = metrics.frontlight_track_width,
        knob_radius = metrics.frontlight_knob_radius,
        powerd = powerd,
        minimum = tonumber(powerd.fl_warmth_min) or 0,
        maximum = tonumber(powerd.fl_warmth_max) or 100,
        value_reader = function(active_powerd)
            return active_powerd:toNativeWarmth(active_powerd:frontlightWarmth())
        end,
        value_writer = function(active_powerd, native_warmth)
            active_powerd:setWarmth(active_powerd:fromNativeWarmth(native_warmth))
        end,
        show_parent = dialog,
    })
    local info_button = self:makeWarmthInfoButton(
        metrics.button_width,
        dialog,
        slider,
        metrics
    )
    local column = VerticalGroup:new({
        slider,
        VerticalSpan:new({ width = metrics.side_button_gap }),
        info_button,
    })
    column.info_button = info_button
    return column
end

function QuickDock:refreshStatefulActionButton(action_id)
    if not STATEFUL_ACTIONS[action_id] or not self.dialog then
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
    local icon = self:getIcon(item.key)
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
    if icon then
        button.icon = icon
    else
        button.text = makeFallbackLabel(item.text, item.key)
        button.font_size = metrics.fallback_font_size
        button.font_bold = true
    end
    return applyButtonMetrics(button, metrics)
end

function QuickDock:makeContextButton(metrics)
    local bookshelf = self:getParkedBookshelfContext()
    local in_reader = self:isReaderContext()
    local text
    if bookshelf then
        text = _("Return to reader")
    elseif in_reader then
        text = _("File browser")
    else
        text = _("Open last document")
    end
    local icon = self:getIcon(ACTION_HOME)
    local button = {
        id = "quickdock_context_home",
        enabled = true,
        callback = function()
            self:closeDock()
            UIManager:scheduleIn(0.05, function()
                self:onQuickDockContextHome()
            end)
        end,
        hold_callback = function()
            self:showButtonHelp(text)
        end,
    }
    if icon then
        button.icon = icon
    else
        button.text = makeFallbackLabel(text, ACTION_HOME)
        button.font_size = metrics.fallback_font_size
        button.font_bold = true
    end
    return applyButtonMetrics(button, metrics)
end

function QuickDock:makePageButton(direction, target_page, metrics)
    local is_next = direction == "next"
    local icon = self:getIcon(is_next and "chevron-up" or "chevron-down")
    local button = {
        id = is_next and "quickdock_next" or "quickdock_previous",
        enabled = true,
        callback = function()
            self:showDock(target_page, self.current_dock_side, self.info_panel_data)
        end,
        hold_callback = function()
            self:showButtonHelp(
                is_next and _("Show next dock page") or _("Show previous dock page")
            )
        end,
    }
    if icon then
        button.icon = icon
    else
        button.text = is_next and "↑" or "↓"
        button.font_size = metrics.page_font_size
    end
    return applyButtonMetrics(button, metrics)
end

function QuickDock:makeSideButton(width, dialog, metrics)
    local current_side = self.current_dock_side or self:getSide()
    local target_side = current_side == "left" and "right" or "left"
    local icon = self:getIcon("chevron-" .. target_side)
    local button = applyHighlightedButtonMetrics({
        id = "quickdock_switch_side",
        enabled = true,
        show_parent = dialog,
        callback = function()
            local page = self.current_page
            local info_panel_data = self.info_panel_data
            self:setSide(target_side)
            UIManager:scheduleIn(0.05, function()
                self:showDock(page, target_side, info_panel_data)
            end)
        end,
        hold_callback = function()
            local message = target_side == "left"
                and _("Move dock to the left")
                or _("Move dock to the right")
            self:showButtonHelp(message)
        end,
    }, width, metrics)
    if icon then
        button.icon = icon
    else
        button.text = target_side == "left" and "←" or "→"
        button.text_font_size = metrics.side_font_size
        button.text_font_bold = true
    end
    return Button:new(button)
end

function QuickDock:makeCloseButton(width, dialog, metrics)
    local icon = self:getIcon("close")
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
    if icon then
        button.icon = icon
    else
        button.text = _("Close")
        button.text_font_size = metrics.fallback_font_size
        button.text_font_bold = true
    end
    return Button:new(button)
end

function QuickDock:getInfoPanelToggleDisplay()
    if self.current_info_panel_kind == "network" then
        return self:getIcon("network_info"), makeFallbackLabel(_("Network information"), "network_info")
    end
    return self:getIcon("reading_info"), makeFallbackLabel(_("Reading information"), "reading_info")
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
            local target = self.current_info_panel_kind == "network"
                and "reading"
                or "network"
            self:switchInfoPanel(target)
        end,
        hold_callback = function()
            local message = self.current_info_panel_kind == "network"
                and _("Showing network information. Tap to show reading information.")
                or _("Showing reading information. Tap to show network information.")
            self:showButtonHelp(message)
        end,
    }, width, metrics)
    if icon then
        button.icon = icon
    else
        button.text = fallback
        button.text_font_size = metrics.side_font_size
        button.text_font_bold = true
    end
    return InfoPanelToggleButton:new(button)
end

end
