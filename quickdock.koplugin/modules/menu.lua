local Device = require("device")
local Dispatcher = require("dispatcher")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("quickdock_l10n")
local T = require("ffi/util").template

local function refreshMenu(touchmenu_instance)
    if touchmenu_instance and touchmenu_instance.updateItems then
        touchmenu_instance:updateItems()
    end
end

local function makeRadioOption(text, help_text, checked_func, select_callback)
    return {
        text = text,
        help_text = help_text,
        checked_func = checked_func,
        callback = function(touchmenu_instance)
            select_callback()
            refreshMenu(touchmenu_instance)
        end,
        keep_menu_open = true,
        radio = true,
    }
end

local function makeToggleOption(text, help_text, checked_func, set_callback, enabled_func)
    return {
        text = text,
        help_text = help_text,
        enabled_func = enabled_func,
        checked_func = checked_func,
        callback = function(touchmenu_instance)
            set_callback(not checked_func())
            refreshMenu(touchmenu_instance)
        end,
        keep_menu_open = true,
    }
end

return function(QuickDock, constants)
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
    local MAX_ACTION_DOCK_HEIGHT_100 = constants.MAX_ACTION_DOCK_HEIGHT_100
    local MAX_ACTION_DOCK_HEIGHT_60 = constants.MAX_ACTION_DOCK_HEIGHT_60
    local MAX_ACTION_DOCK_HEIGHT_33 = constants.MAX_ACTION_DOCK_HEIGHT_33
    local INFO_PANEL_TEXT_LEFT = constants.INFO_PANEL_TEXT_LEFT
    local INFO_PANEL_TEXT_CENTER = constants.INFO_PANEL_TEXT_CENTER
    local INFO_PANEL_TEXT_SCREEN_EDGE = constants.INFO_PANEL_TEXT_SCREEN_EDGE
    local PLUGIN_VERSION = constants.PLUGIN_VERSION

local function showResetConfirmation(plugin, touchmenu_instance, text, ok_text, reset_callback)
    UIManager:show(ConfirmBox:new({
        text = text,
        ok_text = ok_text,
        ok_callback = function()
            reset_callback(plugin)
            refreshMenu(touchmenu_instance)
        end,
    }))
end

function QuickDock:showResetActionsConfirmation(touchmenu_instance)
    showResetConfirmation(
        self,
        touchmenu_instance,
        _("Reset the Quick Dock actions and their order to the defaults?"),
        _("Reset"),
        self.resetActions
    )
end

function QuickDock:showResetBehaviorConfirmation(touchmenu_instance)
    showResetConfirmation(
        self,
        touchmenu_instance,
        _("Reset Quick Dock behavior to its defaults? Your actions and their order will be kept."),
        _("Reset"),
        self.resetBehavior
    )
end

function QuickDock:showResetBehaviorAndActionsConfirmation(touchmenu_instance)
    showResetConfirmation(
        self,
        touchmenu_instance,
        _("Reset Quick Dock behavior and actions to their defaults? Appearance settings will be kept."),
        _("Reset all"),
        self.resetBehaviorAndButtons
    )
end

function QuickDock:getActionsMenu()
    local menu = {}
    Dispatcher:addSubMenu(self, menu, self, "actions")
    return menu
end

function QuickDock:getActionVisibilityLabel(context)
    if context == ACTION_CONTEXT_AUTOMATIC then
        return _("Automatic")
    elseif context == ACTION_CONTEXT_READER then
        return _("Reader only")
    elseif context == ACTION_CONTEXT_BROWSER then
        return _("File browser and Bookshelf only")
    end
    return _("Everywhere")
end

function QuickDock:getActionVisibilitySummary(action_id)
    local mode = self:getActionVisibilityMode(action_id)
    if mode == ACTION_CONTEXT_AUTOMATIC then
        return T(_("Automatic (%1)"),
            self:getActionVisibilityLabel(self:getEffectiveActionVisibility(action_id)))
    end
    return self:getActionVisibilityLabel(mode)
end

function QuickDock:makeActionVisibilityOption(action_id, context)
    local option = makeRadioOption(
        self:getActionVisibilityLabel(context),
        nil,
        function()
            return self:getActionVisibilityMode(action_id) == context
        end,
        function()
            self:setActionVisibility(action_id, context)
        end
    )
    option.enabled_func = function()
        return context ~= ACTION_CONTEXT_AUTOMATIC or self:automaticVisibilityEnabled()
    end
    return option
end

