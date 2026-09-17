--[[
Page Anchor plugin for KOReader.

Shows floating back/forward buttons after a jump (footnote, internal link,
table of contents, etc.) so you can review another part of the book without
losing your reading position, then return to it with a tap.
]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local LineWidget = require("ui/widget/linewidget")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("pageanchor_l10n")
local T = require("ffi/util").template

local History = require("modules/history")

local Screen = Device.screen

-- ============================================================================
-- Constants
-- ============================================================================

local PLUGIN_VERSION = "v1.7.3"

local SETTING_ENABLED = "pageanchor_enabled"
local SETTING_DESTINATION_FORMAT = "pageanchor_destination_format"
local SETTING_BUTTON_SIZE = "pageanchor_button_size"
local SETTING_AUTO_DISMISS_SECONDS = "pageanchor_auto_dismiss_seconds"
local SETTING_FORWARD_DISMISS_PAGES = "pageanchor_forward_dismiss_pages"

-- Format (page/percentage/text) and scope (book/chapter) used to be two
-- separate settings ("Format" and "Relative to" screens), but scope only
-- ever modified format, so they're one flat, self-describing list now --
-- each option already says both what it shows and what it's measured
-- against, instead of asking the user to combine two screens in their head.
local DESTINATION_FORMAT_PAGE_BOOK = "page_book"
local DESTINATION_FORMAT_PAGE_CHAPTER = "page_chapter"
local DESTINATION_FORMAT_PERCENTAGE_BOOK = "percentage_book"
local DESTINATION_FORMAT_PERCENTAGE_CHAPTER = "percentage_chapter"
local DESTINATION_FORMAT_TEXT_ONLY = "text_only"
local DESTINATION_FORMAT_OPTIONS = {
	{ value = DESTINATION_FORMAT_PAGE_BOOK, label = "Page number of the book" },
	{ value = DESTINATION_FORMAT_PAGE_CHAPTER, label = "Page number in this chapter" },
	{ value = DESTINATION_FORMAT_PERCENTAGE_BOOK, label = "Percentage of the book" },
	{ value = DESTINATION_FORMAT_PERCENTAGE_CHAPTER, label = "Percentage in this chapter" },
	{ value = DESTINATION_FORMAT_TEXT_ONLY, label = "Text only (chapter title)" },
}

-- "value = 0" means "Off" for both: it reads clearly in the menu and avoids
-- a separate nil-vs-zero special case in the getters below.
local AUTO_DISMISS_DEFAULT_SECONDS = 30
local AUTO_DISMISS_OPTIONS = {
	{ value = 0, label = "Off" },
	{ value = 15, label = "15 seconds" },
	{ value = 30, label = "30 seconds" },
	{ value = 60, label = "1 minute" },
	{ value = 120, label = "2 minutes" },
	{ value = 300, label = "5 minutes" },
}

local FORWARD_DISMISS_DEFAULT_PAGES = 1
local FORWARD_DISMISS_PAGE_OPTIONS = {
	{ value = 0, label = "Off" },
	{ value = 1, label = "1 page" },
	{ value = 2, label = "2 pages" },
	{ value = 3, label = "3 pages" },
	{ value = 5, label = "5 pages" },
}

local ACTION_BACK = "back"
local ACTION_FORWARD = "forward"
local ACTION_DISMISS = "dismiss"

local ICON_ANCHOR = "anchor.svg"
local ICON_CHEVRON_LEFT = "chevron-left.svg"
local ICON_CHEVRON_RIGHT = "chevron-right.svg"

-- Three predefined scales, the same factors and naming Quick Dock uses for
-- its own dock-size setting (quickdock.koplugin/main.lua's DOCK_SIZE_*),
-- so the two plugins' size pickers feel like the same control.
local BUTTON_SIZE_SMALL = "small"
local BUTTON_SIZE_MEDIUM = "medium"
local BUTTON_SIZE_LARGE = "large"
local BUTTON_SIZE_FACTORS = {
	[BUTTON_SIZE_SMALL] = 1,
	[BUTTON_SIZE_MEDIUM] = 1.2,
	[BUTTON_SIZE_LARGE] = 1.4,
}
local BUTTON_SIZE_OPTIONS = {
	{ value = BUTTON_SIZE_SMALL, label = "Small" },
	{ value = BUTTON_SIZE_MEDIUM, label = "Medium" },
	{ value = BUTTON_SIZE_LARGE, label = "Large" },
}
local BUTTON_METRICS_CACHE = {}

local function scaleMetric(value, factor, minimum)
	return math.max(minimum or 1, math.floor(value * factor + 0.5))
end

-- Base (Small/1x) button geometry. These three values, and the same
-- BUTTON_SIZE_FACTORS table above, are deliberately identical to Quick
-- Dock's own BASE_BUTTON_ICON_SIZE/BASE_BUTTON_HEIGHT/
-- BASE_BUTTON_SIDE_PADDING and DOCK_SIZE_FACTORS: picking the same named
-- size (e.g. Medium) in both plugins produces the exact same icon size,
-- button height, and per-button width, even though the two plugins never
-- share code for it. The width formula below (height + 2 * side padding)
-- mirrors Quick Dock's own button_width derivation for the same reason.
local BASE_BUTTON_ICON_SIZE = Screen:scaleBySize(22)
local BASE_BUTTON_HEIGHT = Screen:scaleBySize(42)
local BASE_BUTTON_SIDE_PADDING = Screen:scaleBySize(6)
-- These two stay fixed across every size: the outer frame padding matches
-- KOReader's own ButtonDialog frame regardless of scale, and the
-- screen-edge margin matches Quick Dock's own DOCK_MARGIN (see
-- getOverlayClearance below) -- neither is part of Quick Dock's own scaled
-- metrics either.
local BUTTON_OUTER_PADDING = Size.padding.button
local BUTTON_MARGIN = Size.padding.large

-- How long a hold-triggered hint stays up before it dismisses itself, and
-- the font it uses -- unrelated to the pill's own geometry above.
local HINT_DISMISS_SECONDS = 3
local HINT_FONT_SIZE = 18

local function pluginDir()
	local source = debug.getinfo(1, "S").source or ""
	local path = source:match("^@(.*/)") or source:match("^(.*/)")
	return path or "plugins/pageanchor.koplugin/"
end

local ICONS_DIR = pluginDir() .. "icons/"

-- ============================================================================
-- Floating overlay: renders and hit-tests the back/forward/dismiss buttons
-- ============================================================================

local FloatingHistoryOverlay = WidgetContainer:extend({})

function FloatingHistoryOverlay:clearCache()
	if self.dock and self.dock.widget and self.dock.widget.free then
		self.dock.widget:free()
	end
	self.dock = nil
	self.dock_key = nil
	self.last_spec = nil
	self.button_dimens = nil
	self.pill_dimen = nil
	self.pill_side = nil
end

-- Builds one merged widget -- the back/forward action segment and the
-- anchor (dismiss) segment sharing a single border, like two buttons docked
-- together, separated by a thin divider instead of floating as two separate
-- pills -- matching Quick Dock's own button proportions: bordersize=0 per
-- segment, a fixed square box around each icon, and the divider sitting
-- flush against both. The anchor segment sits on the side closer to the
-- screen center, mirroring Quick Dock's own icon ordering.
function FloatingHistoryOverlay:_makeDock(spec)
	local metrics = self.owner:getButtonMetrics()
	local action_button = Button:new({
		icon = ICONS_DIR .. spec.icon,
		icon_width = metrics.icon_size,
		icon_height = metrics.icon_size,
		width = metrics.segment_width,
		height = metrics.height,
		bordersize = 0,
		margin = 0,
		padding = 0,
	})
	-- Marked (you're back at the anchor) uses Button's own preselect/invert
	-- treatment, covering this whole square instead of just the icon.
	local dismiss_button = Button:new({
		icon = ICONS_DIR .. ICON_ANCHOR,
		icon_width = metrics.icon_size,
		icon_height = metrics.icon_size,
		width = metrics.segment_width,
		height = metrics.height,
		bordersize = 0,
		margin = 0,
		padding = 0,
		preselect = spec.dismiss_marked,
	})
	local dismiss_size = dismiss_button:getSize()

	-- Spans the full button height and sits flush against each segment,
	-- with no extra gap on either side -- the same way ButtonTable butts its
	-- separator directly against adjacent buttons.
	local divider = LineWidget:new({
		background = Blitbuffer.COLOR_GRAY,
		dimen = Geom:new({ w = Size.line.medium, h = metrics.height }),
	})

	local dock_children
	if spec.side == "left" then
		dock_children = { action_button, divider, dismiss_button }
	else
		dock_children = { dismiss_button, divider, action_button }
	end
	dock_children.allow_mirroring = false
	local dock_content = HorizontalGroup:new(dock_children)
	local content_size = dock_content:getSize()

	local widget = FrameContainer:new({
		background = Blitbuffer.COLOR_WHITE,
		bordersize = Size.border.button,
		radius = Size.radius.button,
		margin = 0,
		padding = metrics.padding,
		CenterContainer:new({
			dimen = Geom:new({ w = content_size.w, h = metrics.height }),
			dock_content,
		}),
	})

	local dismiss_offset = spec.side == "left" and (content_size.w - dismiss_size.w) or 0
	return {
		widget = widget,
		dismiss_x = metrics.padding + Size.border.button + dismiss_offset,
		dismiss_w = dismiss_size.w,
	}
end

function FloatingHistoryOverlay:_getDock(spec)
	-- getButtonSpecs() returns the same cached table between invalidates, so
	-- most repaints (anything not caused by navigation/settings activity)
	-- hit this identity check and skip the content-key rebuild below
	-- entirely -- it would otherwise run on every single screen repaint.
	if spec == self.last_spec then
		return self.dock
	end

	local key = table.concat({
		spec.action, spec.side, spec.icon,
		spec.dismiss_marked and "marked" or "plain",
		self.owner:getButtonSize(),
	}, ":")
	if key ~= self.dock_key then
		self:clearCache()
		self.dock = self:_makeDock(spec)
		self.dock_key = key
	end
	self.last_spec = spec
	return self.dock
end

function FloatingHistoryOverlay:paintTo(bb, x, y)
	local spec = self.owner:getButtonSpecs()
	if not spec then
		self.button_dimens = nil
		self.pill_dimen = nil
		self.pill_side = nil
		return
	end

	local dock = self:_getDock(spec)
	local widget = dock.widget
	local margin = self.owner:getButtonMetrics().margin
	local view = self.owner.ui.view
	local view_width = view and view.dimen and view.dimen.w or Screen:getWidth()
	local view_height = view and view.dimen and view.dimen.h or Screen:getHeight()
	local size = widget:getSize()
	local widget_x = spec.side == "left"
		and x + margin
		or x + view_width - size.w - margin
	local widget_y = y + view_height - margin - size.h

	local dismiss_left = widget_x + dock.dismiss_x
	local dismiss_dimen = Geom:new({ x = dismiss_left, y = widget_y, w = dock.dismiss_w, h = size.h })
	local action_dimen
	if spec.side == "left" then
		action_dimen = Geom:new({ x = widget_x, y = widget_y, w = dismiss_left - widget_x, h = size.h })
	else
		local dismiss_right = dismiss_left + dock.dismiss_w
		action_dimen = Geom:new({ x = dismiss_right, y = widget_y, w = widget_x + size.w - dismiss_right, h = size.h })
	end

	self.button_dimens = {
		{ action = spec.action, dimen = action_dimen },
		{ action = ACTION_DISMISS, dimen = dismiss_dimen },
	}
	-- Kept for the hold hint's own positioning (see PageAnchor:showHint):
	-- it needs the pill's on-screen box and which side it's anchored to.
	self.pill_dimen = Geom:new({ x = widget_x, y = widget_y, w = size.w, h = size.h })
	self.pill_side = spec.side
	widget:paintTo(bb, widget_x, widget_y)
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

-- Long-pressing a segment shows a floating hint with the info the pill no
-- longer displays inline (the destination position, or the anchor's own
-- state) -- so going icon-only never leaves the user without that context.
function FloatingHistoryOverlay:handleHold(gesture)
	local pos = gesture and gesture.pos
	if not pos then
		return false
	end
	for _, button in ipairs(self.button_dimens or {}) do
		if button.dimen:contains(pos) then
			return self.owner:showButtonHint(button.action)
		end
	end
	return false
end

-- A swipe-down anywhere in the overlay's zone dismisses it, without requiring
-- the precise hit-test that tapping a specific button needs. Anything but a
-- clean south swipe (e.g. a diagonal one) is left to fall through so it can
-- still reach the reader's own page-turn/menu swipe handlers underneath.
function FloatingHistoryOverlay:handleSwipe(gesture)
	if gesture and gesture.direction == "south" and self.button_dimens and #self.button_dimens > 0 then
		return self.owner:activate(ACTION_DISMISS)
	end
	return false
end

-- ============================================================================
-- Hold hint: a small, non-blocking bubble shown above the pill
-- ============================================================================

-- toast=true/modal=false is the same pairing KOReader's own Notification
-- widget and Quick Dock's status panel use: it shows above everything else
-- without stealing input, so it never blocks a tap meant for the pill or
-- the page underneath. Plain WidgetContainer (not InputContainer): the
-- onGesture/onKeyPress dismiss-on-any-input trick below comes from the
-- generic EventListener dispatch every widget already has, not from
-- InputContainer's declarative ges_events/key_events matching -- and
-- InputContainer's paintTo treats self.dimen as "wherever my parent just
-- painted me" rather than an absolute offset, which broke this toast's
-- positioning (it painted at the screen's top-left instead of by the pill).
local HintToast = WidgetContainer:extend({
	modal = false,
	toast = true,
})

function HintToast:init()
	self[1] = self.panel
end

function HintToast:onShow()
	UIManager:setDirty(self, "ui", self.dimen)
	return true
end

function HintToast:onCloseWidget()
	UIManager:setDirty(nil, "ui", self.dimen)
end

-- Routed through the owner instead of a plain UIManager:close(self), so the
-- pending auto-dismiss schedule and PageAnchor's own hint_widget bookkeeping
-- stay in sync instead of pointing at an already-closed widget.
--
-- hold_release is skipped: it's not a new, separate touch -- it's the
-- natural tail end of the very hold gesture that opened this hint (the
-- finger lifting after crossing the hold threshold), delivered as its own
-- event once the toast is already on the window stack. Closing on it would
-- make the hint vanish the instant it appears, before it's ever painted.
function HintToast:onGesture(ev)
	if ev and ev.ges == "hold_release" then
		return false
	end
	self.owner:closeHint()
	return false
end

function HintToast:onKeyPress(_key)
	self.owner:closeHint()
	return false
end
HintToast.onKeyRepeat = HintToast.onKeyPress

-- ============================================================================
-- Plugin definition/state
-- ============================================================================

local PageAnchor = WidgetContainer:extend({
	name = "pageanchor",
	is_doc_only = true,
})

function PageAnchor:init()
	self.overlay = FloatingHistoryOverlay:new({ owner = self })
	self.reference_page = nil
	self.reference_location = nil
	self.anchor = nil
	self.forward_target = nil
	self.return_baseline_page = nil
	self.auto_dismiss_fn = nil
	self.button_specs = nil
	self.button_specs_computed = false
	self.hint_widget = nil
	self.hint_dismiss_fn = nil
	self._installed = false

	self:patchIconWidget()

	if self.ui and self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end
	self.ui:registerPostInitCallback(function()
		self:installOverlay()
	end)
end

local function fileExists(path)
	return path ~= nil and lfs.attributes(path, "mode") == "file"
end

-- Reuses Quick Dock's own trick: IconWidget only resolves bare icon names
-- against KOReader's system icon directories, so Button (which always
-- builds its icon through IconWidget) can't show this plugin's own SVGs on
-- its own. This patch teaches IconWidget to recognize a full, existing file
-- path passed as `icon` and use it directly, without touching the
-- name-resolution path every other caller in KOReader still relies on.
-- Namespaced separately from Quick Dock's own copy of this patch (distinct
-- fields on IconWidget), so the two coexist safely if both plugins are
-- installed.
function PageAnchor:patchIconWidget()
	if self._pageanchor_icon_patch_active then
		return
	end
	self._pageanchor_icon_patch_active = true
	IconWidget._pageanchor_patch_users = (IconWidget._pageanchor_patch_users or 0) + 1

	if IconWidget._pageanchor_original_init then
		return
	end

	local original_init = IconWidget.init
	IconWidget._pageanchor_original_init = original_init

	local patched_init = function(icon_widget)
		local explicit_icon = rawget(icon_widget, "icon")
		if type(explicit_icon) == "string" and explicit_icon:match("%.[%a%d]+$") and fileExists(explicit_icon) then
			icon_widget.file = explicit_icon
		end
		return original_init(icon_widget)
	end

	IconWidget._pageanchor_patched_init = patched_init
	IconWidget.init = patched_init
end

function PageAnchor:unpatchIconWidget()
	if not self._pageanchor_icon_patch_active then
		return
	end
	self._pageanchor_icon_patch_active = nil
	IconWidget._pageanchor_patch_users = math.max(0, (IconWidget._pageanchor_patch_users or 1) - 1)
	if IconWidget._pageanchor_patch_users > 0 then
		return
	end

	if IconWidget.init ~= IconWidget._pageanchor_patched_init then
		-- Something else replaced IconWidget.init after we patched it (a
		-- future KOReader version touching the same hook, or another patch
		-- layered on top without chaining back to ours). Restoring blindly
		-- here could drop that other patch, so leave it alone and just log --
		-- a starting point if plugin icons ever start misbehaving.
		logger.warn("PageAnchor: IconWidget.init changed unexpectedly during unpatch; leaving it as-is")
		IconWidget._pageanchor_patch_users = nil
		return
	end

	IconWidget.init = IconWidget._pageanchor_original_init
	IconWidget._pageanchor_original_init = nil
	IconWidget._pageanchor_patched_init = nil
	IconWidget._pageanchor_patch_users = nil
end

-- A display setting changing invalidates the cached button specs (their
-- content or presence depends on it), drops any cached button widgets built
-- from the old content, and repaints the overlay region.
function PageAnchor:_onDisplaySettingChanged()
	self:invalidateButtonSpecs()
	self.overlay:clearCache()
	self:refresh()
end

function PageAnchor:isEnabled()
	return G_reader_settings:nilOrTrue(SETTING_ENABLED)
end

function PageAnchor:setEnabled(enabled)
	G_reader_settings:saveSetting(SETTING_ENABLED, enabled and true or false)
	self:_onDisplaySettingChanged()
end

function PageAnchor:getDestinationFormat()
	local value = G_reader_settings:readSetting(SETTING_DESTINATION_FORMAT)
	for _index, option in ipairs(DESTINATION_FORMAT_OPTIONS) do
		if option.value == value then
			return value
		end
	end
	return DESTINATION_FORMAT_PAGE_BOOK
end

function PageAnchor:setDestinationFormat(format)
	G_reader_settings:saveSetting(SETTING_DESTINATION_FORMAT, format)
	self:_onDisplaySettingChanged()
end

function PageAnchor:getButtonSize()
	local size = G_reader_settings:readSetting(SETTING_BUTTON_SIZE)
	return BUTTON_SIZE_FACTORS[size] and size or BUTTON_SIZE_SMALL
end

function PageAnchor:setButtonSize(size)
	G_reader_settings:saveSetting(
		SETTING_BUTTON_SIZE,
		BUTTON_SIZE_FACTORS[size] and size or BUTTON_SIZE_SMALL
	)
	self.overlay:clearCache() -- geometry changed; the cached pill no longer matches
	self:_onDisplaySettingChanged()
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
	local factor = BUTTON_SIZE_FACTORS[size]
	local height = scaleMetric(BASE_BUTTON_HEIGHT, factor)
	local metrics = {
		icon_size = scaleMetric(BASE_BUTTON_ICON_SIZE, factor),
		height = height,
		segment_width = height + 2 * scaleMetric(BASE_BUTTON_SIDE_PADDING, factor),
		padding = BUTTON_OUTER_PADDING,
		margin = BUTTON_MARGIN,
	}
	BUTTON_METRICS_CACHE[size] = metrics
	return metrics
end

function PageAnchor:getAutoDismissSeconds()
	local value = G_reader_settings:readSetting(SETTING_AUTO_DISMISS_SECONDS)
	if type(value) == "number" then
		return value
	end
	return AUTO_DISMISS_DEFAULT_SECONDS
end

function PageAnchor:setAutoDismissSeconds(seconds)
	G_reader_settings:saveSetting(SETTING_AUTO_DISMISS_SECONDS, seconds)
	-- Realign a pending timer to the new duration immediately, rather than
	-- waiting for the next navigation event to pick it up.
	if self.anchor or self.forward_target then
		self:scheduleAutoDismiss()
	end
end

function PageAnchor:getForwardDismissPages()
	local value = G_reader_settings:readSetting(SETTING_FORWARD_DISMISS_PAGES)
	if type(value) == "number" then
		return value
	end
	return FORWARD_DISMISS_DEFAULT_PAGES
end

function PageAnchor:setForwardDismissPages(pages)
	G_reader_settings:saveSetting(SETTING_FORWARD_DISMISS_PAGES, pages)
end

-- Hides the floating buttons after a period without any relevant activity,
-- so one left on screen doesn't linger forever. Follows Reader Header/
-- Footer's own schedule/cancel-by-reference pattern: a self-nilling closure,
-- scheduled and unscheduled by that same stored reference.
function PageAnchor:cancelAutoDismiss()
	if self.auto_dismiss_fn then
		UIManager:unschedule(self.auto_dismiss_fn)
		self.auto_dismiss_fn = nil
	end
end

-- Optional integration point in the other direction from
-- getOverlayClearance: whether a sibling plugin's own floating element
-- (currently just Quick Dock's dock) is on screen right now, so the
-- auto-dismiss timer below can hold off instead of disappearing out from
-- under a dock that already reserved clearance for this pill. Duck-typed
-- and pcall-wrapped like the rest of this integration, so a missing
-- plugin, a missing method, or a bug just reports "not visible" instead of
-- breaking the timer.
function PageAnchor:isSiblingOverlayBlockingDismiss()
	local sibling = self.ui and self.ui.quickdock
	local getter = sibling and sibling.isDockVisible
	if type(getter) ~= "function" then
		return false
	end
	local ok, visible = pcall(getter, sibling)
	if not ok then
		if not self._logged_sibling_dock_visible_error then
			self._logged_sibling_dock_visible_error = true
			logger.warn("PageAnchor: isDockVisible from Quick Dock failed:", visible)
		end
		return false
	end
	return visible == true
end

function PageAnchor:scheduleAutoDismiss()
	self:cancelAutoDismiss()
	local seconds = self:getAutoDismissSeconds()
	if not seconds or seconds <= 0 then
		return
	end
	self.auto_dismiss_fn = function()
		self.auto_dismiss_fn = nil
		if self:isSiblingOverlayBlockingDismiss() then
			-- Quick Dock's dock is open right now -- check again later
			-- instead of dismissing out from under it.
			self:scheduleAutoDismiss()
			return
		end
		self:clearHistory()
	end
	UIManager:scheduleIn(seconds, self.auto_dismiss_fn)
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

-- The anchor and the forward target are mutually exclusive: either you are
-- away from a pinned anchor (show "back", with the anchor/dismiss segment
-- unmarked), or you have just returned to one and can hop back out to where
-- you were (show "forward", with the anchor/dismiss segment marked, since
-- reaching this branch means you're at the anchor right now). Never both at
-- once -- see trackPage for why that keeps this predictable. Returns a
-- single spec for the one merged dock widget, or nil when nothing to show.
function PageAnchor:computeButtonSpecs()
	if not self:isEnabled() or not self.ui or not self.ui.link then
		return nil
	end

	if self.anchor then
		local side = self:getTargetSide(self.anchor, -1)
		return {
			action = ACTION_BACK,
			side = side,
			icon = side == "left" and ICON_CHEVRON_LEFT or ICON_CHEVRON_RIGHT,
			label = self:getDestinationLabel(self.anchor),
			dismiss_marked = false,
		}
	elseif self.forward_target then
		local side = self:getTargetSide(self.forward_target, 1)
		return {
			action = ACTION_FORWARD,
			side = side,
			icon = side == "left" and ICON_CHEVRON_LEFT or ICON_CHEVRON_RIGHT,
			label = self:getDestinationLabel(self.forward_target),
			dismiss_marked = true,
		}
	end
	return nil
end

-- The friendlier destination text used in the hold hint: a chapter title
-- plus either a book-wide or chapter-relative position, per the "Position
-- hint" format setting -- or the chapter title alone, with "Text only".
-- Falls back to the plain page/percentage label when there's no usable
-- chapter title (e.g. a document with no table of contents) -- nothing
-- else to show as "text only" in that case -- worded so it still reads
-- naturally after "Go to %1"/"Back to %1" either way (see showButtonHint).
function PageAnchor:getDestinationLabel(location)
	local ui = self.ui
	local format = self:getDestinationFormat()
	local chapter = History.getChapterInfo(ui, location)

	if not chapter then
		if format == DESTINATION_FORMAT_PERCENTAGE_BOOK or format == DESTINATION_FORMAT_PERCENTAGE_CHAPTER then
			return History.getPercentageLabel(ui, location)
		end
		return T(_("page %1"), History.getPageLabel(ui, location))
	end

	if format == DESTINATION_FORMAT_TEXT_ONLY then
		return chapter.title
	end
	if format == DESTINATION_FORMAT_PERCENTAGE_CHAPTER then
		return T(_("%1 (%2 into this chapter)"), chapter.title, string.format("%.2f%%", chapter.percentage))
	end
	if format == DESTINATION_FORMAT_PAGE_CHAPTER then
		return T(_("%1 (page %2 of this chapter)"), chapter.title, chapter.page)
	end
	if format == DESTINATION_FORMAT_PERCENTAGE_BOOK then
		return T(_("%1 (%2 of the book)"), chapter.title, History.getPercentageLabel(ui, location))
	end
	-- DESTINATION_FORMAT_PAGE_BOOK
	local book_total = History.getBookPageCount(ui)
	if book_total then
		return T(_("%1 (page %2 of %3)"), chapter.title, History.getPageLabel(ui, location), book_total)
	end
	return T(_("%1 (page %2)"), chapter.title, History.getPageLabel(ui, location))
end

-- Computing specs walks the location stacks and compares XPointers, which is
-- unnecessary work to repeat on every screen paint. The result only changes
-- on navigation, page/position updates, or a relevant setting change, so it
-- is cached here and invalidated at those specific points instead.
function PageAnchor:invalidateButtonSpecs()
	self.button_specs = nil
	self.button_specs_computed = false
	-- Any open hint was describing the spec that's now stale (a different
	-- destination, or the anchor no longer being where it said).
	self:closeHint()
end

-- A plain `not self.button_specs` check would recompute on every single
-- paint while idle, since computeButtonSpecs legitimately returns nil then
-- (nothing to show) -- so "computed" is tracked separately from "what it
-- computed to".
function PageAnchor:getButtonSpecs()
	if not self.button_specs_computed then
		self.button_specs = self:computeButtonSpecs()
		self.button_specs_computed = true
	end
	return self.button_specs
end

-- Optional integration point for other floating-button plugins (currently
-- just Quick Dock): reports how much clearance from the bottom edge they
-- should keep on the given side to avoid rendering on top of the pill, or
-- nil when nothing is showing there. Purely a query -- this never reaches
-- into another plugin itself, so each one works fine without the other
-- installed.
--
-- The gap this leaves above the pill (Size.padding.default) matches the gap
-- Quick Dock leaves between its own dock and its side-switch button, so the
-- two read as one consistent stack instead of two independently floating
-- things. This relies on Quick Dock's own outer margin equalling ours
-- (BUTTON_MARGIN) -- true today, both Size.padding.large -- which is what
-- cancels the two bottom margins out of this formula; see the comment above
-- BUTTON_MARGIN's definition.
function PageAnchor:getOverlayClearance(side)
	local spec = self:getButtonSpecs()
	if not spec or spec.side ~= side then
		return nil
	end
	local size = self.overlay:_getDock(spec).widget:getSize()
	return size.h + Size.padding.default
end

-- Shown on hold, above the pill: the info that no longer lives on the
-- button itself (the destination position, or what the anchor segment
-- would do right now).
function PageAnchor:showButtonHint(action)
	local spec = self:getButtonSpecs()
	if not spec then
		return false
	end
	local text
	if action == ACTION_DISMISS then
		text = spec.dismiss_marked and _("This is the starting position") or _("Continue here")
	elseif action == spec.action then
		-- ACTION_BACK genuinely returns to the anchor, so it says so
		-- ("Back to") instead of the generic "Go to" ACTION_FORWARD keeps
		-- (jumping *out* to wherever you'd wandered isn't really "back").
		-- spec.label (built by getDestinationLabel) already reads
		-- naturally after either verb, with or without a chapter title.
		text = T(spec.action == ACTION_BACK and _("Back to %1") or _("Go to %1"), spec.label)
	else
		return false
	end
	self:showHint(text)
	return true
end

function PageAnchor:showHint(text)
	self:closeHint()
	local pill_dimen = self.overlay.pill_dimen
	local pill_side = self.overlay.pill_side
	if not self.ui or not pill_dimen or not pill_side then
		return
	end

	local panel = FrameContainer:new({
		background = Blitbuffer.COLOR_WHITE,
		bordersize = Size.border.button,
		color = Blitbuffer.COLOR_BLACK,
		radius = Size.radius.button,
		margin = 0,
		padding = Size.padding.default,
		TextWidget:new({
			text = BD.ltr(tostring(text or "")),
			face = Font:getFace("cfont", HINT_FONT_SIZE),
			bold = true,
		}),
	})
	local panel_size = panel:getSize()
	local margin = self:getButtonMetrics().margin
	local left = pill_side == "left"
		and margin
		or Screen:getWidth() - margin - panel_size.w
	local top = pill_dimen.y - Size.padding.default - panel_size.h

	local hint = HintToast:new({
		owner = self,
		panel = panel,
		dimen = Geom:new({
			x = math.floor(left),
			y = math.floor(top),
			w = panel_size.w,
			h = panel_size.h,
		}),
	})
	panel.show_parent = hint
	self.hint_widget = hint
	UIManager:show(hint, "ui")

	self.hint_dismiss_fn = function()
		self.hint_dismiss_fn = nil
		self:closeHint()
	end
	UIManager:scheduleIn(HINT_DISMISS_SECONDS, self.hint_dismiss_fn)
end

function PageAnchor:closeHint()
	if self.hint_dismiss_fn then
		UIManager:unschedule(self.hint_dismiss_fn)
		self.hint_dismiss_fn = nil
	end
	if self.hint_widget then
		local hint_widget = self.hint_widget
		self.hint_widget = nil
		UIManager:close(hint_widget)
	end
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
		-- "ui" (non-flashing) is the right waveform for this small floating
		-- overlay: on e-ink, a flash sweeps the full panel black/white and
		-- costs noticeably more time and battery than a partial update, and
		-- this region is too small to need one to avoid ghosting.
		UIManager:setDirty(self.ui.dialog, function()
			return refresh_type or "ui", region
		end)
	end
end

function PageAnchor:installOverlay()
	if self._installed or not self.ui or not self.ui.view then
		return
	end
	self._installed = true

	-- Deliberately not using ReaderView:registerViewModule() here: it draws
	-- every registered module by iterating view_modules with pairs(), whose
	-- order is unspecified, so it cannot guarantee these buttons paint after
	-- another plugin's own view module (e.g. Reader Header/Footer's status
	-- indicators) -- it's a coin flip which one ends up on top, and users
	-- running both have hit exactly that. Wrapping view.paintTo instead
	-- guarantees the overlay always paints last, strictly on top of the
	-- entire view, regardless of what else is installed.
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
		{
			id = "pageanchor_hold",
			ges = "hold",
			screen_zone = { ratio_x = 0, ratio_y = 0.7, ratio_w = 1, ratio_h = 0.3 },
			handler = function(gesture)
				return self.overlay:handleHold(gesture)
			end,
			overrides = overrides,
		},
		{
			id = "pageanchor_swipe",
			ges = "swipe",
			screen_zone = { ratio_x = 0, ratio_y = 0.7, ratio_w = 1, ratio_h = 0.3 },
			handler = function(gesture)
				return self.overlay:handleSwipe(gesture)
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
		self.ui:unRegisterTouchZones({
			{ id = "pageanchor_tap" },
			{ id = "pageanchor_hold" },
			{ id = "pageanchor_swipe" },
		})
	end
	self:closeHint()
	self.overlay:clearCache()
	self._installed = false
end

-- Jumps straight to a saved location, the same way ReaderLink's own
-- back/forward handlers do, without touching ReaderLink's history stacks --
-- the anchor and forward target are tracked entirely by PageAnchor itself
-- (see trackPage), so a real footnote/link jump elsewhere never interferes
-- with them, and vice versa.
function PageAnchor:goToLocation(location)
	if not location or not self.ui then
		return
	end
	self.ui:handleEvent(Event:new("RestoreBookLocation", location))
end

function PageAnchor:activate(action)
	if not self.ui then
		return false
	end
	if action == ACTION_DISMISS then
		self:clearHistory()
		return true
	elseif action == ACTION_BACK and self.anchor then
		-- Resolve right away instead of waiting for the reader's own
		-- page/position update event to notice we've arrived: that event
		-- lands after this call returns, so a repaint in between would still
		-- see the old anchor and show it for one extra frame (it took a
		-- second tap to "catch up" before this fix).
		local anchor_location = self.anchor
		local departure_location = History.getCurrentLocation(self.ui)
		self:goToLocation(anchor_location)
		self.anchor = nil
		self.forward_target = departure_location
		self.reference_page = History.getLocationPage(self.ui, anchor_location)
		self.reference_location = anchor_location
		self.return_baseline_page = self.reference_page
		self:invalidateButtonSpecs()
		self:scheduleAutoDismiss()
		return true
	elseif action == ACTION_FORWARD and self.forward_target then
		-- Same reasoning as above, mirrored: re-arm the anchor at the spot
		-- being left immediately, rather than waiting for trackPage to infer
		-- it from the next position update.
		local target_location = self.forward_target
		local departure_location = History.getCurrentLocation(self.ui)
		self:goToLocation(target_location)
		self.anchor = departure_location
		self.forward_target = target_location
		self.return_baseline_page = nil
		self:invalidateButtonSpecs()
		self:scheduleAutoDismiss()
		return true
	end
	return false
end

-- The anchor, once pinned, prevails: it does not move or get replaced no
-- matter how far or how long you wander, and the only ways to change it are
-- to return to it (resolving it, see below) or to dismiss it from the menu
-- or the center button. This intentionally ignores ReaderLink's own
-- location_stack/forward_location_stack, which are for real link/footnote
-- navigation and have different rules (e.g. a new jump there discards any
-- pending forward target) that made a borrowed anchor drift and get
-- corrupted across repeated back-and-forth navigation.
function PageAnchor:trackPage(page)
	page = tonumber(page)
	if not page then
		return
	end
	-- The reachable back/forward target and its side can change on every
	-- page/position update even without a history mutation, so refresh the
	-- cached button specs here rather than in the much hotter paint path.
	self:invalidateButtonSpecs()

	local current_location = History.getCurrentLocation(self.ui)
	if not current_location then
		return
	end

	if not self.reference_page or not self.reference_location then
		self.reference_page = page
		self.reference_location = current_location
		return
	end

	if self.anchor then
		if History.isCurrentLocation(self.ui, self.anchor) then
			-- Resolved: back at the anchor. forward_target already holds the
			-- most recent position visited while away (see the else branch
			-- below), or the jump's original destination if you returned
			-- immediately without wandering further.
			self.anchor = nil
			self.reference_page = page
			self.reference_location = current_location
			self.return_baseline_page = page
			self:scheduleAutoDismiss()
		else
			self.forward_target = current_location
			self:scheduleAutoDismiss()
		end
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

		-- Just returned to the anchor and reading on: hide the forward
		-- target once enough pages have passed, so it does not linger
		-- indefinitely as a stale "go back out" option.
		if self.forward_target and self.return_baseline_page then
			local dismiss_after = self:getForwardDismissPages()
			if dismiss_after > 0 and math.abs(page - self.return_baseline_page) >= dismiss_after then
				self.forward_target = nil
				self.return_baseline_page = nil
				self:cancelAutoDismiss()
			end
		end
	else
		self.anchor = self.reference_location
		self.forward_target = current_location
		self.return_baseline_page = nil
		self:scheduleAutoDismiss()
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
	end
end

function PageAnchor:onCloseDocument()
	self:cancelAutoDismiss()
	self:uninstallOverlay()
	self:unpatchIconWidget()
end

function PageAnchor:stopPlugin()
	self:cancelAutoDismiss()
	self:uninstallOverlay()
	self:unpatchIconWidget()
	self:refresh()
	return true
end

-- The center button and the menu's "Clear location history" both call this:
-- it is how a new anchor gets accepted, by dropping the current one (and any
-- pending forward target) and restarting tracking fresh from here.
function PageAnchor:clearHistory()
	if not self.ui then
		return
	end
	self:cancelAutoDismiss()
	self.anchor = nil
	self.forward_target = nil
	self.return_baseline_page = nil
	self.reference_page = self.ui:getCurrentPage()
	self.reference_location = History.getCurrentLocation(self.ui)
	self:invalidateButtonSpecs()
	self:refresh()
end

-- ============================================================================
-- Menu
-- ============================================================================

-- Builds a set of mutually exclusive radio sub-items from a list of
-- {value, label} options, shared by the two option lists below. An optional
-- caption is inserted first as a plain, non-interactive line (no callback,
-- disabled so it reads as a label rather than a dead button) -- context
-- shown right above the options themselves, without needing help_text.
local function buildValueRadioItems(options, get_value, set_value, caption)
	local items = {}
	if caption then
		items[#items + 1] = { text = caption, enabled = false }
	end
	-- Named (not "_"): that would shadow the gettext function used as
	-- `_(option.label)` below for the rest of this loop body.
	for _index, option in ipairs(options) do
		items[#items + 1] = {
			text = _(option.label),
			radio = true,
			checked_func = function()
				return get_value() == option.value
			end,
			callback = function()
				set_value(option.value)
			end,
		}
	end
	return items
end

function PageAnchor:addToMainMenu(menu_items)
	menu_items.pageanchor = {
		text = _("Page Anchor"),
		sorting_hint = "navi",
		sub_item_table = {
			{
				-- Static text (the checkmark alone shows current state) --
				-- reuses KOReader's own "Enable" string (already translated
				-- into every language it supports) instead of a
				-- plugin-specific phrase, so only "Page Anchor" itself (a
				-- proper noun) needs no translation at all.
				text = _("Enable") .. " " .. _("Page Anchor"),
				help_text = _("Turns Page Anchor off entirely, without losing the navigation history it uses."),
				checked_func = function()
					return self:isEnabled()
				end,
				callback = function()
					self:setEnabled(not self:isEnabled())
				end,
			},
			{
				-- Three predefined scales, same idea as Quick Dock's own
				-- dock-size setting -- affects both segments' width and
				-- height together, so the pill grows as one shape rather
				-- than the icon and its box drifting apart.
				text = _("Button size"),
				help_text = _("Scales the floating buttons up for an easier target, without changing their shape."),
				sub_item_table = buildValueRadioItems(
					BUTTON_SIZE_OPTIONS,
					function() return self:getButtonSize() end,
					function(value) self:setButtonSize(value) end
				),
			},
			{
				-- One flat list instead of a "Format" screen plus a
				-- separately nested, sometimes-disabled "Relative to"
				-- screen: each option already names both what it shows and
				-- what it's measured against, so there's nothing left to
				-- combine in your head across two menus.
				text = _("Position hint"),
				help_text = _("Chooses what the text shown when you hold down a navigation button says."),
				sub_item_table = buildValueRadioItems(
					DESTINATION_FORMAT_OPTIONS,
					function() return self:getDestinationFormat() end,
					function(value) self:setDestinationFormat(value) end
				),
			},
			{
				-- Groups both ways the floating buttons can disappear on
				-- their own (a shared parent screen instead of two
				-- unrelated-looking top-level items, per touchmenu.lua's
				-- own nesting) -- neither child repeats "Auto-dismiss" in
				-- its own text since the parent screen's title already says
				-- it.
				text = _("Auto-dismiss"),
				help_text = _("Controls when the floating buttons disappear on their own, both from inactivity and after you've returned to the anchor."),
				sub_item_table = {
					{
						text = _("Timeout"),
						help_text = _("Hides the floating buttons after this much time without navigation activity."),
						sub_item_table = buildValueRadioItems(
							AUTO_DISMISS_OPTIONS,
							function() return self:getAutoDismissSeconds() end,
							function(value) self:setAutoDismissSeconds(value) end
						),
					},
					{
						text = _("After returning to anchor"),
						help_text = _("Auto-dismisses the floating button once you've read this many pages past the anchor. Off keeps it until you dismiss it yourself."),
						sub_item_table = buildValueRadioItems(
							FORWARD_DISMISS_PAGE_OPTIONS,
							function() return self:getForwardDismissPages() end,
							function(value) self:setForwardDismissPages(value) end,
							_("Auto-dismiss after:")
						),
					},
				},
			},
			{
				text = _("Clear location history"),
				help_text = _("Forgets the current back/forward targets without changing your reading position."),
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
			{
				-- Reuses KOReader's own "Version: %1" string (see
				-- common_info_menu_table.lua) instead of a plugin-specific
				-- one, so this line is already translated everywhere
				-- KOReader is.
				text_func = function()
					return T(_("Version: %1"), PLUGIN_VERSION)
				end,
				callback = function()
					UIManager:show(InfoMessage:new({
						text = _("Page Anchor") .. "\n" .. T(_("Version: %1"), PLUGIN_VERSION),
					}))
				end,
			},
		},
	}
end

return PageAnchor
