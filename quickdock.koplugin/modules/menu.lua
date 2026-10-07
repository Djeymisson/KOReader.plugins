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

-- Radio options for the values of a setting, in list order: each entry
-- gives the value, its label and, optionally, its help text.
local function makeRadioOptions(entries, get_value, set_value)
    local options = {}
    for index, entry in ipairs(entries) do
        local value = entry[1]
        options[index] = makeRadioOption(
            entry[2], entry[3],
            function() return get_value() == value end,
            function() set_value(value) end
        )
    end
    return options
end

return function(QuickDock, C, lib)
    local Prefs = lib.Prefs
    local ACTION_CONTEXT_ALL = C.ACTION_CONTEXT_ALL
    local ACTION_CONTEXT_AUTOMATIC = C.ACTION_CONTEXT_AUTOMATIC
    local ACTION_CONTEXT_READER = C.ACTION_CONTEXT_READER
    local ACTION_CONTEXT_BROWSER = C.ACTION_CONTEXT_BROWSER
    local ACTION_HOME = C.ACTION_HOME
    local DOCK_SHAPE_COLUMN = C.DOCK_SHAPE_COLUMN
    local DOCK_SHAPE_ARC = C.DOCK_SHAPE_ARC
    local ARC_ANGLES = C.ARC_ANGLES
    local DEFAULT_ARC_ANGLE = C.DEFAULT_ARC_ANGLE
    local ARC_EMPTY_SPACE_END = C.ARC_EMPTY_SPACE_END
    local ARC_EMPTY_SPACE_START = C.ARC_EMPTY_SPACE_START
    local SIDE_MODE_FIXED = C.SIDE_MODE_FIXED
    local SIDE_MODE_GESTURE = C.SIDE_MODE_GESTURE
    local DOCK_SIZE_SMALL = C.DOCK_SIZE_SMALL
    local DOCK_SIZE_MEDIUM = C.DOCK_SIZE_MEDIUM
    local DOCK_SIZE_LARGE = C.DOCK_SIZE_LARGE
    local INFO_PANEL_TEXT_LEFT = C.INFO_PANEL_TEXT_LEFT
    local INFO_PANEL_TEXT_CENTER = C.INFO_PANEL_TEXT_CENTER
    local INFO_PANEL_TEXT_SCREEN_EDGE = C.INFO_PANEL_TEXT_SCREEN_EDGE
    local INFO_PANEL_MODES = C.INFO_PANEL_MODES
    local PLUGIN_VERSION = C.PLUGIN_VERSION

    function QuickDock:resetBehavior()
        Prefs.setSide("right")
        Prefs.setSideMode(SIDE_MODE_GESTURE)
        Prefs.setCloseDockTogether(false)
        self.current_page = 1
        self.current_dock_side = nil
    end

    function QuickDock:resetBehaviorAndButtons()
        self:resetBehavior()
        Prefs.setShowContextButton(true)
        Prefs.setShowSideButton(true)
        Prefs.setShowCloseButton(false)
        Prefs.setAutomaticVisibility(false)
        self:resetActionVisibility()
        self:resetActions()
    end

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
        self:reloadSharedSettings()
        local menu = {}
        Dispatcher:addSubMenu(self, menu, self, "actions")
        -- Quick Dock runs each action from its own button, so Dispatcher's
        -- execution modes and QuickMenu options after “Arrange actions” do not
        -- apply. Keep “Nothing”, the action sections and the arrange entry, all
        -- on the first page with a separator before “Arrange actions”.
        local arrange_index = (menu.max_per_page or 0) + 1
        local arrange_item = menu[arrange_index]
        if arrange_item and arrange_item.text_func and arrange_item.callback then
            for index = #menu, arrange_index + 1, -1 do
                table.remove(menu, index)
            end
            arrange_item.separator = nil
            menu[arrange_index - 1].separator = true
            menu.max_per_page = nil
        end
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
            return context ~= ACTION_CONTEXT_AUTOMATIC or Prefs.automaticVisibilityEnabled()
        end
        return option
    end

    function QuickDock:getActionVisibilityMenu()
        self:reloadSharedSettings()
        local menu = {
            {
                text_func = function()
                    return Prefs.automaticVisibilityEnabled()
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

    function QuickDock:getInfoPanelSwitchIconItem()
        local files = {}
        local lines = {}
        for _index, mode in ipairs(INFO_PANEL_MODES) do
            files[#files + 1] = mode.icon_files:match("^(%S+)")
            lines[#lines + 1] = mode.title .. ": " .. mode.icon_files
        end
        return makeIconInfoItem(
            _("Information panel switch") .. ": " .. table.concat(files, " / "),
            _("Uses a dedicated icon for each information panel mode, showing which one is visible."),
            _("Information panel switch") .. "\n\n" .. table.concat(lines, "\n")
        )
    end

    function QuickDock:getIconFilenamesMenu()
        self:reloadSharedSettings()
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
                _("Icon of the warmth control: below its slider in the column dock, or on its button inside the arc."),
                _("Warmth control") .. "\n\nSVG: warmth.svg\nPNG: warmth.png"
            ),
            self:getInfoPanelSwitchIconItem(),
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
                local side = Prefs.getSideMode() == SIDE_MODE_GESTURE
                    and _("Follow gesture")
                    or (Prefs.getSide() == "left" and _("Left") or _("Right"))
                return T(_("Dock side: %1"), side)
            end,
            help_text = _("Choose a fixed side or place the dock on the side where its gesture started."),
            sub_item_table = {
                makeRadioOption(
                    _("Left"), nil,
                    function()
                        return Prefs.getSideMode() == SIDE_MODE_FIXED and Prefs.getSide() == "left"
                    end,
                    function()
                        Prefs.setSide("left")
                        Prefs.setSideMode(SIDE_MODE_FIXED)
                    end
                ),
                makeRadioOption(
                    _("Right"), nil,
                    function()
                        return Prefs.getSideMode() == SIDE_MODE_FIXED and Prefs.getSide() == "right"
                    end,
                    function()
                        Prefs.setSide("right")
                        Prefs.setSideMode(SIDE_MODE_FIXED)
                    end
                ),
                makeRadioOption(
                    _("Follow gesture side"),
                    _("Places the dock on the half of the screen where the gesture started. Uses the fixed side when no gesture position is available."),
                    function()
                        return Prefs.getSideMode() == SIDE_MODE_GESTURE
                    end,
                    function()
                        Prefs.setSideMode(SIDE_MODE_GESTURE)
                    end
                ),
            },
        }

        local closing_item = {
            text_func = function()
                local mode = Prefs.closeDockTogether()
                    and _("All blocks at once")
                    or _("One block at a time")
                return T(_("Dock and panel closing: %1"), mode)
            end,
            help_text = _("Choose whether the dock and its panels disappear in the same repaint cycle or close separately."),
            sub_item_table = {
                makeRadioOption(
                    _("One block at a time"),
                    _("Closes each visible block separately, using the original sequential behavior."),
                    function() return not Prefs.closeDockTogether() end,
                    function() Prefs.setCloseDockTogether(false) end
                ),
                makeRadioOption(
                    _("All blocks at once"),
                    _("Closes all blocks with one non-flashing update over the smallest rectangle that contains them."),
                    function() return Prefs.closeDockTogether() end,
                    function() Prefs.setCloseDockTogether(true) end
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
                function() return Prefs.showContextButton() end,
                function(enabled) Prefs.setShowContextButton(enabled) end
            ),
            makeToggleOption(
                _("Show side-switch button"),
                _("Shows a button that moves the dock to the other side without opening the settings: above the column dock, or inside the arc next to its start."),
                function() return Prefs.showSideButton() end,
                function(enabled) Prefs.setShowSideButton(enabled) end
            ),
            makeToggleOption(
                _("Show close button"),
                _("Shows a button that closes the dock, using close.svg: above the column dock, or inside the arc."),
                function() return Prefs.showCloseButton() end,
                function(enabled) Prefs.setShowCloseButton(enabled) end
            ),
        }
    end

    function QuickDock:getActionSettingsMenu()
        self:reloadSharedSettings()
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
                        function() return Prefs.automaticVisibilityEnabled() end,
                        function(enabled) Prefs.setAutomaticVisibility(enabled) end
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
        local shape_item = {
            text_func = function()
                local shape = Prefs.getDockShape() == DOCK_SHAPE_ARC and _("Arc") or _("Column")
                return T(_("Dock shape: %1"), shape)
            end,
            help_text = _("Choose a column beside the screen edge or a quarter ring around the lower corner for one-handed use."),
            sub_item_table = {
                makeRadioOption(
                    _("Column"),
                    _("Stacks the buttons in a column, with the lighting sliders beside it and the information panel on the opposite edge."),
                    function() return Prefs.getDockShape() == DOCK_SHAPE_COLUMN end,
                    function() Prefs.setDockShape(DOCK_SHAPE_COLUMN) end
                ),
                makeRadioOption(
                    _("Arc"),
                    _("Places the actions in a single row on a quarter ring around the lower corner, within reach of the thumb, with the other buttons floating inside it. Tapping the brightness or warmth button shows its slider in place of the actions; pages turn by swiping along the ring or with its arrows. The information panel moves to the top of the screen."),
                    function() return Prefs.getDockShape() == DOCK_SHAPE_ARC end,
                    function() Prefs.setDockShape(DOCK_SHAPE_ARC) end
                ),
            },
        }
        local sizes = {
            { DOCK_SIZE_SMALL, _("Small"), _("Uses the base dock dimensions.") },
            { DOCK_SIZE_MEDIUM, _("Medium"), _("Increases the dock dimensions by 20 percent.") },
            { DOCK_SIZE_LARGE, _("Large"), _("Increases the dock dimensions by 40 percent.") },
        }
        local size_labels = {}
        for _index, size in ipairs(sizes) do
            size_labels[size[1]] = size[2]
        end
        local scale_item = {
            text_func = function()
                return T(_("Dock scale: %1"), size_labels[Prefs.getDockSize()])
            end,
            help_text = _("Sets the size of the buttons, icons, and lighting controls. With the arc's Fill the arc option enabled, its buttons may grow beyond this size."),
            sub_item_table = makeRadioOptions(
                sizes,
                function() return Prefs.getDockSize() end,
                function(size) Prefs.setDockSize(size) end
            ),
        }
        local heights = {}
        for _index, height in ipairs({ C.MAX_ACTION_DOCK_HEIGHT_100, C.MAX_ACTION_DOCK_HEIGHT_60, C.MAX_ACTION_DOCK_HEIGHT_33 }) do
            heights[#heights + 1] = { height, height .. "%" }
        end
        local height_item = {
            text_func = function()
                return T(_("Maximum dock height: %1%"), Prefs.getMaxActionDockHeight())
            end,
            help_text = _("Limits the dock's height (the column with its lighting sliders, or the arc) to the selected percentage of the screen, and paginates the actions when they do not fit."),
            sub_item_table = makeRadioOptions(
                heights,
                function() return Prefs.getMaxActionDockHeight() end,
                function(height) Prefs.setMaxActionDockHeight(height) end
            ),
        }
        local arc_item = {
            text = _("Arc options"),
            help_text = _("The arc's angle, its background band, and how its buttons use its length. Available with the Arc shape."),
            enabled_func = function() return Prefs.getDockShape() == DOCK_SHAPE_ARC end,
            sub_item_table_func = function() return self:getArcOptionsMenu() end,
        }
        return { shape_item, scale_item, height_item, arc_item }
    end

    function QuickDock:getArcOptionsMenu()
        local angles = {}
        for _index, angle in ipairs(ARC_ANGLES) do
            local label = T(_("%1°"), angle)
            if angle == DEFAULT_ARC_ANGLE then
                label = T(_("%1° (quarter circle)"), angle)
            elseif angle == ARC_ANGLES[1] then
                label = T(_("%1° (widest and lowest)"), angle)
            elseif angle == ARC_ANGLES[#ARC_ANGLES] then
                label = T(_("%1° (tallest and narrowest)"), angle)
            end
            angles[#angles + 1] = { angle, label }
        end
        local angle_options = makeRadioOptions(
            angles,
            function() return Prefs.getArcAngle() end,
            function(angle) Prefs.setArcAngle(angle) end
        )
        local angle_item = {
            text_func = function()
                return T(_("Arc angle: %1°"), Prefs.getArcAngle())
            end,
            help_text = _("Tilts the arc: the angle between the bottom edge and the line joining its two ends. Higher angles bring the bottom end closer to the side and make the arc taller; lower angles spread it along the bottom and make it lower. The arc keeps about the same size."),
            sub_item_table = angle_options,
        }
        local band_item = makeToggleOption(
            _("Show band behind buttons"),
            _("Draws the arc's buttons on a white band. Without it, each button floats on the page with its own outline."),
            function() return Prefs.showArcBand() end,
            function(enabled) Prefs.setShowArcBand(enabled) end
        )
        local fill_item = makeToggleOption(
            _("Fill the arc when there are few actions"),
            _("Spreads each page's buttons along the whole arc and, when every action fits on one page, enlarges them up to 1.5 times to close the gaps. Button size then varies with the number of actions, and Dock scale only sets the smallest size. When disabled, the buttons keep the Dock scale size and the spacing of a full page, and the unused part of the arc stays empty."),
            function() return Prefs.fillArc() end,
            function(enabled) Prefs.setFillArc(enabled) end
        )
        fill_item.separator = true
        local empty_labels = {
            [ARC_EMPTY_SPACE_END] = _("At the end, near the side edge"),
            [ARC_EMPTY_SPACE_START] = _("At the start, near the bottom edge"),
        }
        local empty_item = {
            text_func = function()
                return T(_("Empty space: %1"), empty_labels[Prefs.getArcEmptySpace()])
            end,
            help_text = _("Where the unused part of the arc stays when a page has fewer buttons than the arc holds. Available when Fill the arc is disabled."),
            enabled_func = function() return not Prefs.fillArc() end,
            sub_item_table = makeRadioOptions(
                {
                    {
                        ARC_EMPTY_SPACE_END,
                        empty_labels[ARC_EMPTY_SPACE_END],
                        _("The buttons, including the floating ones inside the arc, start at its bottom end."),
                    },
                    {
                        ARC_EMPTY_SPACE_START,
                        empty_labels[ARC_EMPTY_SPACE_START],
                        _("The buttons end at the side end of the arc, and the floating ones inside it start there too."),
                    },
                },
                function() return Prefs.getArcEmptySpace() end,
                function(position) Prefs.setArcEmptySpace(position) end
            ),
        }
        return { angle_item, band_item, fill_item, empty_item }
    end

    -- Options of each information panel mode, listed below its visibility
    -- toggle in the mode's submenu. Modes without an entry only have the toggle.
    local INFO_PANEL_MODE_OPTIONS = {}

    function INFO_PANEL_MODE_OPTIONS.reading(self)
        return { self:getInfoPanelCoverItem("reading") }
    end

    function INFO_PANEL_MODE_OPTIONS.stats(self)
        return { self:getInfoPanelCoverItem("stats") }
    end

    function INFO_PANEL_MODE_OPTIONS.recent()
        local counts = {}
        for _index, count in ipairs(C.RECENT_DOCUMENTS_COUNTS) do
            counts[#counts + 1] = { count, tostring(count) }
        end
        local options = makeRadioOptions(
            counts,
            function() return Prefs.getRecentDocumentsCount() end,
            function(count) Prefs.setRecentDocumentsCount(count) end
        )
        return {
            {
                text_func = function()
                    return T(_("Documents to show: %1"), Prefs.getRecentDocumentsCount())
                end,
                help_text = _("The maximum number of recent documents in the recent documents panel. The document open in the reader is not listed. Documents that do not fit the panel are split into pages."),
                enabled_func = function() return Prefs.isInfoPanelKindEnabled("recent") end,
                sub_item_table = options,
            },
        }
    end

    -- The cover setting is shared by the reading and statistics panels, so it
    -- appears in both submenus.
    function QuickDock:getInfoPanelCoverItem(kind)
        return makeToggleOption(
            _("Show book cover"),
            _("Shows the open book's cover in the reading information and book statistics: above the text beside the column dock, or to its left in the arc dock's top panel. The thumbnail is loaded once and reused while the document remains open. This option applies to both panels."),
            function() return Prefs.showInfoPanelCover() end,
            function(enabled) self:setShowInfoPanelCover(enabled) end,
            function() return Prefs.isInfoPanelKindEnabled(kind) end
        )
    end

    -- One entry per mode: its check mark tells whether the mode is shown, and
    -- tapping it opens the visibility toggle and the mode's own options.
    function QuickDock:getInfoPanelModeItem(mode)
        local kind = mode.kind
        return {
            text = mode.title,
            help_text = mode.help,
            checked_func = function() return Prefs.isInfoPanelKindEnabled(kind) end,
            sub_item_table_func = function()
                local items = {
                    makeToggleOption(
                        _("Show this panel"),
                        mode.help,
                        function() return Prefs.isInfoPanelKindEnabled(kind) end,
                        function(enabled) self:setInfoPanelKindEnabled(kind, enabled) end
                    ),
                }
                local options = INFO_PANEL_MODE_OPTIONS[kind]
                if options then
                    items[1].separator = true
                    for _index, item in ipairs(options(self)) do
                        items[#items + 1] = item
                    end
                end
                return items
            end,
        }
    end

    function QuickDock:getInformationPanelMenu()
        local alignment_labels = {
            [INFO_PANEL_TEXT_LEFT] = _("Left"),
            [INFO_PANEL_TEXT_CENTER] = _("Center"),
            [INFO_PANEL_TEXT_SCREEN_EDGE] = _("Nearest screen edge"),
        }
        local menu = {}
        for _index, mode in ipairs(INFO_PANEL_MODES) do
            menu[#menu + 1] = self:getInfoPanelModeItem(mode)
        end
        menu[#menu].separator = true
        menu[#menu + 1] = {
            text_func = function()
                return T(_("Panel text alignment: %1"), alignment_labels[Prefs.getInfoPanelTextAlignment()])
            end,
            help_text = _("Aligns every line in the selected information panel, including the clock and battery."),
            enabled_func = function() return Prefs.showInfoPanel() end,
            sub_item_table = makeRadioOptions(
                {
                    { INFO_PANEL_TEXT_LEFT, alignment_labels[INFO_PANEL_TEXT_LEFT] },
                    { INFO_PANEL_TEXT_CENTER, alignment_labels[INFO_PANEL_TEXT_CENTER] },
                    {
                        INFO_PANEL_TEXT_SCREEN_EDGE,
                        alignment_labels[INFO_PANEL_TEXT_SCREEN_EDGE],
                        _("Aligns left on the left edge and right on the right edge. The arc dock's top panel aligns left."),
                    },
                },
                function() return Prefs.getInfoPanelTextAlignment() end,
                function(alignment) Prefs.setInfoPanelTextAlignment(alignment) end
            ),
        }
        return menu
    end

    function QuickDock:getLightingControlsMenu()
        return {
            makeToggleOption(
                _("Show frontlight control"),
                _("On devices with a frontlight, shows the brightness slider and light toggle: a column beside the column dock, or a button inside the arc that shows the slider along it."),
                function() return Prefs.showFrontlightSlider() end,
                function(enabled) Prefs.setShowFrontlightSlider(enabled) end,
                function() return Device:hasFrontlight() end
            ),
            makeToggleOption(
                _("Show warmth control"),
                _("On supported devices, shows the frontlight warmth slider: a second column beside the column dock, or a second button inside the arc."),
                function() return Prefs.showWarmthSlider() end,
                function(enabled) Prefs.setShowWarmthSlider(enabled) end,
                function() return Device:hasNaturalLight() end
            ),
        }
    end

    function QuickDock:getAppearanceMenu()
        return {
            {
                text = _("Dock layout"),
                help_text = _("Choose the dock shape, its scale and maximum height, and the arc's options."),
                sub_item_table_func = function() return self:getDockLayoutMenu() end,
            },
            {
                text = _("Information panel"),
                help_text = _("Choose the content and text alignment of the information panel: on the edge opposite the column dock, or along the top of the screen with the arc dock."),
                sub_item_table_func = function() return self:getInformationPanelMenu() end,
            },
            {
                text = _("Lighting controls"),
                help_text = _("Show or hide the frontlight brightness and warmth controls."),
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
                    help_text = _("Controls dock layout, information panels, lighting controls, and custom icons."),
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
