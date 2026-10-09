-- What the floating control shows and when: the button spec, labels and side,
-- hiding and showing (with their timers), and repainting its area.

local BD = require("ui/bidi")
local Device = require("device")
local Geom = require("ui/geometry")
local logger = require("logger")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local _ = require("pageanchor_l10n")
local T = require("ffi/util").template

local Screen = Device.screen

local C = ...
local lib = select(2, ...)
local History = lib.History

local PageAnchor = {}

-- The text shown next to the arrow for `location`, or nil for none (the
-- setting is off, or the distance can't be worked out / is zero). The
-- distance is signed, with a real minus sign, counted from the page on
-- screen -- the arrow already says which way, the number says how far.
function PageAnchor:getInlineLabel(location)
	local mode = self:getInlineLabelMode()
	if mode == C.INLINE_LABEL_PAGE then
		return History.getPageLabel(self.ui, location)
	elseif mode == C.INLINE_LABEL_DISTANCE then
		local target_page = History.getLocationPage(self.ui, location)
		local current_page = History.getLocationPage(self.ui, History.getCurrentLocation(self.ui))
			or tonumber(self.ui:getCurrentPage())
		if not target_page or not current_page or target_page == current_page then
			return nil
		end
		local distance = target_page - current_page
		-- "\226\136\146" is U+2212 MINUS SIGN as UTF-8 bytes (LuaJIT-safe,
		-- unlike a \u{} escape).
		return distance > 0 and ("+" .. distance) or ("\226\136\146" .. -distance)
	end
	return nil
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
	-- One callback per instance, reused on every (re)schedule: this runs on
	-- each page turn while away, and a fresh closure each time is just
	-- garbage. auto_dismiss_fn doubles as "is it scheduled".
	self._auto_dismiss_cb = self._auto_dismiss_cb or function()
		self.auto_dismiss_fn = nil
		if self:isSiblingOverlayBlockingDismiss() then
			-- Quick Dock's dock is open right now -- check again later
			-- instead of dismissing out from under it.
			self:scheduleAutoDismiss()
			return
		end
		self:hideControls()
	end
	self.auto_dismiss_fn = self._auto_dismiss_cb
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
	-- Reused like the auto-dismiss callback; hidden_expiry_fn doubles as
	-- "is it scheduled".
	self._hidden_expiry_cb = self._hidden_expiry_cb or function()
		self.hidden_expiry_fn = nil
		if self:areControlsHidden() then
			self:clearHistory()
		end
	end
	self.hidden_expiry_fn = self._hidden_expiry_cb
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
		if self:getHideMode() ~= C.HIDE_MODE_MINIMIZE or not self:hasNavTargets() then
			return nil
		end
		-- Parked in the corner the full control would use, so expanding it
		-- doesn't make the buttons jump to the other side.
		local side = self.anchor and self:getTargetSide(self.anchor, -1)
			or self:getTargetSide(self.forward_target, 1)
		return {
			action = C.ACTION_SHOW,
			side = side,
			icon = C.ICON_ANCHOR,
			minimized = true,
			pinned = self.pinned_location ~= nil,
		}
	end

	if self.anchor then
		local side = self:getTargetSide(self.anchor, -1)
		return {
			action = C.ACTION_BACK,
			side = side,
			icon = side == "left" and C.ICON_CHEVRON_LEFT or C.ICON_CHEVRON_RIGHT,
			inline_text = self:getInlineLabel(self.anchor),
			dismiss_marked = false,
			pinned = self.pinned_location ~= nil,
		}
	elseif self.forward_target then
		local side = self:getTargetSide(self.forward_target, 1)
		return {
			action = C.ACTION_FORWARD,
			side = side,
			icon = side == "left" and C.ICON_CHEVRON_LEFT or C.ICON_CHEVRON_RIGHT,
			inline_text = self:getInlineLabel(self.forward_target),
			dismiss_marked = true,
			pinned = self.pinned_location ~= nil,
		}
	end
	return nil
end

-- Where the arrow leads right now, from the trip itself rather than the
-- on-screen buttons (so it holds with them minimized or hidden): back to
-- the anchor while away from it, back out to the return point once there.
function PageAnchor:getArrowTarget()
	if self.anchor then
		return C.ACTION_BACK, self.anchor
	elseif self.forward_target then
		return C.ACTION_FORWARD, self.forward_target
	end
end

-- The arrow's hint text. ACTION_BACK genuinely returns to the anchor, so it
-- says so ("Back to") instead of the generic "Go to" ACTION_FORWARD keeps
-- (jumping *out* to wherever you'd wandered isn't really "back"). Built on
-- demand -- the chapter lookups behind the label only run when the text is
-- actually shown, not on every page turn.
function PageAnchor:getArrowText()
	local action, target = self:getArrowTarget()
	if not action then
		return nil
	end
	return T(action == C.ACTION_BACK and _("Back to %1") or _("Go to %1"), self:getDestinationLabel(target))
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
		if format == C.DESTINATION_FORMAT_PERCENTAGE_BOOK or format == C.DESTINATION_FORMAT_PERCENTAGE_CHAPTER then
			return History.getPercentageLabel(ui, location)
		end
		return T(_("page %1"), History.getPageLabel(ui, location))
	end

	if format == C.DESTINATION_FORMAT_TEXT_ONLY then
		return chapter.title
	end
	if format == C.DESTINATION_FORMAT_PERCENTAGE_CHAPTER then
		return T(_("%1 (%2 into this chapter)"), chapter.title, string.format("%.2f%%", chapter.percentage))
	end
	if format == C.DESTINATION_FORMAT_PAGE_CHAPTER then
		return T(_("%1 (page %2 of this chapter)"), chapter.title, chapter.page)
	end
	if format == C.DESTINATION_FORMAT_PERCENTAGE_BOOK then
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
	-- Every state change comes through here, so the anchor's on-screen
	-- visibility trackPage remembered (scroll mode) may be stale too.
	self.last_home_visible = nil
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
-- BUTTON_MARGIN's definition in constants.lua.
function PageAnchor:getOverlayClearance(side)
	local spec = self:getButtonSpecs()
	-- Only the bottom position shares the corner Quick Dock uses.
	if not spec or spec.side ~= side or self:getVerticalPosition() ~= C.VERTICAL_BOTTOM then
		return nil
	end
	local size = self.overlay:_getDock(spec).widget:getSize()
	return size.h + Size.padding.default
end

-- The band the pill lives in (the same one its touch zones cover).
function PageAnchor:getRefreshRegion()
	local zone = C.VERTICAL_ZONES[self:getVerticalPosition()]
	local height = Screen:getHeight()
	return Geom:new({
		x = 0,
		y = math.floor(height * zone.ratio_y),
		w = Screen:getWidth(),
		h = math.ceil(height * zone.ratio_h),
	})
end

-- Repaints the page under the floating control and refreshes only the
-- screen area it changed: where the control was before plus where it is
-- after (worked out once the repaint is done, which is when KOReader calls
-- the refresh function), rather than the whole band. On e-ink a smaller
-- partial update is faster, uses less power and ghosts less. When there's
-- nothing on screen and nothing to show, there's nothing to do at all --
-- not even the repaint. `before` is where the control was, for callers
-- that had to drop the overlay's cache (and with it that box) first.
function PageAnchor:refresh(refresh_type, before)
	if not (self.ui and self.ui.dialog) then
		return
	end
	before = before or self.overlay.pill_dimen
	before = before and before:copy()
	if not before and self._installed and not self:getButtonSpecs() then
		return
	end
	UIManager:setDirty(self.ui.dialog, function()
		local after = self.overlay.pill_dimen
		local region
		if before and after then
			region = before:combine(after)
		else
			region = before or (after and after:copy())
		end
		if region then
			-- A border's width of slack for the frame's anti-aliased edge.
			local pad = Size.border.button
			region = Geom:new({
				x = region.x - pad,
				y = region.y - pad,
				w = region.w + 2 * pad,
				h = region.h + 2 * pad,
			})
		else
			-- Not painted before or after (e.g. right after uninstalling):
			-- fall back to the whole band it can occupy.
			region = self:getRefreshRegion()
		end
		-- "ui" (non-flashing) is the right waveform for this small floating
		-- overlay: on e-ink, a flash sweeps the full panel black/white and
		-- costs noticeably more time and battery than a partial update, and
		-- this region is too small to need one to avoid ghosting.
		return refresh_type or "ui", region
	end)
end

return PageAnchor
