--[[
Reader Header/Footer plugin for KOReader.

Shows small reader indicators in the document margins:
- Top right: optional Wi-Fi, clock and battery indicators, or chapter information when empty.
- Top left: primary author + book title when right-side device indicators are disabled.
- Header: hidden at chapter starts only when device indicators are disabled.
- Bottom left: optional pages left in chapter or book.
- Bottom right: optional document read percentage.

The plugin avoids full-screen refreshes by invalidating only the top/bottom
indicator regions, and defers refreshes while KOReader menus/dialogs are open.
]]

local Device = require("device")
local Screen = Device.screen

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local TextWidget = require("ui/widget/textwidget")
local SpinWidget = require("ui/widget/spinwidget")
local InfoMessage = require("ui/widget/infomessage")

local Font = require("ui/font")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local logger = require("logger")
local _ = require("gettext")

-- ============================================================================
-- Constants
-- ============================================================================

local PLUGIN_NAME = "reader_header_footer"
local PLUGIN_VERSION = "v1.0.7"

local SETTINGS = {
	enabled = "reader_header_footer_enabled",
	font_size = "reader_header_footer_font_size",
	show_wifi = "reader_header_footer_show_wifi",
	show_clock = "reader_header_footer_show_clock",
	show_battery_status = "reader_header_footer_show_battery_status",
	show_battery_percentage = "reader_header_footer_show_battery_percentage",
	show_footer_left = "reader_header_footer_show_footer_left",
	show_read_percentage = "reader_header_footer_show_read_percentage",
	follow_document_margins = "reader_header_footer_follow_document_margins",
	custom_left_margin = "reader_header_footer_custom_left_margin",
	custom_right_margin = "reader_header_footer_custom_right_margin",
	custom_horizontal_margin = "reader_header_footer_custom_horizontal_margin",
	footer_left_mode_setting_key = "reader_header_footer_left_footer_mode",
	footer_left_mode = "chapter",
}

local FONT = {
	name = "NotoSans-Regular.ttf",
	default_size = 16,
	min_size = 10,
	max_size = 28,
}

local LAYOUT = {
	padding = 10,
	top_padding = 2,
	bottom_padding = 10,
	text_clear_extra = 6,
	line_extra_for_region = 8,
	line_extra_for_paint = 4,
	left_right_gap = 16,
}

local INDICATOR_MARGINS = {
	default_follow_document = true,
	default_left = 20,
	default_right = 20,
	min = 0,
	max = 300,
}

local REFRESH = {
	battery_check_interval = 300, -- 5 minutes.
	deferred_menu_check_interval = 0.5,
	after_dialog_close_delay = 0.1,
}

-- ============================================================================
-- Plugin definition/state
-- ============================================================================

local ReaderHeaderFooter = WidgetContainer:extend({
	name = PLUGIN_NAME,
	is_doc_only = true,

	-- Persistent settings loaded at init().
	enabled = true,
	font_size = FONT.default_size,
	show_wifi = true,
	show_clock = true,
	show_battery_status = true,
	show_battery_percentage = true,
	show_footer_left = true,
	show_read_percentage = true,
	follow_document_margins = INDICATOR_MARGINS.default_follow_document,
	custom_left_margin = INDICATOR_MARGINS.default_left,
	custom_right_margin = INDICATOR_MARGINS.default_right,
	custom_horizontal_margin = INDICATOR_MARGINS.default_left,

	-- Used to clear the old larger region after font size changes.
	refresh_region_font_size = FONT.default_size,

	-- Runtime state.
	menu_registered = false,
	font_face = nil,

	footer_left_mode = "chapter",

	pageno = nil,
	pages = nil,

	visible_area = nil,
	page_area = nil,

	clock_refresh_fn = nil,
	battery_check_fn = nil,

	last_wifi_on = nil,
	last_battery_level = nil,
	last_charging = nil,

	top_refresh_pending = false,
	bottom_refresh_pending = false,

	deferred_top_refresh = false,
	deferred_bottom_refresh = false,
	deferred_refresh_fn = nil,

	-- When margins change, the old indicator regions must also be invalidated,
	-- otherwise stale text may remain at the previous coordinates.
	extra_top_refresh_region = nil,
	extra_bottom_refresh_region = nil,
})

-- ============================================================================
-- Small utilities
-- ============================================================================

local function safe_call(fn, fallback)
	local ok, result = pcall(fn)
	if ok and result ~= nil then
		return result
	end
	return fallback
end

local function clamp(value, min_value, max_value)
	value = tonumber(value) or min_value
	value = math.floor(value)

	if value < min_value then
		return min_value
	elseif value > max_value then
		return max_value
	end

	return value
end

function ReaderHeaderFooter:isEnabled()
	return self.enabled ~= false
end

function ReaderHeaderFooter:showsWifi()
	return self.show_wifi ~= false
end

function ReaderHeaderFooter:showsClock()
	return self.show_clock ~= false
end

function ReaderHeaderFooter:showsBatteryStatus()
	return self.show_battery_status ~= false
end

function ReaderHeaderFooter:showsBatteryPercentage()
	return self.show_battery_percentage ~= false
end

function ReaderHeaderFooter:showsFooterLeft()
	return self.show_footer_left ~= false
end

function ReaderHeaderFooter:showsReadPercentage()
	return self.show_read_percentage ~= false
end

function ReaderHeaderFooter:hasRightTopIndicatorsEnabled()
	return self:showsWifi() or self:showsClock() or self:showsBatteryStatus()
end

function ReaderHeaderFooter:hasReaderContext()
	return self.ui and self.ui.document and self.ui.view and self.ui.view.dialog
end

-- ============================================================================
-- Settings
-- ============================================================================

function ReaderHeaderFooter:normalizeFontSize(value)
	return clamp(value or FONT.default_size, FONT.min_size, FONT.max_size)
end

