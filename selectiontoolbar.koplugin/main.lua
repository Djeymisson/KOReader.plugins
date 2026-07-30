local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local IconWidget = require("ui/widget/iconwidget")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Device = require("device")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local PLUGIN_VERSION = "v1.0.3"
local QR_MESSAGE_MODULE = "ui/widget/qrmessage"

local BUTTON_ICON_SIZE = Screen:scaleBySize(22)
local BUTTON_HEIGHT = Screen:scaleBySize(42)
local BUTTON_SIDE_PADDING = Screen:scaleBySize(6)
local BUTTON_WIDTH = BUTTON_HEIGHT + 2 * BUTTON_SIDE_PADDING

local SHADOW_WIDTH = math_max(2, Screen:scaleBySize(12))
local SHADOW_OVERLAP = math_min(SHADOW_WIDTH - 1, math_max(1, Screen:scaleBySize(6)))
local SHADOW_EXTENT = math_max(0, SHADOW_WIDTH - SHADOW_OVERLAP)
local SHADOW_BAYER8 = {
	{ 0, 32, 8, 40, 2, 34, 10, 42 },
	{ 48, 16, 56, 24, 50, 18, 58, 26 },
	{ 12, 44, 4, 36, 14, 46, 6, 38 },
	{ 60, 28, 52, 20, 62, 30, 54, 22 },
	{ 3, 35, 11, 43, 1, 33, 9, 41 },
	{ 51, 19, 59, 27, 49, 17, 57, 25 },
	{ 15, 47, 7, 39, 13, 45, 5, 37 },
	{ 63, 31, 55, 23, 61, 29, 53, 21 },
}

local SETTING_ENABLED = "selectiontoolbar_enabled"
local SETTING_ACTIONS = "selectiontoolbar_actions"
local SETTING_SHADOWS = "selectiontoolbar_shadows"

local ACTIONS = {
	{ id = "select", key = "01_select", icon = "select", text = _("Select") },
	{ id = "highlight", key = "02_highlight", icon = "highlight", text = _("Highlight") },
	{ id = "copy", key = "03_copy", icon = "copy", text = _("Copy") },
	{ id = "add_note", key = "04_add_note", icon = "add_note", text = _("Add note") },
	{ id = "wikipedia", key = "05_wikipedia", icon = "wikipedia", text = _("Wikipedia") },
	{ id = "dictionary", key = "06_dictionary", icon = "dictionary", text = _("Dictionary") },
	{ id = "translate", key = "07_translate", icon = "translate", text = _("Translate") },
	{ id = "view_html", key = "09_view_html", icon = "view_html", text = _("View HTML") },
	{ id = "qr_code", key = nil, icon = "qr_code", text = _("Generate QR code") },
	{ id = "search", key = "12_search", icon = "search", text = _("Search") },
}
local QR_ICON_ACTION = { icon = "qr_code" }

local TOOLBAR_SHADOW_CACHE = {}

local function clearToolbarShadowCache()
	if TOOLBAR_SHADOW_CACHE.right then
		TOOLBAR_SHADOW_CACHE.right:free()
	end
	if TOOLBAR_SHADOW_CACHE.bottom then
		TOOLBAR_SHADOW_CACHE.bottom:free()
	end
	TOOLBAR_SHADOW_CACHE = {}
end

local ShadowedPopup = WidgetContainer:extend({})

function ShadowedPopup:getSize()
	local size = self[1]:getSize()
	return Geom:new({
		w = size.w + SHADOW_EXTENT,
		h = size.h + SHADOW_EXTENT,
	})
end

