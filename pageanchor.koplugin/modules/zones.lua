-- Installing the overlay on the reader: the view paint hook and the touch zones.

local Device = require("device")

local Screen = Device.screen

local C = ...

local PageAnchor = {}

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
		-- Only on screen. The view also gets painted into other buffers to
		-- capture the page itself -- ReaderThumbnail does it for every
		-- Page browser / Book map thumbnail -- and the floating buttons
		-- don't belong to the page. Skipping those also keeps their
		-- coordinates out of the buttons' hit areas.
		if bb == Screen.bb then
			plugin.overlay:paintTo(bb, x, y)
		end
	end

	self:patchReaderLink()

	self:registerOverlayZones()
end

-- Registers (or re-registers: same ids replace the old ones) the tap, hold
-- and swipe zones over the pill's band. They take precedence over every
-- zone known at that moment -- KOReader's own and other plugins' -- and
-- just pass through anything not on the pill. Called at install, again
-- once the book is ready (some plugins only register their zones then, and
-- would otherwise end up above ours), and when the position changes.
function PageAnchor:registerOverlayZones()
	if not self.ui or not self.ui.registerTouchZones then
		return
	end
	local own = { pageanchor_tap = true, pageanchor_hold = true, pageanchor_swipe = true }
	local overrides = {}
	local seen = {}
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
	for _, id in ipairs(known_overrides) do
		seen[id] = true
		overrides[#overrides + 1] = id
	end
	for id in pairs(self.ui._zones or {}) do
		if not seen[id] and not own[id] then
			seen[id] = true
			overrides[#overrides + 1] = id
		end
	end
	local band = C.VERTICAL_ZONES[self:getVerticalPosition()]
	local screen_zone = { ratio_x = 0, ratio_y = band.ratio_y, ratio_w = 1, ratio_h = band.ratio_h }
	self.ui:registerTouchZones({
		{
			id = "pageanchor_tap",
			ges = "tap",
			screen_zone = screen_zone,
			handler = function(gesture)
				return self.overlay:handleTap(gesture)
			end,
			overrides = overrides,
		},
		{
			id = "pageanchor_hold",
			ges = "hold",
			screen_zone = screen_zone,
			handler = function(gesture)
				return self.overlay:handleHold(gesture)
			end,
			overrides = overrides,
		},
		{
			id = "pageanchor_swipe",
			ges = "swipe",
			screen_zone = screen_zone,
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

return PageAnchor