function ReaderHeaderFooter:loadSettings()
	local saved_enabled = G_reader_settings:readSetting(SETTINGS.enabled)
	self.enabled = saved_enabled ~= false

	local saved_font_size = G_reader_settings:readSetting(SETTINGS.font_size)
	self.font_size = self:normalizeFontSize(saved_font_size or FONT.default_size)
	self.refresh_region_font_size = self.font_size

	local saved_show_wifi = G_reader_settings:readSetting(SETTINGS.show_wifi)
	self.show_wifi = saved_show_wifi ~= false

	local saved_show_clock = G_reader_settings:readSetting(SETTINGS.show_clock)
	self.show_clock = saved_show_clock ~= false

	local saved_show_battery_status = G_reader_settings:readSetting(SETTINGS.show_battery_status)
	self.show_battery_status = saved_show_battery_status ~= false

	local saved_show_battery_percentage = G_reader_settings:readSetting(SETTINGS.show_battery_percentage)
	self.show_battery_percentage = saved_show_battery_percentage ~= false

	local saved_show_footer_left = G_reader_settings:readSetting(SETTINGS.show_footer_left)
	self.show_footer_left = saved_show_footer_left ~= false

	local saved_show_read_percentage = G_reader_settings:readSetting(SETTINGS.show_read_percentage)
	self.show_read_percentage = saved_show_read_percentage ~= false

	local saved_follow_document_margins = G_reader_settings:readSetting(SETTINGS.follow_document_margins)
	self.follow_document_margins = saved_follow_document_margins ~= false

	local saved_left_margin = G_reader_settings:readSetting(SETTINGS.custom_left_margin)
	local saved_right_margin = G_reader_settings:readSetting(SETTINGS.custom_right_margin)
	local saved_horizontal_margin = G_reader_settings:readSetting(SETTINGS.custom_horizontal_margin)

	self.custom_left_margin = self:normalizeIndicatorMargin(saved_left_margin or INDICATOR_MARGINS.default_left)
	self.custom_right_margin = self:normalizeIndicatorMargin(saved_right_margin or INDICATOR_MARGINS.default_right)

	-- This value feeds the “both margins” menu item. It is intentionally
	-- independent from left/right so the menu can remember the last common
	-- margin used, even after fine-tuning only one side later.
	self.custom_horizontal_margin = self:normalizeIndicatorMargin(
		saved_horizontal_margin or self.custom_left_margin or INDICATOR_MARGINS.default_left
	)

	local saved_footer_left_mode = G_reader_settings:readSetting(SETTINGS.footer_left_mode_setting_key)

	if saved_footer_left_mode == "book" then
		self.footer_left_mode = "book"
	else
		self.footer_left_mode = "chapter"
	end
end

function ReaderHeaderFooter:saveEnabled()
	G_reader_settings:saveSetting(SETTINGS.enabled, self.enabled)
end

function ReaderHeaderFooter:saveFontSize()
	G_reader_settings:saveSetting(SETTINGS.font_size, self.font_size)
end

function ReaderHeaderFooter:refreshFontFace()
	self.font_face = Font:getFace(FONT.name, self.font_size)
end

function ReaderHeaderFooter:setFontSize(font_size)
	local old_font_size = self.font_size
	local new_font_size = self:normalizeFontSize(font_size)

	if old_font_size == new_font_size then
		return
	end

	self.font_size = new_font_size
	self.refresh_region_font_size = math.max(old_font_size, new_font_size)

	self:saveFontSize()
	self:refreshFontFace()
end

function ReaderHeaderFooter:resetFontSize()
	self:setFontSize(FONT.default_size)
	G_reader_settings:delSetting(SETTINGS.font_size)
end

function ReaderHeaderFooter:setShowWifi(enabled)
	local new_value = enabled == true

	if self.show_wifi == new_value then
		return
	end

	self.show_wifi = new_value
	G_reader_settings:saveSetting(SETTINGS.show_wifi, self.show_wifi)
end

function ReaderHeaderFooter:toggleShowWifi()
	self:setShowWifi(not self:showsWifi())
end

function ReaderHeaderFooter:setShowClock(enabled)
	local new_value = enabled == true

	if self.show_clock == new_value then
		return
	end

	self.show_clock = new_value
	G_reader_settings:saveSetting(SETTINGS.show_clock, self.show_clock)
	self:refreshIndicatorWatchers()
end

function ReaderHeaderFooter:toggleShowClock()
	self:setShowClock(not self:showsClock())
end

function ReaderHeaderFooter:setShowBatteryStatus(enabled)
	local new_value = enabled == true

	if self.show_battery_status == new_value then
		return
	end

	self.show_battery_status = new_value
	G_reader_settings:saveSetting(SETTINGS.show_battery_status, self.show_battery_status)
	self:refreshIndicatorWatchers()
end

function ReaderHeaderFooter:toggleShowBatteryStatus()
	self:setShowBatteryStatus(not self:showsBatteryStatus())
end

function ReaderHeaderFooter:setShowBatteryPercentage(enabled)
	local new_value = enabled == true

	if self.show_battery_percentage == new_value then
		return
	end

	self.show_battery_percentage = new_value
	G_reader_settings:saveSetting(SETTINGS.show_battery_percentage, self.show_battery_percentage)
	self:refreshIndicatorWatchers()
end

function ReaderHeaderFooter:toggleShowBatteryPercentage()
	self:setShowBatteryPercentage(not self:showsBatteryPercentage())
end

function ReaderHeaderFooter:setShowFooterLeft(enabled)
	local new_value = enabled == true

	if self.show_footer_left == new_value then
		return
	end

	self.show_footer_left = new_value
	G_reader_settings:saveSetting(SETTINGS.show_footer_left, self.show_footer_left)
end

function ReaderHeaderFooter:toggleShowFooterLeft()
	self:setShowFooterLeft(not self:showsFooterLeft())
end

function ReaderHeaderFooter:setShowReadPercentage(enabled)
	local new_value = enabled == true

	if self.show_read_percentage == new_value then
		return
	end

	self.show_read_percentage = new_value
	G_reader_settings:saveSetting(SETTINGS.show_read_percentage, self.show_read_percentage)
end

function ReaderHeaderFooter:toggleShowReadPercentage()
	self:setShowReadPercentage(not self:showsReadPercentage())
end

function ReaderHeaderFooter:normalizeIndicatorMargin(value)
	return clamp(value or INDICATOR_MARGINS.default_left, INDICATOR_MARGINS.min, INDICATOR_MARGINS.max)
end

function ReaderHeaderFooter:usesDocumentMargins()
	return self.follow_document_margins ~= false
end

function ReaderHeaderFooter:rememberIndicatorRegionsForCleanup()
	if not self:hasReaderContext() then
		return
	end

	self.extra_top_refresh_region, self.extra_bottom_refresh_region = self:getIndicatorRefreshRegions()
end

function ReaderHeaderFooter:setFollowDocumentMargins(enabled)
	local new_value = enabled == true

	if self.follow_document_margins == new_value then
		return
	end

	self:rememberIndicatorRegionsForCleanup()
	self.follow_document_margins = new_value
	G_reader_settings:saveSetting(SETTINGS.follow_document_margins, self.follow_document_margins)
