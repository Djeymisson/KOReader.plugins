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
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local LineWidget = require("ui/widget/linewidget")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Notification = require("ui/widget/notification")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("pageanchor_l10n")
local T = require("ffi/util").template

local History = require("modules/history")

local Screen = Device.screen

-- ============================================================================
-- Constants
-- ============================================================================

local PLUGIN_VERSION = "v1.11.4"

local SETTING_ENABLED = "pageanchor_enabled"
local SETTING_DESTINATION_FORMAT = "pageanchor_destination_format"
local SETTING_BUTTON_SIZE = "pageanchor_button_size"
local SETTING_AUTO_DISMISS_SECONDS = "pageanchor_auto_dismiss_seconds"
local SETTING_FORWARD_DISMISS_PAGES = "pageanchor_forward_dismiss_pages"
local SETTING_HIDE_MODE = "pageanchor_hide_mode"
local SETTING_HIDDEN_EXPIRY_SECONDS = "pageanchor_hidden_expiry_seconds"

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

-- How long the buttons may stay hidden (or parked as a tab) before Page
-- Anchor gives up on the trip: the anchor is discarded and the current
-- position becomes the reading reference, exactly as tapping the anchor
-- button would. Counted from the moment they were hidden; "Never" (0, the
-- default) keeps them waiting until dismissed by hand.
local HIDDEN_EXPIRY_DEFAULT_SECONDS = 0
local HIDDEN_EXPIRY_OPTIONS = {
	{ value = 0, label = "Never (until dismissed)" },
	{ value = 60, label = "1 minute" },
	{ value = 300, label = "5 minutes" },
	{ value = 900, label = "15 minutes" },
	{ value = 1800, label = "30 minutes" },
	{ value = 3600, label = "1 hour" },
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
local ACTION_SHOW = "show"

-- What hiding the buttons (inactivity timeout, or the show/hide gesture
-- action) leaves on screen: a small anchor tab in the same corner that one
-- tap expands back into the full control -- so getting the buttons back
-- never means digging through the menu -- or nothing at all, for a clean
-- page (then the menu or the gesture action brings them back).
local HIDE_MODE_MINIMIZE = "minimize"
local HIDE_MODE_HIDE = "hide"
local HIDE_MODE_OPTIONS = {
	{ value = HIDE_MODE_MINIMIZE, label = "Minimize to an anchor tab" },
	{ value = HIDE_MODE_HIDE, label = "Hide completely" },
}

local ICON_ANCHOR = "anchor.svg"
local ICON_CHEVRON_LEFT = "chevron-left.svg"
local ICON_CHEVRON_RIGHT = "chevron-right.svg"
local ICON_UNDO = "undo.svg"

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
-- How long the undo notice stays up after a discard. The undo itself stays
-- available afterwards from the menu and the gesture action.
local UNDO_HINT_SECONDS = 3
local HINT_FONT_SIZE = 18

-- Page-turn tolerance for telling plain reading apart from a jump made by a
-- tool that doesn't announce itself (see trackPage): one turn back is a
-- re-read, up to two turns forward is reading on. Counted in page turns,
-- not raw page numbers (see History.countPageTurns).
local READING_TURNS_BEHIND = 1
local READING_TURNS_AHEAD = 2

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
	if spec.minimized then
		return self:_makeTab(spec, metrics)
	end
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

-- The minimized form: a narrow tab glued to the screen edge, holding just
-- the anchor icon, so it reads as "something is parked here" rather than
-- as live navigation. Drawn by hand instead of with a FrameContainer, which
-- can only round all four corners: here the inner corners are rounded and
-- the screen-edge side is square and borderless, like a tab pulled out of
-- the side of the page. Everything is painted inside the screen -- the
-- outer side is squared off by overpainting, never by drawing past the
-- edge, which not every blitbuffer path clips.
local AnchorTab = Widget:extend({
	side = "right",
	width = 0,
	height = 0,
	radius = 0,
	bordersize = 0,
	border_color = Blitbuffer.COLOR_DARK_GRAY,
	icon_widget = nil,
})

function AnchorTab:getSize()
	return Geom:new({ w = self.width, h = self.height })
end

function AnchorTab:paintTo(bb, x, y)
	local w, h, bw = self.width, self.height, self.bordersize
	local r = math.min(self.radius, math.floor(w / 2), math.floor(h / 2))
	bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_WHITE, r)
	bb:paintBorder(x, y, w, h, bw, self.border_color, r)
	if r > 0 then
		-- Square off the screen-edge side: white over its rounded corners
		-- and side border, then carry the top and bottom edges across.
		local edge_x = self.side == "left" and x or x + w - r
		bb:paintRect(edge_x, y, r, h, Blitbuffer.COLOR_WHITE)
		bb:paintRect(edge_x, y, r, bw, self.border_color)
		bb:paintRect(edge_x, y + h - bw, r, bw, self.border_color)
	else
		local edge_x = self.side == "left" and x or x + w - bw
		bb:paintRect(edge_x, y + bw, bw, h - 2 * bw, Blitbuffer.COLOR_WHITE)
	end
	local icon_size = self.icon_widget:getSize()
	self.icon_widget:paintTo(bb,
		x + math.floor((w - icon_size.w) / 2),
		y + math.floor((h - icon_size.h) / 2))
