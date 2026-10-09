-- The settings menu in Top menu > Settings > Selection toolbar, and the dialog to arrange
-- the actions and their groups.

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Device = require("device")
local T = require("ffi/util").template
local _ = require("selectiontoolbar_l10n")

local C, lib = ...
local findChoice = lib.findChoice

local SelectionToolbar = {}

-- Where the group separators are in an action order, to tell whether they were moved.
local function separatorPositions(order)
    local positions = {}
    for i, id in ipairs(order) do
        if id == C.GROUP_SEPARATOR then
            positions[#positions + 1] = i
        end
    end
    return table.concat(positions, ",")
end

-- Reorders the actions and group separators. Hidden actions are listed dimmed, so they
-- keep their place for when they are shown again.
function SelectionToolbar:showArrangeActions()
    local separator_text = "—— " .. _("Group separator") .. " ——"
    local items = {}
    for _, id in ipairs(self:getActionOrder()) do
        if id == C.GROUP_SEPARATOR then
            items[#items + 1] = { text = separator_text, id = id }
        else
            items[#items + 1] = { text = C.ACTIONS_BY_ID[id].text, id = id, dim = not self:isActionEnabled(id) }
        end
    end
    local SortWidget = require("ui/widget/sortwidget")
    UIManager:show(SortWidget:new({
        title = _("Arrange actions"),
        item_table = items,
        callback = function()
            local order = {}
            for i, item in ipairs(items) do
                order[i] = item.id
            end
            local groups_moved = separatorPositions(order) ~= separatorPositions(self:getActionOrder())
            self:setActionOrder(order)
            self:refreshPreview()
            -- The groups only show as lines with one separators choice, set in another menu.
            if groups_moved and self:getSeparators() ~= C.SEPARATORS_GROUPS then
                UIManager:show(InfoMessage:new({
                    text = _("Groups are shown as lines with Toolbar appearance > Separators set to Between groups."),
                    timeout = 4,
                }))
            end
        end,
    }))
end

-- Radio items for a multiple-choice setting. get and set are methods of the plugin.
-- Other items may depend on the choice, so the menu is updated after each change.
function SelectionToolbar:choiceMenuItems(choices, get, set)
    local items = {}
    for _, choice in ipairs(choices) do
        items[#items + 1] = {
            text = choice.text,
            help_text = choice.help_text,
            radio = true,
            checked_func = function()
                return get(self) == choice.id
            end,
            callback = function(touchmenu_instance)
                set(self, choice.id)
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
                self:refreshPreview()
            end,
            keep_menu_open = true,
        }
    end
    return items
end

-- "Label: chosen value", for the item opening the choices of a multiple-choice setting.
function SelectionToolbar:choiceMenuText(label, choices, get)
    return function()
        local choice = findChoice(choices, get(self))
        return T(_("%1: %2"), label, choice and choice.text or _("Custom"))
    end
end

function SelectionToolbar:addToMainMenu(menu_items)
    local function updateMenu(touchmenu_instance)
        if touchmenu_instance and touchmenu_instance.updateItems then
            touchmenu_instance:updateItems()
        end
        self:refreshPreview()
    end

    local function isEnabled()
        return self:isEnabled()
    end

    local main_action_items = self:choiceMenuItems(C.MAIN_ACTION_COUNTS, self.getMainActions, self.setMainActions)

    -- The actions first, as they are what this page is mostly opened for; the resets last.
    local action_items = {}
    for _, action in ipairs(C.ACTIONS) do
        table.insert(action_items, {
            text = action.text,
            checked_func = function()
                return self:isActionEnabled(action.id)
            end,
            callback = function(touchmenu_instance)
                self:setActionEnabled(action.id, not self:isActionEnabled(action.id))
                updateMenu(touchmenu_instance)
            end,
            keep_menu_open = true,
        })
    end
    action_items[#action_items].separator = true
    table.insert(action_items, {
        text = _("Arrange actions and groups"),
        -- Says whether the groups show now, as that is chosen in the Toolbar menu.
        help_text_func = function()
            local help_text = _(
                "Change the order of the actions and move the group separators between them. A separator moved to the start or the end of the list is not used."
            )
            if self:getSeparators() == C.SEPARATORS_GROUPS then
                return help_text .. "\n\n" .. _("Groups are shown as lines: Toolbar appearance > Separators is set to Between groups.")
            end
            return help_text .. "\n\n" .. _("Groups are not shown now: set Toolbar appearance > Separators to Between groups to show them as lines.")
        end,
        keep_menu_open = true,
        callback = function()
            self:showArrangeActions()
        end,
    })
    table.insert(action_items, {
        text_func = self:choiceMenuText(_("Shorten the toolbar"), C.MAIN_ACTION_COUNTS, self.getMainActions),
        help_text = _(
            "Show only the first actions of the order, and a More button (…) that shows the others in a second row. Useful with many actions enabled, so the toolbar covers less of the text."
        ),
        sub_item_table = main_action_items,
        separator = true,
    })
    table.insert(action_items, {
        text = _("Show all actions"),
        help_text = _("Re-enables every selection toolbar action at once."),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:resetActions()
            updateMenu(touchmenu_instance)
            UIManager:show(InfoMessage:new({ text = _("All selection toolbar actions are enabled."), timeout = 2 }))
        end,
    })
    table.insert(action_items, {
        text = _("Restore default order"),
        help_text = _("Annotation, lookup and tools groups, in the plugin's original order."),
        keep_menu_open = true,
        callback = function()
            self:resetActionOrder()
            self:refreshPreview()
            UIManager:show(InfoMessage:new({ text = _("The default order of the actions is restored."), timeout = 2 }))
        end,
    })

    local handle_style_items = self:choiceMenuItems(C.HANDLE_STYLES, self.getHandleStyle, function(_, style)
        self:setHandleStyle(style, self:handleOutline())
    end)
    handle_style_items[#handle_style_items].separator = true
    table.insert(handle_style_items, {
        text = _("High-contrast outline"),
        help_text = _(
            "Black outline over white, readable over dark or highlighted text. Not for brackets."
        ),
        enabled_func = function()
            return self:canOutlineHandles()
        end,
        checked_func = function()
            return self:canOutlineHandles() and self:handleOutline()
        end,
        callback = function()
            self:setHandleStyle(self:getHandleStyle(), not self:handleOutline())
            self:refreshPreview()
        end,
        keep_menu_open = true,
    })

    local position_items = self:choiceMenuItems(C.POSITIONS, self.getToolbarPosition, self.setToolbarPosition)
    local density_items = self:choiceMenuItems(C.DENSITIES, self.getDensity, self.setDensity)
    local icon_size_items = self:choiceMenuItems(C.ICON_SIZES, self.getIconSize, self.setIconSize)
    local shape_items = self:choiceMenuItems(C.SHAPES, self.getShape, self.setShape)
    local border_items = self:choiceMenuItems(C.BORDERS, self.getBorder, self.setBorder)
    local separator_items = self:choiceMenuItems(C.SEPARATOR_STYLES, self.getSeparators, self.setSeparators)
    local shadow_items = self:choiceMenuItems(C.SHADOW_STYLES, self.getShadowStyle, self.setShadowStyle)
    local preset_items = self:choiceMenuItems(C.STYLE_PRESETS, self.getStylePreset, self.applyStylePreset)
    preset_items[#preset_items].separator = true
    table.insert(preset_items, {
        text = _("Custom"),
        help_text = _("Your own combination: shown when the current look matches none of the styles above."),
        radio = true,
        enabled_func = function()
            return false
        end,
        checked_func = function()
            return self:getStylePreset() == nil
        end,
    })
    local handle_size_items = self:choiceMenuItems(C.HANDLE_SIZES, self.getHandleSize, self.setHandleSize)
    local marker_width_items = self:choiceMenuItems(C.LINE_MARKER_WIDTHS, self.getLineMarkerWidth, self.setLineMarkerWidth)
    local marker_gap_items = self:choiceMenuItems(C.LINE_MARKER_GAPS, self.getLineMarkerGap, self.setLineMarkerGap)

    local function showHandles()
        return self:showHandles()
    end
    local function showLineMarker()
        return self:showLineMarker()
    end

    local marks_items = {
        {
            text = _("Show selection handles"),
            help_text = _("Drag the selection handles to adjust it, or into a page corner to continue."),
            enabled_func = function()
                return Device:isTouchDevice()
            end,
            checked_func = showHandles,
            callback = function(touchmenu_instance)
                self:toggleSetting(C.SETTING_HANDLES, true)
                updateMenu(touchmenu_instance)
            end,
            keep_menu_open = true,
        },
        {
            text_func = self:choiceMenuText(_("Handle style"), C.HANDLE_STYLES, self.getHandleStyle),
            help_text = _("Choose how the selection handles are drawn."),
            enabled_func = showHandles,
            sub_item_table = handle_style_items,
        },
        {
            text_func = self:choiceMenuText(_("Handle size"), C.HANDLE_SIZES, self.getHandleSize),
            help_text = _("Choose how large the handles are drawn. Their touch area stays the same."),
            enabled_func = showHandles,
            sub_item_table = handle_size_items,
            separator = true,
        },
        {
            text = _("Show line marker"),
            help_text = _("Show a vertical line in the page margin beside the selected lines."),
            checked_func = showLineMarker,
            callback = function(touchmenu_instance)
                self:toggleSetting(C.SETTING_LINE_MARKER, true)
                updateMenu(touchmenu_instance)
            end,
            keep_menu_open = true,
        },
        {
            text = _("Line marker in right margin"),
            help_text = _("Draw the line marker in the right margin. Mirrored for right-to-left languages."),
            enabled_func = showLineMarker,
            checked_func = function()
                return self:lineMarkerOnRight()
            end,
            callback = function()
                self:toggleSetting(C.SETTING_LINE_MARKER_RIGHT, false)
                self:refreshPreview()
            end,
            keep_menu_open = true,
        },
        {
            text_func = self:choiceMenuText(_("Line marker thickness"), C.LINE_MARKER_WIDTHS, self.getLineMarkerWidth),
            help_text = _("Choose how thick the line marker is."),
            enabled_func = showLineMarker,
            sub_item_table = marker_width_items,
        },
        {
            text_func = self:choiceMenuText(_("Line marker distance"), C.LINE_MARKER_GAPS, self.getLineMarkerGap),
            help_text = _(
                "Choose how far from the text the line marker is drawn. It stays in the page margin, closer to the text when the margin is narrow."
            ),
            enabled_func = showLineMarker,
            sub_item_table = marker_gap_items,
        },
    }

    -- Where the toolbar shows, then its size, then its frame: the last two are what the
    -- style presets change.
    local toolbar_items = {
        {
            text_func = self:choiceMenuText(_("Position"), C.POSITIONS, self.getToolbarPosition),
            help_text = _("Choose where the toolbar is shown on screen."),
            sub_item_table = position_items,
            separator = true,
        },
        {
            text_func = self:choiceMenuText(_("Button density"), C.DENSITIES, self.getDensity),
            help_text = _("Choose the size and spacing of the toolbar buttons."),
            sub_item_table = density_items,
        },
        {
            text_func = self:choiceMenuText(_("Icon size"), C.ICON_SIZES, self.getIconSize),
            help_text = _("Choose the size of the icons, independently of the button size."),
            sub_item_table = icon_size_items,
            separator = true,
        },
        {
            text_func = self:choiceMenuText(_("Shape"), C.SHAPES, self.getShape),
            help_text = _("Choose how rounded the toolbar corners are."),
            sub_item_table = shape_items,
        },
        {
            text_func = self:choiceMenuText(_("Border"), C.BORDERS, self.getBorder),
            help_text = _("Choose how strong the toolbar outline is."),
            sub_item_table = border_items,
        },
        {
            text_func = self:choiceMenuText(_("Shadow"), C.SHADOW_STYLES, self.getShadowStyle),
            help_text = _("Choose the shadow along the right and bottom edges of the toolbar."),
            sub_item_table = shadow_items,
        },
        {
            text_func = self:choiceMenuText(_("Separators"), C.SEPARATOR_STYLES, self.getSeparators),
            help_text = _("Choose whether lines are drawn between the buttons."),
            sub_item_table = separator_items,
        },
    }

    local toolbar_pages = {
        toolbar_items,
        position_items,
        density_items,
        icon_size_items,
        shape_items,
        border_items,
        separator_items,
        shadow_items,
        action_items,
        main_action_items,
    }
    for _, page in ipairs(toolbar_pages) do
        self:trackPreviewPage(page, C.PREVIEW_TOOLBAR)
    end
    for _, page in ipairs({ marks_items, handle_style_items, handle_size_items, marker_width_items, marker_gap_items }) do
        self:trackPreviewPage(page, C.PREVIEW_MARKS)
    end
    self:trackPreviewPage(preset_items, C.PREVIEW_FULL)

    menu_items.selectiontoolbar = {
        text = _("Selection toolbar"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Use compact selection toolbar"),
                help_text = _("Replaces KOReader's default centered selection menu with a compact icon toolbar near the selection."),
                checked_func = isEnabled,
                callback = function(touchmenu_instance)
                    self:setEnabled(not self:isEnabled())
                    if touchmenu_instance and touchmenu_instance.updateItems then
                        touchmenu_instance:updateItems()
                    end
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text_func = self:choiceMenuText(_("Style preset"), C.STYLE_PRESETS, self.getStylePreset),
                help_text = _(
                    "Ready-made looks for the toolbar, the handles and the line marker. You can still adjust each setting afterwards."
                ),
                enabled_func = isEnabled,
                sub_item_table_func = function()
                    self:schedulePreview()
                    return preset_items
                end,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Actions: %1 of %2"), self:countEnabledActions(), #C.ACTIONS)
                end,
                help_text = _("Choose which actions appear in the toolbar, their order, and whether the toolbar is shortened."),
                enabled_func = isEnabled,
                sub_item_table_func = function()
                    self:schedulePreview()
                    return action_items
                end,
            },
            {
                text = _("Toolbar appearance"),
                help_text = _("Choose where the toolbar is shown, its size, shape, border, shadow and separators."),
                enabled_func = isEnabled,
                sub_item_table_func = function()
                    self:schedulePreview()
                    return toolbar_items
                end,
            },
            {
                text = _("Handles and line marker"),
                help_text = _("Handles to adjust the selection and a margin line beside the selected lines."),
                enabled_func = isEnabled,
                sub_item_table_func = function()
                    self:schedulePreview()
                    return marks_items
                end,
                separator = true,
            },
            {
                text = _("Restore all defaults"),
                help_text = _(
                    "Restores every selection toolbar setting, the visible actions and their order. The toolbar stays turned on or off as it is."
                ),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local ConfirmBox = require("ui/widget/confirmbox")
                    UIManager:show(ConfirmBox:new({
                        text = _("Restore all selection toolbar settings to their defaults?"),
                        ok_text = _("Restore"),
                        ok_callback = function()
                            self:resetAllSettings()
                            if touchmenu_instance and touchmenu_instance.updateItems then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    }))
                end,
            },
            {
                text = _("About"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new({
                        text = _("Selection Toolbar")
                            .. "\n"
                            .. T(_("Version: %1"), C.PLUGIN_VERSION)
                            .. "\n\n"
                            .. _("Shows a compact icon toolbar near selected text instead of the default centered selection menu."),
                    }))
                end,
            },
        },
    }
end

return SelectionToolbar