end

function ReaderHeaderFooter:setCustomIndicatorMargin(side, value)
	local new_value = self:normalizeIndicatorMargin(value)

	self:rememberIndicatorRegionsForCleanup()

	if side == "left" then
		if self.custom_left_margin == new_value then
			return
		end
		self.custom_left_margin = new_value
		G_reader_settings:saveSetting(SETTINGS.custom_left_margin, self.custom_left_margin)
	elseif side == "right" then
		if self.custom_right_margin == new_value then
			return
		end
		self.custom_right_margin = new_value
		G_reader_settings:saveSetting(SETTINGS.custom_right_margin, self.custom_right_margin)
	end
end

function ReaderHeaderFooter:setCustomHorizontalMargin(value)
	local new_value = self:normalizeIndicatorMargin(value)

	if
		self.custom_left_margin == new_value
		and self.custom_right_margin == new_value
		and self.custom_horizontal_margin == new_value
	then
		return
	end

	-- Capture the old top/bottom regions before moving both sides, so a
	-- regional refresh also clears stale text at the previous coordinates.
	self:rememberIndicatorRegionsForCleanup()

	self.custom_horizontal_margin = new_value
	self.custom_left_margin = new_value
	self.custom_right_margin = new_value

	G_reader_settings:saveSetting(SETTINGS.custom_horizontal_margin, self.custom_horizontal_margin)
	G_reader_settings:saveSetting(SETTINGS.custom_left_margin, self.custom_left_margin)
	G_reader_settings:saveSetting(SETTINGS.custom_right_margin, self.custom_right_margin)
end

function ReaderHeaderFooter:setEnabled(enabled)
	local old_enabled = self:isEnabled()
	self.enabled = enabled == true
	self:saveEnabled()

	if self:isEnabled() then
		self:rememberCurrentIndicatorState()
		self:refreshIndicatorWatchers()
	else
		self:stopIndicatorWatchers()
		self:stopDeferredRefreshCheck()
	end

	-- Redraw the indicator regions after the menu/dialog closes. When disabling,
	-- this clears the old overlay; when enabling, it draws it again.
	if old_enabled ~= self:isEnabled() then
		UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
			self:requestAllIndicatorRefresh()
		end)
	end
end

function ReaderHeaderFooter:toggleEnabled()
	self:setEnabled(not self:isEnabled())
end

function ReaderHeaderFooter:setFooterLeftMode(mode)
	if mode ~= "book" then
		mode = "chapter"
	end

	if self.footer_left_mode == mode then
		return
	end

	self.footer_left_mode = mode
	G_reader_settings:saveSetting(SETTINGS.footer_left_mode_setting_key, self.footer_left_mode)
end

function ReaderHeaderFooter:toggleFooterLeftMode()
	if self.footer_left_mode == "chapter" then
		self:setFooterLeftMode("book")
	else
		self:setFooterLeftMode("chapter")
	end
end

-- ============================================================================
-- Menu
-- ============================================================================

function ReaderHeaderFooter:registerMenu()
	if self.menu_registered then
		logger.dbg(PLUGIN_NAME .. ": menu already registered")
		return
	end

	if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
		logger.dbg(PLUGIN_NAME .. ": registering reader menu")
		self.ui.menu:registerToMainMenu(self)
		self.menu_registered = true
	else
		-- This may happen during init(); onReaderReady() will try again.
		logger.dbg(PLUGIN_NAME .. ": reader menu not available yet")
	end
end

