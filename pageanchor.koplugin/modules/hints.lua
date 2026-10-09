-- Hold hints and the tappable undo notice shown by the pill.

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local _ = require("pageanchor_l10n")

local Screen = Device.screen

local C = ...
local lib = select(2, ...)
local HintToast = lib.HintToast

local PageAnchor = {}

-- Shown on hold, above the pill: the info that no longer lives on the
-- button itself (the destination position, or what the anchor segment
-- would do right now).
function PageAnchor:showButtonHint(action)
	local spec = self:getButtonSpecs()
	if not spec then
		return false
	end
	local text
	if action == C.ACTION_SHOW then
		text = _("Anchor kept · tap to show the buttons")
	elseif action == C.ACTION_DISMISS then
		if spec.pinned then
			text = spec.dismiss_marked and _("This is the pinned anchor") or _("Discard the pinned anchor and continue here")
		else
			text = spec.dismiss_marked and _("This is the starting position") or _("Continue here")
		end
	elseif action == spec.action then
		-- With a trail, holding the arrow opens it instead (its first entry
		-- is this same destination).
		if self:showTrailDialog() then
			return true
		end
		text = self:getArrowText()
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
	local face = Font:getFace("cfont", C.HINT_FONT_SIZE)
	-- opts.icon: a trailing action icon (the undo arrow), set off from the
	-- text by the same kind of divider that splits the pill's segments.
	local icon_size = Screen:scaleBySize(C.HINT_FONT_SIZE + 4)
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
				icon = C.ICONS_DIR .. opts.icon,
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
	-- At the top of the screen the hint goes below the pill (and an in-place
	-- notice hangs from the pill's top edge); elsewhere above it (and
	-- bottom-aligned with it). In place keeps it inside Page Anchor's own
	-- touch zone, which is what makes on_tap reachable at all.
	local at_top = self:getVerticalPosition() == C.VERTICAL_TOP
	local top
	if opts.in_place then
		top = at_top and pill_dimen.y or (pill_dimen.y + pill_dimen.h - panel_size.h)
	elseif at_top then
		top = pill_dimen.y + pill_dimen.h + Size.padding.default
	else
		top = pill_dimen.y - Size.padding.default - panel_size.h
	end
	top = math.max(0, math.min(top, Screen:getHeight() - panel_size.h))

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

	-- Reused across hints; hint_dismiss_fn doubles as "is it scheduled".
	self._hint_dismiss_cb = self._hint_dismiss_cb or function()
		self.hint_dismiss_fn = nil
		self:closeHint()
	end
	self.hint_dismiss_fn = self._hint_dismiss_cb
	UIManager:scheduleIn(opts.seconds or C.HINT_DISMISS_SECONDS, self.hint_dismiss_fn)
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

return PageAnchor
