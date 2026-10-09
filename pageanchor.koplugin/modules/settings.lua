-- Saved settings: getters and setters, and the button metrics for a size.


local C = ...
local lib = select(2, ...)
local scaleMetric = lib.scaleMetric

-- Scaled button geometry per size, shared by every instance.
local BUTTON_METRICS_CACHE = {}

local PageAnchor = {}

-- A display setting changing invalidates the cached button specs (their
-- content or presence depends on it), drops any cached button widgets built
-- from the old content, and repaints the overlay region.
function PageAnchor:_onDisplaySettingChanged()
	-- Where the control was, before dropping the cache that holds it, so
	-- the refresh also clears it from there.
	local before = self.overlay.pill_dimen
	self:invalidateButtonSpecs()
	self.overlay:clearCache()
	self:refresh(nil, before)
end

-- A saved choice among `options` ({value, label} list), or `default` when
-- it's unset or no longer one of them.
local function readOption(setting, options, default)
	local value = G_reader_settings:readSetting(setting)
	for i = 1, #options do
		if options[i].value == value then
			return value
		end
	end
	return default
end

function PageAnchor:isEnabled()
	return G_reader_settings:nilOrTrue(C.SETTING_ENABLED)
end

function PageAnchor:setEnabled(enabled)
	G_reader_settings:saveSetting(C.SETTING_ENABLED, enabled and true or false)
	self:_onDisplaySettingChanged()
end

function PageAnchor:getDestinationFormat()
	return readOption(C.SETTING_DESTINATION_FORMAT, C.DESTINATION_FORMAT_OPTIONS, C.DESTINATION_FORMAT_PAGE_BOOK)
end

function PageAnchor:setDestinationFormat(format)
	G_reader_settings:saveSetting(C.SETTING_DESTINATION_FORMAT, format)
	self:_onDisplaySettingChanged()
end

function PageAnchor:getButtonSize()
	local size = G_reader_settings:readSetting(C.SETTING_BUTTON_SIZE)
	return C.BUTTON_SIZE_FACTORS[size] and size or C.BUTTON_SIZE_SMALL
end

function PageAnchor:setButtonSize(size)
	G_reader_settings:saveSetting(
		C.SETTING_BUTTON_SIZE,
		C.BUTTON_SIZE_FACTORS[size] and size or C.BUTTON_SIZE_SMALL
	)
	self:_onDisplaySettingChanged() -- also drops the pill cached at the old size
end

-- Scaled button geometry for the current size setting. Cached per size (at
-- most 3 entries) since this is read on every paint and hold, not just on
-- a setting change -- mirrors Quick Dock's own getDockMetrics/
-- DOCK_METRICS_CACHE pattern.
function PageAnchor:getButtonMetrics()
	local size = self:getButtonSize()
	local cached = BUTTON_METRICS_CACHE[size]
	if cached then
		return cached
	end
	local factor = C.BUTTON_SIZE_FACTORS[size]
	local height = scaleMetric(C.BASE_BUTTON_HEIGHT, factor)
	local metrics = {
		icon_size = scaleMetric(C.BASE_BUTTON_ICON_SIZE, factor),
		height = height,
		segment_width = height + 2 * scaleMetric(C.BASE_BUTTON_SIDE_PADDING, factor),
		side_padding = scaleMetric(C.BASE_BUTTON_SIDE_PADDING, factor),
		label_font_size = math.floor(C.BASE_INLINE_LABEL_FONT_SIZE * factor + 0.5),
		padding = C.BUTTON_OUTER_PADDING,
		margin = C.BUTTON_MARGIN,
	}
	BUTTON_METRICS_CACHE[size] = metrics
	return metrics
end

function PageAnchor:getAutoDismissSeconds()
	local value = G_reader_settings:readSetting(C.SETTING_AUTO_DISMISS_SECONDS)
	if type(value) == "number" then
		return value
	end
	return C.AUTO_DISMISS_DEFAULT_SECONDS
end

function PageAnchor:setAutoDismissSeconds(seconds)
	G_reader_settings:saveSetting(C.SETTING_AUTO_DISMISS_SECONDS, seconds)
	-- Realign a pending timer to the new duration immediately, rather than
	-- waiting for the next navigation event to pick it up.
	if self.anchor or self.forward_target then
		self:scheduleAutoDismiss()
	end
end

function PageAnchor:getForwardDismissPages()
	local value = G_reader_settings:readSetting(C.SETTING_FORWARD_DISMISS_PAGES)
	if type(value) == "number" then
		return value
	end
	return C.FORWARD_DISMISS_DEFAULT_PAGES
end

function PageAnchor:setForwardDismissPages(pages)
	G_reader_settings:saveSetting(C.SETTING_FORWARD_DISMISS_PAGES, pages)
end

function PageAnchor:getHideMode()
	return readOption(C.SETTING_HIDE_MODE, C.HIDE_MODE_OPTIONS, C.HIDE_MODE_MINIMIZE)
end

function PageAnchor:getInlineLabelMode()
	return readOption(C.SETTING_INLINE_LABEL, C.INLINE_LABEL_OPTIONS, C.INLINE_LABEL_OFF)
end

function PageAnchor:setInlineLabelMode(mode)
	G_reader_settings:saveSetting(C.SETTING_INLINE_LABEL, mode)
	self:_onDisplaySettingChanged()
end

function PageAnchor:getVerticalPosition()
	local value = G_reader_settings:readSetting(C.SETTING_VERTICAL_POSITION)
	return C.VERTICAL_ZONES[value] and value or C.VERTICAL_BOTTOM
end

function PageAnchor:setVerticalPosition(position)
	G_reader_settings:saveSetting(C.SETTING_VERTICAL_POSITION, C.VERTICAL_ZONES[position] and position or C.VERTICAL_BOTTOM)
	if self._installed then
		self:registerOverlayZones()
	end
	self:_onDisplaySettingChanged()
end

function PageAnchor:getRereadTurns()
	local value = G_reader_settings:readSetting(C.SETTING_REREAD_TURNS)
	if type(value) == "number" and value >= 1 then
		return value
	end
	return C.READING_TURNS_BEHIND
end

function PageAnchor:setRereadTurns(turns)
	G_reader_settings:saveSetting(C.SETTING_REREAD_TURNS, turns)
end

function PageAnchor:setHideMode(mode)
	G_reader_settings:saveSetting(C.SETTING_HIDE_MODE, mode == C.HIDE_MODE_HIDE and C.HIDE_MODE_HIDE or C.HIDE_MODE_MINIMIZE)
	self:_onDisplaySettingChanged()
end

function PageAnchor:getHiddenExpirySeconds()
	local value = G_reader_settings:readSetting(C.SETTING_HIDDEN_EXPIRY_SECONDS)
	if type(value) == "number" then
		return value
	end
	return C.HIDDEN_EXPIRY_DEFAULT_SECONDS
end

function PageAnchor:setHiddenExpirySeconds(seconds)
	G_reader_settings:saveSetting(C.SETTING_HIDDEN_EXPIRY_SECONDS, seconds)
	-- Restart a pending countdown with the new duration (or drop it, for
	-- "Never"), rather than waiting for the next hide to pick it up.
	if self:areControlsHidden() then
		self:scheduleHiddenExpiry()
	end
end

return PageAnchor
