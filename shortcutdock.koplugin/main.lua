local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local PLUGIN_VERSION = "v0.6.1"
local SETTING_ACTIONS = "shortcutdock_actions"
local SETTING_ACTION_CONTEXTS = "shortcutdock_action_contexts"
local SETTING_AUTO_VISIBILITY = "shortcutdock_auto_visibility"
local SETTING_SIDE = "shortcutdock_side"
local SETTING_SHOW_SIDE_BUTTON = "shortcutdock_show_side_button"
local SETTING_SHOW_CONTEXT_BUTTON = "shortcutdock_show_context_button"

local ACTION_CONTEXT_ALL = "all"
local ACTION_CONTEXT_AUTOMATIC = "automatic"
local ACTION_CONTEXT_READER = "reader"
local ACTION_CONTEXT_BROWSER = "browser"

local BUTTON_ICON_SIZE = Screen:scaleBySize(22)
local BUTTON_HEIGHT = Screen:scaleBySize(42)
local BUTTON_SIDE_PADDING = Screen:scaleBySize(6)
local BUTTON_WIDTH = BUTTON_HEIGHT + 2 * BUTTON_SIDE_PADDING
local DOCK_MARGIN = Size.padding.large
local SIDE_BUTTON_ICON_SIZE = Screen:scaleBySize(18)
local SIDE_BUTTON_HEIGHT = Screen:scaleBySize(28)
local SIDE_BUTTON_PADDING = Screen:scaleBySize(4)
local SIDE_BUTTON_OUTER_HEIGHT = SIDE_BUTTON_HEIGHT
    + 2 * SIDE_BUTTON_PADDING
    + 2 * Size.border.button
local SIDE_BUTTON_GAP = Size.padding.default

local ACTION_HOME = "shortcutdock_context_home"
local ACTION_SEARCH = "shortcutdock_context_search"

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
            "increase_frontlight",
            "decrease_frontlight",
            ACTION_SEARCH,
            "history",
        },
    },
    toggle_wifi = true,
    increase_frontlight = 1,
    decrease_frontlight = 1,
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
    toggle_wifi = "wifi",
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

local function pluginDir()
    local source = debug.getinfo(1, "S").source or ""
    local path = source:match("^@(.*/)") or source:match("^(.*/)")
    return path or "plugins/shortcutdock.koplugin/"
end

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

local function fileExists(path)
    return lfs.attributes(path, "mode") == "file"
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

local function applyButtonMetrics(button)
    button.icon_width = BUTTON_ICON_SIZE
    button.icon_height = BUTTON_ICON_SIZE
    button.height = BUTTON_HEIGHT
    button.width = BUTTON_WIDTH
    button.padding = BUTTON_SIDE_PADDING
    button.margin = 0
    return button
end

local FloatingControlButtonDialog = ButtonDialog:extend({})

function FloatingControlButtonDialog:init()
    ButtonDialog.init(self)
    if not self.side_button_factory then
        return
    end

    local dock_frame = self.movable[1]
    local side_button = self.side_button_factory(dock_frame:getSize().w, self)
    self.movable[1] = VerticalGroup:new({
        side_button,
        VerticalSpan:new({ width = SIDE_BUTTON_GAP }),
        dock_frame,
    })

    if Device:hasDPad() and self.layout then
        table.insert(self.layout, 1, { side_button })
    end
end

local ShortcutDock = WidgetContainer:extend({
    name = "shortcutdock",
})

function ShortcutDock:init()
    self.plugin_path = pluginDir()
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
    self.current_page = 1

    self:patchIconWidget()
    self:onDispatcherRegisterActions()

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function ShortcutDock:onDispatcherRegisterActions()
    Dispatcher:registerAction(ACTION_SEARCH, {
        category = "none",
        event = "ShortcutDockContextSearch",
        title = _("Search current context"),
        general = true,
    })
    Dispatcher:registerAction("show_shortcut_dock", {
        category = "none",
        event = "ShowShortcutDock",
        title = _("Show Shortcut Dock"),
        general = true,
    })
end

