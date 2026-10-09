-- The small non-blocking bubble used for hold hints and the undo notice.

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

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

return {
	HintToast = HintToast,
}