function ReaderHeaderFooter:addToMainMenu(menu_items)
	menu_items.reader_header_footer = {
		text = _("Header/footer indicators"),
		sorting_hint = "tools",
		sub_item_table = {
			{
				text_func = function()
					return self:isEnabled() and _("Show header/footer") or _("Show header/footer")
				end,

				checked_func = function()
					return self:isEnabled()
				end,

				callback = function(touchmenu_instance)
					self:toggleEnabled()

					if touchmenu_instance and touchmenu_instance.updateItems then
						touchmenu_instance:updateItems()
					end
				end,
			},

			{
				text = _("Displayed items"),

				-- Keep submenu visible, but disabled when the plugin is off.
				enabled_func = function()
					return self:isEnabled()
				end,

				sub_item_table = {
					{
						text = _("Wi-Fi status"),

						checked_func = function()
							return self:showsWifi()
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() then
								return
							end

							self:toggleShowWifi()

							if touchmenu_instance and touchmenu_instance.updateItems then
								touchmenu_instance:updateItems()
							end

							UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
								self:requestTopIndicatorRefresh()
							end)
						end,
					},

					{
						text = _("Clock"),

						checked_func = function()
							return self:showsClock()
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() then
								return
							end

							self:toggleShowClock()

							if touchmenu_instance and touchmenu_instance.updateItems then
								touchmenu_instance:updateItems()
							end

							UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
								self:requestTopIndicatorRefresh()
							end)
						end,
					},

					{
						text = _("Battery status"),

						enabled_func = function()
							return self:isEnabled() and Device:hasBattery()
						end,

						checked_func = function()
							return self:showsBatteryStatus()
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() or not Device:hasBattery() then
								return
							end

							self:toggleShowBatteryStatus()

							if touchmenu_instance and touchmenu_instance.updateItems then
								touchmenu_instance:updateItems()
							end

							UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
								self:requestTopIndicatorRefresh()
							end)
						end,
					},

					{
						text = _("Battery percentage"),

						enabled_func = function()
							return self:isEnabled() and Device:hasBattery() and self:showsBatteryStatus()
						end,

						checked_func = function()
							return self:showsBatteryPercentage()
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() or not Device:hasBattery() or not self:showsBatteryStatus() then
								return
							end

							self:toggleShowBatteryPercentage()

							if touchmenu_instance and touchmenu_instance.updateItems then
								touchmenu_instance:updateItems()
							end

							UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
								self:requestTopIndicatorRefresh()
							end)
						end,
					},

					{
						text = _("Bottom-left pages left"),

						checked_func = function()
							return self:showsFooterLeft()
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() then
								return
							end

							self:toggleShowFooterLeft()

							if touchmenu_instance and touchmenu_instance.updateItems then
								touchmenu_instance:updateItems()
							end

							UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
								self:requestBottomIndicatorRefresh()
							end)
						end,
					},

					{
						text = _("Reading percentage"),

						checked_func = function()
							return self:showsReadPercentage()
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() then
								return
							end

							self:toggleShowReadPercentage()

							if touchmenu_instance and touchmenu_instance.updateItems then
								touchmenu_instance:updateItems()
							end

							UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
								self:requestBottomIndicatorRefresh()
							end)
						end,
					},
				},
			},

			{
				text_func = function()
					if self.footer_left_mode == "book" then
						return _("Bottom-left info: pages left in book")
					end

					return _("Bottom-left info: pages left in chapter")
				end,

				-- Keep visible but disabled when the bottom-left footer is hidden.
				enabled_func = function()
					return self:isEnabled() and self:showsFooterLeft()
				end,

				callback = function(touchmenu_instance)
					if not self:isEnabled() or not self:showsFooterLeft() then
						return
					end

					self:toggleFooterLeftMode()

					if touchmenu_instance and touchmenu_instance.updateItems then
						touchmenu_instance:updateItems()
					end

					UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
						self:requestBottomIndicatorRefresh()
					end)
				end,
			},

			{
				text = _("Font"),

				-- Keep submenu visible, but disabled when the plugin is off.
				enabled_func = function()
					return self:isEnabled()
				end,

				sub_item_table = {
					{
						text_func = function()
							return string.format(_("Font size: %d"), self.font_size)
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() then
								return
							end

							local widget = SpinWidget:new({
								title_text = _("Header/footer font size"),
								value = self.font_size,
								value_min = FONT.min_size,
								value_max = FONT.max_size,
								default_value = FONT.default_size,
								keep_shown_on_apply = false,

								callback = function(spin)
									self:setFontSize(spin.value)

									if touchmenu_instance and touchmenu_instance.updateItems then
										touchmenu_instance:updateItems()
									end

									-- Let the spin dialog close first; otherwise the regional
									-- refresh could be deferred by the menu protection logic.
									UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
										self:requestAllIndicatorRefresh()
									end)
								end,
							})

							UIManager:show(widget)
						end,
					},

					{
						text = _("Reset font size"),

						callback = function(touchmenu_instance)
							if not self:isEnabled() then
								return
							end

							self:resetFontSize()

							if touchmenu_instance and touchmenu_instance.updateItems then
								touchmenu_instance:updateItems()
							end

							UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
								self:requestAllIndicatorRefresh()
							end)
						end,
					},
				},
			},

			{
				text = _("Margins"),

				-- Keep submenu visible, but disabled when the plugin is off.
				enabled_func = function()
					return self:isEnabled()
				end,

				sub_item_table = {
					{
						text = _("Follow document margins"),

						checked_func = function()
							return self:usesDocumentMargins()
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() then
								return
							end

							self:setFollowDocumentMargins(not self:usesDocumentMargins())

							if touchmenu_instance and touchmenu_instance.updateItems then
								touchmenu_instance:updateItems()
							end

							UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
								self:requestAllIndicatorRefresh()
							end)
						end,
					},

					{
						text_func = function()
							return string.format(_("Custom side margins: %d"), self.custom_horizontal_margin)
						end,

						-- Applies the same custom margin to both sides. Like the
						-- individual controls, it is only meaningful in manual mode.
						enabled_func = function()
							return self:isEnabled() and not self:usesDocumentMargins()
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() or self:usesDocumentMargins() then
								return
							end

							local widget = SpinWidget:new({
								title_text = _("Custom side indicator margins"),
								value = self.custom_horizontal_margin,
								value_min = INDICATOR_MARGINS.min,
								value_max = INDICATOR_MARGINS.max,
								default_value = INDICATOR_MARGINS.default_left,
								keep_shown_on_apply = false,

								callback = function(spin)
									self:setCustomHorizontalMargin(spin.value)

									if touchmenu_instance and touchmenu_instance.updateItems then
										touchmenu_instance:updateItems()
									end

									UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
										self:requestAllIndicatorRefresh()
									end)
								end,
							})

							UIManager:show(widget)
						end,
					},

					{
						text_func = function()
							return string.format(_("Custom left margin: %d"), self.custom_left_margin)
						end,

						-- Custom margins only apply when the document-margin checkbox is off.
						enabled_func = function()
							return self:isEnabled() and not self:usesDocumentMargins()
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() or self:usesDocumentMargins() then
								return
							end

							local widget = SpinWidget:new({
								title_text = _("Custom left indicator margin"),
								value = self.custom_left_margin,
								value_min = INDICATOR_MARGINS.min,
								value_max = INDICATOR_MARGINS.max,
								default_value = INDICATOR_MARGINS.default_left,
								keep_shown_on_apply = false,

								callback = function(spin)
									self:setCustomIndicatorMargin("left", spin.value)

									if touchmenu_instance and touchmenu_instance.updateItems then
										touchmenu_instance:updateItems()
									end

									UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
										self:requestAllIndicatorRefresh()
									end)
								end,
							})

							UIManager:show(widget)
						end,
					},

					{
						text_func = function()
							return string.format(_("Custom right margin: %d"), self.custom_right_margin)
						end,

						enabled_func = function()
							return self:isEnabled() and not self:usesDocumentMargins()
						end,

						callback = function(touchmenu_instance)
							if not self:isEnabled() or self:usesDocumentMargins() then
								return
							end

							local widget = SpinWidget:new({
								title_text = _("Custom right indicator margin"),
								value = self.custom_right_margin,
								value_min = INDICATOR_MARGINS.min,
								value_max = INDICATOR_MARGINS.max,
								default_value = INDICATOR_MARGINS.default_right,
								keep_shown_on_apply = false,

								callback = function(spin)
									self:setCustomIndicatorMargin("right", spin.value)

									if touchmenu_instance and touchmenu_instance.updateItems then
										touchmenu_instance:updateItems()
									end

									UIManager:scheduleIn(REFRESH.after_dialog_close_delay, function()
										self:requestAllIndicatorRefresh()
									end)
								end,
							})

							UIManager:show(widget)
						end,
					},
				},
			},

			{
				text_func = function()
					return string.format(_("Version: %s"), PLUGIN_VERSION)
				end,

				callback = function()
					UIManager:show(InfoMessage:new({
						text = string.format(_("Reader Header/Footer\nVersion: %s"), PLUGIN_VERSION),
					}))
				end,
			},
		},
	}
end

-- ============================================================================
-- Refresh scheduling and menu-overlay protection
-- ============================================================================

function ReaderHeaderFooter:getReaderWindowWidget()
	if self.ui and self.ui.view and self.ui.view.dialog then
		return self.ui.view.dialog
	end
	return nil
end

function ReaderHeaderFooter:isReaderWindowOnTop()
	local reader_widget = self:getReaderWindowWidget()
	if not reader_widget then
		return false
	end

	return UIManager:getTopmostVisibleWidget() == reader_widget
