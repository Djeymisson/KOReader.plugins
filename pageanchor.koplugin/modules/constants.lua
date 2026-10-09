-- Shared constants: settings keys, the options of each setting, actions, icons,
-- geometry and timings. Every other module receives this table as C.

local Device = require("device")
local Size = require("ui/size")

local Screen = Device.screen

local C = {}

C.PLUGIN_VERSION = "v1.15.2"

C.SETTING_ENABLED = "pageanchor_enabled"
C.SETTING_DESTINATION_FORMAT = "pageanchor_destination_format"
C.SETTING_BUTTON_SIZE = "pageanchor_button_size"
C.SETTING_AUTO_DISMISS_SECONDS = "pageanchor_auto_dismiss_seconds"
C.SETTING_FORWARD_DISMISS_PAGES = "pageanchor_forward_dismiss_pages"
C.SETTING_HIDE_MODE = "pageanchor_hide_mode"
C.SETTING_HIDDEN_EXPIRY_SECONDS = "pageanchor_hidden_expiry_seconds"
C.SETTING_INLINE_LABEL = "pageanchor_inline_label"
C.SETTING_VERTICAL_POSITION = "pageanchor_vertical_position"
C.SETTING_REREAD_TURNS = "pageanchor_reread_turns"

-- Format (page/percentage/text) and scope (book/chapter) used to be two
-- separate settings ("Format" and "Relative to" screens), but scope only
-- ever modified format, so they're one flat, self-describing list now --
-- each option already says both what it shows and what it's measured
-- against, instead of asking the user to combine two screens in their head.
C.DESTINATION_FORMAT_PAGE_BOOK = "page_book"
C.DESTINATION_FORMAT_PAGE_CHAPTER = "page_chapter"
C.DESTINATION_FORMAT_PERCENTAGE_BOOK = "percentage_book"
C.DESTINATION_FORMAT_PERCENTAGE_CHAPTER = "percentage_chapter"
C.DESTINATION_FORMAT_TEXT_ONLY = "text_only"
C.DESTINATION_FORMAT_OPTIONS = {
	{ value = C.DESTINATION_FORMAT_PAGE_BOOK, label = "Page number of the book" },
	{ value = C.DESTINATION_FORMAT_PAGE_CHAPTER, label = "Page number in this chapter" },
	{ value = C.DESTINATION_FORMAT_PERCENTAGE_BOOK, label = "Percentage of the book" },
	{ value = C.DESTINATION_FORMAT_PERCENTAGE_CHAPTER, label = "Percentage in this chapter" },
	{ value = C.DESTINATION_FORMAT_TEXT_ONLY, label = "Text only (chapter title)" },
}

-- Optional text next to the arrow, so the destination is visible without
-- holding the button: its page number (the same label the hold hint uses,
-- page-map aware), or how many pages away it is. Off by default -- the
-- icon-only pill stays the compact one.
C.INLINE_LABEL_OFF = "off"
C.INLINE_LABEL_PAGE = "page"
C.INLINE_LABEL_DISTANCE = "distance"
C.INLINE_LABEL_OPTIONS = {
	{ value = C.INLINE_LABEL_OFF, label = "Off" },
	{ value = C.INLINE_LABEL_PAGE, label = "Destination page" },
	{ value = C.INLINE_LABEL_DISTANCE, label = "Distance in pages" },
}
-- Where the pill sits vertically. Each position comes with the screen band
-- its touch zones cover (as ratios of the screen height), which must hold
-- the pill and anything shown in place of it (the undo notice).
C.VERTICAL_BOTTOM = "bottom"
C.VERTICAL_MIDDLE = "middle"
C.VERTICAL_TOP = "top"
C.VERTICAL_POSITION_OPTIONS = {
	{ value = C.VERTICAL_BOTTOM, label = "Bottom" },
	{ value = C.VERTICAL_MIDDLE, label = "Middle" },
	{ value = C.VERTICAL_TOP, label = "Top" },
}
C.VERTICAL_ZONES = {
	[C.VERTICAL_BOTTOM] = { ratio_y = 0.7, ratio_h = 0.3 },
	[C.VERTICAL_MIDDLE] = { ratio_y = 0.35, ratio_h = 0.3 },
	[C.VERTICAL_TOP] = { ratio_y = 0, ratio_h = 0.3 },
}

