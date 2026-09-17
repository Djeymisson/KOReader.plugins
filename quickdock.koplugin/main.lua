local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("quickdock_l10n")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local function scaleMetric(value, factor, minimum)
    return math_max(minimum or 1, math_floor(value * factor + 0.5))
end

local PLUGIN_VERSION = "v0.22.3"
local SETTING_ACTIONS = "quickdock_actions"
local SETTING_ACTION_CONTEXTS = "quickdock_action_contexts"
local SETTING_AUTO_VISIBILITY = "quickdock_auto_visibility"
local SETTING_SIDE = "quickdock_side"
local SETTING_SIDE_MODE = "quickdock_side_mode"
local SETTING_SHOW_SIDE_BUTTON = "quickdock_show_side_button"
local SETTING_SHOW_CLOSE_BUTTON = "quickdock_show_close_button"
local SETTING_SHOW_CONTEXT_BUTTON = "quickdock_show_context_button"
local SETTING_SHOW_FRONTLIGHT_SLIDER = "quickdock_show_frontlight_slider"
local SETTING_SHOW_WARMTH_SLIDER = "quickdock_show_warmth_slider"
local SETTING_SHOW_INFO_PANEL = "quickdock_show_info_panel"
local SETTING_SHOW_NETWORK_INFO_PANEL = "quickdock_show_network_info_panel"
local SETTING_SHOW_INFO_PANEL_COVER = "quickdock_show_info_panel_cover"
local SETTING_INFO_PANEL_TEXT_ALIGNMENT = "quickdock_info_panel_text_alignment"
local SETTING_DOCK_SIZE = "quickdock_dock_size"
local SETTING_MAX_ACTION_DOCK_HEIGHT = "quickdock_max_action_dock_height"
local SETTING_CLOSE_TOGETHER = "quickdock_close_together"

local SIDE_MODE_FIXED = "fixed"
local SIDE_MODE_GESTURE = "gesture"

local INFO_PANEL_TEXT_LEFT = "left"
local INFO_PANEL_TEXT_CENTER = "center"
local INFO_PANEL_TEXT_SCREEN_EDGE = "screen_edge"
local INFO_PANEL_TEXT_ALIGNMENTS = {
    [INFO_PANEL_TEXT_LEFT] = true,
    [INFO_PANEL_TEXT_CENTER] = true,
    [INFO_PANEL_TEXT_SCREEN_EDGE] = true,
}

local DOCK_SIZE_SMALL = "small"
local DOCK_SIZE_MEDIUM = "medium"
local DOCK_SIZE_LARGE = "large"
local DOCK_SIZE_FACTORS = {
    [DOCK_SIZE_SMALL] = 1,
    [DOCK_SIZE_MEDIUM] = 1.2,
    [DOCK_SIZE_LARGE] = 1.4,
}
local MAX_ACTION_DOCK_HEIGHT_100 = "100"
local MAX_ACTION_DOCK_HEIGHT_60 = "60"
local MAX_ACTION_DOCK_HEIGHT_33 = "33"
local MAX_ACTION_DOCK_HEIGHT_FACTORS = {
    [MAX_ACTION_DOCK_HEIGHT_100] = 1,
    [MAX_ACTION_DOCK_HEIGHT_60] = 0.6,
    [MAX_ACTION_DOCK_HEIGHT_33] = 0.33,
}
local DOCK_METRICS_CACHE = {}

local STATEFUL_ACTIONS = {
    night_mode = true,
    toggle_wifi = true,
}

local ACTION_CONTEXT_ALL = "all"
local ACTION_CONTEXT_AUTOMATIC = "automatic"
local ACTION_CONTEXT_READER = "reader"
local ACTION_CONTEXT_BROWSER = "browser"

local BASE_BUTTON_ICON_SIZE = Screen:scaleBySize(22)
local BASE_BUTTON_HEIGHT = Screen:scaleBySize(42)
local BASE_BUTTON_SIDE_PADDING = Screen:scaleBySize(6)
local DOCK_MARGIN = Size.padding.large
local BASE_SIDE_BUTTON_ICON_SIZE = Screen:scaleBySize(18)
local BASE_SIDE_BUTTON_HEIGHT = Screen:scaleBySize(28)
local BASE_SIDE_BUTTON_PADDING = Screen:scaleBySize(4)
local BASE_SIDE_BUTTON_GAP = Size.padding.default
local BASE_FRONTLIGHT_SLIDER_GAP = Size.padding.default
local BASE_FRONTLIGHT_SLIDER_PADDING = Screen:scaleBySize(8)
local BASE_FRONTLIGHT_TRACK_WIDTH = math_max(2, Screen:scaleBySize(3))
local BASE_FRONTLIGHT_KNOB_RADIUS = math_max(5, Screen:scaleBySize(8))

local ACTION_HOME = "quickdock_context_home"
local ACTION_SEARCH = "quickdock_context_search"

