-- Shared constants: settings keys, the choices of each setting with their sizes, the style
-- presets, the actions and their default order, the handle styles and the preview modes.
-- Every other module receives this table as C.

local Device = require("device")
local Size = require("ui/size")
local _ = require("selectiontoolbar_l10n")

local Screen = Device.screen
local math_max = math.max
local math_min = math.min

local C = {}

C.QR_MESSAGE_MODULE = "ui/widget/qrmessage"

-- Handle shapes are sized per handle size (see getHandleMetrics); these stay the same.
C.HANDLE_OUTLINE = math_max(1, Screen:scaleBySize(1))
C.HANDLE_RING_WIDTH = math_max(2, Screen:scaleBySize(2))
-- The touch area does not follow the handle size: small handles stay easy to grab.
C.HANDLE_TOUCH_SIZE = Screen:scaleBySize(48)
-- Finger moves smaller than this are not sent to crengine: selection snaps to words,
-- so they would only recompute the same text range.
C.DRAG_MIN_MOVE = math_max(2, Screen:scaleBySize(4))
C.MARKS_VIEW_MODULE = "selectiontoolbar_selection_marks"
C.HANDLE_SIDES = { "start", "end" }

-- A dithered toolbar shadow: width is how far it reaches from the toolbar edge, overlap
-- how much of it lies under the toolbar, and strength scales its darkness.
local function shadowFinish(id, width, overlap, strength)
    width = math_max(2, Screen:scaleBySize(width))
    overlap = math_min(width - 1, math_max(1, Screen:scaleBySize(overlap)))
    return { id = id, width = width, overlap = overlap, extent = math_max(0, width - overlap), strength = strength }
end

C.SETTING_ENABLED = "selectiontoolbar_enabled"
C.SETTING_ACTIONS = "selectiontoolbar_actions"
C.SETTING_SHADOWS = "selectiontoolbar_shadows"
C.SETTING_HANDLES = "selectiontoolbar_handles"
C.SETTING_LINE_MARKER = "selectiontoolbar_line_marker"
C.SETTING_LINE_MARKER_RIGHT = "selectiontoolbar_line_marker_right"
C.SETTING_HANDLE_STYLE = "selectiontoolbar_handle_style"
C.SETTING_HANDLE_OUTLINE = "selectiontoolbar_handle_outline"
C.SETTING_POSITION = "selectiontoolbar_position"
C.SETTING_DENSITY = "selectiontoolbar_density"
C.SETTING_ICON_SIZE = "selectiontoolbar_icon_size"
C.SETTING_SHAPE = "selectiontoolbar_shape"
C.SETTING_BORDER = "selectiontoolbar_border"
C.SETTING_SEPARATORS = "selectiontoolbar_separators"
C.SETTING_SHADOW_STYLE = "selectiontoolbar_shadow_style"
C.SETTING_ACTION_ORDER = "selectiontoolbar_action_order"
C.SETTING_MAIN_ACTIONS = "selectiontoolbar_main_actions"
C.SETTING_HANDLE_SIZE = "selectiontoolbar_handle_size"
C.SETTING_LINE_MARKER_WIDTH = "selectiontoolbar_line_marker_width"
C.SETTING_LINE_MARKER_GAP = "selectiontoolbar_line_marker_gap"
-- v1.3.0 had the outline as a separate "wireframe" style: read it as lollipop + outline.
C.LEGACY_WIREFRAME_STYLE = "wireframe"

C.POSITION_NEAR = "near"
C.POSITION_EDGE = "edge"
C.POSITIONS = {
    {
        id = C.POSITION_NEAR,
        text = _("Near the selection"),
        help_text = _("Show the toolbar right below the selection, or above it when there is no room."),
    },
    {
        id = C.POSITION_EDGE,
        text = _("Fixed at screen edge"),
        help_text = _(
            "Show the toolbar centered at the bottom of the screen, or at the top when the selection is in the lower part."
        ),
    },
}

-- Button height (the icon area; ButtonTable adds its own vertical padding) and the side
-- padding that, added on both sides, gives the button width.
C.DEFAULT_DENSITY = "normal"
C.DENSITIES = {
    {
        id = "compact",
        text = _("Compact"),
        help_text = _("Smaller, tighter buttons: the toolbar covers less of the page."),
        height = 34,
        side_padding = 4,
    },
    {
        id = "normal",
        text = _("Normal"),
        help_text = _("The default button size and spacing."),
        height = 42,
        side_padding = 6,
    },
    {
        id = "comfortable",
        text = _("Comfortable"),
        help_text = _("Taller, more spaced buttons: easier to tap."),
        height = 50,
        side_padding = 10,
    },
}

C.DEFAULT_ICON_SIZE = "normal"
C.ICON_SIZES = {
    { id = "small", text = _("Small"), size = 18 },
    { id = "normal", text = _("Normal"), size = 22 },
    { id = "large", text = _("Large"), size = 28 },
}

