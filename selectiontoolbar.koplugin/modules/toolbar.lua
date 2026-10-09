-- The toolbar itself: the patch of ReaderHighlight that shows it instead of KOReader's
-- selection menu, its buttons and their actions, the More button and the toolbar dialog.

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Device = require("device")
local Size = require("ui/size")
local util = require("util")
local _ = require("selectiontoolbar_l10n")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local C, lib = ...
local readChoice = lib.readChoice
local refreshRects = lib.refreshRects
local applyToolbarButtonMetrics = lib.applyToolbarButtonMetrics
local getToolbarMetrics = lib.getToolbarMetrics
local ShadowedButtonDialog = lib.ShadowedButtonDialog

local SelectionToolbar = {}

-- The toolbar buttons of the visible actions, in the chosen order. make(action) returns
-- the button of an action, or nil to leave it out. A button followed by a group
-- separator gets group_end, unless no other button follows: separators around hidden
-- or left out actions collapse, so groups never show an empty slot.
function SelectionToolbar:buildActionRow(make)
    local action_settings = self:getActionSettings()
    local row = {}
    local group_ended = false
    for _, id in ipairs(self:getActionOrder()) do
        if id == C.GROUP_SEPARATOR then
            group_ended = #row > 0
        elseif action_settings[id] ~= false then
            local button = make(C.ACTIONS_BY_ID[id])
            if button then
                if group_ended then
                    row[#row].group_end = true
                    group_ended = false
                end
                row[#row + 1] = button
            end
        end
    end
    return row
end

function SelectionToolbar:getQRMessage()
    if self.qr_message_checked then
        return self.qr_message_class
    end

    self.qr_message_checked = true
    local ok_qr, QRMessage = pcall(require, C.QR_MESSAGE_MODULE)
    if ok_qr and QRMessage then
        self.qr_message_class = QRMessage
    end

    return self.qr_message_class
end

function SelectionToolbar:closeHighlightDialog(reader_highlight)
    if reader_highlight.highlight_dialog then
        UIManager:close(reader_highlight.highlight_dialog)
        reader_highlight.highlight_dialog = nil
    end
end

-- The toolbar dialog for a row of buttons, with the current appearance settings. Used
-- for both the real toolbar and its preview, so that they always look the same.
-- available_width: the room for the toolbar and its shadow (default: the screen width
-- less a margin on both sides).
-- rows: one row of buttons, or two with the More button expanded. The toolbar is sized
-- for the widest one.
function SelectionToolbar:buildToolbarDialog(rows, metrics, options, available_width)
    local shadow = self:getShadowFinish()
    local shadow_extent = shadow and shadow.extent or 0
    local count = 0
    for _, row in ipairs(rows) do
        count = math_max(count, #row)
    end
    local style = self:getFrameStyle(metrics, #rows)
    -- ButtonTable puts a separator line between buttons; the frame adds border and padding.
    local separators = (count - 1) * Size.line.medium
    local frame_extra = 2 * style.border + 2 * style.padding_h
    local max_width = (available_width or (Screen:getWidth() - 2 * Size.padding.large)) - shadow_extent

    -- ButtonTable never shrinks buttons with a given width, so a row wider than the
    -- screen would run off it: narrow the buttons (and icons, if needed) to fit.
    local button_width = metrics.button_width
    local fit_width = math_floor((max_width - frame_extra - separators) / count)
    if fit_width < button_width then
        button_width = fit_width
        local icon_size = math_min(metrics.icon_size, button_width - 2 * Size.padding.button)
        for _, row in ipairs(rows) do
            for _, button in ipairs(row) do
                button.width = button_width
                button.icon_width = icon_size
                button.icon_height = icon_size
            end
        end
    end

    local separator_style = self:getSeparators()
    if separator_style ~= C.DEFAULT_SEPARATORS then
        -- ButtonTable keeps the width of a hidden separator, but draws it in the
        -- background color, so the toolbar width does not depend on this setting.
        for _, row in ipairs(rows) do
            for _, button in ipairs(row) do
                button.no_vertical_sep = separator_style == C.SEPARATORS_NONE or not button.group_end
            end
        end
    end

    options.buttons = rows
    -- ButtonTable also draws a line between rows, which no_vertical_sep does not cover.
    options.hide_row_separators = separator_style == C.SEPARATORS_NONE
    -- ButtonDialog sizes its ButtonTable for its own default border and padding.
    options.width = count * button_width + separators + 2 * Size.border.window + 2 * Size.padding.button
    options.frame_style = style
    options.shadow = shadow
    options.shrink_unneeded_width = true
    options.shrink_min_width = button_width
    return ShadowedButtonDialog:new(options)
end

function SelectionToolbar:patchHighlight(highlight)
    if highlight._selectiontoolbar_patched then
        return
    end

    highlight._selectiontoolbar_original_onShowHighlightMenu = highlight.onShowHighlightMenu
    local plugin = self

    highlight.onShowHighlightMenu = function(reader_highlight, index)
        if not plugin:isEnabled() then
            return reader_highlight:_selectiontoolbar_original_onShowHighlightMenu(index)
        end
        return plugin:showToolbar(reader_highlight, index)
    end

    highlight._selectiontoolbar_patched = true
end

function SelectionToolbar:getSelectedText(reader_highlight)
    if reader_highlight.selected_text then
        if reader_highlight.selected_text.text then
            return util.cleanupSelectedText(reader_highlight.selected_text.text)
        end
        if type(reader_highlight.selected_text) == "string" then
            return util.cleanupSelectedText(reader_highlight.selected_text)
        end
    end
    return ""
end

function SelectionToolbar:showQRCode(reader_highlight)
    local text = self:getSelectedText(reader_highlight)
    if text == "" then
        UIManager:show(InfoMessage:new({ text = _("No selected text.") }))
        return
    end

    self:closeHighlightDialog(reader_highlight)

    local QRMessage = self:getQRMessage()
    if not QRMessage then
        UIManager:show(InfoMessage:new({ text = _("QR code widget is not available in this KOReader build.") }))
        return
    end

    local qr_size = math_floor(math_min(Screen:getWidth(), Screen:getHeight()) * 0.85)
    UIManager:show(QRMessage:new({
        text = text,
        width = qr_size,
        height = qr_size,
    }))
end

function SelectionToolbar:makeQRButton(reader_highlight, metrics)
    return applyToolbarButtonMetrics({
        id = "selectiontoolbar_qr_code",
        icon = self:getIconPath(C.QR_ICON_ACTION),
        enabled = true,
        callback = function()
            self:showQRCode(reader_highlight)
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new({ text = _("Generate QR code") }))
        end,
    }, metrics)
end

function SelectionToolbar:makeButton(reader_highlight, action, index, metrics)
    if action.id == "qr_code" then
        return self:makeQRButton(reader_highlight, metrics)
    end

    local make_original = reader_highlight._highlight_buttons and reader_highlight._highlight_buttons[action.key]
    if not make_original then
        return nil
    end

    local original = make_original(reader_highlight, index)
    if not original then
        return nil
    end

    if original.show_in_highlight_dialog_func and not original.show_in_highlight_dialog_func(reader_highlight) then
        return nil
    end

    local original_callback = original.callback
    local button = applyToolbarButtonMetrics(original, metrics)
    button.id = "selectiontoolbar_" .. action.id
    button.text = nil
    button.icon = self:getIconPath(action)
    button.show_in_highlight_dialog_func = nil

    button.callback = function()
        if original_callback then
            return original_callback()
        end
    end
    button.hold_callback = function()
        UIManager:show(InfoMessage:new({ text = action.text }))
    end

    return button
end

-- Shows the toolbar again for the same selection, e.g. anchored to an adjusted selection
-- or with the More row expanded or collapsed. The marks on screen are already up to
-- date, so they are not refreshed again.
function SelectionToolbar:reopenToolbar(reader_highlight, index, expanded)
    if reader_highlight.highlight_dialog then
        reader_highlight.highlight_dialog.replaced = true
    end
    self.reopening_toolbar = true
    local ok, err = pcall(self.showToolbar, self, reader_highlight, index, expanded)
    self.reopening_toolbar = nil
    if not ok then
        error(err, 0)
    end
end

-- The More button: shows the actions of the second row, or hides them when expanded.
function SelectionToolbar:makeMoreButton(metrics, expanded, callback)
    local label = expanded and _("Fewer actions") or _("More actions")
    return applyToolbarButtonMetrics({
        id = "selectiontoolbar_more",
        icon = self:getIconPath(C.MORE_ICON_ACTION),
        callback = callback,
        hold_callback = function()
            UIManager:show(InfoMessage:new({ text = label }))
        end,
    }, metrics)
end

-- The toolbar rows for a row of action buttons: all of them, or the main actions then the
-- More button, plus the other actions in a second row when expanded. More only shows
-- when it saves room: with a single action left, that action takes its place.
function SelectionToolbar:splitToolbarRows(row, expanded, more_button)
    local count = readChoice(C.SETTING_MAIN_ACTIONS, C.MAIN_ACTION_COUNTS, C.DEFAULT_MAIN_ACTIONS).count
    if not count or #row <= count + 1 then
        return { row }
    end
    local main, rest = {}, {}
    for i, button in ipairs(row) do
        if i <= count then
            main[#main + 1] = button
        else
            rest[#rest + 1] = button
        end
    end
    -- More is a group of its own.
    main[#main].group_end = true
    main[#main + 1] = more_button
    if expanded then
        return { main, rest }
    end
    return { main }
end

-- expanded: show the actions after the More button in a second row.
function SelectionToolbar:showToolbar(reader_highlight, index, expanded)
    local metrics = getToolbarMetrics()
    local row = self:buildActionRow(function(action)
        return self:makeButton(reader_highlight, action, index, metrics)
    end)

    if #row == 0 then
        UIManager:show(InfoMessage:new({ text = _("No selection toolbar actions are enabled.") }))
        return true
    end

    self:closeHighlightDialog(reader_highlight)

    local with_marks = self:canShowMarks(reader_highlight, index)
    local more_button = self:makeMoreButton(metrics, expanded, function()
        self:reopenToolbar(reader_highlight, index, not expanded)
    end)
    local rows = self:splitToolbarRows(row, expanded, more_button)

    reader_highlight.highlight_dialog = self:buildToolbarDialog(rows, metrics, {
        toolbar_expanded = expanded,
        dismissable = true,
        handle_controller = with_marks and self or nil,
        handle_pan_rate = with_marks and self:getHandlePanRate() or nil,
        anchor = function()
            return self:getToolbarAnchor(reader_highlight, reader_highlight.highlight_dialog, index)
        end,
        tap_close_callback = function()
            if reader_highlight.hold_pos and reader_highlight.clear then
                reader_highlight:clear()
            end
        end,
    })

    if with_marks then
        self.marks_dialog = reader_highlight.highlight_dialog
        self.marks_highlight = reader_highlight
        local marks = self:computeSelectionMarks(reader_highlight)
        -- Current handle positions, for the toolbar anchor computed at its first paint.
        self.marks = marks
        if marks and not self.reopening_toolbar then
            refreshRects(reader_highlight.dialog, marks.rects)
        end
    end

    UIManager:show(reader_highlight.highlight_dialog, "[ui]")
    return true
end

return SelectionToolbar