function ShadowedPopup:_ensureShadowBuffers(bb, width, height)
	local night = Screen.night_mode
	local inv = bb.getInverse and bb:getInverse() == 1
	local render_inv = inv and not (night and Device.isAndroid and Device:isAndroid())
	local cache_key = table.concat({
		tostring(width),
		tostring(height),
		tostring(night),
		tostring(render_inv),
	}, ":")
	if TOOLBAR_SHADOW_CACHE.key == cache_key then
		return
	end

	clearToolbarShadowCache()
	TOOLBAR_SHADOW_CACHE.key = cache_key

	local shadow_value = render_inv and 0x00 or (night and 0xFF or 0x00)
	local shadow_on = Blitbuffer.ColorRGB32(shadow_value, shadow_value, shadow_value, 255)
	local shadow_off = Blitbuffer.ColorRGB32(shadow_value, shadow_value, shadow_value, 0)
	local base_strength = night and 1.0 or 0.5
	local peak_level = night and 1.0 or 0.62
	local bump_width = 0.18

	local function baseFraction(t)
		if night then
			return t < 0.5 and (1 - 0.8 * t) or 0.6 * (1 - (t - 0.5) * 2) ^ 2
		end
		return 1 - t
	end

	local function shadowLevel(pos)
		local t = (pos + 0.5) / SHADOW_WIDTH
		local original_level = base_strength * baseFraction(t)
		local visible_start = SHADOW_OVERLAP / SHADOW_WIDTH
		local bump
		if t <= visible_start then
			bump = 1
		else
			local distance = (t - visible_start) / bump_width
			bump = distance < 1 and 0.5 * (1 + math.cos(math.pi * distance)) or 0
		end
		return (original_level + bump * (peak_level - original_level)) * 255
	end

	TOOLBAR_SHADOW_CACHE.right = Blitbuffer.new(SHADOW_WIDTH, height, Blitbuffer.TYPE_BBRGB32)
	for x = 0, SHADOW_WIDTH - 1 do
		local level = shadowLevel(x)
		local column = (x % 8) + 1
		for y = 0, height - 1 do
			local threshold = (SHADOW_BAYER8[column][(y % 8) + 1] + 0.5) * 4
			local color = level > threshold and shadow_on or shadow_off
			TOOLBAR_SHADOW_CACHE.right:setPixel(x, y, color)
		end
	end
	TOOLBAR_SHADOW_CACHE.right:setInverse(render_inv and 1 or 0)

	local bottom_width = width + SHADOW_EXTENT
	TOOLBAR_SHADOW_CACHE.bottom = Blitbuffer.new(bottom_width, SHADOW_WIDTH, Blitbuffer.TYPE_BBRGB32)
	for y = 0, SHADOW_WIDTH - 1 do
		local bottom_level = shadowLevel(y)
		local row = (y % 8) + 1
		for x = 0, bottom_width - 1 do
			local level = bottom_level
			if y < SHADOW_OVERLAP and x >= width - SHADOW_OVERLAP then
				level = 0
			elseif x >= width then
				level = math_min(level, shadowLevel(SHADOW_OVERLAP + x - width))
			end
			local threshold = (SHADOW_BAYER8[(x % 8) + 1][row] + 0.5) * 4
			local color = level > threshold and shadow_on or shadow_off
			TOOLBAR_SHADOW_CACHE.bottom:setPixel(x, y, color)
		end
	end
	TOOLBAR_SHADOW_CACHE.bottom:setInverse(render_inv and 1 or 0)
end

function ShadowedPopup:_alphaBlitClipped(bb, source, x, y)
	local source_x, source_y = 0, 0
	local width, height = source:getWidth(), source:getHeight()
	if x < 0 then
		source_x = -x
		width = width - source_x
		x = 0
	end
	if y < 0 then
		source_y = -y
		height = height - source_y
		y = 0
	end
	width = math_min(width, bb:getWidth() - x)
	height = math_min(height, bb:getHeight() - y)
	if width > 0 and height > 0 then
		bb:alphablitFrom(source, x, y, source_x, source_y, width, height)
	end
end

