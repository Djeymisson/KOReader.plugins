local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local History = require("modules/history")

local Screen = Device.screen

local SETTING_ENABLED = "pageanchor_enabled"
local SETTING_SHOW_PAGE = "pageanchor_show_page"
local SETTING_PERCENTAGE = "pageanchor_percentage"

-- Match Quick Dock's main action buttons, including their roomier padding.
local BUTTON_ICON_SIZE = Screen:scaleBySize(22)
local BUTTON_HEIGHT = Screen:scaleBySize(42)
local BUTTON_PADDING = Screen:scaleBySize(6)
local BUTTON_MIN_WIDTH = BUTTON_HEIGHT + 2 * BUTTON_PADDING
local BUTTON_GAP = Size.padding.default
local BUTTON_MARGIN = Size.padding.large
local BUTTON_FONT_SIZE = 18

local function pluginDir()
	local source = debug.getinfo(1, "S").source or ""
	local path = source:match("^@(.*/)") or source:match("^(.*/)")
	return path or "plugins/pageanchor.koplugin/"
end

local ICONS_DIR = pluginDir() .. "icons/"

local FloatingHistoryOverlay = WidgetContainer:extend({})

function FloatingHistoryOverlay:clearCache()
	for _, entry in ipairs(self.buttons or {}) do
		if entry.widget and entry.widget.free then
			entry.widget:free()
		end
	end
	self.buttons = nil
	self.buttons_key = nil
	self.button_dimens = nil
end

