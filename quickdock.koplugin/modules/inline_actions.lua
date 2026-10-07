local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local _ = require("quickdock_l10n")

-- NetworkMgr gives up on a connection after 45 s; one check right after
-- that replaces its error InfoMessage with the dock's status block.
local WIFI_CONNECT_TIMEOUT = 46
local WIFI_ERROR_TIMEOUT = 3
local WIFI_STATE_TIMEOUT = 2

-- The actions that run without closing the dock: Wi-Fi, whose progress is
-- reported in the status block, and night mode. Wi-Fi and night mode are the
-- only Dispatcher actions designed to run in place.
return function(QuickDock)

    function QuickDock:cancelWifiStatusTimeout()
        local task = self.wifi_status_timeout_task
        if task then
            self.wifi_status_timeout_task = nil
            UIManager:unschedule(task)
        end
    end

    -- A newer Wi-Fi state makes any pending connection check obsolete.
    function QuickDock:invalidateWifiChecks()
        self.wifi_status_generation = self.wifi_status_generation + 1
        self:cancelWifiStatusTimeout()
    end

    function QuickDock:reportWifiState(state, message, timeout)
        self:refreshVisibleNetworkInfoPanel(state)
        self:showStatusPanel(message, timeout)
        self:refreshStatefulActionButton("toggle_wifi")
    end

    function QuickDock:reportWifiError()
        self:invalidateWifiChecks()
        self:reportWifiState("error", _("Error connecting to the network"), WIFI_ERROR_TIMEOUT)
    end

    function QuickDock:scheduleWifiStatusTimeout()
        self:cancelWifiStatusTimeout()
        if not self.dialog then
            return
        end
        local generation = self.wifi_status_generation
        -- NetworkMgr already performs its own 250 ms connectivity checks. One
        -- final check after its 45 s deadline is enough to replace the native
        -- error InfoMessage without adding another polling loop.
        local task
        task = function()
            if self.wifi_status_timeout_task == task then
                self.wifi_status_timeout_task = nil
            end
            if generation ~= self.wifi_status_generation or not self.dialog then
                return
            end
            if not NetworkMgr:isConnected() then
                self:reportWifiError()
            end
        end
        self.wifi_status_timeout_task = task
        UIManager:scheduleIn(WIFI_CONNECT_TIMEOUT, task)
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
            -- Level 0 keeps the original error's position.
            error(result, 0)
        end
        return result
    end

    function QuickDock:toggleWifiInline()
        if NetworkMgr:isWifiOn() then
            self:invalidateWifiChecks()
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
            self:reportWifiError()
        end
        return true
    end

    function QuickDock:toggleNightModeInline()
        local listener = self.ui and self.ui.devicelistener
        local method = listener and listener.onToggleNightMode
        if type(method) ~= "function" then
            return false
        end
        method(listener)
        self:refreshStatefulActionButton("night_mode")
        return true
    end

    -- Action id → the method running it in place. A method returns false
    -- when it cannot, and the action is then dispatched normally.
    local INLINE_HANDLERS = {
        toggle_wifi = QuickDock.toggleWifiInline,
        night_mode = QuickDock.toggleNightModeInline,
    }

    -- Runs an action in place when it has a handler and the dock is open.
    -- Returns false when the action must be dispatched normally instead.
    function QuickDock:executeInlineAction(action_id)
        local handler = INLINE_HANDLERS[action_id]
        if not handler or not self.dialog then
            return false
        end
        return handler(self)
    end

    function QuickDock:onNetworkConnected()
        self:invalidateWifiChecks()
        self:reportWifiState("connected", _("Connected to Wi-Fi"), WIFI_STATE_TIMEOUT)
    end

    function QuickDock:onNetworkDisconnected()
        self:invalidateWifiChecks()
        self:reportWifiState("disconnected", _("Wi-Fi off."), WIFI_STATE_TIMEOUT)
    end

    function QuickDock:onNetworkConnecting()
        self:invalidateWifiChecks()
        self:refreshVisibleNetworkInfoPanel("connecting")
        self:showStatusPanel(_("Connecting to Wi-Fi…"))
        self:scheduleWifiStatusTimeout()
    end

    function QuickDock:onNetworkDisconnecting()
        self:invalidateWifiChecks()
        self:showStatusPanel(_("Turning off Wi-Fi…"))
    end

end