function ShadowedPopup:paintTo(bb, x, y)
	local content_size = self[1]:getSize()
	local width, height = content_size.w, content_size.h
	self:_ensureShadowBuffers(bb, width, height)
	self.dimen = Geom:new({
		x = x,
		y = y,
		w = width + SHADOW_EXTENT,
		h = height + SHADOW_EXTENT,
	})
	self:_alphaBlitClipped(bb, TOOLBAR_SHADOW_CACHE.bottom, x, y + height - SHADOW_OVERLAP)
	self:_alphaBlitClipped(bb, TOOLBAR_SHADOW_CACHE.right, x + width - SHADOW_OVERLAP, y)
	self[1]:paintTo(bb, x, y)
end

local ShadowedButtonDialog = ButtonDialog:extend({})

function ShadowedButtonDialog:init()
	ButtonDialog.init(self)
	if self.show_shadow then
		self.movable[1] = ShadowedPopup:new({
			self.movable[1],
		})
	end
end

local function pluginDir()
	local source = debug.getinfo(1, "S").source or ""
	local path = source:match("^@(.*/)") or source:match("^(.*/)")
	return path or "plugins/selectiontoolbar.koplugin/"
end

local function applyToolbarButtonMetrics(button)
	button.icon_width = BUTTON_ICON_SIZE
	button.icon_height = BUTTON_ICON_SIZE
	button.height = BUTTON_HEIGHT
	button.width = BUTTON_WIDTH
	button.padding = BUTTON_SIDE_PADDING
	button.margin = 0
	return button
end

local SelectionToolbar = WidgetContainer:extend({
	name = "selectiontoolbar",
	is_doc_only = true,
})

function SelectionToolbar:init()
	self.plugin_path = pluginDir()
	self.icons_path = self.plugin_path .. "icons/"
	self.icon_cache = {}
	self.qr_message_checked = false
	self.qr_message_class = nil

	self:patchIconWidget()
	if self.ui and self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end
	if self.ui and self.ui.highlight then
		self:patchHighlight(self.ui.highlight)
	end
end

function SelectionToolbar:onClose()
	if self.ui and self.ui.highlight and self.ui.highlight._selectiontoolbar_original_onShowHighlightMenu then
		self.ui.highlight.onShowHighlightMenu = self.ui.highlight._selectiontoolbar_original_onShowHighlightMenu
		self.ui.highlight._selectiontoolbar_original_onShowHighlightMenu = nil
		self.ui.highlight._selectiontoolbar_patched = nil
	end

	self:unpatchIconWidget()
	clearToolbarShadowCache()
end

function SelectionToolbar:isEnabled()
	return G_reader_settings:readSetting(SETTING_ENABLED) ~= false
end

function SelectionToolbar:setEnabled(enabled)
	G_reader_settings:saveSetting(SETTING_ENABLED, enabled and true or false)
end

function SelectionToolbar:showToolbarShadows()
	return G_reader_settings:nilOrTrue(SETTING_SHADOWS)
end

function SelectionToolbar:setToolbarShadows(enabled)
	G_reader_settings:saveSetting(SETTING_SHADOWS, enabled and true or false)
	if not enabled then
		clearToolbarShadowCache()
	end
end

function SelectionToolbar:getActionSettings()
	local settings = G_reader_settings:readSetting(SETTING_ACTIONS)
	if type(settings) ~= "table" then
		settings = {}
	end
	return settings
end

function SelectionToolbar:isActionEnabled(action_id)
	local settings = self:getActionSettings()
	return settings[action_id] ~= false
end

function SelectionToolbar:setActionEnabled(action_id, enabled)
	local settings = self:getActionSettings()
	settings[action_id] = enabled and true or false
	G_reader_settings:saveSetting(SETTING_ACTIONS, settings)
end

function SelectionToolbar:resetActions()
	if G_reader_settings.delSetting then
		G_reader_settings:delSetting(SETTING_ACTIONS)
	else
		G_reader_settings:saveSetting(SETTING_ACTIONS, {})
	end
end

function SelectionToolbar:patchIconWidget()
	if IconWidget._selectiontoolbar_original_init then
		return
	end

	IconWidget._selectiontoolbar_original_init = IconWidget.init

	local patched_init = function(icon_widget)
		local explicit_icon = rawget(icon_widget, "icon")
		if
			type(explicit_icon) == "string"
			and explicit_icon:match("%.%a+$")
			and lfs.attributes(explicit_icon, "mode") == "file"
		then
			icon_widget.file = explicit_icon
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