end

function ReaderHeaderFooter:hasDeferredIndicatorRefresh()
	return self.deferred_top_refresh or self.deferred_bottom_refresh
end

function ReaderHeaderFooter:deferIndicatorRefresh(which)
	if which == "top" then
		self.deferred_top_refresh = true
	elseif which == "bottom" then
		self.deferred_bottom_refresh = true
	elseif which == "all" then
		self.deferred_top_refresh = true
		self.deferred_bottom_refresh = true
	end

	self:scheduleDeferredRefreshCheck()
end

function ReaderHeaderFooter:scheduleDeferredRefreshCheck()
	if self.deferred_refresh_fn or not self:hasDeferredIndicatorRefresh() then
		return
	end

	self.deferred_refresh_fn = function()
		self.deferred_refresh_fn = nil

		if not self:hasDeferredIndicatorRefresh() then
			return
		end

		if not self.ui or not self.ui.document then
			self.deferred_top_refresh = false
			self.deferred_bottom_refresh = false
			return
		end

		-- Do not repaint the reader while a KOReader menu/dialog is on top.
		if not self:isReaderWindowOnTop() then
			self:scheduleDeferredRefreshCheck()
			return
		end

		local refresh_top = self.deferred_top_refresh
		local refresh_bottom = self.deferred_bottom_refresh

		self.deferred_top_refresh = false
		self.deferred_bottom_refresh = false

		if refresh_top then
			self:requestTopIndicatorRefresh()
		end

		if refresh_bottom then
			self:requestBottomIndicatorRefresh()
		end
	end

	-- This check does not repaint anything; it only waits for menus to close.
	UIManager:scheduleIn(REFRESH.deferred_menu_check_interval, self.deferred_refresh_fn)
end

function ReaderHeaderFooter:stopDeferredRefreshCheck()
	if self.deferred_refresh_fn then
		UIManager:unschedule(self.deferred_refresh_fn)
		self.deferred_refresh_fn = nil
	end

	self.deferred_top_refresh = false
	self.deferred_bottom_refresh = false
end

function ReaderHeaderFooter:requestRegionRefresh(region)
	if not self:hasReaderContext() then
		return
	end

	-- "ui" is preferable for small UI overlays; it avoids heavier page refreshes.
	UIManager:setDirty(self.ui.view.dialog, "ui", region)
end

function ReaderHeaderFooter:requestTopIndicatorRefresh()
	if self.top_refresh_pending then
		return
	end

	self.top_refresh_pending = true

	UIManager:nextTick(function()
		self.top_refresh_pending = false

		if not self:hasReaderContext() then
			return
		end

		if not self:isReaderWindowOnTop() then
			self:deferIndicatorRefresh("top")
			return
		end

		local extra_region = self.extra_top_refresh_region
		self.extra_top_refresh_region = nil

		if extra_region then
			self:requestRegionRefresh(extra_region)
		end

		local top_region = self:getIndicatorRefreshRegions()
		self:requestRegionRefresh(top_region)
	end)
end

function ReaderHeaderFooter:requestBottomIndicatorRefresh()
	if self.bottom_refresh_pending then
		return
	end

	self.bottom_refresh_pending = true

	UIManager:nextTick(function()
		self.bottom_refresh_pending = false

		if not self:hasReaderContext() then
			return
		end

		if not self:isReaderWindowOnTop() then
			self:deferIndicatorRefresh("bottom")
			return
		end

		local extra_region = self.extra_bottom_refresh_region
		self.extra_bottom_refresh_region = nil

		if extra_region then
			self:requestRegionRefresh(extra_region)
		end

		local _, bottom_region = self:getIndicatorRefreshRegions()
		self:requestRegionRefresh(bottom_region)
	end)
end

function ReaderHeaderFooter:requestAllIndicatorRefresh()
	self:requestTopIndicatorRefresh()
	self:requestBottomIndicatorRefresh()
end

-- ============================================================================
-- Device indicators and watchers
-- ============================================================================

function ReaderHeaderFooter:getWifiState()
	return safe_call(function()
		return NetworkMgr:isWifiOn()
	end, false)
end

function ReaderHeaderFooter:getPowerSnapshot()
	if not Device:hasBattery() then
		return { level = nil, charging = false }
	end

	local powerd = Device:getPowerDevice()
	if not powerd then
		return { level = nil, charging = false }
	end

	return {
		level = safe_call(function()
			return powerd:getCapacity()
		end, nil),

		charging = safe_call(function()
			return powerd:isCharging()
		end, false),
	}
end

function ReaderHeaderFooter:rememberCurrentIndicatorState()
	local power = self:getPowerSnapshot()

	self.last_wifi_on = self:getWifiState()
	self.last_battery_level = power.level
	self.last_charging = power.charging
end

function ReaderHeaderFooter:shouldWatchClock()
	return self:isEnabled() and self:showsClock()
end

function ReaderHeaderFooter:shouldWatchBattery()
	return self:isEnabled() and Device:hasBattery() and self:showsBatteryStatus()
end

function ReaderHeaderFooter:refreshIndicatorWatchers()
	if self:shouldWatchClock() then
		self:startClockWatcher()
	else
		self:stopClockWatcher()
	end

	if self:shouldWatchBattery() then
		self:startBatteryWatcher()
	else
		self:stopBatteryWatcher()
	end
end

function ReaderHeaderFooter:stopIndicatorWatchers()
	self:stopClockWatcher()
	self:stopBatteryWatcher()
end

function ReaderHeaderFooter:startClockWatcher()
	if self.clock_refresh_fn or not self:shouldWatchClock() then
		return
	end

	self.clock_refresh_fn = function()
		self.clock_refresh_fn = nil

		if not self.ui or not self.ui.document or not self:shouldWatchClock() then
			return
		end

		self:requestTopIndicatorRefresh()
		self:startClockWatcher()
	end

	-- Align refresh to the next minute, because the clock displays HH:MM only.
	local seconds_now = tonumber(os.date("%S")) or 0
	local delay = 60 - seconds_now
	if delay <= 0 then
		delay = 60
	end

	UIManager:scheduleIn(delay, self.clock_refresh_fn)
end

function ReaderHeaderFooter:stopClockWatcher()
	if self.clock_refresh_fn then
		UIManager:unschedule(self.clock_refresh_fn)
		self.clock_refresh_fn = nil
	end
end