-- How many page turns back still count as re-reading rather than a jump
-- (for tools that jump without announcing it; see trackPage).
C.REREAD_TURNS_OPTIONS = {
	{ value = 1, label = "1 page turn" },
	{ value = 2, label = "2 page turns" },
	{ value = 3, label = "3 page turns" },
	{ value = 5, label = "5 page turns" },
}

-- Base (Small) size of that text, scaled with the button size like the
-- icon is.
C.BASE_INLINE_LABEL_FONT_SIZE = 16

-- "value = 0" means "Off" for both: it reads clearly in the menu and avoids
-- a separate nil-vs-zero special case in the getters (settings.lua).
C.AUTO_DISMISS_DEFAULT_SECONDS = 30
C.AUTO_DISMISS_OPTIONS = {
	{ value = 0, label = "Never" },
	{ value = 15, label = "15 seconds" },
	{ value = 30, label = "30 seconds" },
	{ value = 60, label = "1 minute" },
	{ value = 120, label = "2 minutes" },
	{ value = 300, label = "5 minutes" },
}

-- How long the buttons may stay hidden (or parked as a tab) before Page
-- Anchor gives up on the trip: the anchor is discarded and the current
-- position becomes the reading reference, exactly as tapping the anchor
-- button would. Counted from the moment they were hidden; "Never" (0, the
-- default) keeps them waiting until dismissed by hand.
C.HIDDEN_EXPIRY_DEFAULT_SECONDS = 0
C.HIDDEN_EXPIRY_OPTIONS = {
	{ value = 0, label = "Never (until dismissed)" },
	{ value = 60, label = "1 minute" },
	{ value = 300, label = "5 minutes" },
	{ value = 900, label = "15 minutes" },
	{ value = 1800, label = "30 minutes" },
	{ value = 3600, label = "1 hour" },
}

C.FORWARD_DISMISS_DEFAULT_PAGES = 1
C.FORWARD_DISMISS_PAGE_OPTIONS = {
	{ value = 0, label = "Never" },
	{ value = 1, label = "1 page" },
	{ value = 2, label = "2 pages" },
	{ value = 3, label = "3 pages" },
	{ value = 5, label = "5 pages" },
}

C.ACTION_BACK = "back"
C.ACTION_FORWARD = "forward"
C.ACTION_DISMISS = "dismiss"
C.ACTION_SHOW = "show"

-- What hiding the buttons (inactivity timeout, or the show/hide gesture
-- action) leaves on screen: a small anchor tab in the same corner that one
-- tap expands back into the full control -- so getting the buttons back
-- never means digging through the menu -- or nothing at all, for a clean
-- page (then the menu or the gesture action brings them back).
C.HIDE_MODE_MINIMIZE = "minimize"
C.HIDE_MODE_HIDE = "hide"
C.HIDE_MODE_OPTIONS = {
	{ value = C.HIDE_MODE_MINIMIZE, label = "Leave an anchor tab" },
	{ value = C.HIDE_MODE_HIDE, label = "Leave nothing" },
}

