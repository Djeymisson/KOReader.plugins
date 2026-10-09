-- Position tracking: when an anchor is armed, followed, resolved or dropped,
-- the back/forward taps, pinned anchors and clearing.

local _ = require("pageanchor_l10n")

local C = ...
local lib = select(2, ...)
local History = lib.History

local PageAnchor = {}

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
	local turns_behind = self:getRereadTurns()
	local turns = History.countPageTurns(self.ui, from_page, page, math.max(C.READING_TURNS_AHEAD, turns_behind))
	return not (turns and turns >= -turns_behind and turns <= C.READING_TURNS_AHEAD)
end

-- Pins a new anchor with the given location as the way out, and shows the
-- buttons again if the inactivity timeout had hidden them.
function PageAnchor:armAnchor(anchor_location, current_location)
	-- A new trip supersedes whatever was discarded before it.
	self.last_discarded = nil
	if self.forward_target then
		-- Leaving again while a return point was pending (back at the
		-- anchor): same trip, and that old return point stays reachable
		-- from the trail.
		self:pushTrail(self.forward_target)
	elseif not self.anchor then
		self.trail = {}
	end
	self.anchor = anchor_location
	self.forward_target = current_location
	self.return_baseline_location = nil
	self:showControls()
end

-- Whether a saved location can stand in for the fresh one just read from
-- the reader. Only worth it -- and only safe -- for a location carrying an
-- exact line (marker_xpointer: a link origin or destination) that a fresh
-- location would lose, and only while the view is still the one it was
-- saved from: in page mode a page always shows the same view, so being on
-- its page is enough; in scroll mode the view must not have moved at all.
-- Anything else (every PDF view state, which also holds zoom and the
-- visible area, and any plain page-level location) is always taken fresh,
-- so a pan or scroll within the same page is never undone.
function PageAnchor:canReuseLocation(saved, fresh)
	if not saved or not saved.marker_xpointer or not self.ui or not self.ui.rolling then
		return false
	end
	if self.ui.view and self.ui.view.view_mode == "scroll" then
		return fresh ~= nil and fresh.xpointer == saved.xpointer
	end
	return History.isCurrentLocation(self.ui, saved)
end

-- The spot being left by a back/forward tap, which becomes the target of
-- the opposite button: `known` (the target that already pointed here) when
-- it can be reused (see canReuseLocation), else the fresh position.
function PageAnchor:departureLocation(known)
	local fresh = History.getCurrentLocation(self.ui)
	if self:canReuseLocation(known, fresh) then
		return known
	end
	return fresh
end

-- The return point while away follows wherever you are, except for an
-- update that leaves the view as it was (a redraw, a repeated position
-- event) while the return point holds the exact line refineJumpDestination
-- found.
function PageAnchor:followLocation(previous, current_location)
	if self:canReuseLocation(previous, current_location) then
		return previous
	end
	return current_location
end

function PageAnchor:activate(action)
	if not self.ui then
		return false
	end
	if action == C.ACTION_DISMISS then
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
	elseif action == C.ACTION_SHOW then
		self:showControls()
		return true
	elseif action == C.ACTION_BACK and self.anchor then
		-- Resolve right away instead of waiting for the reader's own
		-- page/position update event to notice we've arrived: that event
		-- lands after this call returns, so a repaint in between would still
		-- see the old anchor and show it for one extra frame (it took a
		-- second tap to "catch up" before this fix).
		local anchor_location = self.anchor
		local departure_location = self:departureLocation(self.forward_target)
		self:goToLocation(anchor_location)
		self.anchor = nil
		self.forward_target = departure_location
		self:setReference(History.getLocationPage(self.ui, anchor_location), anchor_location)
		self.return_baseline_location = anchor_location
		self:invalidateButtonSpecs()
		self:showControls()
		return true
	elseif action == C.ACTION_FORWARD and self.forward_target then
		-- Same reasoning as above, mirrored: re-arm the anchor at the spot
		-- being left immediately, rather than waiting for trackPage to infer
		-- it from the next position update.
		local target_location = self.forward_target
		-- Standing on the resolved anchor: return_baseline_location is that
		-- anchor, possibly with its exact line (a link origin).
		local departure_location = self:departureLocation(self.anchor or self.return_baseline_location)
		self:goToLocation(target_location)
		self.anchor = departure_location
		self.forward_target = target_location
		self.return_baseline_location = nil
		self:removeFromTrail(target_location)
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
	-- Fast path for updates that don't change the page and don't come from
	-- a jump: every scroll step in scroll mode, redraws, repeated position
	-- events. In page mode the same page is the same view, so none of them
	-- can arm, resolve or move an anchor; in scroll mode the view moves
	-- within a page, so the anchor (pinned or not) can leave or re-enter the
	-- screen without the page number changing -- that one transition still
	-- gets the full evaluation. Otherwise skip it (and the button respec and
	-- timer reschedule it implies); only keep the return point on the view
	-- while away, so going back still remembers exactly where you were.
	if page == self.last_tracked_page and not self.pending_jump_origin
			and not self:homeVisibilityChanged() then
		if self.anchor and self.forward_target then
			self.forward_target = self:followLocation(self.forward_target, History.getCurrentLocation(self.ui))
		end
		return
	end
	self.last_tracked_page = page
	self:evaluatePosition(page)
	self.last_home_visible = self:isHomeVisible()