function ShortcutDock:onClose()
    self:closeDock()
    self:saveActions()
    self:unpatchIconWidget()
end

function ShortcutDock:onFlushSettings()
    if self.updated then
        self:saveActions()
        self.updated = false
    end
end

function ShortcutDock:loadActions()
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

    -- Since v0.3.0 this context-aware action is a fixed dock button. Remove
    -- the old configurable entry so upgraded settings cannot show it twice.
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

function ShortcutDock:saveActions()
    G_reader_settings:saveSetting(SETTING_ACTIONS, self.actions)
end

function ShortcutDock:loadActionContexts()
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

function ShortcutDock:saveActionContexts()
    G_reader_settings:saveSetting(SETTING_ACTION_CONTEXTS, self.action_contexts)
end

function ShortcutDock:loadAutomaticVisibility()
    return G_reader_settings:readSetting(SETTING_AUTO_VISIBILITY) == true
end

function ShortcutDock:automaticVisibilityEnabled()
    if self.auto_visibility == nil then
        self.auto_visibility = self:loadAutomaticVisibility()
    end
    return self.auto_visibility
end

function ShortcutDock:setAutomaticVisibility(enabled)
    self.auto_visibility = enabled and true or false
    G_reader_settings:saveSetting(SETTING_AUTO_VISIBILITY, self.auto_visibility)
end

function ShortcutDock:getAutomaticActionVisibility(action_id)
    if BROWSER_ONLY_ACTIONS[action_id] then
        return ACTION_CONTEXT_BROWSER
    elseif READER_ONLY_ACTIONS[action_id] or tostring(action_id):match("^kopt_") then
        return ACTION_CONTEXT_READER
    end
    return ACTION_CONTEXT_ALL
end

function ShortcutDock:getActionVisibilityMode(action_id)
    local override = self.action_contexts[action_id]
    if override then
        return override
    elseif self:automaticVisibilityEnabled() then
        return ACTION_CONTEXT_AUTOMATIC
    end
    return ACTION_CONTEXT_ALL
end

function ShortcutDock:getEffectiveActionVisibility(action_id)
    local mode = self:getActionVisibilityMode(action_id)
    if mode == ACTION_CONTEXT_AUTOMATIC then
        return self:getAutomaticActionVisibility(action_id)
    end
    return mode
end

function ShortcutDock:setActionVisibility(action_id, context)
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

function ShortcutDock:resetActionVisibility()
    self.action_contexts = {}
    self:saveActionContexts()
end

function ShortcutDock:resetActions()
    self.actions = copyTable(DEFAULT_ACTIONS)
    self.updated = false
    self:saveActions()
end

function ShortcutDock:getSide()
    return G_reader_settings:readSetting(SETTING_SIDE) == "left" and "left" or "right"
end

function ShortcutDock:setSide(side)
    G_reader_settings:saveSetting(SETTING_SIDE, side == "left" and "left" or "right")
end

function ShortcutDock:showSideButton()
    return G_reader_settings:readSetting(SETTING_SHOW_SIDE_BUTTON) ~= false
end

function ShortcutDock:setShowSideButton(enabled)
    G_reader_settings:saveSetting(SETTING_SHOW_SIDE_BUTTON, enabled and true or false)
end

function ShortcutDock:showContextButton()
    return G_reader_settings:readSetting(SETTING_SHOW_CONTEXT_BUTTON) ~= false
end

function ShortcutDock:setShowContextButton(enabled)
    G_reader_settings:saveSetting(SETTING_SHOW_CONTEXT_BUTTON, enabled and true or false)
end

function ShortcutDock:isReaderContext()
    return self.ui and self.ui.document ~= nil
end

