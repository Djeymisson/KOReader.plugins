local Device = require("device")
local Dispatcher = require("dispatcher")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

return function(ShortcutDock, constants)
    local ACTION_CONTEXT_ALL = constants.ACTION_CONTEXT_ALL
    local ACTION_CONTEXT_AUTOMATIC = constants.ACTION_CONTEXT_AUTOMATIC
    local ACTION_CONTEXT_READER = constants.ACTION_CONTEXT_READER
    local ACTION_CONTEXT_BROWSER = constants.ACTION_CONTEXT_BROWSER
    local ACTION_HOME = constants.ACTION_HOME
    local SIDE_MODE_FIXED = constants.SIDE_MODE_FIXED
    local SIDE_MODE_GESTURE = constants.SIDE_MODE_GESTURE
    local DOCK_SIZE_SMALL = constants.DOCK_SIZE_SMALL
    local DOCK_SIZE_MEDIUM = constants.DOCK_SIZE_MEDIUM
    local DOCK_SIZE_LARGE = constants.DOCK_SIZE_LARGE
    local PLUGIN_VERSION = constants.PLUGIN_VERSION

function ShortcutDock:showResetButtonsConfirmation(touchmenu_instance)
    UIManager:show(ConfirmBox:new({
        text = _("Reset the Shortcut Dock buttons and their order to the defaults?"),
        ok_text = _("Reset"),
        ok_callback = function()
            self:resetActions()
            if touchmenu_instance and touchmenu_instance.updateItems then
                touchmenu_instance:updateItems()
            end
        end,
    }))
end

function ShortcutDock:showResetBehaviorConfirmation(touchmenu_instance)
    UIManager:show(ConfirmBox:new({
        text = _("Reset Shortcut Dock behavior to its defaults? Your buttons and their order will be kept."),
        ok_text = _("Reset"),
        ok_callback = function()
            self:resetBehavior()
            if touchmenu_instance and touchmenu_instance.updateItems then
                touchmenu_instance:updateItems()
            end
        end,
    }))
end

function ShortcutDock:showResetBehaviorAndButtonsConfirmation(touchmenu_instance)
    UIManager:show(ConfirmBox:new({
        text = _("Reset Shortcut Dock behavior and buttons to their defaults? Appearance settings will be kept."),
        ok_text = _("Reset all"),
        ok_callback = function()
            self:resetBehaviorAndButtons()
            if touchmenu_instance and touchmenu_instance.updateItems then
                touchmenu_instance:updateItems()
            end
        end,
    }))
end

function ShortcutDock:getActionsMenu()
    local menu = {}

    Dispatcher:addSubMenu(self, menu, self, "actions")
    return menu
end

function ShortcutDock:getActionVisibilityLabel(context)
    if context == ACTION_CONTEXT_AUTOMATIC then
        return _("Automatic")
    elseif context == ACTION_CONTEXT_READER then
        return _("Reader only")
    elseif context == ACTION_CONTEXT_BROWSER then
        return _("File browser and Bookshelf only")
    end
    return _("Everywhere")
end

function ShortcutDock:getActionVisibilitySummary(action_id)
    local mode = self:getActionVisibilityMode(action_id)
    if mode == ACTION_CONTEXT_AUTOMATIC then
        return self:getActionVisibilityLabel(mode)
            .. " (" .. self:getActionVisibilityLabel(self:getEffectiveActionVisibility(action_id)) .. ")"
    end
    return self:getActionVisibilityLabel(mode)
end

function ShortcutDock:makeActionVisibilityOption(action_id, context)
    return {
        text = self:getActionVisibilityLabel(context),
        enabled_func = function()
            return context ~= ACTION_CONTEXT_AUTOMATIC or self:automaticVisibilityEnabled()
        end,
        checked_func = function()
            return self:getActionVisibilityMode(action_id) == context
        end,
        radio = true,
        callback = function(touchmenu_instance)
            self:setActionVisibility(action_id, context)
            if touchmenu_instance and touchmenu_instance.updateItems then
                touchmenu_instance:updateItems()
            end
        end,
        keep_menu_open = true,
    }
