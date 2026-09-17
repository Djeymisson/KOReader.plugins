local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local _ = require("quickdock_l10n")

local INLINE_ACTIONS = {
    night_mode = true,
    toggle_wifi = true,
}
local BUTTON_HELP_TIMEOUT = 3

return function(QuickDock, options)
    local InfoPanel = options.InfoPanel
    local dock_margin = options.dock_margin

function QuickDock:closeStatusPanel(expected_widget)
    local status_panel_widget = self.status_panel_widget
    if expected_widget and status_panel_widget ~= expected_widget then
        return
    end
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
        and status_panel_widget.lower_widget == self.info_panel_widget
    then
        -- Native Wi-Fi backends may announce the same connection phase many
        -- times while forcing a repaint after each scan/authentication step.
        -- Keep the existing overlay so those repaints have no widget teardown
        -- or underlying screen region to flush.
        if timeout then
            UIManager:scheduleIn(timeout, function()
                self:closeStatusPanel(status_panel_widget)
            end)
        end
        return status_panel_widget
    end
    self:closeStatusPanel()
    local side = self.current_dock_side == "left" and "right" or "left"
    status_panel_widget = InfoPanel.createStatusOverlay(
        self:getDockMetrics(),
        side,
        dock_margin,
        text,
        self.info_panel_widget,
        self:getSiblingOverlayClearance(side)
    )
    self.status_panel_widget = status_panel_widget
    self.status_panel_text = text
    UIManager:show(status_panel_widget, "ui")
    if timeout then
        UIManager:scheduleIn(timeout, function()
            self:closeStatusPanel(status_panel_widget)
        end)
    end
    return status_panel_widget
end

function QuickDock:showButtonHelp(text)
    return self:showStatusPanel(text, BUTTON_HELP_TIMEOUT)
end

function QuickDock:scheduleWifiStatusTimeout()
    local generation = self.wifi_status_generation
    -- NetworkMgr already performs its own 250 ms connectivity checks. One
    -- final check after its 45 s deadline is enough to replace the native
    -- error InfoMessage without adding another polling loop.
    UIManager:scheduleIn(46, function()
        if generation ~= self.wifi_status_generation or not self.dialog then
            return
        end
        if not NetworkMgr:isConnected() then
            self.wifi_status_generation = self.wifi_status_generation + 1
            self:refreshVisibleNetworkInfoPanel("error")
            self:showStatusPanel(_("Error connecting to the network"), 3)
            self:refreshStatefulActionButton("toggle_wifi")
        end
    end)
end

function QuickDock:runWithWifiInfoRedirect(callback)
    local original_show = UIManager.show
    local original_close = UIManager.close
    local redirected_widgets = {}

    local function isInfoMessage(widget)
        local prototype = widget and getmetatable(widget)
        while prototype do
            if prototype == InfoMessage then
                return true
            end
            prototype = getmetatable(prototype)
        end
        return false
    end

    -- Device backends may synchronously show progress InfoMessages while
    -- scanning or reconnecting. Redirect only those messages for the duration
    -- of this call; confirmation, password, and network-selection widgets keep
    -- using KOReader's native UI.
    UIManager.show = function(manager, widget, ...)
        if isInfoMessage(widget) then
            redirected_widgets[widget] = true
            if NetworkMgr.pending_connection then
                -- Backends may announce scanning or even an early association
                -- with a short-lived (usually 3 s) InfoMessage. Neither means
                -- that KOReader's connectivity check has completed, so keep a
                -- persistent status until NetworkConnected, failure, or the
                -- user closes the dock.
                self:showStatusPanel(_("Connecting to Wi-Fi…"))
            else
                self:showStatusPanel(widget.text, widget.timeout)
            end
            return
        end
        return original_show(manager, widget, ...)
    end
    UIManager.close = function(manager, widget, ...)
        if redirected_widgets[widget] then
            redirected_widgets[widget] = nil
            return
        end
        return original_close(manager, widget, ...)
    end

    local ok, result = pcall(callback)
    UIManager.show = original_show
    UIManager.close = original_close
    if not ok then
        error(result)
    end
    return result
end

function QuickDock:toggleWifiInline()
    if NetworkMgr:isWifiOn() then
        self.wifi_status_generation = self.wifi_status_generation + 1
        self:showStatusPanel(_("Turning off Wi-Fi…"))
        UIManager:forceRePaint()
        NetworkMgr:disableWifi(nil, true)
        return true
    end

    if NetworkMgr.pending_connection then
        self:onNetworkConnecting()
        return true
    end

    -- Start with the persistent state used throughout native scanning and
    -- authentication, avoiding an immediate status-widget replacement before
    -- the backend's first forced repaint.
    self:showStatusPanel(_("Connecting to Wi-Fi…"))
    UIManager:forceRePaint()
    local status = self:runWithWifiInfoRedirect(function()
        return NetworkMgr:enableWifi(nil, true)
    end)
    if status == false then
        self.wifi_status_generation = self.wifi_status_generation + 1
        self:refreshVisibleNetworkInfoPanel("error")
        self:showStatusPanel(_("Error connecting to the network"), 3)
        self:refreshStatefulActionButton("toggle_wifi")
    end
    return true
end

function QuickDock:executeInlineAction(action_id)
    if not INLINE_ACTIONS[action_id] or not self.dialog then
        return false
    end
    if action_id == "toggle_wifi" then
        return self:toggleWifiInline()
    end

    local listener = self.ui and self.ui.devicelistener
    local method = listener and listener.onToggleNightMode
    if type(method) ~= "function" then
        return false
    end
    method(listener)
    self:refreshStatefulActionButton(action_id)
    return true
end

function QuickDock:onNetworkConnected()
    self.wifi_status_generation = self.wifi_status_generation + 1
    self:refreshStatefulActionButton("toggle_wifi")
    self:refreshVisibleNetworkInfoPanel("connected")
    self:showStatusPanel(_("Connected to Wi-Fi"), 2)
end

function QuickDock:onNetworkDisconnected()
    self.wifi_status_generation = self.wifi_status_generation + 1
    self:refreshStatefulActionButton("toggle_wifi")
    self:refreshVisibleNetworkInfoPanel("disconnected")
    self:showStatusPanel(_("Wi-Fi off."), 2)
end

function QuickDock:onNetworkConnecting()
    self.wifi_status_generation = self.wifi_status_generation + 1
    self:refreshVisibleNetworkInfoPanel("connecting")
    self:showStatusPanel(_("Connecting to Wi-Fi…"))
    self:scheduleWifiStatusTimeout()
end

function QuickDock:onNetworkDisconnecting()
    self.wifi_status_generation = self.wifi_status_generation + 1
    self:showStatusPanel(_("Turning off Wi-Fi…"))
end

end