C.ICON_ANCHOR = "anchor.svg"
-- The same anchor, lifted and underlined: marks a pinned anchor, on the
-- pill's anchor segment and on the minimized tab alike.
C.ICON_ANCHOR_PINNED = "anchor-pinned.svg"
-- White anchor in a filled circle: you're at the anchor right now. Drawn
-- into the icon instead of inverting the segment (Button's preselect),
-- which left the pill's border and corners white and made the segment
-- look pressed rather than tappable. Plus its pinned (underlined) variant.
C.ICON_ANCHOR_HERE = "anchor-here.svg"
C.ICON_ANCHOR_HERE_PINNED = "anchor-here-pinned.svg"

C.ICON_CHEVRON_LEFT = "chevron-left.svg"
C.ICON_CHEVRON_RIGHT = "chevron-right.svg"
C.ICON_UNDO = "undo.svg"

-- Three predefined scales, the same factors and naming Quick Dock uses for
-- its own dock-size setting (quickdock.koplugin/main.lua's DOCK_SIZE_*),
-- so the two plugins' size pickers feel like the same control.
C.BUTTON_SIZE_SMALL = "small"
C.BUTTON_SIZE_MEDIUM = "medium"
C.BUTTON_SIZE_LARGE = "large"
C.BUTTON_SIZE_FACTORS = {
	[C.BUTTON_SIZE_SMALL] = 1,
	[C.BUTTON_SIZE_MEDIUM] = 1.2,
	[C.BUTTON_SIZE_LARGE] = 1.4,
}
C.BUTTON_SIZE_OPTIONS = {
	{ value = C.BUTTON_SIZE_SMALL, label = "Small" },
	{ value = C.BUTTON_SIZE_MEDIUM, label = "Medium" },
	{ value = C.BUTTON_SIZE_LARGE, label = "Large" },
}


-- Base (Small/1x) button geometry. These three values, and the same
-- BUTTON_SIZE_FACTORS table above, are deliberately identical to Quick
-- Dock's own BASE_BUTTON_ICON_SIZE/BASE_BUTTON_HEIGHT/
-- BASE_BUTTON_SIDE_PADDING and DOCK_SIZE_FACTORS: picking the same named
-- size (e.g. Medium) in both plugins produces the exact same icon size,
-- button height, and per-button width, even though the two plugins never
-- share code for it. The width formula below (height + 2 * side padding)
-- mirrors Quick Dock's own button_width derivation for the same reason.
C.BASE_BUTTON_ICON_SIZE = Screen:scaleBySize(22)
C.BASE_BUTTON_HEIGHT = Screen:scaleBySize(42)
C.BASE_BUTTON_SIDE_PADDING = Screen:scaleBySize(6)
-- These two stay fixed across every size: the outer frame padding matches
-- KOReader's own ButtonDialog frame regardless of scale, and the
-- screen-edge margin matches Quick Dock's own DOCK_MARGIN (see
-- getOverlayClearance in controls.lua) -- neither is part of Quick Dock's own scaled
-- metrics either.
C.BUTTON_OUTER_PADDING = Size.padding.button
C.BUTTON_MARGIN = Size.padding.large

-- How long a hold-triggered hint stays up before it dismisses itself, and
-- the font it uses -- unrelated to the pill's own geometry above.
C.HINT_DISMISS_SECONDS = 3
-- How long the undo notice stays up after a discard. The undo itself stays
-- available afterwards from the menu and the gesture action.
C.UNDO_HINT_SECONDS = 3

-- The trail: other places visited during the current trip (each spot left
-- by a jump while away), offered when holding the arrow. Capped, oldest
-- dropped first, one entry per page.
C.TRAIL_MAX = 8
C.HINT_FONT_SIZE = 18

-- Page-turn tolerance for telling plain reading apart from a jump made by a
-- tool that doesn't announce itself (see trackPage): one turn back is a
-- re-read, up to two turns forward is reading on. Counted in page turns,
-- not raw page numbers (see History.countPageTurns).
C.READING_TURNS_BEHIND = 1 -- default; see getRereadTurns
C.READING_TURNS_AHEAD = 2
-- Wider backward tolerance while there's a way back to protect: a pending
-- return point (just came back to the anchor), or a discard you can still
-- undo and haven't read past. Stepping back a few turns to re-read then
-- doesn't make a new anchor that would silently replace the return point
-- or void the undo. Announced jumps still arm an anchor at any distance.
C.READING_TURNS_BEHIND_PROTECTED = 5

return C