C.DEFAULT_SHAPE = "rounded"
C.SHAPE_CAPSULE = "capsule"
C.SHAPES = {
    {
        id = "rectangle",
        text = _("Rectangle"),
        help_text = _("Square corners: the most sober look."),
    },
    {
        id = "rounded",
        text = _("Rounded corners"),
        help_text = _("Slightly rounded corners, as KOReader's own dialogs."),
    },
    {
        id = C.SHAPE_CAPSULE,
        text = _("Capsule"),
        help_text = _("Fully rounded ends. The toolbar gets a little wider, to keep the buttons inside the curves."),
    },
}

C.DEFAULT_BORDER = "medium"
C.BORDERS = {
    {
        id = "thin",
        text = _("Thin"),
        help_text = _("A discreet outline."),
        width = math_max(1, Size.border.thin),
    },
    {
        id = "medium",
        text = _("Medium"),
        help_text = _("The default outline, as KOReader's own dialogs."),
        width = Size.border.window,
    },
    {
        id = "thick",
        text = _("Thick"),
        help_text = _("A strong outline that stands out over the text, useful without the shadow."),
        width = Screen:scaleBySize(2.5),
    },
}

C.DEFAULT_SEPARATORS = "all"
C.SEPARATORS_GROUPS = "groups"
C.SEPARATORS_NONE = "none"
C.SEPARATOR_STYLES = {
    {
        id = "all",
        text = _("Between all buttons"),
        help_text = _("A thin line between each pair of buttons."),
    },
    {
        id = C.SEPARATORS_GROUPS,
        text = _("Between groups"),
        help_text = _(
            "A line only between groups of actions, such as annotation, lookup and tools. Arrange the groups in Actions."
        ),
    },
    {
        id = C.SEPARATORS_NONE,
        text = _("None"),
        help_text = _("No lines between buttons, for a lighter look."),
    },
}

C.SHADOW_NONE = "none"
C.DEFAULT_SHADOW_STYLE = "standard"
C.SHADOW_STYLES = {
    {
        id = C.SHADOW_NONE,
        text = _("No shadow"),
        help_text = _("A flat toolbar. A stronger border helps it stand out over the text."),
    },
    {
        id = "subtle",
        text = _("Subtle"),
        help_text = _("A shorter, lighter shadow."),
        finish = shadowFinish("subtle", 8, 4, 0.6),
    },
    {
        id = C.DEFAULT_SHADOW_STYLE,
        text = _("Standard"),
        help_text = _("A dithered shadow along the right and bottom edges."),
        finish = shadowFinish(C.DEFAULT_SHADOW_STYLE, 12, 6, 1),
    },
}

-- Scale of the handle shapes, relative to the normal size.
C.DEFAULT_HANDLE_SIZE = "normal"
C.HANDLE_SIZES = {
    { id = "small", text = _("Small"), help_text = _("Discreet handles. They are as easy to grab as normal ones."), scale = 0.7 },
    { id = C.DEFAULT_HANDLE_SIZE, text = _("Normal"), help_text = _("The default handle size."), scale = 1 },
    { id = "large", text = _("Large"), help_text = _("Handles that are easier to see."), scale = 1.4 },
}

C.DEFAULT_LINE_MARKER_WIDTH = "medium"
C.LINE_MARKER_WIDTHS = {
    { id = "thin", text = _("Thin"), width = math_max(1, Screen:scaleBySize(2)) },
    { id = C.DEFAULT_LINE_MARKER_WIDTH, text = _("Medium"), width = math_max(2, Screen:scaleBySize(3)) },
    { id = "thick", text = _("Thick"), width = math_max(3, Screen:scaleBySize(5)) },
}

-- Distance between the line marker and the text. It never leaves the page margin.
C.DEFAULT_HANDLE_STYLE = "lollipop"
C.DEFAULT_LINE_MARKER_GAP = "normal"
C.LINE_MARKER_GAPS = {
    { id = "near", text = _("Close to the text"), gap = Screen:scaleBySize(2) },
    { id = C.DEFAULT_LINE_MARKER_GAP, text = _("Normal"), gap = Screen:scaleBySize(6) },
    { id = "far", text = _("Far from the text"), gap = Screen:scaleBySize(14) },
}