-- Dispatcher keeps action context metadata private, so automatic visibility
-- uses the stable IDs of KOReader's native reader and file-browser actions.
-- Unknown and third-party actions safely default to all contexts.
local BROWSER_ONLY_ACTIONS = {
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

local READER_ONLY_ACTIONS = {
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

local DEFAULT_ACTIONS = {
    settings = {
        order = {
            "toggle_wifi",
            "night_mode",
            ACTION_SEARCH,
            "history",
        },
    },
    toggle_wifi = true,
    night_mode = true,
    [ACTION_SEARCH] = true,
    history = true,
}

local ACTION_ICONS = {
    [ACTION_HOME] = "book.opened",
    [ACTION_SEARCH] = "appbar.search",
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

local ICON_EXTENSIONS = { ".svg", ".png" }

local MODULE_CONSTANTS = {
    PLUGIN_VERSION = PLUGIN_VERSION,
    ACTION_HOME = ACTION_HOME,
    ACTION_ICONS = ACTION_ICONS,
    ICON_EXTENSIONS = ICON_EXTENSIONS,
    STATEFUL_ACTIONS = STATEFUL_ACTIONS,
    ACTION_CONTEXT_ALL = ACTION_CONTEXT_ALL,
    ACTION_CONTEXT_AUTOMATIC = ACTION_CONTEXT_AUTOMATIC,
    ACTION_CONTEXT_READER = ACTION_CONTEXT_READER,
    ACTION_CONTEXT_BROWSER = ACTION_CONTEXT_BROWSER,
    SIDE_MODE_FIXED = SIDE_MODE_FIXED,
    SIDE_MODE_GESTURE = SIDE_MODE_GESTURE,
    DOCK_SIZE_SMALL = DOCK_SIZE_SMALL,
    DOCK_SIZE_MEDIUM = DOCK_SIZE_MEDIUM,
    DOCK_SIZE_LARGE = DOCK_SIZE_LARGE,
    MAX_ACTION_DOCK_HEIGHT_100 = MAX_ACTION_DOCK_HEIGHT_100,
    MAX_ACTION_DOCK_HEIGHT_60 = MAX_ACTION_DOCK_HEIGHT_60,
    MAX_ACTION_DOCK_HEIGHT_33 = MAX_ACTION_DOCK_HEIGHT_33,
    INFO_PANEL_TEXT_LEFT = INFO_PANEL_TEXT_LEFT,
    INFO_PANEL_TEXT_CENTER = INFO_PANEL_TEXT_CENTER,
    INFO_PANEL_TEXT_SCREEN_EDGE = INFO_PANEL_TEXT_SCREEN_EDGE,
}

local function pluginDir()
    local source = debug.getinfo(1, "S").source or ""
    local path = source:match("^@(.*/)") or source:match("^(.*/)")
    return path or "plugins/quickdock.koplugin/"
end

local PLUGIN_DIR = pluginDir()

local function copyTable(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, child in pairs(value) do
        result[copyTable(key)] = copyTable(child)
    end
    return result
end

local function firstCharacters(text, count)
    local characters = util.splitToChars(text or "")
    local result = {}
    for index = 1, math.min(count, #characters) do
        result[#result + 1] = characters[index]
    end
    return table.concat(result)
end

local function makeFallbackLabel(text, action_id)
    local words = {}
    for word in tostring(text or ""):gmatch("%S+") do
        words[#words + 1] = word
        if #words == 2 then
            break
        end
    end

    if #words >= 2 then
        return string.upper(firstCharacters(words[1], 1) .. firstCharacters(words[2], 1))
    elseif #words == 1 then
        return string.upper(firstCharacters(words[1], 2))
    end

    local readable_id = tostring(action_id or "?"):gsub("_", " ")
    return string.upper(firstCharacters(readable_id, 2))
end

local function applyButtonMetrics(button, metrics)
    button.icon_width = metrics.button_icon_size
    button.icon_height = metrics.button_icon_size
    button.height = metrics.button_height
    button.width = metrics.button_width
    button.padding = metrics.button_side_padding
    button.margin = 0
    return button
end

-- Keep every detached/highlighted control on the same geometry. The close,
-- side-switch, information-panel, and frontlight buttons all share these
-- dimensions instead of duplicating them independently.
local function applyHighlightedButtonMetrics(button, width, metrics)
    button.width = width
    button.height = metrics.side_button_height
    button.padding = metrics.side_button_padding
    button.margin = 0
    button.bordersize = Size.border.button
    button.radius = Size.radius.button
    button.icon_width = metrics.side_button_icon_size
    button.icon_height = metrics.side_button_icon_size
    return button
end

local DockWidgets = dofile(PLUGIN_DIR .. "modules/widgets.lua")
local InfoPanel = dofile(PLUGIN_DIR .. "modules/info_panel.lua")
local FloatingControlButtonDialog = DockWidgets.FloatingControlButtonDialog
local QuickDock = WidgetContainer:extend({
    name = "quickdock",
})
dofile(PLUGIN_DIR .. "modules/inline_actions.lua")(QuickDock, {
    InfoPanel = InfoPanel,
    dock_margin = DOCK_MARGIN,
})

function QuickDock:init()
    self.plugin_path = PLUGIN_DIR
    self.icons_path = self.plugin_path .. "icons/"
    self.system_icon_paths = {
        DataStorage:getDataDir() .. "/icons/",
        "resources/icons/mdlight/",
        "resources/icons/",
        "resources/",
    }
    self.icon_cache = {}
    self.actions = self:loadActions()
    self.action_contexts = self:loadActionContexts()
    self.auto_visibility = self:loadAutomaticVisibility()
    self.updated = false
    self.dialog = nil
    self.info_panel_widget = nil
    self.info_panel_data = nil
    self.current_info_panel_kind = nil
    self.info_panel_cover_cache = nil
    self.status_panel_widget = nil
    self.status_panel_text = nil
    self.network_info_refresh_state = nil
    self.wifi_status_generation = 0
    self.current_page = 1

    self:patchIconWidget()
    self:onDispatcherRegisterActions()

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function QuickDock:onDispatcherRegisterActions()
    Dispatcher:registerAction(ACTION_SEARCH, {
        category = "none",
        event = "QuickDockContextSearch",
        title = _("Search current context"),
        general = true,
    })
    Dispatcher:registerAction("show_quick_dock", {
        -- The arg category lets KOReader's gesture manager forward the gesture
        -- object, including its screen position, to onShowQuickDock().
        category = "arg",
        event = "ShowQuickDock",
        title = _("Show Quick Dock"),
        general = true,
    })
end

function QuickDock:onClose()
    self:closeDock()
    InfoPanel.clearCoverCache(self)
    self:saveActions()
    self:unpatchIconWidget()
end

-- On Kindle, the screensaver is shown immediately before KOReader broadcasts
-- Suspend. Close every dock-owned overlay when that broadcast reaches the
-- plugin, otherwise a later refresh may paint an information/status panel on
-- top of the sleep screen. Do not return true: the power event must continue
-- to the other listeners.
function QuickDock:onSuspend()
    if self.dialog or self.info_panel_widget or self.status_panel_widget then
        self:closeDock()
    end
end

function QuickDock:onFlushSettings()
    if self.updated then
        self:saveActions()
        self.updated = false
    end
end

function QuickDock:loadActions()
    local actions = G_reader_settings:readSetting(SETTING_ACTIONS)
    if type(actions) ~= "table" then
        return copyTable(DEFAULT_ACTIONS)
    end

    -- Dispatcher represents “Nothing” as an empty table. Keep that as an
    -- explicit empty configuration instead of mistaking it for first use and
    -- restoring the default actions when another KOReader UI is opened.
    if type(actions.settings) ~= "table" then
        actions.settings = {}
    end

    -- The context-aware action is a fixed dock button, not a configurable
    -- action. Discard a stray saved entry to avoid showing it twice.
    actions[ACTION_HOME] = nil
    local order = actions.settings.order
    if type(order) == "table" then
        for index = #order, 1, -1 do
            if order[index] == ACTION_HOME then
                table.remove(order, index)
            end
        end
    end
    return actions
end

function QuickDock:saveActions()
    G_reader_settings:saveSetting(SETTING_ACTIONS, self.actions)
end

function QuickDock:loadActionContexts()
    local saved_contexts = G_reader_settings:readSetting(SETTING_ACTION_CONTEXTS)
    local action_contexts = {}
    if type(saved_contexts) == "table" then
        for action_id, context in pairs(saved_contexts) do
            if
                context == ACTION_CONTEXT_ALL
                or context == ACTION_CONTEXT_READER
                or context == ACTION_CONTEXT_BROWSER
            then
                action_contexts[action_id] = context
            end
        end
    end
    return action_contexts
end

function QuickDock:saveActionContexts()
    G_reader_settings:saveSetting(SETTING_ACTION_CONTEXTS, self.action_contexts)
end

function QuickDock:loadAutomaticVisibility()
    return G_reader_settings:readSetting(SETTING_AUTO_VISIBILITY) == true
end

function QuickDock:automaticVisibilityEnabled()
    if self.auto_visibility == nil then
        self.auto_visibility = self:loadAutomaticVisibility()
    end
    return self.auto_visibility
end

function QuickDock:setAutomaticVisibility(enabled)
    self.auto_visibility = enabled and true or false
    G_reader_settings:saveSetting(SETTING_AUTO_VISIBILITY, self.auto_visibility)
end

function QuickDock:getAutomaticActionVisibility(action_id)
    if BROWSER_ONLY_ACTIONS[action_id] then
        return ACTION_CONTEXT_BROWSER
    elseif READER_ONLY_ACTIONS[action_id] or tostring(action_id):match("^kopt_") then
        return ACTION_CONTEXT_READER
    end
    return ACTION_CONTEXT_ALL
end

function QuickDock:getActionVisibilityMode(action_id)
    local override = self.action_contexts[action_id]
    if override then
        return override
    elseif self:automaticVisibilityEnabled() then
        return ACTION_CONTEXT_AUTOMATIC
    end
    return ACTION_CONTEXT_ALL
end

function QuickDock:getEffectiveActionVisibility(action_id)
    local mode = self:getActionVisibilityMode(action_id)
    if mode == ACTION_CONTEXT_AUTOMATIC then
        return self:getAutomaticActionVisibility(action_id)
    end
    return mode
end

function QuickDock:setActionVisibility(action_id, context)
    if
        context == ACTION_CONTEXT_ALL
        or context == ACTION_CONTEXT_READER
        or context == ACTION_CONTEXT_BROWSER
    then
        self.action_contexts[action_id] = context
    else
        self.action_contexts[action_id] = nil
    end
    self:saveActionContexts()
end

function QuickDock:resetActionVisibility()
    self.action_contexts = {}
    self:saveActionContexts()
end

function QuickDock:resetActions()
    self.actions = copyTable(DEFAULT_ACTIONS)
    self.updated = false
    self:saveActions()
end

function QuickDock:resetBehavior()
    self:setSide("right")
    self:setSideMode(SIDE_MODE_GESTURE)
    self:setCloseDockTogether(false)
    self.current_page = 1
    self.current_dock_side = nil
end

function QuickDock:resetBehaviorAndButtons()
    self:resetBehavior()
    self:setShowContextButton(true)
    self:setShowSideButton(true)
    self:setShowCloseButton(false)
    self:setAutomaticVisibility(false)
    self:resetActionVisibility()
    self:resetActions()
end

function QuickDock:getSide()
    return G_reader_settings:readSetting(SETTING_SIDE) == "left" and "left" or "right"
end

function QuickDock:setSide(side)
    G_reader_settings:saveSetting(SETTING_SIDE, side == "left" and "left" or "right")
end

function QuickDock:getSideMode()
    return G_reader_settings:readSetting(SETTING_SIDE_MODE) == SIDE_MODE_FIXED
        and SIDE_MODE_FIXED
        or SIDE_MODE_GESTURE
end

function QuickDock:setSideMode(mode)
    G_reader_settings:saveSetting(
        SETTING_SIDE_MODE,
        mode == SIDE_MODE_GESTURE and SIDE_MODE_GESTURE or SIDE_MODE_FIXED
    )
end

function QuickDock:getGestureSide(gesture)
    if self:getSideMode() ~= SIDE_MODE_GESTURE or type(gesture) ~= "table" then
        return nil
    end

    local pos = gesture.pos or gesture.start_pos or gesture.end_pos
    local x = pos and tonumber(pos.x)
    if not x then
        return nil
    end
    return x < Screen:getWidth() / 2 and "left" or "right"
end

function QuickDock:getDockSize()
    local size = G_reader_settings:readSetting(SETTING_DOCK_SIZE)
    return DOCK_SIZE_FACTORS[size] and size or DOCK_SIZE_SMALL
end

function QuickDock:setDockSize(size)
    G_reader_settings:saveSetting(
        SETTING_DOCK_SIZE,
        DOCK_SIZE_FACTORS[size] and size or DOCK_SIZE_SMALL
    )
end

function QuickDock:getMaxActionDockHeight()
    local height = G_reader_settings:readSetting(SETTING_MAX_ACTION_DOCK_HEIGHT)
    return MAX_ACTION_DOCK_HEIGHT_FACTORS[height]
        and height
        or MAX_ACTION_DOCK_HEIGHT_100
end

function QuickDock:setMaxActionDockHeight(height)
    G_reader_settings:saveSetting(
        SETTING_MAX_ACTION_DOCK_HEIGHT,
        MAX_ACTION_DOCK_HEIGHT_FACTORS[height]
            and height
            or MAX_ACTION_DOCK_HEIGHT_100
    )
end

function QuickDock:getDockMetrics()
    local dock_size = self:getDockSize()
    if DOCK_METRICS_CACHE[dock_size] then
        return DOCK_METRICS_CACHE[dock_size]
    end
    local factor = DOCK_SIZE_FACTORS[dock_size]
    local button_height = scaleMetric(BASE_BUTTON_HEIGHT, factor)
    local button_side_padding = scaleMetric(BASE_BUTTON_SIDE_PADDING, factor)
    local side_button_height = scaleMetric(BASE_SIDE_BUTTON_HEIGHT, factor)
    local side_button_padding = scaleMetric(BASE_SIDE_BUTTON_PADDING, factor)
    local metrics = {
        button_icon_size = scaleMetric(BASE_BUTTON_ICON_SIZE, factor),
        button_height = button_height,
        button_side_padding = button_side_padding,
        button_width = button_height + 2 * button_side_padding,
        fallback_font_size = scaleMetric(18, factor),
        page_font_size = scaleMetric(24, factor),
        side_font_size = scaleMetric(22, factor),
        side_button_icon_size = scaleMetric(BASE_SIDE_BUTTON_ICON_SIZE, factor),
        side_button_height = side_button_height,
        side_button_padding = side_button_padding,
        side_button_outer_height = side_button_height
            + 2 * side_button_padding
            + 2 * Size.border.button,
        side_button_gap = scaleMetric(BASE_SIDE_BUTTON_GAP, factor),
        frontlight_slider_gap = scaleMetric(BASE_FRONTLIGHT_SLIDER_GAP, factor),
        frontlight_slider_padding = scaleMetric(BASE_FRONTLIGHT_SLIDER_PADDING, factor),
        frontlight_track_width = scaleMetric(BASE_FRONTLIGHT_TRACK_WIDTH, factor, 2),
        frontlight_knob_radius = scaleMetric(BASE_FRONTLIGHT_KNOB_RADIUS, factor, 5),
        scale_factor = factor,
    }
    DOCK_METRICS_CACHE[dock_size] = metrics
    return metrics
end

-- Optional integration with sibling floating-button plugins (currently just
-- Page Anchor): if one is visible on the given side, add whatever extra
-- clearance it reports so this dock (or its info/status panels) doesn't
-- render on top of it. Never a hard dependency -- duck-typed and
-- pcall-wrapped, so a missing plugin, a missing method, or a bug on the
-- other side just falls back to 0 extra margin instead of breaking the dock.
function QuickDock:getSiblingOverlayClearance(side)
    local sibling = self.ui and self.ui.pageanchor
    local getter = sibling and sibling.getOverlayClearance
    if type(getter) ~= "function" then
        return 0
    end
    local ok, clearance = pcall(getter, sibling, side)
    if not ok then
        if not self._logged_sibling_clearance_error then
            self._logged_sibling_clearance_error = true
            logger.warn("QuickDock: getOverlayClearance from Page Anchor failed:", clearance)
        end
        return 0
    end
    if type(clearance) == "number" and clearance > 0 then
        return clearance
    end
    return 0
end

-- Optional integration point for sibling plugins (currently just Page
-- Anchor): whether the dock is currently on screen, so a plugin whose own
-- floating element sits nearby can hold off on something -- e.g. not
-- auto-dismissing itself and leaving an empty gap under an already-open
-- dock -- while it's up.
function QuickDock:isDockVisible()
    return self.dialog ~= nil
end

function QuickDock:showSideButton()
    return G_reader_settings:readSetting(SETTING_SHOW_SIDE_BUTTON) ~= false
end

function QuickDock:setShowSideButton(enabled)
    G_reader_settings:saveSetting(SETTING_SHOW_SIDE_BUTTON, enabled and true or false)
end

function QuickDock:showCloseButton()
    return G_reader_settings:readSetting(SETTING_SHOW_CLOSE_BUTTON) == true
end

function QuickDock:setShowCloseButton(enabled)
    G_reader_settings:saveSetting(SETTING_SHOW_CLOSE_BUTTON, enabled and true or false)
end

function QuickDock:showContextButton()
    return G_reader_settings:readSetting(SETTING_SHOW_CONTEXT_BUTTON) ~= false
end

function QuickDock:setShowContextButton(enabled)
    G_reader_settings:saveSetting(SETTING_SHOW_CONTEXT_BUTTON, enabled and true or false)
end

function QuickDock:showFrontlightSlider()
    return Device:hasFrontlight()
        and G_reader_settings:readSetting(SETTING_SHOW_FRONTLIGHT_SLIDER) ~= false
end

function QuickDock:setShowFrontlightSlider(enabled)
    G_reader_settings:saveSetting(SETTING_SHOW_FRONTLIGHT_SLIDER, enabled and true or false)
end

function QuickDock:showWarmthSlider()
    return Device:hasNaturalLight()
        and G_reader_settings:readSetting(SETTING_SHOW_WARMTH_SLIDER) ~= false
end

function QuickDock:setShowWarmthSlider(enabled)
    G_reader_settings:saveSetting(SETTING_SHOW_WARMTH_SLIDER, enabled and true or false)
end

function QuickDock:showReadingInfoPanel()
    return G_reader_settings:readSetting(SETTING_SHOW_INFO_PANEL) ~= false
end

function QuickDock:setShowReadingInfoPanel(enabled)
    G_reader_settings:saveSetting(SETTING_SHOW_INFO_PANEL, enabled and true or false)
    if not enabled then
        InfoPanel.clearCoverCache(self)
    end
end

function QuickDock:showNetworkInfoPanel()
    return G_reader_settings:readSetting(SETTING_SHOW_NETWORK_INFO_PANEL) == true
end

function QuickDock:setShowNetworkInfoPanel(enabled)
    G_reader_settings:saveSetting(
        SETTING_SHOW_NETWORK_INFO_PANEL,
        enabled and true or false
    )
end

function QuickDock:showInfoPanel()
    return self:showReadingInfoPanel() or self:showNetworkInfoPanel()
end

function QuickDock:getInfoPanelKind()
    local reading = self:showReadingInfoPanel()
    local network = self:showNetworkInfoPanel()
    if self.current_info_panel_kind == "network" and network then
        return "network"
    elseif self.current_info_panel_kind == "reading" and reading then
        return "reading"
    elseif reading then
        return "reading"
    elseif network then
        return "network"
    end
end

function QuickDock:showInfoPanelCover()
    return G_reader_settings:readSetting(SETTING_SHOW_INFO_PANEL_COVER) ~= false
end

function QuickDock:setShowInfoPanelCover(enabled)
    G_reader_settings:saveSetting(SETTING_SHOW_INFO_PANEL_COVER, enabled and true or false)
    if not enabled then
        InfoPanel.clearCoverCache(self)
    end
end

function QuickDock:getInfoPanelTextAlignment()
    local alignment = G_reader_settings:readSetting(SETTING_INFO_PANEL_TEXT_ALIGNMENT)
    if INFO_PANEL_TEXT_ALIGNMENTS[alignment] then
        return alignment
    end
    return INFO_PANEL_TEXT_LEFT
end

function QuickDock:setInfoPanelTextAlignment(alignment)
    G_reader_settings:saveSetting(
        SETTING_INFO_PANEL_TEXT_ALIGNMENT,
        INFO_PANEL_TEXT_ALIGNMENTS[alignment]
            and alignment
            or INFO_PANEL_TEXT_LEFT
    )
end

function QuickDock:collectInfoPanelData(kind, metrics)
    if kind == "network" then
        return InfoPanel.collectNetwork()
    end
    return InfoPanel.collect(
        self,
        metrics,
        DOCK_MARGIN,
        self:showInfoPanelCover()
    )
end

function QuickDock:createInfoPanelOverlay(data, metrics)
    -- Always the side opposite the dock, so it can collide with a sibling
    -- overlay sitting there even when the dock itself is on the other side.
    local panel_side = self.current_dock_side == "left" and "right" or "left"
    return InfoPanel.createOverlay(
        self,
        metrics,
        panel_side,
        DOCK_MARGIN,
        data,
        self:getSiblingOverlayClearance(panel_side)
    )
end

function QuickDock:showInfoPanelToggleButton()
    return self:showReadingInfoPanel() and self:showNetworkInfoPanel()
end

function QuickDock:replaceInfoPanel(kind, metrics)
    metrics = metrics or self:getDockMetrics()
    local previous_widget = self.info_panel_widget
    local data = self:collectInfoPanelData(kind, metrics)
    local widget = self:createInfoPanelOverlay(data, metrics)

    self.info_panel_widget = nil
    self.info_panel_data = nil
    if previous_widget then
        UIManager:close(previous_widget)
    end

    self.info_panel_data = data
    self.info_panel_widget = widget
    UIManager:show(widget, "[ui]")
    return widget
end

function QuickDock:switchInfoPanel(kind)
    if
        not self.dialog
        or (kind ~= "reading" and kind ~= "network")
        or (kind == "reading" and not self:showReadingInfoPanel())
        or (kind == "network" and not self:showNetworkInfoPanel())
    then
        return
    end

    self.current_info_panel_kind = kind
    self.network_info_refresh_state = nil
    self:closeStatusPanel()
    self:replaceInfoPanel(kind)
    local toggle_button = self.dialog and self.dialog.info_panel_toggle_button
    if toggle_button and toggle_button.dimen then
        UIManager:setDirty(self.dialog, "ui", toggle_button.dimen)
    end
end

function QuickDock:refreshVisibleNetworkInfoPanel(network_state)
    if
        not self.dialog
        or self.current_info_panel_kind ~= "network"
        or not self.info_panel_widget
    then
        return false
    end
    if network_state and self.network_info_refresh_state == network_state then
        return false
    end

    self:replaceInfoPanel("network")
    self.network_info_refresh_state = network_state
    return true
end

function QuickDock:closeDockTogether()
    return G_reader_settings:readSetting(SETTING_CLOSE_TOGETHER) == true
end

function QuickDock:setCloseDockTogether(enabled)
    G_reader_settings:saveSetting(SETTING_CLOSE_TOGETHER, enabled and true or false)
end

dofile(PLUGIN_DIR .. "modules/context.lua")(QuickDock, MODULE_CONSTANTS)
function QuickDock:onShowQuickDock(gesture)
    self:showDock(1, self:getGestureSide(gesture))
    return true
end

dofile(PLUGIN_DIR .. "modules/icons.lua")(QuickDock, MODULE_CONSTANTS)
dofile(PLUGIN_DIR .. "modules/controls.lua")(QuickDock, {
    action_home = ACTION_HOME,
    stateful_actions = STATEFUL_ACTIONS,
    apply_button_metrics = applyButtonMetrics,
    apply_highlighted_button_metrics = applyHighlightedButtonMetrics,
    make_fallback_label = makeFallbackLabel,
    widgets = DockWidgets,
})
function QuickDock:getConfiguredActions()
    local configured_actions = {}
    for _, item in ipairs(Dispatcher.getDisplayList(self.actions)) do
        if item.key ~= ACTION_HOME then
            configured_actions[#configured_actions + 1] = item
        end
    end
    return configured_actions
end

function QuickDock:getDisplayActions()
    local display_actions = {}
    local current_context = self:getCurrentActionContext()
    for _, item in ipairs(self:getConfiguredActions()) do
        local visibility = self:getEffectiveActionVisibility(item.key)
        if visibility == ACTION_CONTEXT_ALL or visibility == current_context then
            display_actions[#display_actions + 1] = item
        end
    end
    return display_actions
end

function QuickDock:getMaxPageRows(metrics)
    metrics = metrics or self:getDockMetrics()
    -- ButtonTable adds vertical padding and separators around the requested
    -- button height. Account for all of it before ButtonDialog decides that
    -- it needs a ScrollableContainer (and, consequently, a scrollbar).
    local button_row_height = metrics.button_height
        + 2 * Size.padding.buttontable
        + 2 * Size.span.vertical_default
    local row_separator_height = Size.line.medium
    local dialog_height = Screen:getHeight()
        - 2 * Size.padding.buttontable
        - 2 * Size.margin.default
    local screen_available_height = Screen:getHeight()
        - 2 * DOCK_MARGIN
        - 2 * Size.border.window
    local external_button_count = (self:showSideButton() and 1 or 0)
        + (self:showCloseButton() and 1 or 0)
        + (self:showInfoPanelToggleButton() and 1 or 0)
    screen_available_height = screen_available_height
        - external_button_count * metrics.side_button_outer_height
        - external_button_count * metrics.side_button_gap
    local configured_height = math_floor(
        Screen:getHeight()
            * MAX_ACTION_DOCK_HEIGHT_FACTORS[self:getMaxActionDockHeight()]
    ) - 2 * Size.border.window
    local available_height = math_min(
        dialog_height,
        screen_available_height,
        configured_height
    )

    local minimum_rows = self:showContextButton() and 4 or 3
    return math_max(minimum_rows, math_floor(
        (available_height + row_separator_height)
        / (button_row_height + row_separator_height)
    ))
end

function QuickDock:getPages(action_count, metrics)
    local fixed_rows = self:showContextButton() and 1 or 0
    local max_rows = self:getMaxPageRows(metrics)
    local first_page_capacity = max_rows - fixed_rows
    if action_count <= first_page_capacity then
        return { { first = 1, last = action_count } }
    end

    local pages = {}
    local first = 1
    while first <= action_count do
        local remaining = action_count - first + 1
        local action_capacity
        if #pages == 0 then
            -- The reader/browser button belongs only to the first page, which
            -- also needs the next-page arrow when pagination is active.
            action_capacity = max_rows - fixed_rows - 1
        elseif remaining <= max_rows - 1 then
            -- The last page only needs the previous-page arrow.
            action_capacity = remaining
        else
            -- Intermediate pages need one navigation arrow at each end.
            action_capacity = max_rows - 2
        end
        local last = math_min(action_count, first + action_capacity - 1)
        pages[#pages + 1] = { first = first, last = last }
        first = last + 1
    end
    return pages
end

function QuickDock:closeInfoPanel()
    local info_panel_widget = self.info_panel_widget
    self.info_panel_widget = nil
    self.info_panel_data = nil
    self.network_info_refresh_state = nil
    if info_panel_widget then
        UIManager:close(info_panel_widget)
    end
end

function QuickDock:closeDock()
    local dialog = self.dialog
    if not self:closeDockTogether() then
        self.dialog = nil
        self:closeStatusPanel()
        self:closeInfoPanel()
        if dialog then
            UIManager:close(dialog)
        end
        return
    end

    local info_panel_widget = self.info_panel_widget
    local status_panel_widget = self.status_panel_widget
    self.dialog = nil
    self.info_panel_widget = nil
    self.info_panel_data = nil
    self.network_info_refresh_state = nil
    self.status_panel_widget = nil
    self.status_panel_text = nil

    local widgets = {}
    if status_panel_widget then
        widgets[#widgets + 1] = status_panel_widget
    end
    if info_panel_widget then
        widgets[#widgets + 1] = info_panel_widget
    end
    if dialog then
        widgets[#widgets + 1] = dialog
    end
    local update_region
    for index = 1, #widgets do
        local widget = widgets[index]
        if widget then
            local dimen = widget.dimen
                or (widget.movable and widget.movable.dimen)
            if dimen and dimen.x and dimen.y and dimen.w and dimen.h then
                local region = Geom:new({
                    x = dimen.x,
                    y = dimen.y,
                    w = dimen.w,
                    h = dimen.h,
                })
                update_region = update_region and update_region:combine(region) or region
            end
            -- These widgets normally enqueue their own close refresh. During
            -- a grouped dock shutdown that would make the panels disappear
            -- one at a time, so defer the refresh until all are unregistered.
            widget._quickdock_suppress_close_refresh = true
            UIManager:close(widget)
        end
    end
    if update_region then
        -- E-ink refresh backends accept rectangular regions. Separate regions
        -- are separate hardware updates and appear sequentially on some
        -- devices, so use the smallest bounding rectangle for an atomic close.
        -- The non-flashing UI waveform avoids a large black/white flash across
        -- the empty space between opposite-edge elements.
        UIManager:setDirty("all", "ui", update_region)
    end
end

function QuickDock:executeAction(action_id)
    local value = self.actions[action_id]
    if value == nil then
        return
    end

    -- Wi-Fi and night mode are the only Dispatcher actions designed to run
    -- in place. Every other action closes the dock before dispatch so dialogs
    -- and context changes always start from a clean widget stack.
    if self:executeInlineAction(action_id) then
        return
    end
    self:closeDock()
    UIManager:scheduleIn(0.05, function()
        if action_id == "history" and self:openBookshelfRecent() then
            -- Bookshelf handled the action directly.
        else
            Dispatcher:execute({ [action_id] = value })
        end
    end)
end

function QuickDock:showDock(page, side, info_panel_data)
    -- Another UI instance (reader or file browser) may have changed these
    -- shared preferences since this instance was created.
    self.action_contexts = self:loadActionContexts()
    self.auto_visibility = self:loadAutomaticVisibility()
    side = side == "left" and "left" or side == "right" and "right" or self:getSide()
    self.current_dock_side = side
    local metrics = self:getDockMetrics()
    local actions = self:getDisplayActions()
    if #actions == 0 and not self:showContextButton() then
        UIManager:show(InfoMessage:new({ text = _("No Quick Dock actions are configured.") }))
        return
    end

    local pages = self:getPages(#actions, metrics)
    local page_count = #pages
    self.current_page = math_max(1, math.min(page or 1, page_count))
    local page_range = pages[self.current_page]
    local rows = {}

    for index = page_range.last, page_range.first, -1 do
        rows[#rows + 1] = { self:makeActionButton(actions[index], metrics) }
    end

    if self.current_page < page_count then
        table.insert(rows, 1, { self:makePageButton("next", self.current_page + 1, metrics) })
    end
    if self.current_page == 1 and self:showContextButton() then
        rows[#rows + 1] = { self:makeContextButton(metrics) }
    end
    if self.current_page > 1 then
        rows[#rows + 1] = { self:makePageButton("previous", self.current_page - 1, metrics) }
    end

    self:closeDock()

    local dialog
    local side_button_factory
    if self:showSideButton() then
        side_button_factory = function(width, parent)
            return self:makeSideButton(width, parent, metrics)
        end
    end
    local close_button_factory
    if self:showCloseButton() then
        close_button_factory = function(width, parent)
            return self:makeCloseButton(width, parent, metrics)
        end
    end
    local info_panel_toggle_button_factory
    if self:showInfoPanelToggleButton() then
        info_panel_toggle_button_factory = function(width, parent)
            return self:makeInfoPanelToggleButton(width, parent, metrics)
        end
    end
    local frontlight_slider_factory
    if self:showFrontlightSlider() then
        frontlight_slider_factory = function(dock_height, parent)
            return self:makeFrontlightSlider(dock_height, parent, metrics)
        end
    end
    local warmth_slider_factory
    if self:showWarmthSlider() then
        warmth_slider_factory = function(dock_height, parent)
            return self:makeWarmthSlider(dock_height, parent, metrics)
        end
    end
    local info_panel_kind = self:getInfoPanelKind()
    self.current_info_panel_kind = info_panel_kind
    if info_panel_kind then
        if not info_panel_data or info_panel_data.kind ~= info_panel_kind then
            info_panel_data = self:collectInfoPanelData(info_panel_kind, metrics)
        end
    else
        info_panel_data = nil
        InfoPanel.clearCoverCache(self)
    end
    dialog = FloatingControlButtonDialog:new({
        buttons = rows,
        width = metrics.button_width + 2 * Size.border.window + 2 * Size.padding.button,
        shrink_unneeded_width = true,
        shrink_min_width = metrics.button_width,
        dismissable = true,
        side_button_factory = side_button_factory,
        close_button_factory = close_button_factory,
        info_panel_toggle_button_factory = info_panel_toggle_button_factory,
        frontlight_slider_factory = frontlight_slider_factory,
        warmth_slider_factory = warmth_slider_factory,
        side_button_gap = metrics.side_button_gap,
        frontlight_slider_gap = metrics.frontlight_slider_gap,
        dock_side = side,
        anchor = function()
            local dialog_size = dialog:getContentSize()
            local left
            if side == "left" then
                left = DOCK_MARGIN
            else
                left = Screen:getWidth() - DOCK_MARGIN - dialog_size.w
            end
            local bottom_margin = DOCK_MARGIN + self:getSiblingOverlayClearance(side)
            return Geom:new({
                x = math_floor(left),
                y = Screen:getHeight() - bottom_margin,
                -- Giving the anchor the dialog width keeps x as the physical
                -- left edge in both regular and mirrored UI layouts.
                w = dialog_size.w,
                h = 0,
            }), false
        end,
        close_all_callback = function()
            if self.dialog == dialog then
                self:closeDock()
                return true
            end
            return false
        end,
    })

    self.dialog = dialog
    self.info_panel_data = info_panel_data
    if info_panel_data then
        self.info_panel_widget = self:createInfoPanelOverlay(info_panel_data, metrics)
        UIManager:show(self.info_panel_widget, "[ui]")
    end
    UIManager:show(dialog, "[ui]")
end

dofile(PLUGIN_DIR .. "modules/menu.lua")(QuickDock, MODULE_CONSTANTS)
return QuickDock