function ShortcutDock:getActiveBookshelfWidget()
    -- Use already-loaded Bookshelf modules to keep this integration optional
    -- and avoid loading the plugin merely because Shortcut Dock is opened.
    local BookshelfWidget = package.loaded["lib/bookshelf_widget"]
        or package.loaded["bookshelf_widget"]
    local live_widget = type(BookshelfWidget) == "table" and BookshelfWidget.live or nil
    if
        not live_widget
        or type(UIManager.isWidgetShown) ~= "function"
    then
        return nil
    end

    local shown_ok, shown = pcall(UIManager.isWidgetShown, UIManager, live_widget)
    if not shown_ok or not shown then
        return nil
    end

    -- Bookshelf deliberately remains in UIManager's stack after a parked
    -- reader is resumed. In that state isWidgetShown() is still true, but the
    -- ReaderUI that owns this plugin is above Bookshelf and is the active
    -- context. Compare both positions so search and history target the screen
    -- actually in the foreground.
    local stack = UIManager._window_stack
    if type(stack) == "table" then
        local bookshelf_index
        local host_index
        for index, window in ipairs(stack) do
            local widget = type(window) == "table" and window.widget or nil
            if widget == live_widget then
                bookshelf_index = index
            elseif widget == self.ui then
                host_index = index
            end
        end

        if not bookshelf_index then
            return nil
        elseif host_index then
            return bookshelf_index > host_index and live_widget or nil
        end
    end

    -- Compatibility fallback for UIManager implementations whose stack is
    -- unavailable or does not expose the host widget. In reader context,
    -- Bookshelf is active only while that reader is parked.
    if self:isReaderContext() then
        local Park = package.loaded["lib/bookshelf_reader_park"]
            or package.loaded["bookshelf_reader_park"]
        if type(Park) ~= "table" or type(Park.isParked) ~= "function" then
            return nil
        end
        local parked_ok, parked = pcall(Park.isParked)
        if not parked_ok or not parked then
            return nil
        end
    end

    return live_widget
end

function ShortcutDock:getParkedBookshelfContext()
    -- Bookshelf keeps ReaderUI alive while showing its full-screen widget, so
    -- self.ui.document alone cannot distinguish the shelf from the reader.
    local live_widget = self:getActiveBookshelfWidget()
    local Park = package.loaded["lib/bookshelf_reader_park"]
        or package.loaded["bookshelf_reader_park"]
    if
        not live_widget
        or type(Park) ~= "table"
        or type(Park.isParked) ~= "function"
        or type(Park.unpark) ~= "function"
    then
        return nil
    end

    local parked_ok, parked = pcall(Park.isParked)
    if parked_ok and parked then
        return {
            park = Park,
            widget = live_widget,
        }
    end
end

function ShortcutDock:getCurrentActionContext()
    if self:getParkedBookshelfContext() then
        return ACTION_CONTEXT_BROWSER
    end
    return self:isReaderContext() and ACTION_CONTEXT_READER or ACTION_CONTEXT_BROWSER
end

function ShortcutDock:onShortcutDockContextHome()
    local bookshelf = self:getParkedBookshelfContext()
    if bookshelf then
        local ok, resumed = pcall(bookshelf.park.unpark, bookshelf.widget)
        if not ok or resumed == false then
            UIManager:show(InfoMessage:new({
                text = _("Could not return to the reader."),
            }))
        end
        return true
    end

    if self:isReaderContext() then
        UIManager:broadcastEvent(require("ui/event"):new("Home"))
    else
        UIManager:broadcastEvent(require("ui/event"):new("OpenLastDoc"))
    end
    return true
end

function ShortcutDock:onShortcutDockContextSearch()
    local bookshelf = self:getActiveBookshelfWidget()
    if bookshelf and type(bookshelf._openSearchDialog) == "function" then
        local ok = pcall(bookshelf._openSearchDialog, bookshelf)
        if ok then
            return true
        end
    end

    local event = self:isReaderContext() and "ShowFulltextSearchInput" or "ShowFileSearch"
    UIManager:broadcastEvent(require("ui/event"):new(event))
    return true
end

