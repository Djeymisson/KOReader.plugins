-- The trail: other places visited during a trip, and the list that offers them.

local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local _ = require("pageanchor_l10n")

local C = ...
local lib = select(2, ...)
local History = lib.History

local PageAnchor = {}

-- Trail bookkeeping. Locations are compared by page: one entry per page,
-- and a page already reachable some other way (the anchor, the return
-- point, where you are) is left out when the trail is offered.
local function samePage(ui, a, b)
	local page_a = History.getLocationPage(ui, a)
	return page_a ~= nil and page_a == History.getLocationPage(ui, b)
end

function PageAnchor:pushTrail(location)
	if not location then
		return
	end
	self:removeFromTrail(location)
	table.insert(self.trail, location)
	while #self.trail > C.TRAIL_MAX do
		table.remove(self.trail, 1)
	end
end

function PageAnchor:removeFromTrail(location)
	for i = #self.trail, 1, -1 do
		if samePage(self.ui, self.trail[i], location) then
			table.remove(self.trail, i)
		end
	end
end

-- The trail as offered right now, newest first.
function PageAnchor:getVisibleTrail()
	local current = History.getCurrentLocation(self.ui)
	local home = self.pinned_location or self.anchor or self.return_baseline_location
	local visible = {}
	for i = #self.trail, 1, -1 do
		local location = self.trail[i]
		if not samePage(self.ui, location, current)
				and not samePage(self.ui, location, home)
				and not samePage(self.ui, location, self.forward_target) then
			visible[#visible + 1] = location
		end
	end
	return visible
end

-- With a trail to offer: a list with the arrow's own destination first
-- (worded like the hold hint), then the trail. Returns false when there's
-- no trail, so holding the arrow shows the plain hint instead.
function PageAnchor:showTrailDialog()
	-- Built from the trip itself (getArrowTarget), not from the on-screen
	-- buttons, so it works the same with the buttons minimized, hidden or
	-- disabled (the gesture action opens it then too).
	local action = self:getArrowTarget()
	if not action then
		return false
	end
	local trail = self:getVisibleTrail()
	if #trail == 0 then
		return false
	end
	local arrow_text = self:getArrowText()
	self:closeHint()
	local dialog
	local buttons = {
		{
			{
				text = arrow_text,
				callback = function()
					UIManager:close(dialog)
					self:activate(action)
				end,
			},
		},
	}
	-- Indexed, not "for _, location": "_" is gettext in this file.
	for i = 1, #trail do
		local location = trail[i]
		local label = self:getDestinationLabel(location)
		buttons[#buttons + 1] = {
			{
				text = label,
				callback = function()
					UIManager:close(dialog)
					self:goToTrail(location)
				end,
			},
		}
	end
	dialog = ButtonDialog:new({
		title = _("Places visited on this trip"),
		title_align = "center",
		buttons = buttons,
	})
	UIManager:show(dialog)
	return true
end

-- Goes to a trail entry. The spot being left joins the trail, the entry
-- becomes the return point, and the anchor stays where it is -- or, if
-- you were standing on the anchor, it's re-armed there, as the forward
-- button would.
function PageAnchor:goToTrail(location)
	if not location then
		return false
	end
	local departure
	if self.anchor then
		departure = self:departureLocation(self.forward_target)
	else
		departure = self:departureLocation(self.return_baseline_location)
	end
	local at_anchor = self.anchor == nil
	self:removeFromTrail(location)
	if not at_anchor then
		self:pushTrail(departure)
	elseif self.forward_target then
		self:pushTrail(self.forward_target)
	end
	self:goToLocation(location)
	if at_anchor then
		self.anchor = departure
	end
	self.forward_target = location
	self.return_baseline_location = nil
	self:removeFromTrail(location)
	self:invalidateButtonSpecs()
	self:showControls()
	return true
end

return PageAnchor