function QuickDock:getActionVisibilityMenu()
    self.action_contexts = self:loadActionContexts()
    self.auto_visibility = self:loadAutomaticVisibility()
    local menu = {
        {
            text_func = function()
                return self:automaticVisibilityEnabled()
                    and _("Use automatic visibility for all actions")
                    or _("Show all actions everywhere")
            end,
            checked_func = function()
                return next(self.action_contexts) == nil
            end,
            callback = function(touchmenu_instance)
                self:resetActionVisibility()
                refreshMenu(touchmenu_instance)
            end,
            keep_menu_open = true,
            separator = true,
        },
    }

    local actions = self:getConfiguredActions()
    if #actions == 0 then
        menu[#menu + 1] = {
            text = _("No Quick Dock actions are configured."),
            enabled = false,
        }
        return menu
    end

    for _idx, item in ipairs(actions) do
        local action_id = item.key
        local action_text = tostring(item.text or action_id)
        menu[#menu + 1] = {
            text_func = function()
                return T(_("%1: %2"), action_text, self:getActionVisibilitySummary(action_id))
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

local function makeIconInfoItem(text, help_text, details)
    return {
        text = text,
        help_text = help_text,
        callback = function()
            UIManager:show(InfoMessage:new({ text = details }))
        end,
    }
end

function QuickDock:getIconFilenamesMenu()
    local menu = {
        makeIconInfoItem(
            _("Close button") .. ": close.svg",
            _("Icon shown in the separate button that closes the dock."),
            _("Close button") .. "\n\nSVG: close.svg\nPNG: close.png"
        ),
        makeIconInfoItem(
            _("Frontlight toggle") .. ": light_on.svg / light_off.svg",
            _("Uses a different icon for the active and inactive frontlight states."),
            _("Frontlight toggle")
                .. "\n\n" .. _("Frontlight on") .. ": light_on.svg / light_on.png"
                .. "\n" .. _("Frontlight off") .. ": light_off.svg / light_off.png"
        ),
        makeIconInfoItem(
            _("Warmth control") .. ": warmth.svg",
            _("Icon shown below the frontlight warmth slider."),
            _("Warmth control") .. "\n\nSVG: warmth.svg\nPNG: warmth.png"
        ),
        makeIconInfoItem(
            _("Information panel switch") .. ": reading_info.svg / stats.svg / network_info.svg",
            _("Uses a dedicated icon for the visible reading, book statistics, or network information panel."),
            _("Information panel switch")
                .. "\n\n" .. _("Reading information")
                .. ": reading_info.svg / reading_info.png"
                .. "\n" .. _("Book statistics")
                .. ": stats.svg / stats.png"
                .. "\n" .. _("Network information")
                .. ": network_info.svg / network_info.png"
        ),
    }
    menu[#menu].separator = true

    local actions = self:getConfiguredActions()
    table.insert(actions, 1, {
        key = ACTION_HOME,
        text = _("File browser / return to reader / open last document"),
    })
    for _idx, item in ipairs(actions) do
        local basename = tostring(item.key)
        local svg_name = basename .. ".svg"
        local help_text = _("Alternative PNG filename") .. ": " .. basename .. ".png"
        local details = tostring(item.text or basename)
            .. "\n\nSVG: " .. svg_name
            .. "\nPNG: " .. basename .. ".png"
        if item.key == "night_mode" then
            svg_name = "day_mode.svg / night_mode.svg"
            help_text = _("Uses a different icon for day and night modes.")
            details = tostring(item.text or basename)
                .. "\n\n" .. _("Day mode") .. ": day_mode.svg / day_mode.png"
                .. "\n" .. _("Night mode") .. ": night_mode.svg / night_mode.png"
        elseif item.key == "toggle_wifi" then
            svg_name = "wifi_on.svg / wifi_off.svg"
            help_text = _("Uses a different icon for the active and inactive Wi-Fi states.")
            details = tostring(item.text or basename)
                .. "\n\n" .. _("Wi-Fi on") .. ": wifi_on.svg / wifi_on.png"
                .. "\n" .. _("Wi-Fi off") .. ": wifi_off.svg / wifi_off.png"
        elseif item.key == ACTION_HOME then
            svg_name = "exit_reader.svg / last_doc.svg"
            help_text = _("Uses a different icon inside and outside the reader.")
            details = tostring(item.text or basename)
                .. "\n\n" .. _("While reading") .. ": exit_reader.svg / exit_reader.png"
                .. "\n" .. _("In the file browser") .. ": last_doc.svg / last_doc.png"
                .. "\n" .. _("In Bookshelf with a parked reader")
                .. ": last_doc.svg / last_doc.png"
        end
        menu[#menu + 1] = makeIconInfoItem(
            tostring(item.text or basename) .. ": " .. svg_name,
            help_text,
            details
        )
    end
    return menu
end

function QuickDock:getBehaviorMenu()
    local side_item = {
        text_func = function()
            local side = self:getSideMode() == SIDE_MODE_GESTURE
                and _("Follow gesture")
                or (self:getSide() == "left" and _("Left") or _("Right"))
            return T(_("Dock side: %1"), side)
        end,
        help_text = _("Choose a fixed side or place the dock on the side where its gesture started."),
        sub_item_table = {
            makeRadioOption(
                _("Left"), nil,
                function()
                    return self:getSideMode() == SIDE_MODE_FIXED and self:getSide() == "left"
                end,
                function()
                    self:setSide("left")
                    self:setSideMode(SIDE_MODE_FIXED)
                end
            ),
            makeRadioOption(
                _("Right"), nil,
                function()
                    return self:getSideMode() == SIDE_MODE_FIXED and self:getSide() == "right"
                end,
                function()
                    self:setSide("right")
                    self:setSideMode(SIDE_MODE_FIXED)
                end
            ),
            makeRadioOption(
                _("Follow gesture side"),
                _("Places the dock on the half of the screen where the gesture started. Uses the fixed side when no gesture position is available."),
                function()
                    return self:getSideMode() == SIDE_MODE_GESTURE
                end,
                function()
                    self:setSideMode(SIDE_MODE_GESTURE)
                end
            ),
        },
    }

    local closing_item = {
        text_func = function()
            local mode = self:closeDockTogether()
                and _("All blocks at once")
                or _("One block at a time")
            return T(_("Dock and panel closing: %1"), mode)
        end,
        help_text = _("Choose whether the dock and its panels disappear in the same repaint cycle or close separately."),
        sub_item_table = {
            makeRadioOption(
                _("One block at a time"),
                _("Closes each visible block separately, using the original sequential behavior."),
                function() return not self:closeDockTogether() end,
                function() self:setCloseDockTogether(false) end
            ),
            makeRadioOption(
                _("All blocks at once"),
                _("Closes all blocks with one non-flashing update over the smallest rectangle that contains them."),
                function() return self:closeDockTogether() end,
                function() self:setCloseDockTogether(true) end
            ),
        },
    }
    return { side_item, closing_item }
end

function QuickDock:getExtraButtonsMenu()
    return {
        makeToggleOption(
            _("Show reader/browser button"),
            _("Shows the first dock button: it opens the file browser while reading, returns from Bookshelf to the reader, or opens the last document from the file browser."),
            function() return self:showContextButton() end,
            function(enabled) self:setShowContextButton(enabled) end
        ),
        makeToggleOption(
            _("Show side-switch button"),
            _("Shows a separate chevron button above the dock for changing sides without opening the settings."),
            function() return self:showSideButton() end,
            function(enabled) self:setShowSideButton(enabled) end
        ),
        makeToggleOption(
            _("Show close button"),
            _("Shows a separate close button above the dock using close.svg."),
            function() return self:showCloseButton() end,
            function(enabled) self:setShowCloseButton(enabled) end
        ),
    }
end

function QuickDock:getActionSettingsMenu()
    return {
        {
            text_func = function()
                return T(_("Configured actions: %1"), #self:getConfiguredActions())
            end,
            help_text = _("Choose the actions shown in the dock and arrange their order."),
            sub_item_table_func = function()
                return self:getActionsMenu()
            end,
        },
        {
            text = _("Extra buttons"),
            help_text = _("Show or hide the reader/browser, side-switch, and close buttons around the dock. These are not configurable actions."),
            sub_item_table_func = function()
                return self:getExtraButtonsMenu()
            end,
        },
        {
            text = _("Action visibility"),
            help_text = _("Control which actions appear in the reader, file browser, and Bookshelf."),
            sub_item_table = {
                makeToggleOption(
                    _("Automatic visibility"),
                    _("Automatically shows native reader and file-browser actions only in their relevant context. Manual choices override the automatic result."),
                    function() return self:automaticVisibilityEnabled() end,
                    function(enabled) self:setAutomaticVisibility(enabled) end
                ),
                {
                    text = _("Per-action visibility"),
                    help_text = _("Review automatic results or override each action for all screens, the reader, or the file browser and Bookshelf."),
                    sub_item_table_func = function()
                        return self:getActionVisibilityMenu()
                    end,
                },
            },
        },
    }
end

function QuickDock:getDockLayoutMenu()
    local size_labels = {
        [DOCK_SIZE_SMALL] = _("Small"),
        [DOCK_SIZE_MEDIUM] = _("Medium"),
        [DOCK_SIZE_LARGE] = _("Large"),
    }
    local scale_item = {
        text_func = function()
            return T(_("Dock scale: %1"), size_labels[self:getDockSize()])
        end,
        help_text = _("Change the size of buttons, icons, pagination controls, and lighting columns."),
        sub_item_table = {
            makeRadioOption(
                _("Small"), _("Uses the base dock dimensions."),
                function() return self:getDockSize() == DOCK_SIZE_SMALL end,
                function() self:setDockSize(DOCK_SIZE_SMALL) end
            ),
            makeRadioOption(
                _("Medium"), _("Increases the dock dimensions by 20 percent."),
                function() return self:getDockSize() == DOCK_SIZE_MEDIUM end,
                function() self:setDockSize(DOCK_SIZE_MEDIUM) end
            ),
            makeRadioOption(
                _("Large"), _("Increases the dock dimensions by 40 percent."),
                function() return self:getDockSize() == DOCK_SIZE_LARGE end,
                function() self:setDockSize(DOCK_SIZE_LARGE) end
            ),
        },
    }
    local height_item = {
        text_func = function()
            return T(_("Maximum dock height: %1%"), self:getMaxActionDockHeight())
        end,
        help_text = _("Limits the action and lighting columns to the selected percentage of the screen and paginates buttons when necessary."),
        sub_item_table = {
            makeRadioOption(
                "100%", nil,
                function() return self:getMaxActionDockHeight() == MAX_ACTION_DOCK_HEIGHT_100 end,
                function() self:setMaxActionDockHeight(MAX_ACTION_DOCK_HEIGHT_100) end
            ),
            makeRadioOption(
                "60%", nil,
                function() return self:getMaxActionDockHeight() == MAX_ACTION_DOCK_HEIGHT_60 end,
                function() self:setMaxActionDockHeight(MAX_ACTION_DOCK_HEIGHT_60) end
            ),
            makeRadioOption(
                "33%", nil,
                function() return self:getMaxActionDockHeight() == MAX_ACTION_DOCK_HEIGHT_33 end,
                function() self:setMaxActionDockHeight(MAX_ACTION_DOCK_HEIGHT_33) end
            ),
        },
    }
    return { scale_item, height_item }
end

function QuickDock:getInformationPanelMenu()
    local alignment_labels = {
        [INFO_PANEL_TEXT_LEFT] = _("Left"),
        [INFO_PANEL_TEXT_CENTER] = _("Center"),
        [INFO_PANEL_TEXT_SCREEN_EDGE] = _("Nearest screen edge"),
    }
    return {
        makeToggleOption(
            _("Show reading information"),
            _("Shows book, chapter, daily reading, clock, and battery information on the screen edge opposite the dock."),
            function() return self:showReadingInfoPanel() end,
            function(enabled) self:setShowReadingInfoPanel(enabled) end
        ),
        makeToggleOption(
            _("Show book statistics"),
            _("Shows the open book's reading time, remaining time, progress, daily average, reading speed, start date, and estimated end date, as recorded by KOReader's Statistics plugin."),
            function() return self:showStatsInfoPanel() end,
            function(enabled) self:setShowStatsInfoPanel(enabled) end
        ),
        makeToggleOption(
            _("Show network information"),
            _("Shows Wi-Fi state and the network details reported by KOReader in the information panel."),
            function() return self:showNetworkInfoPanel() end,
            function(enabled) self:setShowNetworkInfoPanel(enabled) end
        ),
        makeToggleOption(
            _("Show book cover at the top"),
            _("Shows the open book's cover above the reading information and book statistics. The thumbnail is loaded once and reused while the document remains open."),
            function() return self:showInfoPanelCover() end,
            function(enabled) self:setShowInfoPanelCover(enabled) end,
            function() return self:showReadingInfoPanel() or self:showStatsInfoPanel() end
        ),
        {
            text_func = function()
                return T(_("Panel text alignment: %1"), alignment_labels[self:getInfoPanelTextAlignment()])
            end,
            help_text = _("Aligns every line in the selected information panel, including the clock and battery."),
            enabled_func = function() return self:showInfoPanel() end,
            sub_item_table = {
                makeRadioOption(
                    _("Left"), nil,
                    function() return self:getInfoPanelTextAlignment() == INFO_PANEL_TEXT_LEFT end,
                    function() self:setInfoPanelTextAlignment(INFO_PANEL_TEXT_LEFT) end
                ),
                makeRadioOption(
                    _("Center"), nil,
                    function() return self:getInfoPanelTextAlignment() == INFO_PANEL_TEXT_CENTER end,
                    function() self:setInfoPanelTextAlignment(INFO_PANEL_TEXT_CENTER) end
                ),
                makeRadioOption(
                    _("Nearest screen edge"),
                    _("Aligns left on the left edge and right on the right edge."),
                    function()
                        return self:getInfoPanelTextAlignment() == INFO_PANEL_TEXT_SCREEN_EDGE
                    end,
                    function() self:setInfoPanelTextAlignment(INFO_PANEL_TEXT_SCREEN_EDGE) end
                ),
            },
        },
    }
end

function QuickDock:getLightingControlsMenu()
    return {
        makeToggleOption(
            _("Show frontlight control"),
            _("Shows the brightness slider and its light toggle button beside the dock on devices with a frontlight."),
            function() return self:showFrontlightSlider() end,
            function(enabled) self:setShowFrontlightSlider(enabled) end,
            function() return Device:hasFrontlight() end
        ),
        makeToggleOption(
            _("Show warmth control"),
            _("Shows a second slider for frontlight warmth on supported devices."),
            function() return self:showWarmthSlider() end,
            function(enabled) self:setShowWarmthSlider(enabled) end,
            function() return Device:hasNaturalLight() end
        ),
    }
end

function QuickDock:getAppearanceMenu()
    return {
        {
            text = _("Dock layout"),
            help_text = _("Adjust the scale and maximum height of the dock."),
            sub_item_table_func = function() return self:getDockLayoutMenu() end,
        },
        {
            text = _("Information panel"),
            help_text = _("Choose the content and text alignment of the opposite-edge panel."),
            sub_item_table_func = function() return self:getInformationPanelMenu() end,
        },
        {
            text = _("Lighting controls"),
            help_text = _("Show or hide the frontlight brightness and warmth columns."),
            sub_item_table_func = function() return self:getLightingControlsMenu() end,
        },
        {
            text = _("Custom icon filenames"),
            help_text = _("Reference list of the SVG/PNG filenames Quick Dock looks for when you want to replace an icon."),
            sub_item_table_func = function() return self:getIconFilenamesMenu() end,
        },
    }
end

function QuickDock:getResetMenu()
    return {
        {
            text = _("Reset behavior to defaults"),
            help_text = _("Restores gesture-following placement, right-side fallback, and one-block-at-a-time closing without changing actions, extra buttons, or appearance."),
            callback = function(touchmenu_instance)
                self:showResetBehaviorConfirmation(touchmenu_instance)
            end,
        },
        {
            text = _("Reset actions to defaults"),
            help_text = _("Restores the initial actions and their order without changing other Quick Dock settings."),
            callback = function(touchmenu_instance)
                self:showResetActionsConfirmation(touchmenu_instance)
            end,
        },
        {
            text = _("Reset behavior and actions"),
            help_text = _("Restores behavior, extra buttons, default actions, order, and action visibility while keeping appearance settings."),
            callback = function(touchmenu_instance)
                self:showResetBehaviorAndActionsConfirmation(touchmenu_instance)
            end,
        },
    }
end

function QuickDock:addToMainMenu(menu_items)
    menu_items.quickdock = {
        text = _("Quick Dock"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Show Quick Dock"),
                callback = function() self:showDock(1) end,
                separator = true,
            },
            {
                text = _("Behavior"),
                help_text = _("Controls where the dock opens and how its visible blocks close."),
                sub_item_table_func = function() return self:getBehaviorMenu() end,
            },
            {
                text = _("Actions"),
                help_text = _("Configure actions, extra buttons, ordering, and contextual visibility."),
                sub_item_table_func = function() return self:getActionSettingsMenu() end,
            },
            {
                text = _("Appearance"),
                help_text = _("Controls dock layout, information panels, lighting columns, and custom icons."),
                sub_item_table_func = function() return self:getAppearanceMenu() end,
            },
            {
                text = _("Reset"),
                help_text = _("Restore default behavior, with or without resetting actions."),
                sub_item_table_func = function() return self:getResetMenu() end,
                separator = true,
            },
            {
                text = _("Gesture setup"),
                help_text = _("Assign 'Show Quick Dock' to any gesture in KOReader's gesture manager."),
                callback = function()
                    UIManager:show(InfoMessage:new({
                        text = _("Open Settings > Taps and gestures > Gesture manager, choose a gesture, then select Show Quick Dock."),
                    }))
                end,
            },
            {
                text = T(_("Version: %1"), PLUGIN_VERSION),
                callback = function()
                    UIManager:show(InfoMessage:new({
                        text = T(_("Quick Dock %1"), PLUGIN_VERSION),
                    }))
                end,
            },
        },
    }
end

end
