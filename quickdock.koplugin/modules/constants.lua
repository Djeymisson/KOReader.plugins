local Device = require("device")
local Size = require("ui/size")
local _ = require("quickdock_l10n")

local Screen = Device.screen
local math_max = math.max

-- Shared constants: settings keys, option values, the action catalog and the
-- base dock dimensions. Every module receives this table when it is loaded.
local C = {}

C.SETTING_ACTIONS = "quickdock_actions"
C.SETTING_ACTION_CONTEXTS = "quickdock_action_contexts"
C.SETTING_AUTO_VISIBILITY = "quickdock_auto_visibility"
C.SETTING_SIDE = "quickdock_side"
C.SETTING_SIDE_MODE = "quickdock_side_mode"
C.SETTING_SHOW_SIDE_BUTTON = "quickdock_show_side_button"
C.SETTING_SHOW_CLOSE_BUTTON = "quickdock_show_close_button"
C.SETTING_SHOW_CONTEXT_BUTTON = "quickdock_show_context_button"
C.SETTING_SHOW_FRONTLIGHT_SLIDER = "quickdock_show_frontlight_slider"
C.SETTING_SHOW_WARMTH_SLIDER = "quickdock_show_warmth_slider"
C.SETTING_SHOW_INFO_PANEL = "quickdock_show_info_panel"
C.SETTING_SHOW_NETWORK_INFO_PANEL = "quickdock_show_network_info_panel"
C.SETTING_SHOW_STATS_INFO_PANEL = "quickdock_show_stats_info_panel"
C.SETTING_SHOW_RECENT_INFO_PANEL = "quickdock_show_recent_info_panel"
C.SETTING_RECENT_DOCUMENTS_COUNT = "quickdock_recent_documents_count"
C.SETTING_SHOW_INFO_PANEL_COVER = "quickdock_show_info_panel_cover"
C.SETTING_INFO_PANEL_TEXT_ALIGNMENT = "quickdock_info_panel_text_alignment"
C.SETTING_DOCK_SIZE = "quickdock_dock_size"
C.SETTING_MAX_ACTION_DOCK_HEIGHT = "quickdock_max_action_dock_height"
C.SETTING_CLOSE_TOGETHER = "quickdock_close_together"
C.SETTING_DOCK_SHAPE = "quickdock_dock_shape"
C.SETTING_ARC_BAND = "quickdock_arc_band"
C.SETTING_ARC_ANGLE = "quickdock_arc_angle"
C.SETTING_ARC_FILL = "quickdock_arc_fill"
C.SETTING_ARC_EMPTY_SPACE = "quickdock_arc_empty_space"

C.DOCK_SHAPE_COLUMN = "column"
C.DOCK_SHAPE_ARC = "arc"

-- Tilt of the arc: the angle between the bottom edge and the line joining
-- its two ends. 45 degrees is a quarter circle.
C.ARC_ANGLES = { 25, 35, 45, 55, 65 }
C.DEFAULT_ARC_ANGLE = 45
-- Where the unused part of the arc stays when it is not filled.
C.ARC_EMPTY_SPACE_END = "end"
C.ARC_EMPTY_SPACE_START = "start"

C.SIDE_MODE_FIXED = "fixed"
C.SIDE_MODE_GESTURE = "gesture"

-- The information panel's modes, in the order the switch button cycles
-- through them and the settings menu lists them. Adding a mode takes an entry
-- here, a collector and a renderer in modules/info_data.lua and
-- modules/info_render.lua and, optionally, its own options in the settings
-- menu (modules/menu.lua).
--   setting / default: the saved visibility and its value when unset
--   icon:  getIcon() id of the switch button while the mode is visible
--   icon_files: the custom icon filenames listed in the settings menu
--   title / name: heading-style and in-sentence names
--   help:  what the mode shows, for the settings menu
C.INFO_PANEL_MODES = {
    {
        kind = "reading",
        setting = C.SETTING_SHOW_INFO_PANEL,
        default = true,
        icon = "reading_info",
        icon_files = "reading_info.svg / reading_info.png",
        title = _("Reading information"),
        name = _("reading information"),
        help = _("Shows book, chapter, daily reading, clock, and battery information in the information panel."),
    },
    {
        kind = "stats",
        setting = C.SETTING_SHOW_STATS_INFO_PANEL,
        default = false,
        icon = "stats_info",
        icon_files = "stats.svg / stats.png",
        title = _("Book statistics"),
        name = _("book statistics"),
        help = _("Shows the open book's reading time, remaining time, progress, daily average, reading speed, start date, and estimated end date, as recorded by KOReader's Statistics plugin."),
    },
    {
        kind = "recent",
        setting = C.SETTING_SHOW_RECENT_INFO_PANEL,
        default = false,
        icon = "recent_info",
        icon_files = "recent_info.svg / history.svg",
        title = _("Recent documents"),
        name = _("recent documents"),
        help = _("Shows the covers of the most recently opened documents in the information panel. Tap a cover to open its document; when they do not fit, arrows above the covers turn the page. Covers come from the Cover browser plugin; documents it has not indexed yet show their title instead."),
    },
    {
        kind = "network",
        setting = C.SETTING_SHOW_NETWORK_INFO_PANEL,
        default = false,
        icon = "network_info",
        icon_files = "network_info.svg / network_info.png",
        title = _("Network information"),
        name = _("network information"),
        help = _("Shows Wi-Fi state and the network details reported by KOReader in the information panel."),
    },
}
C.INFO_PANEL_MODES_BY_KIND = {}
for _index, mode in ipairs(C.INFO_PANEL_MODES) do
    C.INFO_PANEL_MODES_BY_KIND[mode.kind] = mode
