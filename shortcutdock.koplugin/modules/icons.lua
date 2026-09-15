local Device = require("device")
local IconWidget = require("ui/widget/iconwidget")
local NetworkMgr = require("ui/network/manager")
local lfs = require("libs/libkoreader-lfs")

local Screen = Device.screen

local function fileExists(path)
    return lfs.attributes(path, "mode") == "file"
end

return function(ShortcutDock, constants)
    local ACTION_HOME = constants.ACTION_HOME
    local ACTION_ICONS = constants.ACTION_ICONS
    local ICON_EXTENSIONS = constants.ICON_EXTENSIONS
    local STATEFUL_ACTIONS = constants.STATEFUL_ACTIONS

function ShortcutDock:patchIconWidget()
    if self._shortcutdock_icon_patch_active then
        return
    end
    self._shortcutdock_icon_patch_active = true
    IconWidget._shortcutdock_patch_users = (IconWidget._shortcutdock_patch_users or 0) + 1

    if IconWidget._shortcutdock_original_init then
        return
    end

    IconWidget._shortcutdock_original_init = IconWidget.init
    local original_init = IconWidget.init

    local patched_init = function(icon_widget)
        local explicit_icon = rawget(icon_widget, "icon")
        if type(explicit_icon) == "string" and explicit_icon:match("%.[%a%d]+$") and fileExists(explicit_icon) then
            icon_widget.file = explicit_icon
        end
        return original_init(icon_widget)
    end

    IconWidget._shortcutdock_patched_init = patched_init
    IconWidget.init = patched_init
end

function ShortcutDock:unpatchIconWidget()
    if not self._shortcutdock_icon_patch_active then
        return
    end
    self._shortcutdock_icon_patch_active = nil
    IconWidget._shortcutdock_patch_users = math.max(
        0,
        (IconWidget._shortcutdock_patch_users or 1) - 1
    )
    if IconWidget._shortcutdock_patch_users > 0 then
        return
    end

    if
        IconWidget._shortcutdock_original_init
        and IconWidget._shortcutdock_patched_init
        and IconWidget.init == IconWidget._shortcutdock_patched_init
    then
        IconWidget.init = IconWidget._shortcutdock_original_init
        IconWidget._shortcutdock_original_init = nil
        IconWidget._shortcutdock_patched_init = nil
    end
    IconWidget._shortcutdock_patch_users = nil
end

function ShortcutDock:isWifiOn()
    local ok, enabled = pcall(function()
        return NetworkMgr:isWifiOn()
    end)
    return ok and enabled == true
end

function ShortcutDock:isNightMode()
    if type(Screen.night_mode) == "boolean" then
        return Screen.night_mode
    end
    local ok, enabled = pcall(function()
        return G_reader_settings:isTrue("night_mode")
    end)
    return ok and enabled == true
end

function ShortcutDock:getStockIcon(action_id)
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

function ShortcutDock:systemIconExists(icon)
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

function ShortcutDock:getIcon(action_id)
    local stock_icon = self:getStockIcon(action_id)
    local cache_key = action_id .. ":" .. (stock_icon or "")
    local cached = self.icon_cache[cache_key]
    if cached ~= nil then
        return cached or nil
    end

    local candidates = {}
    local context_specific = action_id == ACTION_HOME
    if STATEFUL_ACTIONS[action_id] or context_specific then
        if stock_icon then
            candidates[#candidates + 1] = self.icons_path .. stock_icon .. ".svg"
            candidates[#candidates + 1] = self.icons_path .. stock_icon .. ".png"
        end
    else
        candidates[#candidates + 1] = self.icons_path .. action_id .. ".svg"
        candidates[#candidates + 1] = self.icons_path .. action_id .. ".png"
    end
    if stock_icon and not STATEFUL_ACTIONS[action_id] and not context_specific then
        candidates[#candidates + 1] = self.icons_path .. stock_icon .. ".svg"
        candidates[#candidates + 1] = self.icons_path .. stock_icon .. ".png"
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
