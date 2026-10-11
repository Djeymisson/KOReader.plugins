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
	["Go to word with no entry (said on the page)"] = 1,
	-- The list is painted, and refreshed in its own area only (checked below).
	["opening the suggestions"] = 2,
	-- Closing the list marks the page beneath for repainting, and the new page
	-- is drawn in the same tick: KOReader merges them into one refresh.
	["choosing a suggestion"] = 2,
	-- The list's area, and the page beneath repainted into it (not refreshed).
	["closing the suggestions"] = 2,
	["scrolling the breadcrumb"] = 1,
	["closing the viewer"] = 2,
	-- Continuing an exploration costs what opening does (see above), and
	-- keeping where it is costs nothing on screen.
	["continuing an exploration"] = 2,
	["turning a page while the exploration is kept"] = 1,
	-- Nothing changes, so nothing may be redrawn.
	["swiping past the last page"] = 0,
	["swiping back from the first page"] = 0,
	["scrolling down on the last page"] = 0,
}

return function(H, ui)
	local UIManager = require("ui/uimanager")
	local by = H.dictionaries().by
	local dictionary, profile = by.pt, H.profiles.pt
	if not dictionary then
		dictionary, profile = by.fx, H.profiles.fx
	end
	if not dictionary then
		H.skip("refresh counts", "no dictionary the plugin can open was found")
		H.finish()
		return
	end

	-- KOReader's default settings hide notifications from "other sources" (and
	-- with no gesture behind it, a notification has no source at all), which
	-- would hide a notification an action asks for, and its refreshes: show
	-- them all here, so that such a notification is counted.
	local Notification = require("ui/widget/notification")
	local notification_mask = G_reader_settings:readSetting("notification_sources_to_show_mask")
	G_reader_settings:saveSetting("notification_sources_to_show_mask", Notification.SOURCE_ALL)
	Notification:resetNotifySource()

	local recording, calls, last_refresh = false, {}, nil
	local set_dirty = UIManager.setDirty
	UIManager.setDirty = function(manager, widget, refresh, region, ...)
		if recording then
			local mode, area = refresh, region
			if type(refresh) == "function" then
				mode, area = refresh() -- the region comes with the mode then
			end
			if type(area) == "function" then
				area = area()
			end
			last_refresh = { refresh, region }
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
			viewer = H.newViewer(dictionary, profile.open)
			UIManager:show(viewer)
		end)
		measure("turning a page", function()
			viewer:showNext()
		end)
		measure("Go to word (the breadcrumb appears)", function()
			viewer:goToWord(profile.walk[2])
		end)
		measure("Go to word (again)", function()
			viewer:goToWord(profile.walk[3])
		end)
		measure("Go to word with no entry (said on the page)", function()
			viewer:goToWord("qqqzzzz")
		end)
		measure("opening the suggestions", function()
			viewer:showSuggestions()
		end)
		-- The region of a refresh can be known only once things are laid out.
		UIManager:forceRePaint()
		local refresh, region = last_refresh[1], last_refresh[2]
		local last_area = region
		if type(refresh) == "function" then
			last_area = select(2, refresh())
		end
		local screen = require("device").screen
		H.check(
			"the suggestions refresh only their own area",
			last_area ~= nil and last_area.w * last_area.h < screen:getWidth() * screen:getHeight(),
			last_area and string.format("%dx%d of %dx%d", last_area.w, last_area.h, screen:getWidth(), screen:getHeight())
		)
		measure("choosing a suggestion", function()
			viewer.suggestions_dialog.buttons[1][1].callback()
		end)
		viewer:goToWord("qqqzzzz")
		viewer:showSuggestions()
		measure("closing the suggestions", function()
			UIManager:close(viewer.suggestions_dialog)
		end)
		measure("scrolling the breadcrumb", function()
			viewer.crumb_end = 1
			viewer:_refreshBreadcrumb()
		end)

		-- At the ends of the dictionary, through the real gesture and key paths.
		local area = viewer.html_widget.dimen
		local x, y = area.x + area.w / 2, area.y + area.h / 2
		viewer:goToPosition(dictionary:getCount() - 1)
		measure("swiping past the last page", function()
			H.gesture("swipe", x, y, { direction = "west" })
		end)
		-- What the page-turn keys and side taps do. A last page that scrolls
		-- would rightly scroll first, so start from its bottom.
		for _scroll = 1, 100 do
			if not viewer.html_widget:onScrollDown() then
				break
			end
		end
		measure("scrolling down on the last page", function()
			viewer:onScrollDown()
		end)
		viewer:goToPosition(0)
		measure("swiping back from the first page", function()
			H.gesture("swipe", x, y, { direction = "east" })
		end)

		measure("closing the viewer", function()
			viewer:onClose()
		end)

		local plugin = ui.dictionaryexplorer
		if plugin then
			plugin:openAt(dictionary, profile.open)
			local explored = H.findViewer()
			explored:showNext()
			explored:onClose()
			measure("continuing an exploration", function()
				plugin:continueExploring()
			end)
			explored = H.findViewer()
			measure("turning a page while the exploration is kept", function()
				explored:showNext()
			end)
			explored:onClose()
			G_reader_settings:delSetting("dictionaryexplorer_explorations")
		else
			H.skip("continuing an exploration", "the plugin is not active")
		end
		UIManager.setDirty = set_dirty
		G_reader_settings:saveSetting("notification_sources_to_show_mask", notification_mask)
	end)

	H.finish()
end
