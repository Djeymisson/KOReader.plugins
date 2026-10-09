-- Jump detection and navigation: the ReaderLink hook that announces jumps,
-- exact link destinations, and going to a saved location.

local Event = require("ui/event")
local logger = require("logger")
local UIManager = require("ui/uimanager")

local lib = select(2, ...)
local History = lib.History

local PageAnchor = {}

-- Jumps straight to a saved location, the same way ReaderLink's own
-- back/forward handlers do, without touching ReaderLink's history stacks --
-- the anchor and forward target are tracked entirely by PageAnchor itself
-- (see trackPage), so a real footnote/link jump elsewhere never interferes
-- with them, and vice versa.
--
-- Locations that know their exact line (marker_xpointer, see
-- refineJumpDestination) get KOReader's own brief margin marker on arrival.
-- In scroll mode every location is exact -- it's the top of the view, not
-- of a page -- so it's marked too. Page-top locations from ordinary page
-- turns aren't: the marker would always just point at the first line.
-- KOReader's "followed_link_marker" setting governs the marker either way.
function PageAnchor:goToLocation(location)
	if not location or not self.ui then
		return
	end
	if location.xpointer and not location.marker_xpointer
			and self.ui.view and self.ui.view.view_mode == "scroll" then
		location = { xpointer = location.xpointer, marker_xpointer = location.xpointer }
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
			self:refineJumpDestination()
		end
		UIManager:nextTick(self.pending_jump_clear_fn)
	end
end

-- Exact-line marker, part 2. A link jump's origin already arrives exact:
-- ReaderLink hands addCurrentLocationToStack the tapped link's position as
-- both xpointer and marker_xpointer, that becomes the anchor, and
-- RestoreBookLocation shows KOReader's own "followed link" marker there
-- when going back. The destination is the other half: during the jump
-- Page Anchor only sees the top of the new page, but once the jump has
-- finished ReaderRolling holds the exact target it went to. If that's more
-- precise than the page top (a link or footnote target rather than a page
-- jump), the return point remembers it -- until the next page turn
-- replaces it, at which point it's no longer where you were anyway.
function PageAnchor:refineJumpDestination()
	local target = self.jump_destination
	self.jump_destination = nil
	local rolling = self.ui and self.ui.rolling
	if not target or self.forward_target ~= target or not rolling
			or type(rolling.getBookLocation) ~= "function" then
		return
	end
	local ok, exact = pcall(rolling.getBookLocation, rolling)
	if not ok or type(exact) ~= "string" or exact == target.xpointer
			or not History.isCurrentLocation(self.ui, { xpointer = exact }) then
		return
	end
	-- Same split ReaderLink uses: in scroll mode go back to the same view
	-- and just mark the line; in page mode the exact xpointer lands on the
	-- same page anyway.
	local scroll = self.ui.view and self.ui.view.view_mode == "scroll"
	self.forward_target = {
		xpointer = scroll and target.xpointer or exact,
		marker_xpointer = exact,
	}
	self:invalidateButtonSpecs()
end

return PageAnchor