end
-- How many recent documents the recent-documents panel may list.
C.RECENT_DOCUMENTS_COUNTS = { 3, 6, 9, 12, 18, 24 }
C.DEFAULT_RECENT_DOCUMENTS_COUNT = 6
C.INFO_PANEL_TEXT_LEFT = "left"
C.INFO_PANEL_TEXT_CENTER = "center"
C.INFO_PANEL_TEXT_SCREEN_EDGE = "screen_edge"

C.DOCK_SIZE_SMALL = "small"
C.DOCK_SIZE_MEDIUM = "medium"
C.DOCK_SIZE_LARGE = "large"
C.DOCK_SIZE_FACTORS = {
    [C.DOCK_SIZE_SMALL] = 1,
    [C.DOCK_SIZE_MEDIUM] = 1.2,
    [C.DOCK_SIZE_LARGE] = 1.4,
}
C.MAX_ACTION_DOCK_HEIGHT_100 = "100"
C.MAX_ACTION_DOCK_HEIGHT_60 = "60"
C.MAX_ACTION_DOCK_HEIGHT_33 = "33"
C.MAX_ACTION_DOCK_HEIGHT_FACTORS = {
    [C.MAX_ACTION_DOCK_HEIGHT_100] = 1,
    [C.MAX_ACTION_DOCK_HEIGHT_60] = 0.6,
    [C.MAX_ACTION_DOCK_HEIGHT_33] = 0.33,
}

-- Actions whose icon follows their state (on/off): they have one custom
-- icon per state, and their button is refreshed when the state changes.
-- Which actions run without closing the dock is decided separately, in
-- modules/inline_actions.lua.
C.STATEFUL_ACTIONS = {
    night_mode = true,
    toggle_wifi = true,
}

C.ACTION_CONTEXT_ALL = "all"
C.ACTION_CONTEXT_AUTOMATIC = "automatic"
C.ACTION_CONTEXT_READER = "reader"
C.ACTION_CONTEXT_BROWSER = "browser"

C.BASE_BUTTON_ICON_SIZE = Screen:scaleBySize(22)
C.BASE_BUTTON_HEIGHT = Screen:scaleBySize(42)
C.BASE_BUTTON_SIDE_PADDING = Screen:scaleBySize(6)
C.DOCK_MARGIN = Size.padding.large
C.BASE_SIDE_BUTTON_ICON_SIZE = Screen:scaleBySize(18)
C.BASE_SIDE_BUTTON_HEIGHT = Screen:scaleBySize(28)
C.BASE_SIDE_BUTTON_PADDING = Screen:scaleBySize(4)
C.BASE_SIDE_BUTTON_GAP = Size.padding.default
C.BASE_FRONTLIGHT_SLIDER_GAP = Size.padding.default
C.BASE_FRONTLIGHT_SLIDER_PADDING = Screen:scaleBySize(8)
C.BASE_FRONTLIGHT_TRACK_WIDTH = math_max(2, Screen:scaleBySize(3))
C.BASE_FRONTLIGHT_KNOB_RADIUS = math_max(5, Screen:scaleBySize(8))
-- About 4.5 cm on any screen: a comfortable thumb reach from the corner.
C.BASE_ARC_RADIUS = Screen:scaleBySize(280)
C.BASE_ARC_TRACK_WIDTH = math_max(3, Screen:scaleBySize(5))
C.BASE_ARC_KNOB_RADIUS = math_max(6, Screen:scaleBySize(11))

-- Delay between closing the dock and running what one of its buttons asked
-- for, so the action starts from a clean widget stack.
C.DISPATCH_DELAY = 0.05

C.ACTION_HOME = "quickdock_context_home"
C.ACTION_SEARCH = "quickdock_context_search"

-- Dispatcher keeps action context metadata private, so automatic visibility
-- uses the stable IDs of KOReader's native reader and file-browser actions.
-- Unknown and third-party actions safely default to all contexts.
C.BROWSER_ONLY_ACTIONS = {
    cloud_storage = true,
    file_search = true,
    file_search_results = true,
    fm_back = true,
    fm_go_to = true,
    folder_shortcuts = true,
    folder_up = true,
    refresh_content = true,
    set_display_mode = true,
    set_flat_view = true,
    set_mixed_sorting = true,
    set_reverse_sorting = true,
    set_sort_by = true,
    show_plus_menu = true,
    toggle_select_mode = true,
}