-- Ready-made combinations of the look settings. Applying one sets all of these; it is
-- shown as chosen while the current settings match it (no preset is stored, so any later
-- change simply makes the look custom). Position, visible actions and whether handles
-- and line marker are shown are left as they are.
C.STYLE_PRESETS = {
    {
        id = "default",
        text = _("Default"),
        help_text = _("The plugin's original look."),
        look = {
            density = C.DEFAULT_DENSITY,
            icon_size = C.DEFAULT_ICON_SIZE,
            shape = C.DEFAULT_SHAPE,
            border = C.DEFAULT_BORDER,
            separators = C.DEFAULT_SEPARATORS,
            shadow = C.DEFAULT_SHADOW_STYLE,
            handle_style = C.DEFAULT_HANDLE_STYLE,
            handle_outline = false,
            handle_size = C.DEFAULT_HANDLE_SIZE,
            marker_width = C.DEFAULT_LINE_MARKER_WIDTH,
        },
    },
    {
        id = "discreet",
        text = _("Discreet"),
        help_text = _(
            "A light toolbar: thin border, rounded corners, no shadow and lines only between groups of actions. Bracket handles and a thin line marker."
        ),
        look = {
            density = "normal",
            icon_size = "normal",
            shape = "rounded",
            border = "thin",
            separators = C.SEPARATORS_GROUPS,
            shadow = C.SHADOW_NONE,
            handle_style = "bracket",
            handle_outline = false,
            handle_size = "normal",
            marker_width = "thin",
        },
    },
    {
        id = "classic",
        text = _("Classic"),
        help_text = _(
            "A rectangular toolbar with a medium border, a shadow and separators between the buttons. Round (lollipop) handles."
        ),
        look = {
            density = "normal",
            icon_size = "normal",
            shape = "rectangle",
            border = "medium",
            separators = "all",
            shadow = "standard",
            handle_style = "lollipop",
            handle_outline = false,
            handle_size = "normal",
            marker_width = "medium",
        },
    },
    {
        id = "comfortable",
        text = _("Comfortable"),
        help_text = _(
            "More spaced buttons with larger icons and a thick border. Lollipop handles with the high-contrast outline."
        ),
        look = {
            density = "comfortable",
            icon_size = "large",
            shape = "rounded",
            border = "thick",
            separators = "all",
            shadow = "standard",
            handle_style = "lollipop",
            handle_outline = true,
            handle_size = "normal",
            marker_width = "medium",
        },
    },
}

C.ACTIONS = {
    { id = "select", key = "01_select", icon = "select", text = _("Select") },
    { id = "highlight", key = "02_highlight", icon = "highlight", text = _("Highlight") },
    { id = "copy", key = "03_copy", icon = "copy", text = _("Copy") },
    { id = "add_note", key = "04_add_note", icon = "add_note", text = _("Add note") },
    { id = "wikipedia", key = "05_wikipedia", icon = "wikipedia", text = _("Wikipedia") },
    { id = "dictionary", key = "06_dictionary", icon = "dictionary", text = _("Dictionary") },
    { id = "translate", key = "07_translate", icon = "translate", text = _("Translate") },
    { id = "view_html", key = "09_view_html", icon = "view_html", text = _("View HTML") },
    { id = "qr_code", key = nil, icon = "qr_code", text = _("Generate QR code") },
    { id = "search", key = "12_search", icon = "search", text = _("Search") },
}
C.QR_ICON_ACTION = { icon = "qr_code" }
C.MORE_ICON_ACTION = { icon = "more" }

-- How many actions the toolbar shows before a "More" button, which shows the others in a
-- second row. Saved as strings, as setting values.
C.DEFAULT_MAIN_ACTIONS = "all"
C.MAIN_ACTION_COUNTS = {
    {
        id = C.DEFAULT_MAIN_ACTIONS,
        text = _("No"),
        help_text = _("Show every visible action in a single row."),
    },
    { id = "4", text = _("To 4 actions"), count = 4 },
    { id = "5", text = _("To 5 actions"), count = 5 },
    { id = "6", text = _("To 6 actions"), count = 6 },
}

C.ACTIONS_BY_ID = {}
for _, action in ipairs(C.ACTIONS) do
    C.ACTIONS_BY_ID[action.id] = action
end

-- The toolbar order is a list of action ids and group separators. There are always
-- GROUP_SEPARATOR_COUNT separators: one at the start or the end of the list, or next
-- to another one, simply draws nothing, so groups are made and removed by moving them.
C.GROUP_SEPARATOR = "|"
C.GROUP_SEPARATOR_COUNT = 3
C.DEFAULT_ACTION_ORDER = {
    -- Annotation
    "select",
    "highlight",
    "add_note",
    C.GROUP_SEPARATOR,
    -- Lookup
    "dictionary",
    "wikipedia",
    "translate",
    "search",
    C.GROUP_SEPARATOR,
    -- Tools
    "copy",
    "view_html",
    "qr_code",
    C.GROUP_SEPARATOR,
}

-- Styles drawn with solid shapes large enough to get a high-contrast outline.
C.OUTLINE_STYLES = { lollipop = true, teardrop = true, flag = true }
C.HANDLE_STYLES = {
    {
        id = "lollipop",
        text = _("Lollipop"),
        help_text = _("A bar at the selection edge with a round knob above the start and below the end."),
    },
    {
        id = "teardrop",
        text = _("Teardrop"),
        help_text = _("A drop below the line, pointing at the selection edge, as on Android."),
    },
    {
        id = "bracket",
        text = _("Brackets"),
        help_text = _("A [ at the start and a ] at the end of the selection. The most discreet style."),
    },
    {
        id = "flag",
        text = _("Flag tabs"),
        help_text = _(
            "A pole with a grab tab pointing outwards, above the start and below the end, slanted toward the text."
        ),
    },
}

-- What the preview shows: the toolbar (Toolbar, Actions), the selection marks over a
-- selected sample text (Selection marks), or both (Style preset).
C.PREVIEW_TOOLBAR = "toolbar"
C.PREVIEW_MARKS = "marks"
-- Both: the selection marks with the toolbar below them (Style preset).
C.PREVIEW_FULL = "full"

return C