end

function ShortcutDock:getActionVisibilityMenu()
    self.action_contexts = self:loadActionContexts()
    self.auto_visibility = self:loadAutomaticVisibility()
    local menu = {
        {
            text_func = function()
                if self:automaticVisibilityEnabled() then
                    return _("Use automatic visibility for all actions")
                end
                return _("Show all actions everywhere")
            end,
            checked_func = function()
                return next(self.action_contexts) == nil
            end,
            callback = function(touchmenu_instance)
                self:resetActionVisibility()
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            keep_menu_open = true,
            separator = true,
        },
    }

    local actions = self:getConfiguredActions()
    if #actions == 0 then
        menu[#menu + 1] = {
            text = _("No Shortcut Dock actions are configured."),
            enabled = false,
        }
        return menu
    end

    for _, item in ipairs(actions) do
        local action_id = item.key
        local action_text = tostring(item.text or action_id)
        menu[#menu + 1] = {
            text_func = function()
                return action_text .. ": " .. self:getActionVisibilitySummary(action_id)
            end,
            sub_item_table = {
                self:makeActionVisibilityOption(action_id, ACTION_CONTEXT_AUTOMATIC),
                self:makeActionVisibilityOption(action_id, ACTION_CONTEXT_ALL),
                self:makeActionVisibilityOption(action_id, ACTION_CONTEXT_READER),
                self:makeActionVisibilityOption(action_id, ACTION_CONTEXT_BROWSER),
            },
        }
    end
    return menu
end

function ShortcutDock:getIconFilenamesMenu()
    local light_icon_details = _("Frontlight toggle")
        .. "\n\n" .. _("Frontlight on") .. ": light_on.svg / light_on.png"
        .. "\n" .. _("Frontlight off") .. ": light_off.svg / light_off.png"
    local warmth_icon_details = _("Warmth control")
        .. "\n\nSVG: warmth.svg"
        .. "\nPNG: warmth.png"
    local menu = {
        {
            text = _("Frontlight toggle") .. ": light_on.svg / light_off.svg",
            help_text = _("Uses a different icon for the active and inactive frontlight states."),
            callback = function()
                UIManager:show(InfoMessage:new({ text = light_icon_details }))
            end,
        },
        {
            text = _("Warmth control") .. ": warmth.svg",
            help_text = _("Icon shown below the frontlight warmth slider."),
            callback = function()
                UIManager:show(InfoMessage:new({ text = warmth_icon_details }))
            end,
        },
    }
    local actions = self:getConfiguredActions()
    table.insert(actions, 1, {
        key = ACTION_HOME,
        text = _("File browser / return to reader / open last document"),
    })
    for index = 1, #actions do
        local item = actions[index]
        local basename = tostring(item.key)
        local svg_name = basename .. ".svg"
        local png_name = basename .. ".png"
        local help_text = _("Alternative PNG filename") .. ": " .. png_name
        local details = tostring(item.text or basename)
            .. "\n\nSVG: " .. svg_name
            .. "\nPNG: " .. png_name
        if item.key == "night_mode" then
            svg_name = "day_mode.svg / night_mode.svg"
            png_name = "day_mode.png / night_mode.png"
            help_text = _("Uses a different icon for day and night modes.")
            details = tostring(item.text or basename)
                .. "\n\n" .. _("Day mode") .. ": day_mode.svg / day_mode.png"
                .. "\n" .. _("Night mode") .. ": night_mode.svg / night_mode.png"
        elseif item.key == "toggle_wifi" then
            svg_name = "wifi_on.svg / wifi_off.svg"
            png_name = "wifi_on.png / wifi_off.png"
            help_text = _("Uses a different icon for the active and inactive Wi-Fi states.")
            details = tostring(item.text or basename)
                .. "\n\n" .. _("Wi-Fi on") .. ": wifi_on.svg / wifi_on.png"
                .. "\n" .. _("Wi-Fi off") .. ": wifi_off.svg / wifi_off.png"
        elseif item.key == ACTION_HOME then
            help_text = help_text
                .. "\n" .. _("Context-specific SVG filenames")
                .. ": home.svg / book.opened.svg"
            details = details
                .. "\n\n" .. _("While reading") .. ": home.svg / home.png"
                .. "\n" .. _("In the file browser") .. ": book.opened.svg / book.opened.png"
                .. "\n" .. _("In Bookshelf with a parked reader")
                .. ": book.opened.svg / book.opened.png"
        end
        menu[#menu + 1] = {
            text = tostring(item.text or basename) .. ": " .. svg_name,
            help_text = help_text,
            callback = function()
                UIManager:show(InfoMessage:new({ text = details }))
            end,
        }
    end
    if #menu == 0 then
        menu[1] = {
            text = _("No Shortcut Dock actions are configured."),
            enabled = false,
        }
    end
    return menu