C.READER_ONLY_ACTIONS = {
    add_location_to_history = true,
    b_page_margin = true,
    back = true,
    block_rendering_mode = true,
    book_cover = true,
    book_description = true,
    book_info = true,
    book_map = true,
    book_map_overview = true,
    book_status = true,
    bookmark_search = true,
    bookmarks = true,
    clear_location_history = true,
    cycle_highlight_action = true,
    cycle_highlight_style = true,
    decrease_font = true,
    edit_book_tweak = true,
    embedded_css = true,
    embedded_fonts = true,
    export_annotations = true,
    first_bookmark = true,
    first_page = true,
    flush_settings = true,
    follow_nearest_internal_link = true,
    follow_nearest_link = true,
    font_base_weight = true,
    font_gamma = true,
    font_hinting = true,
    font_kerning = true,
    font_size = true,
    fulltext_search = true,
    fulltext_search_findall_results = true,
    fulltext_search_start_page = true,
    go_to = true,
    go_to_pinned_page = true,
    h_page_margins = true,
    increase_font = true,
    last_bookmark = true,
    last_page = true,
    latest_bookmark = true,
    line_spacing = true,
    load_footer_preset = true,
    nightmode_images = true,
    next_bookmark = true,
    next_chapter = true,
    next_location = true,
    page_browser = true,
    page_jmp = true,
    panel_zoom_toggle = true,
    pin_current_page = true,
    prev_bookmark = true,
    prev_chapter = true,
    previous_location = true,
    random_page = true,
    render_dpi = true,
    select_next_page_link = true,
    select_prev_page_link = true,
    set_font = true,
    set_highlight_action = true,
    set_inverse_reading_order = true,
    set_overlap_style = true,
    set_typography_lang = true,
    show_config_menu = true,
    skim = true,
    smooth_scaling = true,
    status_line = true,
    sync_t_b_page_margins = true,
    t_page_margin = true,
    text_selection = true,
    toc = true,
    toggle_bookmark = true,
    toggle_bookmark_flipping = true,
    toggle_chapter_progress_bar = true,
    toggle_handmade_flows = true,
    toggle_handmade_toc = true,
    toggle_hanging_punctuation = true,
    toggle_inverse_reading_order = true,
    toggle_page_change_animation = true,
    toggle_page_flipping = true,
    toggle_reflow = true,
    toggle_status_bar = true,
    toggle_style_tweaks = true,
    toggle_tap_links = true,
    translate_page = true,
    view_mode = true,
    visible_pages = true,
    word_expansion = true,
    word_spacing = true,
    zoom = true,
    zoom_factor_change = true,
}

C.DEFAULT_ACTIONS = {
    settings = {
        order = {
            "toggle_wifi",
            "night_mode",
            C.ACTION_SEARCH,
            "history",
        },
    },
    toggle_wifi = true,
    night_mode = true,
    [C.ACTION_SEARCH] = true,
    history = true,
}

C.ACTION_ICONS = {
    [C.ACTION_SEARCH] = "appbar.search",
    filemanager = "appbar.filebrowser",
    open_previous_document = "appbar.filebrowser",
    history = "history",
    history_search = "appbar.search",
    favorites = "star",
    collections = "folder",
    dictionary_lookup = "dictionary",
    wikipedia_lookup = "wikipedia",
    show_menu = "appbar.menu",
    menu_search = "appbar.search",
    screenshot = "screenshot",
    suspend = "power-sleep",
    restart = "restart",
    poweroff = "power",
    exit = "exit",
    close = "close",
    toggle_wifi = "wifi",
    reading_info = "book.opened",
    network_info = "wifi",
    stats_info = "stats",
    recent_info = "history",
    show_network_info = "wifi",
    show_frontlight_dialog = "frontlight",
    toggle_frontlight = "frontlight",
    increase_frontlight = "plus",
    decrease_frontlight = "minus",
    night_mode = "nightmode",
    file_search = "appbar.search",
    file_search_results = "appbar.search",
    folder_shortcuts = "folder",
    folder_up = "chevron.up",
    fm_back = "chevron.left",
    fulltext_search = "appbar.search",
    fulltext_search_findall_results = "appbar.search",
    toc = "toc",
    book_map = "map",
    page_browser = "page-browser",
    bookmarks = "bookmark",
    toggle_bookmark = "bookmark",
    first_page = "chevron.first",
    last_page = "chevron.last",
    prev_chapter = "chevron.left",
    next_chapter = "chevron.right",
    ["chevron-up"] = "chevron.up",
    ["chevron-down"] = "chevron.down",
    ["chevron-left"] = "chevron.left",
    ["chevron-right"] = "chevron.right",
}

C.ICON_EXTENSIONS = { ".svg", ".png" }

return C
