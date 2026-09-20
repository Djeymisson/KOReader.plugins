--[[
How many screen refreshes each user action asks KOReader for. On an e-ink
display that is what costs the most battery, so the aim is one refresh per
action and none repeated.

The run fails if an action asks for more than the refreshes listed in EXPECTED.
]]

-- Refreshes asked for by one action (the count of UIManager:setDirty calls).
-- Opening is 2 because the viewer marks itself dirty and UIManager:show marks
-- it again for the same region in the same tick, which KOReader merges into one;
-- closing is 2 for the same reason (the close and the widget beneath).
local EXPECTED = {
	["opening the viewer"] = 2,
	["turning a page"] = 1,
	["Go to word (the breadcrumb appears)"] = 1,
	["Go to word (again)"] = 1,
	["scrolling the breadcrumb"] = 1,
	["closing the viewer"] = 2,
}

return function(H, ui)
	local UIManager = require("ui/uimanager")
	local dictionary = H.dictionaries().by.pt or H.dictionaries().list[1]
	if not dictionary then
		H.skip("refresh counts", "no dictionary the plugin can open was found")
		H.finish()
		return
	end

	local recording, calls = false, {}
	local set_dirty = UIManager.setDirty
	UIManager.setDirty = function(manager, widget, refresh, region, ...)
		if recording then
			local mode = type(refresh) == "function" and (refresh()) or refresh
			local area = type(region) == "function" and region() or region
			calls[#calls + 1] = string.format("%s %s", tostring(mode), area and string.format("%dx%d", area.w or 0, area.h or 0) or "the widget's area")
		end
		return set_dirty(manager, widget, refresh, region, ...)
	end

	local function measure(name, action)
		calls, recording = {}, true
		action()
		recording = false
		H.check(name .. ": " .. #calls .. " refresh(es)", #calls <= EXPECTED[name], table.concat(calls, "; "))
	end

	H.step(1, function()
		local viewer
		measure("opening the viewer", function()
			viewer = H.newViewer(dictionary, H.profiles.pt.open)
			UIManager:show(viewer)
		end)
		measure("turning a page", function()
			viewer:showNext()
		end)
		measure("Go to word (the breadcrumb appears)", function()
			viewer:goToWord(H.profiles.pt.walk[2])
		end)
		measure("Go to word (again)", function()
			viewer:goToWord(H.profiles.pt.walk[3])
		end)
		measure("scrolling the breadcrumb", function()
			viewer.crumb_end = 1
			viewer:_refreshBreadcrumb()
		end)
		measure("closing the viewer", function()
			viewer:onClose()
		end)
		UIManager.setDirty = set_dirty
	end)

	H.finish()
end