function FloatingHistoryOverlay:_makeButton(spec)
	local icon = IconWidget:new({
		file = ICONS_DIR .. spec.icon,
		width = BUTTON_ICON_SIZE,
		height = BUTTON_ICON_SIZE,
	})
	local children = {}
	local show_label = spec.action ~= "dismiss" and self.owner:isPageNumberEnabled()
	local label
	if show_label then
		label = TextWidget:new({
			text = BD.ltr(spec.label),
			face = Font:getFace("cfont", BUTTON_FONT_SIZE),
			bold = true,
		})
	end

	if label and spec.side == "left" then
		children[#children + 1] = icon
		children[#children + 1] = HorizontalSpan:new({ width = Size.padding.default })
		children[#children + 1] = label
	elseif label then
		children[#children + 1] = label
		children[#children + 1] = HorizontalSpan:new({ width = Size.padding.default })
		children[#children + 1] = icon
	else
		children[#children + 1] = icon
	end
	children.allow_mirroring = false
	local content = HorizontalGroup:new(children)
	local content_size = content:getSize()
	local minimum_content_width = BUTTON_MIN_WIDTH
		- 2 * BUTTON_PADDING
		- 2 * Size.border.button
	local centered_content = CenterContainer:new({
		dimen = Geom:new({
			w = math.max(content_size.w, minimum_content_width),
			h = BUTTON_HEIGHT,
		}),
		content,
	})

	return FrameContainer:new({
		background = Blitbuffer.COLOR_WHITE,
		bordersize = Size.border.button,
		radius = Size.radius.button,
		margin = 0,
		padding = BUTTON_PADDING,
		centered_content,
	})
end

function FloatingHistoryOverlay:_buildButtons(specs)
	self.buttons = {}
	for _, spec in ipairs(specs) do
		self.buttons[#self.buttons + 1] = {
			action = spec.action,
			side = spec.side,
			widget = self:_makeButton(spec),
		}
	end
end

function FloatingHistoryOverlay:_getButtons(specs)
	local key_parts = { self.owner:isPageNumberEnabled() and "labels" or "arrows" }
	for _, spec in ipairs(specs) do
		key_parts[#key_parts + 1] = spec.action
		key_parts[#key_parts + 1] = spec.side
		key_parts[#key_parts + 1] = spec.icon
		key_parts[#key_parts + 1] = spec.label
	end
	local key = table.concat(key_parts, ":")
	if key ~= self.buttons_key then
		self:clearCache()
		self:_buildButtons(specs)
		self.buttons_key = key
	end
	return self.buttons
end

function FloatingHistoryOverlay:paintTo(bb, x, y)
	local specs = self.owner:getButtonSpecs()
	if #specs == 0 then
		self.button_dimens = nil
		return
	end

	local buttons = self:_getButtons(specs)
	local view = self.owner.ui.view
	local view_width = view and view.dimen and view.dimen.w or Screen:getWidth()
	local view_height = view and view.dimen and view.dimen.h or Screen:getHeight()
	local bottom = y + view_height - BUTTON_MARGIN
	local next_y = {
		left = bottom,
		right = bottom,
		center = bottom,
	}
	self.button_dimens = {}

	for _, entry in ipairs(buttons) do
		local size = entry.widget:getSize()
		local side = entry.side
		local button_x
		if side == "left" then
			button_x = x + BUTTON_MARGIN
		elseif side == "right" then
			button_x = x + view_width - size.w - BUTTON_MARGIN
		else
			button_x = x + math.floor((view_width - size.w) / 2)
		end
		local button_y = next_y[side] - size.h
		next_y[side] = button_y - BUTTON_GAP
		local dimen = Geom:new({
			x = button_x,
			y = button_y,
			w = size.w,
			h = size.h,
		})
		self.button_dimens[#self.button_dimens + 1] = {
			action = entry.action,
			dimen = dimen,
		}
		entry.widget:paintTo(bb, button_x, button_y)
	end
end

function FloatingHistoryOverlay:handleTap(gesture)
	local pos = gesture and gesture.pos
	if not pos then
		return false
	end
	for _, button in ipairs(self.button_dimens or {}) do
		if button.dimen:contains(pos) then
			return self.owner:activate(button.action)
		end
	end
	return false
end

local PageAnchor = WidgetContainer:extend({
	name = "pageanchor",
	is_doc_only = true,
})

function PageAnchor:init()
	self.overlay = FloatingHistoryOverlay:new({ owner = self })
	self.reference_page = nil
	self.reference_location = nil
	self._installed = false

	if self.ui and self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end
	self.ui:registerPostInitCallback(function()
		self:installOverlay()
	end)
end

function PageAnchor:isEnabled()
	return G_reader_settings:nilOrTrue(SETTING_ENABLED)
end

function PageAnchor:isPageNumberEnabled()
	return G_reader_settings:nilOrTrue(SETTING_SHOW_PAGE)
end

function PageAnchor:isPercentageEnabled()
	return G_reader_settings:isTrue(SETTING_PERCENTAGE)
end

function PageAnchor:isRightToLeftReading()
	local view = self.ui and self.ui.view
	if not view then
		return false
	end
	-- This is the same test ReaderView uses when reporting LTR/RTL page
	-- turning. It accounts for an already mirrored interface language.
	return (view.inverse_reading_order == true) ~= (BD.mirroredUILayout() == true)
end

function PageAnchor:getTargetSide(target, fallback_direction)
	local direction = History.compareLocationToCurrent(self.ui, target)
	if direction == nil or direction == 0 then
		direction = fallback_direction
	end
	local ahead = direction > 0
	if self:isRightToLeftReading() then
		return ahead and "left" or "right"
	end
	return ahead and "right" or "left"
end

function PageAnchor:getButtonSpecs()
	if not self:isEnabled() or not self.ui or not self.ui.link then
		return {}
	end

	local specs = {}
	local back = History.getEffectiveTarget(self.ui, self.ui.link.location_stack)
	local forward = History.getEffectiveTarget(self.ui, self.ui.link.forward_location_stack)
	local get_label = self:isPercentageEnabled()
		and History.getPercentageLabel or History.getPageLabel
	if back then
		local side = self:getTargetSide(back, -1)
		specs[#specs + 1] = {
			action = "back",
			side = side,
			icon = side == "left" and "chevron-left.svg" or "chevron-right.svg",
			label = get_label(self.ui, back),
		}
	end
	if forward then
		local side = self:getTargetSide(forward, 1)
		specs[#specs + 1] = {
			action = "forward",
			side = side,
			icon = side == "left" and "chevron-left.svg" or "chevron-right.svg",
			label = get_label(self.ui, forward),
		}
	end
	if #specs > 0 then
		specs[#specs + 1] = {
			action = "dismiss",
			side = "center",
			icon = "dismiss.svg",
			label = "",
		}
	end
	return specs
end

function PageAnchor:getRefreshRegion()
	return Geom:new({
		x = 0,
		y = math.floor(Screen:getHeight() * 0.72),
		w = Screen:getWidth(),
		h = math.ceil(Screen:getHeight() * 0.28),
	})
end

function PageAnchor:refresh(refresh_type)
	if self.ui and self.ui.dialog then
		local region = self:getRefreshRegion()
		UIManager:setDirty(self.ui.dialog, function()
			return refresh_type or "flashui", region
		end)
	end
end

function PageAnchor:installOverlay()
	if self._installed or not self.ui or not self.ui.view then
		return
	end
	self._installed = true

	local view = self.ui.view
	self._original_view_paintTo = view.paintTo
	local plugin = self
	view.paintTo = function(reader_view, bb, x, y)
		plugin._original_view_paintTo(reader_view, bb, x, y)
		plugin.overlay:paintTo(bb, x, y)
	end

	local overrides = {}
	local known_overrides = {
		"tap_link",
		"readerconfigmenu_ext_tap",
		"readerconfigmenu_tap",
		"readermenu_ext_tap",
		"readermenu_tap",
		"tap_forward",
		"tap_backward",
		"readerfooter_tap",
	}
	local override_ids = {}
	for _, id in ipairs(known_overrides) do
		override_ids[id] = true
		overrides[#overrides + 1] = id
	end
	if self.ui._zones then
		for id in pairs(self.ui._zones) do
			if not override_ids[id] then
				overrides[#overrides + 1] = id
			end
		end
	end
	self.ui:registerTouchZones({
		{
			id = "pageanchor_tap",
			ges = "tap",
			screen_zone = { ratio_x = 0, ratio_y = 0.7, ratio_w = 1, ratio_h = 0.3 },
			handler = function(gesture)
				return self.overlay:handleTap(gesture)
			end,
			overrides = overrides,
		},
	})
end

function PageAnchor:uninstallOverlay()
	if not self._installed then
		return
	end
	local view = self.ui and self.ui.view
	if view and self._original_view_paintTo then
		view.paintTo = self._original_view_paintTo
	end
	if self.ui then
		self.ui:unRegisterTouchZones({ { id = "pageanchor_tap" } })
	end
	self.overlay:clearCache()
	self._installed = false
end

function PageAnchor:activate(action)
	local link = self.ui and self.ui.link
	if not link then
		return false
	end
	if action == "dismiss" then
		self:clearHistory()
		return true
	elseif action == "back" and History.getEffectiveTarget(self.ui, link.location_stack) then
		link:onGoBackLink()
		return true
	elseif action == "forward" and History.getEffectiveTarget(self.ui, link.forward_location_stack) then
		link:onGoForwardLink()
		return true
	end
	return false
end

-- Most KOReader jump tools already populate ReaderLink's history. The
-- explicit reference below also catches gradual backward navigation and
-- third-party jumps that do not add their origin to the native history.
function PageAnchor:trackPage(page)
	page = tonumber(page)
	if not page then
		return
	end

	local link = self.ui and self.ui.link
	local current_location = History.getCurrentLocation(self.ui)
	if not link or not current_location then
		return
	end

	if not self.reference_page or not self.reference_location then
		self.reference_page = page
		self.reference_location = current_location
		return
	end

	local has_history = History.getEffectiveTarget(self.ui, link.location_stack)
		or History.getEffectiveTarget(self.ui, link.forward_location_stack)
	if has_history then
		return
	end

	local pages_behind = self.reference_page - page
	local pages_ahead = page - self.reference_page
	if pages_behind <= 1 and pages_ahead <= 2 then
		-- Forward reading advances the reference. Going back a single page is
		-- tolerated without moving it, so a second backward turn can still
		-- offer the last confirmed reading position.
		if page >= self.reference_page then
			self.reference_page = page
			self.reference_location = current_location
		end
	elseif not History.stackContainsPage(self.ui, link.location_stack, self.reference_page)
			and not History.stackContainsPage(self.ui, link.forward_location_stack, self.reference_page) then
		link:addCurrentLocationToStack(self.reference_location)
	end
end

function PageAnchor:onReaderReady()
	self:trackPage(self.ui:getCurrentPage())
end

function PageAnchor:onPageUpdate(page)
	self:trackPage(page)
end

function PageAnchor:onPosUpdate(_pos, page)
	if page then
		self:trackPage(page)
	else
		self.previous_location = History.getCurrentLocation(self.ui)
	end
end

function PageAnchor:onCloseDocument()
	self:uninstallOverlay()
end

function PageAnchor:stopPlugin()
	self:uninstallOverlay()
	self:refresh()
	return true
end

function PageAnchor:clearHistory()
	local link = self.ui and self.ui.link
	if link then
		link:onClearLocationStack()
		self.reference_page = self.ui:getCurrentPage()
		self.reference_location = History.getCurrentLocation(self.ui)
		self:refresh()
	end
end

function PageAnchor:addToMainMenu(menu_items)
	menu_items.pageanchor = {
		text = _("Page Anchor"),
		sorting_hint = "navi",
		sub_item_table = {
			{
				text = _("Show floating navigation button"),
				checked_func = function()
					return self:isEnabled()
				end,
				callback = function()
					G_reader_settings:saveSetting(SETTING_ENABLED, not self:isEnabled())
					self:refresh()
				end,
			},
			{
				text = _("Show destination position"),
				checked_func = function()
					return self:isPageNumberEnabled()
				end,
				callback = function()
					G_reader_settings:saveSetting(SETTING_SHOW_PAGE, not self:isPageNumberEnabled())
					self.overlay:clearCache()
					self:refresh()
				end,
			},
			{
				text = _("Destination format"),
				enabled_func = function()
					return self:isPageNumberEnabled()
				end,
				sub_item_table = {
					{
						text = _("Page number"),
						checked_func = function()
							return not self:isPercentageEnabled()
						end,
						callback = function()
							G_reader_settings:makeFalse(SETTING_PERCENTAGE)
							self.overlay:clearCache()
							self:refresh()
						end,
					},
					{
						text = _("Percentage"),
						checked_func = function()
							return self:isPercentageEnabled()
						end,
						callback = function()
							G_reader_settings:makeTrue(SETTING_PERCENTAGE)
							self.overlay:clearCache()
							self:refresh()
						end,
					},
				},
			},
			{
				text = _("Clear location history"),
				separator = true,
				callback = function()
					UIManager:show(ConfirmBox:new({
						text = _("Clear location history?"),
						ok_text = _("Clear"),
						ok_callback = function()
							self:clearHistory()
						end,
					}))
				end,
			},
		},
	}
end

return PageAnchor