function ShortcutDock:openBookshelfRecent()
    local bookshelf = self:getActiveBookshelfWidget()
    if not bookshelf then
        return false
    end

    local select_chip = bookshelf._selectChip or bookshelf._setActiveChip
    if type(select_chip) ~= "function" then
        return false
    end

    local recent_id = "recent"
    local TabModel = package.loaded["lib/bookshelf_tab_model"]
        or package.loaded["bookshelf_tab_model"]
    if type(TabModel) == "table" and type(TabModel.load) == "function" then
        local loaded_ok, tabs = pcall(TabModel.load)
        if loaded_ok and type(tabs) == "table" then
            recent_id = nil
            for _, tab in ipairs(tabs) do
                if type(tab) == "table" and tab.source and tab.source.kind == "recent" then
                    recent_id = tab.id
                    break
                end
            end
            if not recent_id then
                return false
            end
        end
    end

    local ok = pcall(select_chip, bookshelf, recent_id)
    return ok
end

function ShortcutDock:onShowShortcutDock()
    self:showDock(1)
    return true
end

function ShortcutDock:patchIconWidget()
    if IconWidget._shortcutdock_original_init then
        return
    end

    IconWidget._shortcutdock_original_init = IconWidget.init
    local original_init = IconWidget.init

    local patched_init = function(icon_widget)
        local explicit_icon = rawget(icon_widget, "icon")
        if type(explicit_icon) == "string" and explicit_icon:match("%.[%a%d]+$") and fileExists(explicit_icon) then
            icon_widget.file = explicit_icon
        end
        return original_init(icon_widget)
    end

    IconWidget._shortcutdock_patched_init = patched_init
    IconWidget.init = patched_init
end

function ShortcutDock:unpatchIconWidget()
    if
        IconWidget._shortcutdock_original_init
        and IconWidget._shortcutdock_patched_init
        and IconWidget.init == IconWidget._shortcutdock_patched_init
    then
        IconWidget.init = IconWidget._shortcutdock_original_init
        IconWidget._shortcutdock_original_init = nil
        IconWidget._shortcutdock_patched_init = nil
    end
end

function ShortcutDock:isWifiOn()
    local ok, enabled = pcall(function()
        return NetworkMgr:isWifiOn()
    end)
    return ok and enabled == true
end

function ShortcutDock:getStockIcon(action_id)
    if action_id == "toggle_wifi" then
        return self:isWifiOn() and "wifi" or "wifi-off"
    end
    if action_id == ACTION_HOME then
        if self:getParkedBookshelfContext() then
            return "book.opened"
        end
        if self:isReaderContext() then
            return "home"
        end
    end
    return ACTION_ICONS[action_id]
end

function ShortcutDock:systemIconExists(icon)
    if not icon then
        return false
    end
    for _, directory in ipairs(self.system_icon_paths) do
        for _, extension in ipairs(ICON_EXTENSIONS) do
            if fileExists(directory .. icon .. extension) then
                return true
            end
        end
    end
    return false
end