function ReaderHeaderFooter:startBatteryWatcher()
	if self.battery_check_fn or not self:shouldWatchBattery() then
		return
	end

	self.battery_check_fn = function()
		self.battery_check_fn = nil

		if not self.ui or not self.ui.document or not self:shouldWatchBattery() then
			return
		end

		local power = self:getPowerSnapshot()

		if power.level ~= self.last_battery_level or power.charging ~= self.last_charging then
			self.last_battery_level = power.level
			self.last_charging = power.charging
			self:requestTopIndicatorRefresh()
		end

		self:startBatteryWatcher()
	end

	UIManager:scheduleIn(REFRESH.battery_check_interval, self.battery_check_fn)
end

function ReaderHeaderFooter:stopBatteryWatcher()
	if self.battery_check_fn then
		UIManager:unschedule(self.battery_check_fn)
		self.battery_check_fn = nil
	end
end

function ReaderHeaderFooter:onNetworkConnected()
	if not self:isEnabled() or not self:showsWifi() then
		return
	end

	local wifi_on = self:getWifiState()
	if wifi_on ~= self.last_wifi_on then
		self.last_wifi_on = wifi_on
		self:requestTopIndicatorRefresh()
	end
end

function ReaderHeaderFooter:onNetworkDisconnected()
	if not self:isEnabled() or not self:showsWifi() then
		return
	end

	local wifi_on = self:getWifiState()
	if wifi_on ~= self.last_wifi_on then
		self.last_wifi_on = wifi_on
		self:requestTopIndicatorRefresh()
	end
end

function ReaderHeaderFooter:onCharging()
	if not self:isEnabled() or not self:showsBatteryStatus() then
		return
	end

	local power = self:getPowerSnapshot()
	self.last_battery_level = power.level
	self.last_charging = power.charging

	self:requestTopIndicatorRefresh()
end

function ReaderHeaderFooter:onNotCharging()
	if not self:isEnabled() or not self:showsBatteryStatus() then
		return
	end

	local power = self:getPowerSnapshot()
	self.last_battery_level = power.level
	self.last_charging = power.charging

	self:requestTopIndicatorRefresh()
end

-- ============================================================================
-- Reader lifecycle events
-- ============================================================================

function ReaderHeaderFooter:init()
	self:loadSettings()
	self:refreshFontFace()

	if self.ui and self.ui.view and self.ui.view.registerViewModule then
		self.ui.view:registerViewModule(self.name, self)
	end

	-- self.ui.menu may not be ready yet; onReaderReady() retries this.
	self:registerMenu()
end

function ReaderHeaderFooter:onReaderReady()
	self:registerMenu()

	if self.ui and self.ui.document then
		self.pages = safe_call(function()
			return self.ui.document:getPageCount()
		end, nil)
	end

	if self.ui and self.ui.view and self.ui.view.state then
		self.pageno = self.ui.view.state.page
	end

	self:rememberCurrentIndicatorState()

	self:refreshIndicatorWatchers()
end

function ReaderHeaderFooter:onCloseDocument()
	self:stopIndicatorWatchers()
	self:stopDeferredRefreshCheck()
end

function ReaderHeaderFooter:onSuspend()
	self:stopIndicatorWatchers()
	self:stopDeferredRefreshCheck()
end

function ReaderHeaderFooter:onResume()
	if not self:isEnabled() then
		self:stopIndicatorWatchers()
		self:stopDeferredRefreshCheck()
		return
	end

	local old_wifi = self.last_wifi_on
	local old_battery = self.last_battery_level
	local old_charging = self.last_charging

	local power = self:getPowerSnapshot()

	self.last_wifi_on = self:getWifiState()
	self.last_battery_level = power.level
	self.last_charging = power.charging

	local battery_changed = old_battery ~= self.last_battery_level or old_charging ~= self.last_charging

	if
		(not self:hasRightTopIndicatorsEnabled())
		or (self:showsWifi() and old_wifi ~= self.last_wifi_on)
		or self:showsClock()
		or (self:showsBatteryStatus() and battery_changed)
	then
		self:requestTopIndicatorRefresh()
	end

	self:refreshIndicatorWatchers()

	if self:hasDeferredIndicatorRefresh() then
		self:scheduleDeferredRefreshCheck()
	end
end

function ReaderHeaderFooter:onPageUpdate(pageno)
	self.pageno = pageno

	if self:isEnabled() then
		self:requestAllIndicatorRefresh()
	end
end

function ReaderHeaderFooter:onPosUpdate(_, pageno)
	if pageno then
		self.pageno = pageno

		if self:isEnabled() then
			self:requestAllIndicatorRefresh()
		end
	end
end

function ReaderHeaderFooter:onViewRecalculate(visible_area, page_area)
	self.visible_area = visible_area and visible_area:copy() or nil
	self.page_area = page_area and page_area:copy() or nil
end

function ReaderHeaderFooter:onSetDimensions()
	-- Kept for layout recalculations/rotation; no explicit work is required here.
end

-- ============================================================================
-- Document metadata/progress helpers
-- ============================================================================

function ReaderHeaderFooter:getLeftBottomStatus()
	if self.footer_left_mode == "book" then
		return string.format("%d pages left in book", self:getPagesLeftInBook())
	end

	return string.format("%d pages left in chapter", self:getPagesLeftInChapter())
end

function ReaderHeaderFooter:getCurrentPage()
	if self.pageno then
		return self.pageno
	end

	if self.ui and self.ui.view and self.ui.view.state then
		return self.ui.view.state.page
	end

	if self.ui and self.ui.document then
		return safe_call(function()
			return self.ui.document:getCurrentPage()
		end, 1)
	end

	return 1
end

function ReaderHeaderFooter:getPageCount()
	if self.pages then
		return self.pages
	end

	if self.ui and self.ui.document then
		self.pages = safe_call(function()
			return self.ui.document:getPageCount()
		end, nil)
	end

	return self.pages
end

function ReaderHeaderFooter:getTitle()
	if self.ui and self.ui.doc_props then
		return self.ui.doc_props.display_title or self.ui.doc_props.title or _("Document")
	end

	return _("Document")
end

function ReaderHeaderFooter:getAuthor()
	if self.ui and self.ui.doc_props then
		local authors = self.ui.doc_props.authors or self.ui.doc_props.author

		if type(authors) == "table" then
			return table.concat(authors, ", ")
		end

		return authors or _("Unknown")
	end

	return _("Unknown")
end

