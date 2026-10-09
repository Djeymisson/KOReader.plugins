-- Discarding with undo: snapshots, the undo notice and restoring.

local _ = require("pageanchor_l10n")

local C = ...
local lib = select(2, ...)
local History = lib.History
local notify = lib.notify

local PageAnchor = {}

local function copyList(list)
	local copy = {}
	for i = 1, #list do
		copy[i] = list[i]
	end
	return copy
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
		trail = copyList(self.trail),
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
	self.trail = snapshot.trail or {}
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
			icon = C.ICON_UNDO,
			seconds = C.UNDO_HINT_SECONDS,
			on_tap = function()
				self:restoreDiscarded()
			end,
		})
	else
		notify(text)
	end
end

return PageAnchor
