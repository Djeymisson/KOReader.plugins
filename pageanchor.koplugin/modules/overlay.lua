-- The floating control: the pill (arrow and anchor segments) and the
-- minimized tab, how they're painted over the page, and their hit-testing.

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen

local C = ...
local lib = select(2, ...)
local anchorIcon = lib.anchorIcon

local FloatingHistoryOverlay = WidgetContainer:extend({})
local AnchorTab -- defined below, used by _makeDock for the compact style

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
	self.layout_dock = nil
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
	if self.owner:isCompactStyle() then
		-- Lower segments in the compact tab (see compact_height); every
		-- builder below reads the height from here.
		metrics = setmetatable({ height = metrics.compact_height }, { __index = metrics })
	end
	if spec.minimized then
		return self:_makeTab(spec, metrics)
	end
	local action_button
	if spec.inline_text then
		action_button = self:_makeLabeledSegment(spec, metrics)
	else
		action_button = Button:new({
			icon = C.ICONS_DIR .. spec.icon,
			icon_width = metrics.icon_size,
			icon_height = metrics.icon_size,
			width = metrics.segment_width,
			height = metrics.height,
			bordersize = 0,
			margin = 0,
			padding = 0,
		})
	end
	-- Marked (you're back at the anchor) shows through the icon itself; see
	-- ICON_ANCHOR_HERE.
	local dismiss_button = Button:new({
		icon = C.ICONS_DIR .. anchorIcon(spec),
		icon_width = metrics.icon_size,
		icon_height = metrics.icon_size,
		width = metrics.segment_width,
		height = metrics.height,
		bordersize = 0,
		margin = 0,
		padding = 0,
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

	local widget
	if self.owner:isCompactStyle() then
		-- Compact: the same segments in a tab growing out of the bottom
		-- edge. Same side insets as the floating pill (so dismiss_x below
		-- holds for both), but no bottom border and no outer padding below.
		local border = Size.border.button
		widget = AnchorTab:new({
			edge = "bottom",
			width = content_size.w + 2 * (metrics.padding + border),
			height = self:_compactHeight(metrics),
			radius = Size.radius.button,
			bordersize = border,
			child = dock_content,
		})
	else
		widget = FrameContainer:new({
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
	end

	local dismiss_offset = spec.side == "left" and (content_size.w - dismiss_size.w) or 0
	return {
		widget = widget,
		dismiss_x = metrics.padding + Size.border.button + dismiss_offset,
		dismiss_w = dismiss_size.w,
	}
end

-- The arrow segment with the destination written next to it. The arrow
-- stays on the outer edge, pointing where it leads ("‹ 100" on the left,
-- "100 ›" on the right), and the segment grows with the text but never
-- gets narrower than the icon-only one. A plain group rather than a
-- Button, since Button shows an icon or a text, not both; taps are
-- hit-tested by the overlay anyway (see paintTo).
function FloatingHistoryOverlay:_makeLabeledSegment(spec, metrics)
	local icon = IconWidget:new({
		icon = C.ICONS_DIR .. spec.icon,
		width = metrics.icon_size,
		height = metrics.icon_size,
	})
	local label = TextWidget:new({
		text = spec.inline_text,
		face = Font:getFace("cfont", metrics.label_font_size),
		bold = true,
	})
	local gap = HorizontalSpan:new({ width = Size.padding.small })
	local row = spec.side == "left" and { icon, gap, label } or { label, gap, icon }
	row.allow_mirroring = false
	local group = HorizontalGroup:new(row)
	return CenterContainer:new({
		dimen = Geom:new({
			w = math.max(metrics.segment_width, group:getSize().w + 2 * metrics.side_padding),
			h = metrics.height,
		}),
		group,
	})
end

-- A tab growing out of one screen edge ("left", "right" or "bottom"),
-- holding `child` centered: the minimized tab glued to the side, and the
-- whole compact-style control and undo notice glued to the bottom. Drawn
-- by hand instead of with a FrameContainer, which can only round all four
-- corners: here the inner corners are rounded and the screen-edge side is
-- square and borderless, like a tab pulled out of the edge of the page.
-- Everything is painted inside the screen -- the outer side is squared off
-- by overpainting, never by drawing past the edge, which not every
-- blitbuffer path clips.
AnchorTab = Widget:extend({
	edge = "right",
	width = 0,
	height = 0,
	radius = 0,
	bordersize = 0,
	border_color = Blitbuffer.COLOR_DARK_GRAY,
	child = nil,
})

function AnchorTab:getSize()
	return Geom:new({ w = self.width, h = self.height })
end

function AnchorTab:paintTo(bb, x, y)
	local w, h, bw = self.width, self.height, self.bordersize
	local r = math.min(self.radius, math.floor(w / 2), math.floor(h / 2))
	local white, color = Blitbuffer.COLOR_WHITE, self.border_color
	bb:paintRoundedRect(x, y, w, h, white, r)
	bb:paintBorder(x, y, w, h, bw, color, r)
	if self.edge == "bottom" then
		if r > 0 then
			-- White over the bottom corners and border, then carry the
			-- side edges down to the screen edge.
			local edge_y = y + h - r
			bb:paintRect(x, edge_y, w, r, white)
			bb:paintRect(x, edge_y, bw, r, color)
			bb:paintRect(x + w - bw, edge_y, bw, r, color)
		else
			bb:paintRect(x + bw, y + h - bw, w - 2 * bw, bw, white)
		end
	elseif r > 0 then
		-- Square off the screen-edge side: white over its rounded corners
		-- and side border, then carry the top and bottom edges across.
		local edge_x = self.edge == "left" and x or x + w - r
		bb:paintRect(edge_x, y, r, h, white)
		bb:paintRect(edge_x, y, r, bw, color)
		bb:paintRect(edge_x, y + h - bw, r, bw, color)
	else
		local edge_x = self.edge == "left" and x or x + w - bw
		bb:paintRect(edge_x, y + bw, bw, h - 2 * bw, white)
	end
	local child_size = self.child:getSize()
	-- Centered in what's drawn: a bottom tab has no border at the bottom.
	local inner_h = self.edge == "bottom" and (h + bw) or h
	self.child:paintTo(bb,
		x + math.floor((w - child_size.w) / 2),
		y + math.floor((inner_h - child_size.h) / 2))
end

function AnchorTab:free()
	if self.child and self.child.free then
		self.child:free()
	end
end

-- Height of the compact control: the low segments plus the top border
-- only -- no outer padding, and the bottom side is the screen edge.
function FloatingHistoryOverlay:_compactHeight(metrics)
	return metrics.compact_height + Size.border.button
end

-- Same height as the full control, so it sits exactly where the control
-- was and keeps Quick Dock's clearance (getOverlayClearance) unchanged when
-- it expands; only as wide as the icon plus a little air. Floating style:
-- glued to the side edge, with a tap target wider than what's drawn (see
-- paintTo), so narrow never means hard to hit. Compact style: glued to the
-- bottom edge like the compact control, in the same corner, and tapped
-- only where it's drawn, so it never takes a tap meant for what's beside
-- or above it (Quick Dock's dock, say).
function FloatingHistoryOverlay:_makeTab(spec, metrics)
	local border = Size.border.button
	local compact = self.owner:isCompactStyle()
	local widget = AnchorTab:new({
		edge = compact and "bottom" or spec.side,
		width = metrics.icon_size + 2 * Size.padding.default + (compact and 2 or 1) * border,
		height = compact and self:_compactHeight(metrics) or (metrics.height + 2 * (metrics.padding + border)),
		radius = Size.radius.button,
		bordersize = border,
		child = IconWidget:new({
			icon = C.ICONS_DIR .. (spec.pinned and C.ICON_ANCHOR_PINNED or C.ICON_ANCHOR),
			width = metrics.icon_size,
			height = metrics.icon_size,
		}),
	})
	return {
		widget = widget,
		minimized = true,
		flush_side = not compact,
		hit_width = not compact and (metrics.segment_width + 2 * (metrics.padding + border)) or nil,
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
		spec.inline_text or "",
		spec.pinned and "pinned" or "free",
		self.owner:getButtonSize(),
		self.owner:getStyle(),
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
		self.layout_dock = nil
		return
	end

	local dock = self:_getDock(spec)
	local widget = dock.widget
	local margin = self.owner:getButtonMetrics().margin
	local view = self.owner.ui.view
	local view_width = view and view.dimen and view.dimen.w or Screen:getWidth()
	local view_height = view and view.dimen and view.dimen.h or Screen:getHeight()
	local size = widget:getSize()
	-- The side tab is glued to the screen edge; everything else keeps a
	-- margin from the side (the compact style is glued to the bottom).
	local side_margin = dock.flush_side and 0 or margin
	local widget_x = spec.side == "left"
		and x + side_margin
		or x + view_width - size.w - side_margin
	local position = self.owner:getVerticalPosition()
	local widget_y
	if self.owner:isCompactStyle() then
		widget_y = y + view_height - size.h
	elseif position == C.VERTICAL_TOP then
		widget_y = y + margin
	elseif position == C.VERTICAL_MIDDLE then
		widget_y = y + math.floor((view_height - size.h) / 2)
	else
		widget_y = y + view_height - margin - size.h
	end

	-- The view repaints on every page turn while the control is up; its
	-- boxes only change with the widget or its position, so reuse them
	-- unless one of those changed.
	if self.layout_dock == dock and self.layout_x == widget_x and self.layout_y == widget_y
			and self.layout_action == spec.action and self.button_dimens then
		widget:paintTo(bb, widget_x, widget_y)
		return
	end
	self.layout_dock, self.layout_x, self.layout_y, self.layout_action = dock, widget_x, widget_y, spec.action

	-- Kept for the hold hint's own positioning (see PageAnchor:showHint),
	-- the swipe zone and refresh regions: the pill's on-screen box and its
	-- side.
	self.pill_dimen = Geom:new({ x = widget_x, y = widget_y, w = size.w, h = size.h })
	self.pill_side = spec.side

	if dock.minimized then
		-- The side tab's tap target reaches further into the page than the
		-- narrow tab; the compact one's is just the tab (no hit_width).
		local hit_w = math.max(size.w, dock.hit_width or size.w)
		local hit_x = spec.side == "left" and widget_x or widget_x + size.w - hit_w
		self.button_dimens = {
			{ action = C.ACTION_SHOW, dimen = Geom:new({ x = hit_x, y = widget_y, w = hit_w, h = size.h }) },
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
		{ action = C.ACTION_DISMISS, dimen = dismiss_dimen },
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
		return self.owner:activate(C.ACTION_DISMISS)
	end
	return false
end

return {
	FloatingHistoryOverlay = FloatingHistoryOverlay,
	AnchorTab = AnchorTab,
}
