local UIManager = require("ui/uimanager")

local BUTTON_HELP_TIMEOUT = 3

-- The status block: a one-line message stacked on the information panel
-- (or where it would be), used for button help and Wi-Fi progress.
return function(QuickDock, _C, lib)
    local InfoPanel = lib.InfoPanel
    local Prefs = lib.Prefs

    function QuickDock:cancelStatusPanelTimeout()
        local task = self.status_panel_close_task
        if task then
            self.status_panel_close_task = nil
            UIManager:unschedule(task)
        end
    end

    -- The latest message decides how long the status block stays: a repeated
    -- message restarts its timeout, and one without a timeout keeps it shown.
    function QuickDock:scheduleStatusPanelTimeout(status_panel_widget, timeout)
        self:cancelStatusPanelTimeout()
        if not timeout then
            return
        end
        local task
        task = function()
            if self.status_panel_close_task == task then
                self.status_panel_close_task = nil
            end
            self:closeStatusPanel(status_panel_widget)
        end
        self.status_panel_close_task = task
        UIManager:scheduleIn(timeout, task)
    end

    -- Pending checks belong to the dock that scheduled them: closing it, the
    -- device suspending or the plugin closing must not let them act later on.
    function QuickDock:cancelDockTimers(keep_wifi_timeout)
        self:cancelStatusPanelTimeout()
        if not keep_wifi_timeout then
            self:cancelWifiStatusTimeout()
        end
    end

    function QuickDock:closeStatusPanel(expected_widget)
        local status_panel_widget = self.status_panel_widget
        if expected_widget and status_panel_widget ~= expected_widget then
            return
        end
        self:cancelStatusPanelTimeout()
        self.status_panel_widget = nil
        self.status_panel_text = nil
        if status_panel_widget then
            UIManager:close(status_panel_widget)
        end
    end

    function QuickDock:showStatusPanel(text, timeout)
        if not self.dialog then
            return
        end
        text = tostring(text or "")
        local status_panel_widget = self.status_panel_widget
        if
            status_panel_widget
            and self.status_panel_text == text
            and status_panel_widget.anchor_widget == self.info_panel_widget
        then
            -- Native Wi-Fi backends may announce the same connection phase many
            -- times while forcing a repaint after each scan/authentication step.
            -- Keep the existing overlay so those repaints have no widget teardown
            -- or underlying screen region to flush.
            self:scheduleStatusPanelTimeout(status_panel_widget, timeout)
            return status_panel_widget
        end
        self:closeStatusPanel()
        local view = self:getPanelView(nil, Prefs.isArcLayout())
        view.anchor_widget = self.info_panel_widget
        status_panel_widget = InfoPanel.createStatusOverlay(text, view)
        self.status_panel_widget = status_panel_widget
        self.status_panel_text = text
        UIManager:show(status_panel_widget, "ui")
        self:scheduleStatusPanelTimeout(status_panel_widget, timeout)
        return status_panel_widget
    end

    function QuickDock:showButtonHelp(text)
        return self:showStatusPanel(text, BUTTON_HELP_TIMEOUT)
    end

end