end

function AnchorTab:free()
	if self.icon_widget and self.icon_widget.free then
		self.icon_widget:free()
	end
end

-- Same height as the full control, so it sits exactly where the control
-- was and keeps Quick Dock's clearance (getOverlayClearance) unchanged when
-- it expands; only as wide as the icon plus a little air. The tap target is
-- wider than what's drawn (see paintTo), so narrow never means hard to hit.
function FloatingHistoryOverlay:_makeTab(spec, metrics)
	local border = Size.border.button
	local widget = AnchorTab:new({
		side = spec.side,
		width = metrics.icon_size + 2 * Size.padding.default + border,
		height = metrics.height + 2 * (metrics.padding + border),
		radius = Size.radius.button,
		bordersize = border,
		icon_widget = IconWidget:new({
			icon = ICONS_DIR .. ICON_ANCHOR,
			width = metrics.icon_size,
			height = metrics.icon_size,
		}),
	})
	return {
		widget = widget,
		minimized = true,
		hit_width = metrics.segment_width + 2 * (metrics.padding + border),
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
		spec.minimized and "minimized" or "full",
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
	-- The tab is glued to the screen edge; the full control keeps a margin.
	local side_margin = dock.minimized and 0 or margin
	local widget_x = spec.side == "left"
		and x + side_margin
		or x + view_width - size.w - side_margin
	local widget_y = y + view_height - margin - size.h

	-- Kept for the hold hint's own positioning (see PageAnchor:showHint)
	-- and the swipe zone: the pill's on-screen box and its side.
	self.pill_dimen = Geom:new({ x = widget_x, y = widget_y, w = size.w, h = size.h })
	self.pill_side = spec.side

	if dock.minimized then
		-- Tap target reaches further into the page than the narrow tab.
		local hit_w = math.max(size.w, dock.hit_width or size.w)
		local hit_x = spec.side == "left" and widget_x or widget_x + size.w - hit_w
		self.button_dimens = {
			{ action = ACTION_SHOW, dimen = Geom:new({ x = hit_x, y = widget_y, w = hit_w, h = size.h }) },
		}
		widget:paintTo(bb, widget_x, widget_y)
		return
	end

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
	widget:paintTo(bb, widget_x, widget_y)
end

function FloatingHistoryOverlay:handleTap(gesture)
	local pos = gesture and gesture.pos
	if not pos then
		return false
	end
	if self.owner:handleHintTap(pos) then
		return true
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

-- A swipe-down starting on or near the pill dismisses it, without requiring
-- the precise hit-test that tapping a specific button needs. The slack
-- around the pill is one button height: forgiving enough to hit, while a
-- swipe elsewhere along the bottom of the screen (frontlight, menus, other
-- plugins' gestures) still falls through, as does anything but a clean
-- south swipe.
function FloatingHistoryOverlay:handleSwipe(gesture)
	local pos = gesture and gesture.pos
	local pill = self.pill_dimen
	if not pos or not pill or gesture.direction ~= "south" then
		return false
	end
	local slack = self.owner:getButtonMetrics().height
	local zone = Geom:new({
		x = pill.x - slack,
		y = pill.y - slack,
		w = pill.w + 2 * slack,
		h = pill.h + 2 * slack,
	})
	if zone:contains(pos) then
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
	-- A tappable notice (undo) must survive the touch/tap landing on it:
	-- toasts can't consume events, so the tap carries on to Page Anchor's
	-- own touch zone underneath, which runs the action and closes this
	-- (see PageAnchor:handleHintTap). Closing here first would leave
	-- nothing for that tap to hit.
	if self.on_tap and ev and (ev.ges == "touch" or ev.ges == "tap")
			and ev.pos and self.dimen:contains(ev.pos) then
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
	self.return_baseline_location = nil
	self.controls_hidden = false
	self.pending_jump_origin = nil
	self.auto_dismiss_fn = nil
	self.hidden_expiry_fn = nil
	self.pinned_location = nil
	self.last_discarded = nil
	self.button_specs = nil
	self.button_specs_computed = false
	self.hint_widget = nil
	self.hint_dismiss_fn = nil
	self._installed = false

	self:patchIconWidget()
	self:onDispatcherRegisterActions()

	if self.ui and self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end
	self.ui:registerPostInitCallback(function()
		self:installOverlay()
	end)
end

-- Gesture/hotkey actions (and, through them, Quick Dock buttons): a way to
-- bring hidden buttons back, or to act on the anchor directly, without
-- opening the Page Anchor menu. Reader-only, like the plugin itself.
function PageAnchor:onDispatcherRegisterActions()
	Dispatcher:registerAction("pageanchor_toggle_buttons", {
		category = "none",
		event = "PageAnchorToggleButtons",
		title = _("Page Anchor: show/hide buttons"),
		reader = true,
	})
	Dispatcher:registerAction("pageanchor_switch", {
		category = "none",
		event = "PageAnchorSwitch",
		title = _("Page Anchor: go to anchor / return point"),
		reader = true,
	})
	Dispatcher:registerAction("pageanchor_pin", {
		category = "none",
		event = "PageAnchorPin",
		title = _("Page Anchor: pin anchor here"),
		reader = true,
	})
	Dispatcher:registerAction("pageanchor_discard", {
		category = "none",
		event = "PageAnchorDiscard",
		title = _("Page Anchor: discard anchor"),
		reader = true,
	})
	Dispatcher:registerAction("pageanchor_undo", {
		category = "none",
		event = "PageAnchorUndo",
		title = _("Page Anchor: restore discarded anchor"),
		reader = true,
		separator = true,
	})
end

-- Gesture actions fire blind (no button on screen to show what happened),
-- so each one confirms itself through KOReader's own notification, which
-- honours the user's "notifications from gestures" preference.
local function notify(text)
	Notification:notify(text, Notification.SOURCE_DISPATCHER)
end

function PageAnchor:onPageAnchorToggleButtons()
	if not self:hasTargets() then
		notify(_("No anchor to show"))
	elseif self.controls_hidden then
		self:showControls()
	else
		self:hideControls()
	end
	return true
end

-- Back to the anchor while away from it; back out to the return point once
-- there -- the same thing the arrow segment does, from any gesture.
function PageAnchor:onPageAnchorSwitch()
	if self.anchor then
		self:activate(ACTION_BACK)
	elseif self.forward_target then
		self:activate(ACTION_FORWARD)
	else
		notify(_("No anchor to show"))
	end
	return true
end

function PageAnchor:onPageAnchorDiscard()
	if self:hasTargets() then
		self:discardWithUndo()
	else
		notify(_("No anchor to show"))
	end
	return true
end

function PageAnchor:onPageAnchorPin()
	if self:pinHere() then
		notify(_("Anchor pinned here"))
	end
	return true
end

function PageAnchor:onPageAnchorUndo()
	if not self:restoreDiscarded() then
		notify(_("Nothing to restore"))
	end
	return true
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
	for i = 1, #DESTINATION_FORMAT_OPTIONS do
		if DESTINATION_FORMAT_OPTIONS[i].value == value then
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

function PageAnchor:getHideMode()
	local value = G_reader_settings:readSetting(SETTING_HIDE_MODE)
	return value == HIDE_MODE_HIDE and HIDE_MODE_HIDE or HIDE_MODE_MINIMIZE
end

function PageAnchor:setHideMode(mode)
	G_reader_settings:saveSetting(SETTING_HIDE_MODE, mode == HIDE_MODE_HIDE and HIDE_MODE_HIDE or HIDE_MODE_MINIMIZE)
	self:_onDisplaySettingChanged()
end

-- Hides the floating buttons after a period without any relevant activity,
-- so one left on screen doesn't linger forever. Hiding is all it does: the
-- anchor and the forward target stay, so a long read away from the anchor
-- never costs the way back (see hideControls/showControls). Follows Reader
-- Header/Footer's own schedule/cancel-by-reference pattern: a self-nilling
-- closure, scheduled and unscheduled by that same stored reference.
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
		self:hideControls()
	end
	UIManager:scheduleIn(seconds, self.auto_dismiss_fn)
end

-- Somewhere the buttons can take you right now.
function PageAnchor:hasNavTargets()
	return self.anchor ~= nil or self.forward_target ~= nil
end

-- Anything Page Anchor is holding on to, including a pinned anchor you are
-- currently standing on (nothing to navigate to yet, but still something
-- to discard).
function PageAnchor:hasTargets()
	return self:hasNavTargets() or self.pinned_location ~= nil
end

function PageAnchor:areControlsHidden()
	return self.controls_hidden and self:hasTargets()
end

-- Takes the floating buttons off screen while keeping both targets, so they
-- can be brought back (showControls) with the way back intact.
function PageAnchor:hideControls()
	self:cancelAutoDismiss()
	if self.controls_hidden then
		return
	end
	self.controls_hidden = true
	self:scheduleHiddenExpiry()
	self:invalidateButtonSpecs()
	self:refresh()
end

function PageAnchor:getHiddenExpirySeconds()
	local value = G_reader_settings:readSetting(SETTING_HIDDEN_EXPIRY_SECONDS)
	if type(value) == "number" then
		return value
	end
	return HIDDEN_EXPIRY_DEFAULT_SECONDS
end

function PageAnchor:setHiddenExpirySeconds(seconds)
	G_reader_settings:saveSetting(SETTING_HIDDEN_EXPIRY_SECONDS, seconds)
	-- Restart a pending countdown with the new duration (or drop it, for
	-- "Never"), rather than waiting for the next hide to pick it up.
	if self:areControlsHidden() then
		self:scheduleHiddenExpiry()
	end
end

function PageAnchor:cancelHiddenExpiry()
	if self.hidden_expiry_fn then
		UIManager:unschedule(self.hidden_expiry_fn)
		self.hidden_expiry_fn = nil
	end
end

-- Started when the buttons get hidden, cancelled when they come back (or
-- the anchor is dismissed some other way); see HIDDEN_EXPIRY_OPTIONS.
function PageAnchor:scheduleHiddenExpiry()
	self:cancelHiddenExpiry()
	local seconds = self:getHiddenExpirySeconds()
	-- A pinned anchor was asked for explicitly and stays until dismissed.
	if not seconds or seconds <= 0 or self.pinned_location then
		return
	end
	self.hidden_expiry_fn = function()
		self.hidden_expiry_fn = nil
		if self:areControlsHidden() then
			self:clearHistory()
		end
	end
	UIManager:scheduleIn(seconds, self.hidden_expiry_fn)
end

-- Brings hidden buttons back and restarts the inactivity timer. Called from
-- the menu, and whenever something new happens that the buttons should
-- announce (a new anchor, arriving back at the anchor).
function PageAnchor:showControls()
	local was_hidden = self.controls_hidden
	self.controls_hidden = false
	self:cancelHiddenExpiry()
	if self:hasNavTargets() then
		self:scheduleAutoDismiss()
	end
	if was_hidden then
		self:invalidateButtonSpecs()
		self:refresh()
	end
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
	if self.controls_hidden then
		if self:getHideMode() ~= HIDE_MODE_MINIMIZE or not self:hasNavTargets() then
			return nil
		end
		-- Parked in the corner the full control would use, so expanding it
		-- doesn't make the buttons jump to the other side.
		local side = self.anchor and self:getTargetSide(self.anchor, -1)
			or self:getTargetSide(self.forward_target, 1)
		return {
			action = ACTION_SHOW,
			side = side,
			icon = ICON_ANCHOR,
			minimized = true,
		}
	end

	if self.anchor then
		local side = self:getTargetSide(self.anchor, -1)
		return {
			action = ACTION_BACK,
			side = side,
			icon = side == "left" and ICON_CHEVRON_LEFT or ICON_CHEVRON_RIGHT,
			label = self:getDestinationLabel(self.anchor),
			dismiss_marked = false,
			pinned = self.pinned_location ~= nil,
		}
	elseif self.forward_target then
		local side = self:getTargetSide(self.forward_target, 1)
		return {
			action = ACTION_FORWARD,
			side = side,
			icon = side == "left" and ICON_CHEVRON_LEFT or ICON_CHEVRON_RIGHT,
			label = self:getDestinationLabel(self.forward_target),
			dismiss_marked = true,
			pinned = self.pinned_location ~= nil,
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
	if action == ACTION_SHOW then
		text = _("Anchor kept · tap to show the buttons")
	elseif action == ACTION_DISMISS then
		if spec.pinned then
			text = spec.dismiss_marked and _("This is the pinned anchor") or _("Discard the pinned anchor and continue here")
		else
			text = spec.dismiss_marked and _("This is the starting position") or _("Continue here")
		end
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

-- opts (all optional): pill_dimen/pill_side to place it against a pill
-- that's no longer on screen (the undo notice, after a discard removed
-- it); in_place to sit where the pill was instead of above it; on_tap to
-- make it tappable; icon to show a trailing action icon; seconds to
-- override how long it stays up.
function PageAnchor:showHint(text, opts)
	opts = opts or {}
	self:closeHint()
	local pill_dimen = opts.pill_dimen or self.overlay.pill_dimen
	local pill_side = opts.pill_side or self.overlay.pill_side
	if not self.ui or not pill_dimen or not pill_side then
		return
	end

	local margin = self:getButtonMetrics().margin
	local screen_width = Screen:getWidth()
	local frame_extra = 2 * (Size.border.button + Size.padding.default)
	-- Long chapter titles wrap instead of running off screen: the text box
	-- is as wide as the text needs, up to the screen width minus both
	-- margins and the frame around it.
	text = BD.ltr(tostring(text or ""))
	local face = Font:getFace("cfont", HINT_FONT_SIZE)
	-- opts.icon: a trailing action icon (the undo arrow), set off from the
	-- text by the same kind of divider that splits the pill's segments.
	local icon_size = Screen:scaleBySize(HINT_FONT_SIZE + 4)
	local gap = Size.padding.default
	local icon_extra = opts.icon and (icon_size + 2 * gap + Size.line.medium) or 0
	local max_text_width = math.max(1, screen_width - 2 * margin - frame_extra - icon_extra)
	local measure = TextWidget:new({ text = text, face = face, bold = true })
	local natural_width = measure:getSize().w
	measure:free()
	local content = TextBoxWidget:new({
		text = text,
		face = face,
		bold = true,
		width = math.min(natural_width + 1, max_text_width),
	})
	if opts.icon then
		local line_height = math.max(content:getSize().h, icon_size)
		local row = {
			content,
			HorizontalSpan:new({ width = gap }),
			LineWidget:new({
				background = Blitbuffer.COLOR_GRAY,
				dimen = Geom:new({ w = Size.line.medium, h = line_height }),
			}),
			HorizontalSpan:new({ width = gap }),
			IconWidget:new({
				icon = ICONS_DIR .. opts.icon,
				width = icon_size,
				height = icon_size,
			}),
		}
		row.allow_mirroring = false
		content = HorizontalGroup:new(row)
	end
	local panel = FrameContainer:new({
		background = Blitbuffer.COLOR_WHITE,
		bordersize = Size.border.button,
		color = Blitbuffer.COLOR_BLACK,
		radius = Size.radius.button,
		margin = 0,
		padding = Size.padding.default,
		content,
	})
	local panel_size = panel:getSize()
	local left = pill_side == "left"
		and margin
		or screen_width - margin - panel_size.w
	left = math.max(0, math.min(left, screen_width - panel_size.w))
	local top
	if opts.in_place then
		-- Bottom-aligned with where the pill was: inside Page Anchor's own
		-- touch zone, which is what makes on_tap reachable at all.
		top = pill_dimen.y + pill_dimen.h - panel_size.h
	else
		top = pill_dimen.y - Size.padding.default - panel_size.h
	end
	top = math.max(0, top)

	local hint = HintToast:new({
		owner = self,
		panel = panel,
		on_tap = opts.on_tap,
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
	UIManager:scheduleIn(opts.seconds or HINT_DISMISS_SECONDS, self.hint_dismiss_fn)
end

-- Runs a tappable hint's action when the tap lands on it; see
-- HintToast:onGesture for why this goes through the overlay's touch zone.
function PageAnchor:handleHintTap(pos)
	local hint = self.hint_widget
	if not hint or not hint.on_tap or not hint.dimen:contains(pos) then
		return false
	end
	local on_tap = hint.on_tap
	self:closeHint()
	on_tap()
	return true
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

	self:patchReaderLink()

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
	self:unpatchReaderLink()
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

-- Explicit-jump detection. Every standard KOReader navigation tool (Go to
-- page, skim bar, table of contents, Book Map, page browser, bookmarks,
-- search results, internal links, next/previous chapter) calls
-- ReaderLink:addCurrentLocationToStack right before it jumps. Wrapping it
-- tells trackPage that the next position update is a jump whatever its
-- distance, so Go to page from 100 to 102 arms an anchor while a plain page
-- turn never does. Patched on this ReaderLink instance only, not the class,
-- and restored by putting back whatever the instance held before.
function PageAnchor:patchReaderLink()
	local link = self.ui and self.ui.link
	if self._link_patch or not link or type(link.addCurrentLocationToStack) ~= "function" then
		return
	end
	local original = link.addCurrentLocationToStack
	local plugin = self
	local patched = function(reader_link, loc)
		-- Never let a bug here get in the way of KOReader's own history.
		local ok, err = pcall(plugin.noteJumpOrigin, plugin, loc)
		if not ok then
			logger.warn("PageAnchor: noting jump origin failed:", err)
		end
		return original(reader_link, loc)
	end
	self._link_patch = {
		link = link,
		raw = rawget(link, "addCurrentLocationToStack"),
		patched = patched,
	}
	link.addCurrentLocationToStack = patched
end

function PageAnchor:unpatchReaderLink()
	if self.pending_jump_clear_fn then
		UIManager:unschedule(self.pending_jump_clear_fn)
		self.pending_jump_clear_fn = nil
	end
	self.pending_jump_origin = nil
	local patch = self._link_patch
	if not patch then
		return
	end
	self._link_patch = nil
	if patch.link.addCurrentLocationToStack ~= patch.patched then
		-- Same caution as unpatchIconWidget: something layered on top of
		-- ours, and restoring blindly would drop it.
		logger.warn("PageAnchor: ReaderLink.addCurrentLocationToStack changed unexpectedly during unpatch; leaving it as-is")
		return
	end
	rawset(patch.link, "addCurrentLocationToStack", patch.raw)
end

-- The origin only lives until the next UI tick: the jump itself follows
-- synchronously in the same handler, while a bare "Add current location to
-- history" gesture, with no jump behind it, must not leak into a later,
-- ordinary page turn.
function PageAnchor:noteJumpOrigin(loc)
	self.pending_jump_origin = loc or History.getCurrentLocation(self.ui)
	if not self.pending_jump_clear_fn then
		self.pending_jump_clear_fn = function()
			self.pending_jump_clear_fn = nil
			self.pending_jump_origin = nil
		end
		UIManager:nextTick(self.pending_jump_clear_fn)
	end
end

function PageAnchor:setReference(page, location)
	self.reference_page = page
	self.reference_location = location
end

-- The reference page, re-derived from the saved location every time: after
-- a font, margin or orientation change the same location lands on another
-- page number, and comparing against the stale number made the
-- repagination itself look like a jump. The stored number is only a
-- fallback for a location the document can no longer resolve.
function PageAnchor:getReferencePage()
	local page = History.getLocationPage(self.ui, self.reference_location)
	if page then
		self.reference_page = page
	end
	return self.reference_page
end

-- Whether moving from `location` to `page` goes beyond the reading
-- tolerance (see READING_TURNS_BEHIND/AHEAD), i.e. looks like a jump rather
-- than a page turn. False when there is no location to compare against.
function PageAnchor:isJumpFrom(location, page)
	local from_page = History.getLocationPage(self.ui, location)
	if not from_page then
		return false
	end
	local turns = History.countPageTurns(self.ui, from_page, page, READING_TURNS_AHEAD)
	return not (turns and turns >= -READING_TURNS_BEHIND)
end

-- Pins a new anchor with the given location as the way out, and shows the
-- buttons again if the inactivity timeout had hidden them.
function PageAnchor:armAnchor(anchor_location, current_location)
	-- A new trip supersedes whatever was discarded before it.
	self.last_discarded = nil
	self.anchor = anchor_location
	self.forward_target = current_location
	self.return_baseline_location = nil
	self:showControls()
end

function PageAnchor:activate(action)
	if not self.ui then
		return false
	end
	if action == ACTION_DISMISS then
		-- Word the notice after what dismissing actually did. Away from the
		-- anchor it moves your reading position here; already at the anchor
		-- (only the way back out is pending) the position stays put and
		-- dismissing just drops the buttons and that return point.
		if self.anchor then
			self:discardWithUndo(_("Anchor set here"))
		else
			self:discardWithUndo(_("Buttons dismissed"))
		end
		return true
	elseif action == ACTION_SHOW then
		self:showControls()
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
		self:setReference(History.getLocationPage(self.ui, anchor_location), anchor_location)
		self.return_baseline_location = anchor_location
		self:invalidateButtonSpecs()
		self:showControls()
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
		self.return_baseline_location = nil
		self:invalidateButtonSpecs()
		self:showControls()
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
-- corrupted across repeated back-and-forth navigation. ReaderLink is only
-- consulted as a signal that a jump is happening (see patchReaderLink).
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

	-- Consumed by the first update after the jump, whatever happens below,
	-- so one jump arms at most once (rolling documents send both a page and
	-- a position update for the same move).
	local jump_origin = self.pending_jump_origin
	self.pending_jump_origin = nil

	if not self.reference_location then
		self:setReference(page, current_location)
		return
	end

	if self.pinned_location then
		self:trackPinned(page, current_location, jump_origin)
		return
	end

	if self.anchor then
		if History.isCurrentLocation(self.ui, self.anchor) then
			-- Resolved: back at the anchor. forward_target already holds the
			-- most recent position visited while away (see the else branch
			-- below), or the jump's original destination if you returned
			-- immediately without wandering further.
			self.anchor = nil
			self:setReference(page, current_location)
			self.return_baseline_location = current_location
			self:showControls()
		else
			-- A new jump while away (announced, or too far from the last
			-- spot visited to be reading) is something the buttons should
			-- announce, so it brings them back if the timeout hid them;
			-- plain page turns leave hidden buttons hidden.
			local previous_target = self.forward_target
			self.forward_target = current_location
			if jump_origin or self:isJumpFrom(previous_target, page) then
				self:showControls()
			elseif not self.controls_hidden then
				self:scheduleAutoDismiss()
			end
		end
		return
	end

	if jump_origin and not History.isCurrentLocation(self.ui, jump_origin) then
		self:armAnchor(jump_origin, current_location)
		return
	end

	-- No announced jump: fall back to distance, for tools that move without
	-- going through ReaderLink's history (some third-party plugins).
	local turns = History.countPageTurns(self.ui, self:getReferencePage(), page, READING_TURNS_AHEAD)
	if turns and turns >= -READING_TURNS_BEHIND then
		-- Forward reading advances the reference. Going back a single turn
		-- is tolerated without moving it, so a second backward turn can
		-- still offer the last confirmed reading position.
		if turns >= 0 then
			self:setReference(page, current_location)
		end

		-- Just returned to the anchor and reading on: hide the forward
		-- target once enough pages have passed, so it does not linger
		-- indefinitely as a stale "go back out" option. Only reading
		-- forward counts -- stepping back a page to re-read the end of the
		-- previous one keeps the way back out.
		if self.forward_target and self.return_baseline_location then
			local dismiss_after = self:getForwardDismissPages()
			local baseline_page = History.getLocationPage(self.ui, self.return_baseline_location)
			if dismiss_after > 0 and baseline_page and page - baseline_page >= dismiss_after then
				self.forward_target = nil
				self.return_baseline_location = nil
				self.controls_hidden = false
				self:cancelAutoDismiss()
				self:cancelHiddenExpiry()
			end
		end
	else
		self:armAnchor(self.reference_location, current_location)
	end
end

-- A pinned anchor doesn't care how you leave it: any move away, a jump or
-- a plain page turn, offers the way back, and coming back never resolves
-- it -- it stays until discarded, so it can be returned to again and again.
-- The return point follows wherever you are while away.
function PageAnchor:trackPinned(page, current_location, jump_origin)
	if History.isCurrentLocation(self.ui, self.pinned_location) then
		if self.anchor then
			self.anchor = nil
			self:setReference(page, current_location)
			self:showControls()
		end
		return
	end
	if not self.anchor then
		self.anchor = self.pinned_location
		self.forward_target = current_location
		self.return_baseline_location = nil
		self:showControls()
		return
	end
	local previous_target = self.forward_target
	self.forward_target = current_location
	if jump_origin or self:isJumpFrom(previous_target, page) then
		self:showControls()
	elseif not self.controls_hidden then
		self:scheduleAutoDismiss()
	end
end

-- Pins the anchor at the current position before exploring: unlike one
-- set by a jump, it survives returning to it, the hidden-buttons expiry
-- and forward reading, until it's discarded.
function PageAnchor:pinHere()
	local location = History.getCurrentLocation(self.ui)
	if not location then
		return false
	end
	self:cancelAutoDismiss()
	self:cancelHiddenExpiry()
	self.last_discarded = nil
	self.pinned_location = location
	self.anchor = nil
	self.forward_target = nil
	self.return_baseline_location = nil
	self.controls_hidden = false
	self:setReference(self.ui:getCurrentPage(), location)
	self:invalidateButtonSpecs()
	self:refresh()
	return true
end

-- Everything restoreDiscarded needs to put a discarded trip back.
function PageAnchor:snapshotTargets()
	return {
		anchor = self.anchor,
		forward_target = self.forward_target,
		return_baseline_location = self.return_baseline_location,
		pinned_location = self.pinned_location,
		reference_location = self.reference_location,
		reference_page = self.reference_page,
	}
end

function PageAnchor:canRestoreDiscarded()
	return self.last_discarded ~= nil and not self:hasTargets()
end

-- Puts back what the last discard dropped. Only while nothing new has been
-- set up since (a new anchor clears the snapshot, and restoring over live
-- targets would silently lose them). If you've moved since, where you are
-- now becomes the return point.
function PageAnchor:restoreDiscarded()
	if not self:canRestoreDiscarded() then
		return false
	end
	local snapshot = self.last_discarded
	self.last_discarded = nil
	self.anchor = snapshot.anchor
	self.forward_target = snapshot.forward_target
	self.return_baseline_location = snapshot.return_baseline_location
	self.pinned_location = snapshot.pinned_location
	self:setReference(snapshot.reference_page, snapshot.reference_location)
	-- Where you are now decides how the snapshot fits: the anchor ("home")
	-- is the pinned spot, the pending anchor, or -- for a snapshot taken
	-- while already back at the anchor -- the spot you'd returned to.
	local current_location = History.getCurrentLocation(self.ui)
	local home = self.pinned_location or self.anchor or self.return_baseline_location
	if home and current_location then
		if History.isCurrentLocation(self.ui, home) then
			-- Back at the anchor since the discard: resolve it as if you'd
			-- just arrived, keeping the way back out. Restoring it as a
			-- pending anchor would make "back" point at this very page and
			-- overwrite the return point with it.
			self.anchor = nil
			self:setReference(self.ui:getCurrentPage(), current_location)
			self.return_baseline_location = current_location
		else
			self.anchor = home
			self.forward_target = current_location
			self.return_baseline_location = nil
		end
	end
	self.controls_hidden = true -- so showControls repaints
	self:showControls()
	return true
end

-- Discards like clearHistory, then offers a few seconds to take it back,
-- right where the buttons were -- or, when there was nothing on screen to
-- put the notice against (buttons fully hidden), a plain notification.
-- `text` words it after what the user just did: the anchor button sets the
-- reading position here ("Continue here"), while the discard gesture
-- action just discards. The undo arrow icon carries the "tap to undo".
function PageAnchor:discardWithUndo(text)
	text = text or _("Anchor discarded")
	local had_targets = self:hasTargets()
	local pill_dimen = self.overlay.pill_dimen
	local pill_side = self.overlay.pill_side
	self:clearHistory()
	if not had_targets then
		return
	end
	if pill_dimen and pill_side then
		self:showHint(text, {
			pill_dimen = pill_dimen,
			pill_side = pill_side,
			in_place = true,
			icon = ICON_UNDO,
			seconds = UNDO_HINT_SECONDS,
			on_tap = function()
				self:restoreDiscarded()
			end,
		})
	else
		notify(text)
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

-- Sent after a font/margin/orientation change re-paginated the book (after
-- the PageUpdate for the new layout). Locations are unaffected, but page
-- numbers and chapter positions in the hint text are not.
function PageAnchor:onDocumentRerendered()
	self:getReferencePage()
	self:invalidateButtonSpecs()
	self:refresh()
end

function PageAnchor:onCloseDocument()
	self:cancelAutoDismiss()
	self:cancelHiddenExpiry()
	self:uninstallOverlay()
	self:unpatchIconWidget()
end

function PageAnchor:stopPlugin()
	self:cancelAutoDismiss()
	self:cancelHiddenExpiry()
	self:uninstallOverlay()
	self:unpatchIconWidget()
	self:refresh()
	return true
end

-- The anchor button and the menu's "Discard anchor and return point" both
-- call this: it is how a new anchor gets accepted, by dropping the current
-- one (and any pending forward target) and restarting tracking fresh from
-- here.
function PageAnchor:clearHistory()
	if not self.ui then
		return
	end
	self:cancelAutoDismiss()
	self:cancelHiddenExpiry()
	if self:hasTargets() then
		self.last_discarded = self:snapshotTargets()
	end
	self.anchor = nil
	self.forward_target = nil
	self.return_baseline_location = nil
	self.pinned_location = nil
	self.controls_hidden = false
	self:setReference(self.ui:getCurrentPage(), History.getCurrentLocation(self.ui))
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
	-- Indexed (not "for _, option"): "_" would shadow the gettext function
	-- used as `_(option.label)` below for the rest of this loop body.
	for i = 1, #options do
		local option = options[i]
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
						help_text = _("Hides the floating buttons after this much time without navigation activity. The anchor is kept: tap the anchor tab (or use the show/hide gesture action) to bring them back."),
						sub_item_table = buildValueRadioItems(
							AUTO_DISMISS_OPTIONS,
							function() return self:getAutoDismissSeconds() end,
							function(value) self:setAutoDismissSeconds(value) end
						),
					},
					{
						text = _("When hiding"),
						help_text = _("What the timeout (or the show/hide gesture action) leaves on screen: a small anchor tab that brings the buttons back with one tap, or nothing."),
						sub_item_table = buildValueRadioItems(
							HIDE_MODE_OPTIONS,
							function() return self:getHideMode() end,
							function(value) self:setHideMode(value) end
						),
					},
					{
						text = _("Discard when hidden for"),
						help_text = _("If the buttons stay hidden (or parked as a tab) this long, the anchor is discarded and the current page becomes your reading position, as if you had tapped the anchor button. Never keeps them waiting until you dismiss them yourself."),
						sub_item_table = buildValueRadioItems(
							HIDDEN_EXPIRY_OPTIONS,
							function() return self:getHiddenExpirySeconds() end,
							function(value) self:setHiddenExpirySeconds(value) end
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
				text = _("Pin anchor here"),
				help_text = _("Marks the current position as the anchor before you go exploring. A pinned anchor stays, through any number of trips away and back, until you discard it."),
				callback = function()
					if self:pinHere() then
						notify(_("Anchor pinned here"))
					end
				end,
			},
			{
				-- Only enabled while the inactivity timeout has hidden the
				-- buttons and there is still somewhere to go.
				text = _("Show floating buttons"),
				help_text = _("Brings back floating buttons hidden by the inactivity timeout, with the anchor and the way back still in place."),
				enabled_func = function()
					return self:areControlsHidden()
				end,
				callback = function()
					self:showControls()
				end,
			},
			{
				-- Named after what it actually drops -- Page Anchor's own
				-- targets -- so it isn't mistaken for clearing KOReader's
				-- native location history, which it never touches.
				text = _("Discard anchor and return point"),
				help_text = _("Forgets the anchor and the return point and keeps reading from the current position. KOReader's own location history is not affected."),
				enabled_func = function()
					return self:hasTargets()
				end,
				callback = function()
					UIManager:show(ConfirmBox:new({
						text = _("Discard anchor and return point?"),
						ok_text = _("Discard"),
						ok_callback = function()
							self:clearHistory()
						end,
					}))
				end,
			},
			{
				text = _("Restore discarded anchor"),
				help_text = _("Brings back the anchor and return point you last discarded, as long as no new anchor has been set since."),
				separator = true,
				enabled_func = function()
					return self:canRestoreDiscarded()
				end,
				callback = function()
					self:restoreDiscarded()
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