end

function ShortcutDock:addToMainMenu(menu_items)
    local behavior_items = {
        {
            text_func = function()
                local side
                if self:getSideMode() == SIDE_MODE_GESTURE then
                    side = _("Follow gesture")
                else
                    side = self:getSide() == "left" and _("Left") or _("Right")
                end
                return _("Dock side") .. ": " .. side
            end,
            help_text = _("Choose a fixed side or place the dock on the side where its gesture started."),
            sub_item_table = {
                {
                    text = _("Left"),
                    checked_func = function()
                        return self:getSideMode() == SIDE_MODE_FIXED and self:getSide() == "left"
                    end,
                    callback = function(touchmenu_instance)
                        self:setSide("left")
                        self:setSideMode(SIDE_MODE_FIXED)
                        if touchmenu_instance and touchmenu_instance.updateItems then
                            touchmenu_instance:updateItems()
                        end
                    end,
                    keep_menu_open = true,
                    radio = true,
                },
                {
                    text = _("Right"),
                    checked_func = function()
                        return self:getSideMode() == SIDE_MODE_FIXED and self:getSide() == "right"
                    end,
                    callback = function(touchmenu_instance)
                        self:setSide("right")
                        self:setSideMode(SIDE_MODE_FIXED)
                        if touchmenu_instance and touchmenu_instance.updateItems then
                            touchmenu_instance:updateItems()
                        end
                    end,
                    keep_menu_open = true,
                    radio = true,
                },
                {
                    text = _("Follow gesture side"),
                    help_text = _("Places the dock on the half of the screen where the gesture started. Uses the fixed side when no gesture position is available."),
                    checked_func = function()
                        return self:getSideMode() == SIDE_MODE_GESTURE
                    end,
                    callback = function(touchmenu_instance)
                        self:setSideMode(SIDE_MODE_GESTURE)
                        if touchmenu_instance and touchmenu_instance.updateItems then
                            touchmenu_instance:updateItems()
                        end
                    end,
                    keep_menu_open = true,
                    radio = true,
                },
            },
        },
        {
            text_func = function()
                local labels = {
                    [DOCK_SIZE_SMALL] = _("Small"),
                    [DOCK_SIZE_MEDIUM] = _("Medium"),
                    [DOCK_SIZE_LARGE] = _("Large"),
                }
                return _("Dock size") .. ": " .. labels[self:getDockSize()]
            end,
            help_text = _("Change the size of the buttons, icons, pagination controls, and frontlight column."),
            sub_item_table = {
                {
                    text = _("Small"),
                    help_text = _("Uses the original Shortcut Dock dimensions."),
                    checked_func = function()
                        return self:getDockSize() == DOCK_SIZE_SMALL
                    end,
                    callback = function(touchmenu_instance)
                        self:setDockSize(DOCK_SIZE_SMALL)
                        if touchmenu_instance and touchmenu_instance.updateItems then
                            touchmenu_instance:updateItems()
                        end
                    end,
                    keep_menu_open = true,
                    radio = true,
                },
                {
                    text = _("Medium"),
                    help_text = _("Increases the dock dimensions by 20 percent."),
                    checked_func = function()
                        return self:getDockSize() == DOCK_SIZE_MEDIUM
                    end,
                    callback = function(touchmenu_instance)
                        self:setDockSize(DOCK_SIZE_MEDIUM)
                        if touchmenu_instance and touchmenu_instance.updateItems then
                            touchmenu_instance:updateItems()
                        end
                    end,
                    keep_menu_open = true,
                    radio = true,
                },
                {
                    text = _("Large"),
                    help_text = _("Increases the dock dimensions by 40 percent."),
                    checked_func = function()
                        return self:getDockSize() == DOCK_SIZE_LARGE
                    end,
                    callback = function(touchmenu_instance)
                        self:setDockSize(DOCK_SIZE_LARGE)
                        if touchmenu_instance and touchmenu_instance.updateItems then
                            touchmenu_instance:updateItems()
                        end
                    end,
                    keep_menu_open = true,
                    radio = true,
                },
            },
        },
        {
            text = _("Keep dock open after actions"),
            help_text = _("Keeps the dock in place for compatible device actions and reopens it after other actions that do not open another screen or dialog."),
            checked_func = function()
                return self:keepOpenAfterAction()
            end,
            callback = function(touchmenu_instance)
                self:setKeepOpenAfterAction(not self:keepOpenAfterAction())
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            keep_menu_open = true,
        },
    }

    local additional_control_items = {
        {
            text = _("Show fixed context button"),
            help_text = _("Shows File browser while reading, Return to reader in Bookshelf, and Open last document in the file browser."),
            checked_func = function()
                return self:showContextButton()
            end,
            callback = function(touchmenu_instance)
                self:setShowContextButton(not self:showContextButton())
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            keep_menu_open = true,
        },
        {
            text = _("Show side-switch button"),
            help_text = _("Shows a separate chevron button above the dock for changing sides without opening the settings."),
            checked_func = function()
                return self:showSideButton()
            end,
            callback = function(touchmenu_instance)
                self:setShowSideButton(not self:showSideButton())
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            keep_menu_open = true,
        },
        {
            text = _("Show panel"),
            help_text = _("Shows book, chapter, daily reading, clock, and battery information on the screen edge opposite the dock."),
            checked_func = function()
                return self:showInfoPanel()
            end,
            callback = function(touchmenu_instance)
                self:setShowInfoPanel(not self:showInfoPanel())
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            keep_menu_open = true,
        },
        {
            text = _("Show book cover at the top"),
            help_text = _("Shows the open book's cover above the reading information. The thumbnail is loaded once and reused while the document remains open."),
            enabled_func = function()
                return self:showInfoPanel()
            end,
            checked_func = function()
                return self:showInfoPanelCover()
            end,
            callback = function(touchmenu_instance)
                self:setShowInfoPanelCover(not self:showInfoPanelCover())
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            keep_menu_open = true,
        },
        {
            text = _("Show frontlight control"),
            help_text = _("Shows the brightness slider and its light toggle button beside the dock on devices with a frontlight."),
            enabled_func = function()
                return Device:hasFrontlight()
            end,
            checked_func = function()
                return self:showFrontlightSlider()
            end,
            callback = function(touchmenu_instance)
                self:setShowFrontlightSlider(not self:showFrontlightSlider())
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            keep_menu_open = true,
        },
        {
            text = _("Show warmth control"),
            help_text = _("Shows a second slider for the frontlight warmth on supported devices."),
            enabled_func = function()
                return Device:hasNaturalLight()
            end,
            checked_func = function()
                return self:showWarmthSlider()
            end,
            callback = function(touchmenu_instance)
                self:setShowWarmthSlider(not self:showWarmthSlider())
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            keep_menu_open = true,
        },
    }

    local dock_size_item = behavior_items[2]
    behavior_items = {
        behavior_items[1],
        behavior_items[3],
    }
    local action_button_items = {
        additional_control_items[1],
        additional_control_items[2],
    }
    local appearance_items = {
        dock_size_item,
        {
            text = _("Reading information panel"),
            help_text = _("Configure the opposite-edge reading summary and its book cover."),
            sub_item_table = {
                additional_control_items[3],
                additional_control_items[4],
            },
        },
        {
            text = _("Lighting controls"),
            help_text = _("Show or hide the frontlight brightness and warmth columns."),
            sub_item_table = {
                additional_control_items[5],
                additional_control_items[6],
            },
        },
        {
            text = _("Expected icon filenames"),
            help_text = _("Shows the custom SVG and PNG filenames expected for each dock action."),
            sub_item_table_func = function()
                return self:getIconFilenamesMenu()
            end,
        },
    }

    local context_visibility_items = {
        {
            text = _("Automatic visibility"),
            help_text = _("Automatically shows native reader and file-browser actions only in their relevant context. Manual choices override the automatic result."),
            checked_func = function()
                return self:automaticVisibilityEnabled()
            end,
            callback = function(touchmenu_instance)
                self:setAutomaticVisibility(not self:automaticVisibilityEnabled())
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            keep_menu_open = true,
        },
        {
            text = _("Per-action visibility"),
            help_text = _("Review automatic results or override each action for all screens, the reader, or the file browser and Bookshelf."),
            sub_item_table_func = function()
                return self:getActionVisibilityMenu()
            end,
        },
    }

    menu_items.shortcutdock = {
        text = _("Shortcut Dock"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Show Shortcut Dock"),
                callback = function()
                    self:showDock(1)
                end,
            },
            {
                text = _("Behavior"),
                help_text = _("Controls where the dock opens and what happens after an action."),
                sub_item_table = behavior_items,
            },
            {
                text = _("Actions and buttons"),
                help_text = _("Configure actions, fixed buttons, ordering, and contextual visibility."),
                sub_item_table = {
                    {
                        text_func = function()
                            return _("Buttons and order") .. ": " .. tostring(#self:getConfiguredActions())
                        end,
                        help_text = _("Choose the actions shown in the dock and arrange their order."),
                        sub_item_table_func = function()
                            return self:getActionsMenu()
                        end,
                    },
                    {
                        text = _("Fixed buttons"),
                        help_text = _("Show or hide the context and side-switch buttons."),
                        sub_item_table = action_button_items,
                    },
                    {
                        text = _("Context visibility"),
                        help_text = _("Control which actions appear in the reader, file browser, and Bookshelf."),
                        sub_item_table = context_visibility_items,
                    },
                },
            },
            {
                text = _("Appearance"),
                help_text = _("Controls dock size, visible panels, lighting columns, and custom icons."),
                sub_item_table = appearance_items,
            },
            {
                text = _("Reset"),
                help_text = _("Restore the default behavior, with or without resetting the buttons."),
                sub_item_table = {
                    {
                        text = _("Reset behavior to defaults"),
                        help_text = _("Restores gesture-following placement, right-side fallback, and keep-open behavior without changing actions, buttons, or appearance."),
                        callback = function(touchmenu_instance)
                            self:showResetBehaviorConfirmation(touchmenu_instance)
                        end,
                    },
                    {
                        text = _("Reset buttons to defaults"),
                        help_text = _("Restores the initial buttons and their order without changing other Shortcut Dock settings."),
                        callback = function(touchmenu_instance)
                            self:showResetButtonsConfirmation(touchmenu_instance)
                        end,
                    },
                    {
                        text = _("Reset behavior and buttons"),
                        help_text = _("Restores behavior, fixed buttons, default actions, order, and action visibility while keeping appearance settings."),
                        callback = function(touchmenu_instance)
                            self:showResetBehaviorAndButtonsConfirmation(touchmenu_instance)
                        end,
                    },
                },
            },
            {
                text = _("Gesture setup"),
                help_text = _("Assign 'Show Shortcut Dock' to any gesture in KOReader's gesture manager."),
                callback = function()
                    UIManager:show(InfoMessage:new({
                        text = _("Open Settings > Taps and gestures > Gesture manager, choose a gesture, then select Show Shortcut Dock."),
                    }))
                end,
            },
            {
                text = _("Version") .. ": " .. PLUGIN_VERSION,
                callback = function()
                    UIManager:show(InfoMessage:new({ text = _("Shortcut Dock") .. " " .. PLUGIN_VERSION }))
                end,
                separator = true,
            },
        },
    }
end

end