function ShortcutDock:getIcon(action_id)
    local stock_icon = self:getStockIcon(action_id)
    local cache_key = action_id .. ":" .. (stock_icon or "")
    local cached = self.icon_cache[cache_key]
    if cached ~= nil then
        return cached or nil
    end

    local candidates = {
        self.icons_path .. action_id .. ".svg",
        self.icons_path .. action_id .. ".png",
    }
    if stock_icon then
        candidates[#candidates + 1] = self.icons_path .. stock_icon .. ".svg"
        candidates[#candidates + 1] = self.icons_path .. stock_icon .. ".png"
    end

    for _, path in ipairs(candidates) do
        if fileExists(path) then
            self.icon_cache[cache_key] = path
            return path
        end
    end

    if self:systemIconExists(stock_icon) then
        self.icon_cache[cache_key] = stock_icon
        return stock_icon
    end

    self.icon_cache[cache_key] = false
end

function ShortcutDock:getConfiguredActions()
    local configured_actions = {}
    for _, item in ipairs(Dispatcher.getDisplayList(self.actions)) do
        if item.key ~= ACTION_HOME then
            configured_actions[#configured_actions + 1] = item
        end
    end
    return configured_actions
end

function ShortcutDock:getDisplayActions()
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

function ShortcutDock:getMaxPageRows()
    -- ButtonTable adds vertical padding and separators around the requested
    -- button height. Account for all of it before ButtonDialog decides that
    -- it needs a ScrollableContainer (and, consequently, a scrollbar).
    local button_row_height = BUTTON_HEIGHT
        + 2 * Size.padding.buttontable
        + 2 * Size.span.vertical_default
    local row_separator_height = Size.line.medium
    local dialog_height = Screen:getHeight()
        - 2 * Size.padding.buttontable
        - 2 * Size.margin.default
    local dock_height = Screen:getHeight()
        - 2 * DOCK_MARGIN
        - 2 * Size.border.window
    if self:showSideButton() then
        dock_height = dock_height - SIDE_BUTTON_OUTER_HEIGHT - SIDE_BUTTON_GAP
    end
    local available_height = math_min(dialog_height, dock_height)

    local minimum_rows = self:showContextButton() and 4 or 3
    return math_max(minimum_rows, math_floor(
        (available_height + row_separator_height)
        / (button_row_height + row_separator_height)
    ))
end

function ShortcutDock:getPages(action_count)
    local fixed_rows = self:showContextButton() and 1 or 0
    local max_rows = self:getMaxPageRows() - fixed_rows
    if action_count <= max_rows then
        return { { first = 1, last = action_count } }
    end

    local pages = {}
    local first = 1
    while first <= action_count do
        local remaining = action_count - first + 1
        local action_capacity
        if #pages == 0 then
            -- The first page only needs the next-page arrow.
            action_capacity = max_rows - 1
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

function ShortcutDock:closeDock()
    if self.dialog then
        local dialog = self.dialog
        self.dialog = nil
        UIManager:close(dialog)
    end
end

function ShortcutDock:executeAction(action_id)
    local value = self.actions[action_id]
    if value == nil then
        return
    end

    self:closeDock()
    UIManager:scheduleIn(0.05, function()
        if action_id == "history" and self:openBookshelfRecent() then
            return
        end
        Dispatcher:execute({ [action_id] = value })
    end)
end

function ShortcutDock:makeActionButton(item)
    local icon = self:getIcon(item.key)
    local button = {
        id = "shortcutdock_" .. item.key,
        enabled = true,
        callback = function()
            self:executeAction(item.key)
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new({ text = item.text }))
        end,
    }
    if icon then
        button.icon = icon
    else
        button.text = makeFallbackLabel(item.text, item.key)
        button.font_size = 18
        button.font_bold = true
    end
    return applyButtonMetrics(button)
end

function ShortcutDock:makeContextButton()
    local bookshelf = self:getParkedBookshelfContext()
    local in_reader = self:isReaderContext()
    local text
    if bookshelf then
        text = _("Return to reader")
    elseif in_reader then
        text = _("File browser")
    else
        text = _("Open last document")
    end
    local icon = self:getIcon(ACTION_HOME)
    local button = {
        id = "shortcutdock_context_home",
        enabled = true,
        callback = function()
            self:closeDock()
            UIManager:scheduleIn(0.05, function()
                self:onShortcutDockContextHome()
            end)
        end,
        hold_callback = function()
            UIManager:show(InfoMessage:new({ text = text }))
        end,
    }
    if icon then
        button.icon = icon
    else
        button.text = makeFallbackLabel(text, ACTION_HOME)
        button.font_size = 18
        button.font_bold = true
    end
    return applyButtonMetrics(button)
end

function ShortcutDock:makePageButton(direction, target_page)
    local is_next = direction == "next"
    local icon = self:getIcon(is_next and "chevron-up" or "chevron-down")
    local button = {
        id = is_next and "shortcutdock_next" or "shortcutdock_previous",
        enabled = true,
        callback = function()
            self:showDock(target_page)
        end,
    }
    if icon then
        button.icon = icon
    else
        button.text = is_next and "↑" or "↓"
        button.font_size = 24
    end
    return applyButtonMetrics(button)
end

function ShortcutDock:makeSideButton(width, dialog)
    local current_side = self:getSide()
    local target_side = current_side == "left" and "right" or "left"
    local icon = self:getIcon("chevron-" .. target_side)
    local button = {
        id = "shortcutdock_switch_side",
        width = width,
        height = SIDE_BUTTON_HEIGHT,
        padding = SIDE_BUTTON_PADDING,
        margin = 0,
        bordersize = Size.border.button,
        radius = Size.radius.button,
        icon_width = SIDE_BUTTON_ICON_SIZE,
        icon_height = SIDE_BUTTON_ICON_SIZE,
        enabled = true,
        show_parent = dialog,
        callback = function()
            local page = self.current_page
            self:setSide(target_side)
            UIManager:scheduleIn(0.05, function()
                self:showDock(page)
            end)
        end,
        hold_callback = function()
            local message = target_side == "left"
                and _("Move dock to the left")
                or _("Move dock to the right")
            UIManager:show(InfoMessage:new({ text = message }))
        end,
    }
    if icon then
        button.icon = icon
    else
        button.text = target_side == "left" and "←" or "→"
        button.text_font_size = 22
        button.text_font_bold = true
    end
    return Button:new(button)
end

function ShortcutDock:showDock(page)
    -- Another UI instance (reader or file browser) may have changed these
    -- shared preferences since this instance was created.
    self.action_contexts = self:loadActionContexts()
    self.auto_visibility = self:loadAutomaticVisibility()
    local actions = self:getDisplayActions()
    if #actions == 0 and not self:showContextButton() then
        UIManager:show(InfoMessage:new({ text = _("No Shortcut Dock actions are configured.") }))
        return
    end

    local pages = self:getPages(#actions)
    local page_count = #pages
    self.current_page = math_max(1, math.min(page or 1, page_count))
    local page_range = pages[self.current_page]
    local rows = {}

    for index = page_range.last, page_range.first, -1 do
        rows[#rows + 1] = { self:makeActionButton(actions[index]) }
    end

    if self.current_page < page_count then
        table.insert(rows, 1, { self:makePageButton("next", self.current_page + 1) })
    end
    if self:showContextButton() then
        rows[#rows + 1] = { self:makeContextButton() }
    end
    if self.current_page > 1 then
        rows[#rows + 1] = { self:makePageButton("previous", self.current_page - 1) }
    end

    self:closeDock()

    local dialog
    local side_button_factory
    if self:showSideButton() then
        side_button_factory = function(width, parent)
            return self:makeSideButton(width, parent)
        end
    end
    dialog = FloatingControlButtonDialog:new({
        buttons = rows,
        width = BUTTON_WIDTH + 2 * Size.border.window + 2 * Size.padding.button,
        shrink_unneeded_width = true,
        shrink_min_width = BUTTON_WIDTH,
        dismissable = true,
        side_button_factory = side_button_factory,
        anchor = function()
            local dialog_size = dialog:getContentSize()
            local left
            if self:getSide() == "left" then
                left = DOCK_MARGIN
            else
                left = Screen:getWidth() - DOCK_MARGIN - dialog_size.w
            end
            return Geom:new({
                x = math_floor(left),
                y = Screen:getHeight() - DOCK_MARGIN,
                -- Giving the anchor the dialog width keeps x as the physical
                -- left edge in both regular and mirrored UI layouts.
                w = dialog_size.w,
                h = 0,
            }), false
        end,
        close_callback = function()
            if self.dialog == dialog then
                self.dialog = nil
            end
        end,
        tap_close_callback = function()
            if self.dialog == dialog then
                self.dialog = nil
            end
        end,
    })

    self.dialog = dialog
    UIManager:show(dialog, "[ui]")
end

function ShortcutDock:getActionsMenu()
    local menu = {
        {
            text = _("Reset default buttons"),
            callback = function(touchmenu_instance)
                self:resetActions()
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            separator = true,
        },
    }

    Dispatcher:addSubMenu(self, menu, self, "actions")
    return menu
end

function ShortcutDock:getActionVisibilityLabel(context)
    if context == ACTION_CONTEXT_AUTOMATIC then
        return _("Automatic")
    elseif context == ACTION_CONTEXT_READER then
        return _("Reader only")
    elseif context == ACTION_CONTEXT_BROWSER then
        return _("File browser and Bookshelf only")
    end
    return _("Everywhere")
end

function ShortcutDock:getActionVisibilitySummary(action_id)
    local mode = self:getActionVisibilityMode(action_id)
    if mode == ACTION_CONTEXT_AUTOMATIC then
        return self:getActionVisibilityLabel(mode)
            .. " (" .. self:getActionVisibilityLabel(self:getEffectiveActionVisibility(action_id)) .. ")"
    end
    return self:getActionVisibilityLabel(mode)
end

function ShortcutDock:makeActionVisibilityOption(action_id, context)
    return {
        text = self:getActionVisibilityLabel(context),
        enabled_func = function()
            return context ~= ACTION_CONTEXT_AUTOMATIC or self:automaticVisibilityEnabled()
        end,
        checked_func = function()
            return self:getActionVisibilityMode(action_id) == context
        end,
        radio = true,
        callback = function(touchmenu_instance)
            self:setActionVisibility(action_id, context)
            if touchmenu_instance and touchmenu_instance.updateItems then
                touchmenu_instance:updateItems()
            end
        end,
        keep_menu_open = true,
    }
end

function ShortcutDock:getActionVisibilityMenu()
    self.action_contexts = self:loadActionContexts()
    self.auto_visibility = self:loadAutomaticVisibility()
    local menu = {
        {
            text_func = function()
                if self:automaticVisibilityEnabled() then
                    return _("Use automatic visibility for all actions")
                end
                return _("Show all actions everywhere")
            end,
            checked_func = function()
                return next(self.action_contexts) == nil
            end,
            callback = function(touchmenu_instance)
                self:resetActionVisibility()
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
            keep_menu_open = true,
            separator = true,
        },
    }

    local actions = self:getConfiguredActions()
    if #actions == 0 then
        menu[#menu + 1] = {
            text = _("No Shortcut Dock actions are configured."),
            enabled = false,
        }
        return menu
    end

    for _, item in ipairs(actions) do
        local action_id = item.key
        local action_text = tostring(item.text or action_id)
        menu[#menu + 1] = {
            text_func = function()
                return action_text .. ": " .. self:getActionVisibilitySummary(action_id)
            end,
            sub_item_table = {
                self:makeActionVisibilityOption(action_id, ACTION_CONTEXT_AUTOMATIC),
                self:makeActionVisibilityOption(action_id, ACTION_CONTEXT_ALL),
                self:makeActionVisibilityOption(action_id, ACTION_CONTEXT_READER),
                self:makeActionVisibilityOption(action_id, ACTION_CONTEXT_BROWSER),
            },
        }
    end
    return menu
end

function ShortcutDock:getIconFilenamesMenu()
    local menu = {}
    local actions = self:getConfiguredActions()
    table.insert(actions, 1, {
        key = ACTION_HOME,
        text = _("File browser / return to reader / open last document"),
    })
    for index = 1, #actions do
        local item = actions[index]
        local basename = tostring(item.key)
        local svg_name = basename .. ".svg"
        local png_name = basename .. ".png"
        local help_text = _("Alternative PNG filename") .. ": " .. png_name
        local details = tostring(item.text or basename)
            .. "\n\nSVG: " .. svg_name
            .. "\nPNG: " .. png_name
        if item.key == ACTION_HOME then
            help_text = help_text
                .. "\n" .. _("Context-specific SVG filenames")
                .. ": home.svg / book.opened.svg"
            details = details
                .. "\n\n" .. _("While reading") .. ": home.svg / home.png"
                .. "\n" .. _("In the file browser") .. ": book.opened.svg / book.opened.png"
                .. "\n" .. _("In Bookshelf with a parked reader")
                .. ": book.opened.svg / book.opened.png"
        end
        menu[#menu + 1] = {
            text = tostring(item.text or basename) .. ": " .. svg_name,
            help_text = help_text,
            callback = function()
                UIManager:show(InfoMessage:new({ text = details }))
            end,
        }
    end
    if #menu == 0 then
        menu[1] = {
            text = _("No Shortcut Dock actions are configured."),
            enabled = false,
        }
    end
    return menu
end

function ShortcutDock:addToMainMenu(menu_items)
    menu_items.shortcutdock = {
        text = _("Shortcut Dock"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Show Shortcut Dock"),
                callback = function()
                    self:showDock(1)
                end,
            },
            {
                text = _("Appearance"),
                sub_item_table = {
                    {
                        text = _("Dock side"),
                        sub_item_table = {
                            {
                                text = _("Left"),
                                checked_func = function()
                                    return self:getSide() == "left"
                                end,
                                callback = function(touchmenu_instance)
                                    self:setSide("left")
                                    if touchmenu_instance and touchmenu_instance.updateItems then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                                keep_menu_open = true,
                            },
                            {
                                text = _("Right"),
                                checked_func = function()
                                    return self:getSide() == "right"
                                end,
                                callback = function(touchmenu_instance)
                                    self:setSide("right")
                                    if touchmenu_instance and touchmenu_instance.updateItems then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                                keep_menu_open = true,
                            },
                        },
                    },
                    {
                        text = _("Show side-switch button"),
                        help_text = _("Shows a separate chevron button above the dock for changing sides without opening the settings."),
                        checked_func = function()
                            return self:showSideButton()
                        end,
                        callback = function(touchmenu_instance)
                            self:setShowSideButton(not self:showSideButton())
                            if touchmenu_instance and touchmenu_instance.updateItems then
                                touchmenu_instance:updateItems()
                            end
                        end,
                        keep_menu_open = true,
                    },
                },
            },
            {
                text = _("Buttons"),
                sub_item_table = {
                    {
                        text = _("Show fixed context button"),
                        help_text = _("Shows File browser while reading, Return to reader in Bookshelf, and Open last document in the file browser."),
                        checked_func = function()
                            return self:showContextButton()
                        end,
                        callback = function(touchmenu_instance)
                            self:setShowContextButton(not self:showContextButton())
                            if touchmenu_instance and touchmenu_instance.updateItems then
                                touchmenu_instance:updateItems()
                            end
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text_func = function()
                            return _("Buttons and order") .. ": " .. tostring(#self:getConfiguredActions())
                        end,
                        sub_item_table_func = function()
                            return self:getActionsMenu()
                        end,
                    },
                    {
                        text = _("Automatic context visibility"),
                        help_text = _("Automatically shows native reader and file-browser actions only in their relevant context. Manual choices override the automatic result."),
                        checked_func = function()
                            return self:automaticVisibilityEnabled()
                        end,
                        callback = function(touchmenu_instance)
                            self:setAutomaticVisibility(not self:automaticVisibilityEnabled())
                            if touchmenu_instance and touchmenu_instance.updateItems then
                                touchmenu_instance:updateItems()
                            end
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Visibility by context"),
                        help_text = _("Review automatic results or override each action for all screens, the reader, or the file browser and Bookshelf."),
                        sub_item_table_func = function()
                            return self:getActionVisibilityMenu()
                        end,
                    },
                    {
                        text = _("Expected icon filenames"),
                        help_text = _("Shows the custom SVG and PNG filenames expected for each dock action."),
                        sub_item_table_func = function()
                            return self:getIconFilenamesMenu()
                        end,
                    },
                },
            },
            {
                text = _("Gesture setup"),
                help_text = _("Assign 'Show Shortcut Dock' to any gesture in KOReader's gesture manager."),
                callback = function()
                    UIManager:show(InfoMessage:new({
                        text = _("Open Settings > Taps and gestures > Gesture manager, choose a gesture, then select Show Shortcut Dock."),
                    }))
                end,
            },
            {
                text = _("Version") .. ": " .. PLUGIN_VERSION,
                callback = function()
                    UIManager:show(InfoMessage:new({ text = _("Shortcut Dock") .. " " .. PLUGIN_VERSION }))
                end,
                separator = true,
            },
        },
    }
end

return ShortcutDock