function SelectionToolbar:getQRMessage()
	if self.qr_message_checked then
		return self.qr_message_class
	end

	self.qr_message_checked = true
	local ok_qr, QRMessage = pcall(require, QR_MESSAGE_MODULE)
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

function SelectionToolbar:addToMainMenu(menu_items)
	local action_items = {
		{
			text = _("Show all actions"),
			callback = function()
				self:resetActions()
				UIManager:show(InfoMessage:new({ text = _("All selection toolbar actions are enabled.") }))
			end,
		},
	}

	for _, action in ipairs(ACTIONS) do
		table.insert(action_items, {
			text = action.text,
			checked_func = function()
				return self:isActionEnabled(action.id)
			end,
			callback = function(touchmenu_instance)
				self:setActionEnabled(action.id, not self:isActionEnabled(action.id))
				if touchmenu_instance and touchmenu_instance.updateItems then
					touchmenu_instance:updateItems()
				end
			end,
			keep_menu_open = true,
		})
	end

	menu_items.selectiontoolbar = {
		text = _("Selection toolbar"),
		sorting_hint = "tools",
		sub_item_table = {
			{
				text = _("Use compact selection toolbar"),
				checked_func = function()
					return self:isEnabled()
				end,
				callback = function(touchmenu_instance)
					self:setEnabled(not self:isEnabled())
					if touchmenu_instance and touchmenu_instance.updateItems then
						touchmenu_instance:updateItems()
					end
				end,
				keep_menu_open = true,
			},
			{
				text = _("Appearance"),
				sub_item_table = {
					{
						text = _("Show toolbar shadow"),
						help_text = _(
							"Show a small dithered shadow along the right and bottom edges of the selection toolbar."
						),
						checked_func = function()
							return self:showToolbarShadows()
						end,
						callback = function()
							self:setToolbarShadows(not self:showToolbarShadows())
						end,
						keep_menu_open = true,
					},
				},
			},
			{
				text = _("Visible actions"),
				sub_item_table = action_items,
			},
			{
				text = _("Version") .. ": " .. PLUGIN_VERSION,
				callback = function()
					UIManager:show(InfoMessage:new({ text = _("Selection Toolbar Plugin") .. " " .. PLUGIN_VERSION }))
				end,
				separator = true,
			},
		},
	}
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

function SelectionToolbar:makeQRButton(reader_highlight)
	return applyToolbarButtonMetrics({
		id = "selectiontoolbar_qr_code",
		icon = self:getIconPath(QR_ICON_ACTION),
		enabled = true,
		callback = function()
			self:showQRCode(reader_highlight)
		end,
		hold_callback = function()
			UIManager:show(InfoMessage:new({ text = _("Generate QR code") }))
		end,
	})
end

function SelectionToolbar:makeButton(reader_highlight, action, index)
	if action.id == "qr_code" then
		return self:makeQRButton(reader_highlight)
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
	local button = applyToolbarButtonMetrics(original)
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

function SelectionToolbar:getSelectionBoxes(reader_highlight, index)
	local boxes

	if index and reader_highlight.getHighlightVisibleBoxes then
		boxes = reader_highlight:getHighlightVisibleBoxes(index)
	elseif reader_highlight.selected_text then
		boxes = reader_highlight.selected_text.sboxes or reader_highlight.selected_text.pboxes
	end

	if not boxes or #boxes == 0 then
		return nil
	end

	return boxes
end

function SelectionToolbar:getPageOffset(reader_highlight, index)
	local ui = reader_highlight.ui
	local document = ui and ui.document
	if not (ui and ui.paging and document and document.getPageDimensions) then
		return nil
	end

	local page
	if index and ui.annotation and ui.annotation.annotations[index] then
		local annotation = ui.annotation.annotations[index]
		page = annotation.pos0 and annotation.pos0.page
	end

	if not page and reader_highlight.selected_text and reader_highlight.selected_text.pos0 then
		page = reader_highlight.selected_text.pos0.page
	end

	if not page then
		return nil
	end

	local page_dimen = document:getPageDimensions(page)
	return page_dimen and page_dimen.offset
