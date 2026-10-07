local Device = require("device")
local IconWidget = require("ui/widget/iconwidget")
local NetworkMgr = require("ui/network/manager")
local lfs = require("libs/libkoreader-lfs")

local Screen = Device.screen

local function fileExists(path)
    return lfs.attributes(path, "mode") == "file"
end

return function(QuickDock, C)
    local ACTION_HOME = C.ACTION_HOME
    local ACTION_ICONS = C.ACTION_ICONS
    local ICON_EXTENSIONS = C.ICON_EXTENSIONS
    local STATEFUL_ACTIONS = C.STATEFUL_ACTIONS

    function QuickDock:patchIconWidget()
        if self._quickdock_icon_patch_active then
            return
        end
        self._quickdock_icon_patch_active = true
        IconWidget._quickdock_patch_users = (IconWidget._quickdock_patch_users or 0) + 1

        if IconWidget._quickdock_original_init then
            return
        end

        IconWidget._quickdock_original_init = IconWidget.init
        local original_init = IconWidget.init

        local patched_init = function(icon_widget)
            local explicit_icon = rawget(icon_widget, "icon")
            if type(explicit_icon) == "string" and explicit_icon:match("%.[%a%d]+$") and fileExists(explicit_icon) then
                icon_widget.file = explicit_icon
            end
            return original_init(icon_widget)
        end

        IconWidget._quickdock_patched_init = patched_init
        IconWidget.init = patched_init
    end

    function QuickDock:unpatchIconWidget()
        if not self._quickdock_icon_patch_active then
            return
        end
        self._quickdock_icon_patch_active = nil
        IconWidget._quickdock_patch_users = math.max(
            0,
            (IconWidget._quickdock_patch_users or 1) - 1
        )
        if IconWidget._quickdock_patch_users > 0 then
            return
        end

        if
            IconWidget._quickdock_original_init
            and IconWidget._quickdock_patched_init
            and IconWidget.init == IconWidget._quickdock_patched_init
        then
            IconWidget.init = IconWidget._quickdock_original_init
            IconWidget._quickdock_original_init = nil
            IconWidget._quickdock_patched_init = nil
        end
        IconWidget._quickdock_patch_users = nil
    end

    function QuickDock:isWifiOn()
        local ok, enabled = pcall(NetworkMgr.isWifiOn, NetworkMgr)
        return ok and enabled == true
    end

    function QuickDock:isNightMode()
        if type(Screen.night_mode) == "boolean" then
            return Screen.night_mode
        end
        local ok, enabled = pcall(G_reader_settings.isTrue, G_reader_settings, "night_mode")
        return ok and enabled == true
    end

    function QuickDock:getStockIcon(action_id)
        if action_id == "toggle_wifi" then
            return self:isWifiOn() and "wifi_on" or "wifi_off"
        elseif action_id == "night_mode" then
            return self:isNightMode() and "night_mode" or "day_mode"
        end
        if action_id == ACTION_HOME then
            if self:getParkedBookshelfContext() then
                return "last_doc"
            end
            return self:isReaderContext() and "exit_reader" or "last_doc"
        end
        return ACTION_ICONS[action_id]
    end

    function QuickDock:systemIconExists(icon)
        if not icon then
            return false
        end
        for _, directory in ipairs(self.system_icon_paths) do
            for _, extension in ipairs(ICON_EXTENSIONS) do
                if fileExists(directory .. icon .. extension) then
                    return true
                end
            end
        end
        return false
    end

    function QuickDock:getIcon(action_id)
        local stock_icon = self:getStockIcon(action_id)
        local cache_key = action_id .. ":" .. (stock_icon or "")
        local cached = self.icon_cache[cache_key]
        if cached ~= nil then
            return cached or nil
        end

        -- A custom icon in the plugin's icons folder: named after the action,
        -- then after its stock icon. Actions whose icon follows their state or
        -- context only have per-state files, named after the stock icon.
        local candidates = {}
        local function addCandidates(name)
            for _, extension in ipairs(ICON_EXTENSIONS) do
                candidates[#candidates + 1] = self.icons_path .. name .. extension
            end
        end
        if not STATEFUL_ACTIONS[action_id] and action_id ~= ACTION_HOME then
            addCandidates(action_id)
        end
        if stock_icon then
            addCandidates(stock_icon)
        end

        for _, path in ipairs(candidates) do
            if fileExists(path) then
                self.icon_cache[cache_key] = path
                return path
            end
        end

        if self:systemIconExists(stock_icon) then
            self.icon_cache[cache_key] = stock_icon
            return stock_icon
        end

        self.icon_cache[cache_key] = false
    end

end