function ReaderHeaderFooter:getPrimaryAuthor()
	local author = self:getAuthor()

	if not author or author == "" or author == _("Unknown") then
		return ""
	end

	-- KOReader metadata may expose multiple authors as a comma/semicolon list.
	-- The fallback header only needs the primary author to stay compact.
	local primary = author:match("^%s*([^,;&]+)") or author
	primary = primary:gsub("%s+$", "")

	return primary
end

function ReaderHeaderFooter:getBookTitleWithPrimaryAuthor()
	local title = self:getTitle()
	local author = self:getPrimaryAuthor()

	if author == "" then
		return title
	end

	return string.format("%s - %s", author, title)
end

function ReaderHeaderFooter:getChapterTitle(pageno)
	if not self.ui or not self.ui.toc then
		return ""
	end

	return safe_call(function()
		return self.ui.toc:getTocTitleByPage(pageno)
	end, "") or ""
end

function ReaderHeaderFooter:getChapterSubtitle(pageno)
	if not self.ui or not self.ui.toc then
		return ""
	end

	local subtitle = safe_call(function()
		if self.ui.toc.getTocSubtitleByPage then
			return self.ui.toc:getTocSubtitleByPage(pageno)
		end
	end, "") or ""

	if subtitle ~= "" then
		return subtitle
	end

	return safe_call(function()
		if self.ui.toc.getTocSubTitleByPage then
			return self.ui.toc:getTocSubTitleByPage(pageno)
		end
	end, "") or ""
end

function ReaderHeaderFooter:getChapterSubtitleStatus()
	local pageno = self:getCurrentPage()
	local title = self:getChapterTitle(pageno)
	local subtitle = self:getChapterSubtitle(pageno)

	if title == "" then
		return subtitle
	end

	if subtitle == "" or subtitle == title then
		return title
	end

	return string.format("%s - %s", title, subtitle)
end

function ReaderHeaderFooter:isChapterStart(pageno)
	if not self.ui or not self.ui.toc or not pageno then
		return false
	end

	-- Preferred path: KOReader tells how many pages were already read in chapter.
	local pages_done = safe_call(function()
		return self.ui.toc:getChapterPagesDone(pageno)
	end, nil)

	if pages_done ~= nil then
		return pages_done == 0
	end

	-- Fallback: first page where the chapter title differs from previous page.
	if pageno > 1 then
		local current = self:getChapterTitle(pageno)
		local previous = self:getChapterTitle(pageno - 1)
		return current ~= "" and current ~= previous
	end

	return true
end

function ReaderHeaderFooter:getPagesLeftInBook()
	local pageno = self:getCurrentPage()
	local pages = self:getPageCount()

	if pages and pages > 0 and pageno then
		return math.max(0, pages - pageno)
	end

	if self.ui and self.ui.document then
		return safe_call(function()
			return self.ui.document:getTotalPagesLeft(pageno)
		end, 0)
	end

	return 0
end

function ReaderHeaderFooter:getPagesLeftInChapter()
	local pageno = self:getCurrentPage()

	if self.ui and self.ui.toc then
		local left = safe_call(function()
			return self.ui.toc:getChapterPagesLeft(pageno)
		end, nil)

		if left ~= nil then
			return left
		end
	end

	if self.ui and self.ui.document then
		return safe_call(function()
			return self.ui.document:getTotalPagesLeft(pageno)
		end, 0)
	end

	return 0
end

function ReaderHeaderFooter:getPercentageRead()
	local pageno = self:getCurrentPage()
	local pages = self:getPageCount()

	if pages and pages > 0 then
		return math.min(100, math.max(0, (pageno / pages) * 100))
	end

	return 0
end

-- ============================================================================
-- Indicator text
-- ============================================================================

function ReaderHeaderFooter:getBatteryText()
	if not self:showsBatteryStatus() or not Device:hasBattery() then
		return ""
	end

	local powerd = Device:getPowerDevice()
	if not powerd then
		return ""
	end

	local level = safe_call(function()
		return powerd:getCapacity()
	end, nil)

	if not level then
		return ""
	end

	local charging = safe_call(function()
		return powerd:isCharging()
	end, false)

	local charged = safe_call(function()
		return powerd:isCharged()
	end, false)

	local icon = safe_call(function()
		return powerd:getBatterySymbol(charged, charging, level)
	end, "")

	if self:showsBatteryPercentage() then
		return string.format("%s %d%%", icon, level)
	end

	return icon
end

function ReaderHeaderFooter:getRightTopStatus()
	local pageno = self:getCurrentPage()

	if not self:hasRightTopIndicatorsEnabled() then
		if self:isChapterStart(pageno) then
			return ""
		end

		return self:getChapterSubtitleStatus()
	end

	local items = {}

	if self:showsWifi() and self:getWifiState() then
		table.insert(items, "")
	end

	if self:showsClock() then
		table.insert(items, os.date("%H:%M"))
	end

	local battery = self:getBatteryText()
	if battery ~= "" then
		table.insert(items, battery)
	end

	return table.concat(items, " • ")
end

function ReaderHeaderFooter:getLeftTopStatus()
	local pageno = self:getCurrentPage()

	if not self:hasRightTopIndicatorsEnabled() then
		if self:isChapterStart(pageno) then
			return ""
		end

		return self:getBookTitleWithPrimaryAuthor()
	end

	if self:isChapterStart(pageno) then
		return ""
	end

	if pageno % 2 == 0 then
		return string.format("%s • %s", self:getAuthor(), self:getTitle())
	end

	return self:getChapterTitle(pageno)
end

-- ============================================================================
-- Layout and text rendering
-- ============================================================================

function ReaderHeaderFooter:getContentHorizontalBounds()
	local screen_w = Screen:getWidth()
	local pad = Screen:scaleBySize(LAYOUT.padding)
	local top_pad = Screen:scaleBySize(LAYOUT.top_padding or LAYOUT.padding)
	local bottom_pad = Screen:scaleBySize(LAYOUT.bottom_padding or LAYOUT.padding)

	local left_x = pad
	local right_x = screen_w - pad

	local offset_x = 0
	if self.ui and self.ui.view and self.ui.view.state and self.ui.view.state.offset then
		offset_x = self.ui.view.state.offset.x or 0
	end

	if self:usesDocumentMargins() then
		-- Best case: align with real document margins.
		if self.ui and self.ui.document and self.ui.document.getPageMargins then
			local ok, margins = pcall(function()
				return self.ui.document:getPageMargins()
			end)

			if ok and type(margins) == "table" then
				local left_margin = margins.left or 0
				local right_margin = margins.right or 0

				left_x = math.max(left_x, offset_x + left_margin)
				right_x = math.min(right_x, screen_w - offset_x - right_margin)
			end
		end

		-- Fallback/refinement: also respect the ReaderView visible area when
		-- following document margins. This keeps indicators aligned with the
		-- actual reading area after layout/zoom changes.
		if self.visible_area then
			left_x = math.max(left_x, self.visible_area.x + pad)
			right_x = math.min(right_x, self.visible_area.x + self.visible_area.w - pad)
		end
	else
		-- Manual mode: margins are controlled by the plugin settings and do not
		-- depend on the current book margins.
		left_x = Screen:scaleBySize(self.custom_left_margin)
		right_x = screen_w - Screen:scaleBySize(self.custom_right_margin)
	end

	-- Safety fallback for uncommon layouts or overly large custom margins.
	if right_x <= left_x then
		left_x = pad
		right_x = screen_w - pad
	end

	return left_x, right_x