end

function SelectionToolbar:selectionBoundingBox(reader_highlight, index)
	local boxes = self:getSelectionBoxes(reader_highlight, index)
	if not boxes then
		return nil
	end

	local page_offset = self:getPageOffset(reader_highlight, index)
	local offset_x = page_offset and page_offset.x or 0
	local offset_y = page_offset and page_offset.y or 0

	local min_x, min_y, max_x, max_y
	for _, box in ipairs(boxes) do
		local x = box.x + offset_x
		local y = box.y + offset_y
		local w, h = box.w, box.h

		min_x = min_x and math_min(min_x, x) or x
		min_y = min_y and math_min(min_y, y) or y
		max_x = max_x and math_max(max_x, x + w) or (x + w)
		max_y = max_y and math_max(max_y, y + h) or (y + h)
	end

	if not min_x then
		return nil
	end

	return Geom:new({ x = min_x, y = min_y, w = max_x - min_x, h = max_y - min_y })
end

function SelectionToolbar:getToolbarAnchor(reader_highlight, dialog, index)
	local selection_box = self:selectionBoundingBox(reader_highlight, index)
	if not selection_box then
		if reader_highlight._getDialogAnchor then
			return reader_highlight:_getDialogAnchor(dialog, index)
		end
		return nil
	end

	local dialog_size = dialog:getContentSize()
	local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
	local gap = Size.padding.large

	local anchor_x = math_floor(selection_box.x + selection_box.w / 2 - dialog_size.w / 2)
	if anchor_x < gap then
		anchor_x = gap
	elseif anchor_x + dialog_size.w > screen_w - gap then
		anchor_x = screen_w - dialog_size.w - gap
	end

	local space_above = selection_box.y
	local space_below = screen_h - (selection_box.y + selection_box.h)
	local prefer_below = space_below >= dialog_size.h + gap or space_below >= space_above

	if prefer_below then
		return Geom:new({ x = anchor_x, y = selection_box.y + selection_box.h + gap, w = 0, h = 0 }), true
	end

	return Geom:new({ x = anchor_x, y = selection_box.y - gap, w = 0, h = 0 }), false
end

function SelectionToolbar:showToolbar(reader_highlight, index)
	local row = {}

	local action_settings = self:getActionSettings()
	for _, action in ipairs(ACTIONS) do
		if action_settings[action.id] ~= false then
			local button = self:makeButton(reader_highlight, action, index)
			if button then
				row[#row + 1] = button
			end
		end
	end

	if #row == 0 then
		UIManager:show(InfoMessage:new({ text = _("No selection toolbar actions are enabled.") }))
		return true
	end

	self:closeHighlightDialog(reader_highlight)

	local button_size = BUTTON_WIDTH
	local show_shadow = self:showToolbarShadows()
	local shadow_extent = show_shadow and SHADOW_EXTENT or 0
	local width = math_min(
		Screen:getWidth() - 2 * Size.padding.large - shadow_extent,
		#row * button_size + 2 * Size.border.window + 2 * Size.padding.button
	)

	reader_highlight.highlight_dialog = ShadowedButtonDialog:new({
		buttons = { row },
		width = width,
		show_shadow = show_shadow,
		shrink_unneeded_width = true,
		shrink_min_width = button_size,
		dismissable = true,
		anchor = function()
			return self:getToolbarAnchor(reader_highlight, reader_highlight.highlight_dialog, index)
		end,
		tap_close_callback = function()
			if reader_highlight.hold_pos and reader_highlight.clear then
				reader_highlight:clear()
			end
		end,
	})

	UIManager:show(reader_highlight.highlight_dialog, "[ui]")
	return true
end

return SelectionToolbar
