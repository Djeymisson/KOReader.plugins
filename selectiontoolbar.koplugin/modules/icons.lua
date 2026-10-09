-- Icon lookup in the plugin's own folder, and the IconWidget patch that lets buttons use
-- an icon file path directly.

local IconWidget = require("ui/widget/iconwidget")
local lfs = require("libs/libkoreader-lfs")

local lib = select(2, ...)
local pluginDir = lib.pluginDir

local SelectionToolbar = {}

function SelectionToolbar:patchIconWidget()
    if IconWidget._selectiontoolbar_original_init then
        return
    end

    IconWidget._selectiontoolbar_original_init = IconWidget.init

    -- File existence per path, so showing the toolbar does not stat each icon every time.
    local is_file = {}
    local patched_init = function(icon_widget)
        local explicit_icon = rawget(icon_widget, "icon")
        if type(explicit_icon) == "string" and explicit_icon:match("%.%a+$") then
            local exists = is_file[explicit_icon]
            if exists == nil then
                exists = lfs.attributes(explicit_icon, "mode") == "file"
                is_file[explicit_icon] = exists
            end
            if exists then
                icon_widget.file = explicit_icon
            end
        end

        return IconWidget._selectiontoolbar_original_init(icon_widget)
    end

    IconWidget._selectiontoolbar_patched_init = patched_init
    IconWidget.init = patched_init
end

function SelectionToolbar:unpatchIconWidget()
    if
        IconWidget._selectiontoolbar_original_init
        and IconWidget._selectiontoolbar_patched_init
        and IconWidget.init == IconWidget._selectiontoolbar_patched_init
    then
        IconWidget.init = IconWidget._selectiontoolbar_original_init
        IconWidget._selectiontoolbar_original_init = nil
        IconWidget._selectiontoolbar_patched_init = nil
    end
end

function SelectionToolbar:getIconPath(action)
    local icon = action and action.icon
    if not icon then
        return nil
    end

    self.icon_cache = self.icon_cache or {}
    self.icons_path = self.icons_path or ((self.plugin_path or pluginDir()) .. "icons/")

    local cached = self.icon_cache[icon]
    if cached then
        return cached
    end

    local path = self.icons_path .. icon .. ".svg"
    self.icon_cache[icon] = path
    return path
end

return SelectionToolbar
