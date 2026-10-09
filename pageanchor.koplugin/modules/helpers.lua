-- Small helpers shared by several modules: gesture-action notifications,
-- the anchor segment's icon for a state, and metric scaling.

local Notification = require("ui/widget/notification")

local C = ...

-- Gesture actions fire blind (no button on screen to show what happened),
-- so each one confirms itself through KOReader's own notification, which
-- honours the user's "notifications from gestures" preference.
local function notify(text)
	Notification:notify(text, Notification.SOURCE_DISPATCHER)
end

-- The anchor segment's icon for a spec: at the anchor or not, pinned or not.
local function anchorIcon(spec)
	if spec.dismiss_marked then
		return spec.pinned and C.ICON_ANCHOR_HERE_PINNED or C.ICON_ANCHOR_HERE
	end
	return spec.pinned and C.ICON_ANCHOR_PINNED or C.ICON_ANCHOR
end

local function scaleMetric(value, factor, minimum)
	return math.max(minimum or 1, math.floor(value * factor + 0.5))
end

return {
	notify = notify,
	anchorIcon = anchorIcon,
	scaleMetric = scaleMetric,
}