end

-- The anchor to come back to (pinned or pending), and whether it's on screen.
function PageAnchor:isHomeVisible()
	local home = self.pinned_location or self.anchor
	return home ~= nil and History.isCurrentLocation(self.ui, home)
end

-- Scroll mode only (see trackPage): whether the anchor came into or went
-- out of view since the last full evaluation.
function PageAnchor:homeVisibilityChanged()
	local view = self.ui and self.ui.view
	if not (view and view.view_mode == "scroll") or not (self.pinned_location or self.anchor) then
		return false
	end
	-- Unknown (state changed outside trackPage: pin, back/forward, undo,
	-- trail; see invalidateButtonSpecs): evaluate.
	if self.last_home_visible == nil then
		return true
	end
	return self:isHomeVisible() ~= self.last_home_visible
end

-- The full evaluation of a position update (see trackPage).
function PageAnchor:evaluatePosition(page)

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
	-- Remembered so refineJumpDestination can tell, once the jump is over,
	-- whether the return point is still this jump's destination.
	self.jump_destination = jump_origin and current_location or nil

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
			self.forward_target = self:followLocation(previous_target, current_location)
			if jump_origin or self:isJumpFrom(previous_target, page) then
				-- An announced jump captured where it left from at that
				-- moment (a PDF's current pan/zoom, a link's exact line);
				-- the return point may lag behind that, so it's only the
				-- fallback for jumps that weren't announced.
				self:pushTrail(jump_origin or previous_target)
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
	local turns_behind = self:getRereadTurns()
	if self:isWayBackProtected(page) then
		turns_behind = math.max(turns_behind, C.READING_TURNS_BEHIND_PROTECTED)
	end
	local turns = History.countPageTurns(self.ui, self:getReferencePage(), page,
		math.max(C.READING_TURNS_AHEAD, turns_behind))
	if turns and turns >= -turns_behind and turns <= C.READING_TURNS_AHEAD then
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

-- Whether a way back is at stake (see READING_TURNS_BEHIND_PROTECTED): a
-- pending return point, or an undoable discard you haven't read past yet.
function PageAnchor:isWayBackProtected(page)
	if self.forward_target then
		return true
	end
	if not self:canRestoreDiscarded() then
		return false
	end
	local discard_page = History.getLocationPage(self.ui, self.discard_location)
	if not discard_page then
		return false
	end
	if page > discard_page then
		-- Read on past it: from here on the undo is left to the menu and
		-- the gesture action, and coming back no longer re-protects it.
		self.discard_location = nil
		return false
	end
	return true
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
		self:pushTrail(self.forward_target)
		self.forward_target = current_location
		self.return_baseline_location = nil
		self:showControls()
		return
	end
	local previous_target = self.forward_target
	self.forward_target = self:followLocation(previous_target, current_location)
	if jump_origin or self:isJumpFrom(previous_target, page) then
		self:pushTrail(jump_origin or previous_target) -- see the same in trackPage
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
	self.trail = {}
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
		-- Where the discard happened, so the undo stays protected only
		-- until you read on past it (see isWayBackProtected).
		self.discard_location = History.getCurrentLocation(self.ui)
	end
	self.anchor = nil
	self.forward_target = nil
	self.return_baseline_location = nil
	self.pinned_location = nil
	self.trail = {}
	self.controls_hidden = false
	self:setReference(self.ui:getCurrentPage(), History.getCurrentLocation(self.ui))
	self:invalidateButtonSpecs()
	self:refresh()
end

return PageAnchor