end

function ReaderHeaderFooter:getIndicatorRefreshRegions()
	local screen_w = Screen:getWidth()
	local screen_h = Screen:getHeight()

	local pad = Screen:scaleBySize(LAYOUT.padding)
	local top_pad = Screen:scaleBySize(LAYOUT.top_padding or LAYOUT.padding)
	local bottom_pad = Screen:scaleBySize(LAYOUT.bottom_padding or LAYOUT.padding)
	local extra = Screen:scaleBySize(LAYOUT.text_clear_extra)

	-- Use the largest recent font size so shrinking text clears old pixels too.
	local region_font_size = self.refresh_region_font_size or self.font_size
	local line_h = Screen:scaleBySize(region_font_size + LAYOUT.line_extra_for_region)

	local left_bound, right_bound = self:getContentHorizontalBounds()
	local region_w = right_bound - left_bound + extra * 2

	local top_region = Geom:new({
		x = math.max(0, left_bound - extra),
		y = math.max(0, top_pad - extra),
		w = math.min(screen_w, region_w),
		h = line_h + extra * 2,
	})

	local bottom_region = Geom:new({
		x = math.max(0, left_bound - extra),
		y = math.max(0, screen_h - line_h - bottom_pad - extra),
		w = math.min(screen_w, region_w),
		h = line_h + extra * 2,
	})

	return top_region, bottom_region
end

function ReaderHeaderFooter:getTextSize(text)
	local widget = TextWidget:new({
		text = text,
		face = self.font_face,
	})

	local size = widget:getSize()
	widget:free()

	return size
end

function ReaderHeaderFooter:fitTextToWidth(text, max_width)
	if not text or text == "" then
		return ""
	end

	if self:getTextSize(text).w <= max_width then
		return text
	end

	local ellipsis = "..."
	local fitted = text

	while #fitted > 1 and self:getTextSize(fitted .. ellipsis).w > max_width do
		fitted = fitted:sub(1, -2)
	end

	return fitted .. ellipsis
end

function ReaderHeaderFooter:drawText(bb, x, y, text)
	if not text or text == "" then
		return
	end

	local widget = TextWidget:new({
		text = text,
		face = self.font_face,
	})

	widget:paintTo(bb, x, y)
	widget:free()
end

function ReaderHeaderFooter:clearTextArea(bb, x, y, width, line_h)
	bb:paintRect(x - 2, y - 1, width + 4, line_h + 2, Blitbuffer.COLOR_WHITE)
end

function ReaderHeaderFooter:paintTo(bb, x, y)
	if not self:isEnabled() then
		return
	end

	if not self.ui or not self.ui.document then
		return
	end

	local screen_h = Screen:getHeight()
	local top_pad = Screen:scaleBySize(LAYOUT.top_padding or LAYOUT.padding)
	local bottom_pad = Screen:scaleBySize(LAYOUT.bottom_padding or LAYOUT.padding)
	local line_h = Screen:scaleBySize(self.font_size + LAYOUT.line_extra_for_paint)

	local left_bound, right_bound = self:getContentHorizontalBounds()
	local usable_w = right_bound - left_bound
	local gap = Screen:scaleBySize(LAYOUT.left_right_gap)

	-- Top left/right: indicators, or book metadata + chapter when no right-side device indicator is enabled.
	local rt_text = self:getRightTopStatus()
	local lt_text = self:getLeftTopStatus()
	local rt_size = { w = 0, h = line_h }

	if rt_text ~= "" then
		local max_right_w = usable_w

		-- When the right side falls back to chapter information, reserve room
		-- for book metadata on the left if it is visible.
		if not self:hasRightTopIndicatorsEnabled() and lt_text ~= "" then
			max_right_w = math.max(40, math.floor(usable_w * 0.5))
		end

		rt_text = self:fitTextToWidth(rt_text, max_right_w)
		rt_size = self:getTextSize(rt_text)

		local rt_x = right_bound - rt_size.w
		local rt_y = top_pad

		self:clearTextArea(bb, rt_x, rt_y, rt_size.w, line_h)
		self:drawText(bb, rt_x, rt_y, rt_text)
	end

	if lt_text ~= "" then
		local max_left_w = usable_w

		if rt_size.w > 0 then
			max_left_w = math.max(40, usable_w - rt_size.w - gap)
		end

		lt_text = self:fitTextToWidth(lt_text, max_left_w)
		local lt_size = self:getTextSize(lt_text)

		self:clearTextArea(bb, left_bound, top_pad, lt_size.w, line_h)
		self:drawText(bb, left_bound, top_pad, lt_text)
	end

	local lb_y = screen_h - line_h - bottom_pad
	local rb_size = { w = 0, h = line_h }

	-- Bottom right: optional read percentage.
	if self:showsReadPercentage() then
		local rb_text = string.format("%d%%", math.floor(self:getPercentageRead()))
		rb_size = self:getTextSize(rb_text)
		local rb_x = right_bound - rb_size.w

		self:clearTextArea(bb, rb_x, lb_y, rb_size.w, line_h)
		self:drawText(bb, rb_x, lb_y, rb_text)
	end

	-- Bottom left: optional pages left in chapter or book.
	if self:showsFooterLeft() then
		local lb_text = self:getLeftBottomStatus()
		local max_left_w = usable_w

		if rb_size.w > 0 then
			max_left_w = math.max(40, usable_w - rb_size.w - gap)
		end

		lb_text = self:fitTextToWidth(lb_text, max_left_w)
		local lb_size = self:getTextSize(lb_text)

		self:clearTextArea(bb, left_bound, lb_y, lb_size.w, line_h)
		self:drawText(bb, left_bound, lb_y, lb_text)
	end
end

return ReaderHeaderFooter
