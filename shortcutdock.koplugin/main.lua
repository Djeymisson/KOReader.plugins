local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetworkMgr = require("ui/network/manager")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local PLUGIN_VERSION = "v0.8.1"
local SETTING_ACTIONS = "shortcutdock_actions"
local SETTING_ACTION_CONTEXTS = "shortcutdock_action_contexts"
local SETTING_AUTO_VISIBILITY = "shortcutdock_auto_visibility"
local SETTING_SIDE = "shortcutdock_side"
local SETTING_SIDE_MODE = "shortcutdock_side_mode"
local SETTING_SHOW_SIDE_BUTTON = "shortcutdock_show_side_button"
local SETTING_SHOW_CONTEXT_BUTTON = "shortcutdock_show_context_button"
local SETTING_SHOW_FRONTLIGHT_SLIDER = "shortcutdock_show_frontlight_slider"

local SIDE_MODE_FIXED = "fixed"
local SIDE_MODE_GESTURE = "gesture"

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
local FRONTLIGHT_SLIDER_WIDTH = BUTTON_WIDTH
local FRONTLIGHT_SLIDER_GAP = Size.padding.default
local FRONTLIGHT_SLIDER_PADDING = Screen:scaleBySize(8)
local FRONTLIGHT_TRACK_WIDTH = math_max(2, Screen:scaleBySize(3))
local FRONTLIGHT_KNOB_RADIUS = math_max(5, Screen:scaleBySize(8))

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

local FrontlightSlider = InputContainer:extend({})

function FrontlightSlider:init()
    self.width = self.width or FRONTLIGHT_SLIDER_WIDTH
    self.height = math_max(1, self.height or Screen:getHeight() / 2)
    self.powerd = self.powerd or Device:getPowerDevice()
    self.minimum = tonumber(self.powerd and self.powerd.fl_min) or 0
    self.maximum = tonumber(self.powerd and self.powerd.fl_max) or 100
    if self.maximum <= self.minimum then
        self.maximum = self.minimum + 1
    end

    self.value = self.minimum
    self.enabled = false
    self:syncFromPower()
    self.last_refresh_time = 0
    self.dimen = Geom:new({ x = 0, y = 0, w = self.width, h = self.height })

    if Device:isTouchDevice() then
        self.ges_events = {
            TapFrontlightSlider = {
                GestureRange:new({ ges = "tap", range = self.dimen }),
            },
            PanFrontlightSlider = {
                GestureRange:new({ ges = "pan", range = self.dimen }),
            },
            PanReleaseFrontlightSlider = {
                GestureRange:new({ ges = "pan_release", range = self.dimen }),
            },
        }
    end
end

function FrontlightSlider:syncFromPower(notify_state_change)
    local was_enabled = self.enabled
    local level_ok, level = pcall(function()
        return self.powerd:frontlightIntensity()
    end)
    if level_ok then
        self.value = tonumber(level) or self.minimum
        self.value = math_max(self.minimum, math_min(self.maximum, self.value))
    end

    local state_ok, light_on = pcall(function()
        return self.powerd:isFrontlightOn()
    end)
    if state_ok then
        self.enabled = light_on == true
    else
        self.enabled = self.value > self.minimum
    end
    if
        notify_state_change
        and was_enabled ~= self.enabled
        and self.state_changed_callback
    then
        self.state_changed_callback(self.enabled)
    end
    return self.enabled
end

function FrontlightSlider:getSize()
    return self.dimen
end

function FrontlightSlider:getTrackBounds()
    local inset = FRONTLIGHT_SLIDER_PADDING + FRONTLIGHT_KNOB_RADIUS
    local top = inset
    local bottom = math_max(top + 1, self.height - inset)
    return top, bottom
end

function FrontlightSlider:getLevelFromPosition(pos)
    if not pos or not self.dimen then
        return nil
    end

    local track_top, track_bottom = self:getTrackBounds()
    local relative_y = math_max(track_top, math_min(track_bottom, pos.y - (self.dimen.y or 0)))
    local percentage = (track_bottom - relative_y) / math_max(1, track_bottom - track_top)
    return math_floor(self.minimum + percentage * (self.maximum - self.minimum) + 0.5)
end

function FrontlightSlider:refreshSlider(force)
    local now = time.now()
    if Screen.low_pan_rate and not force then
        local min_interval = time.s(1 / 3)
        if now - self.last_refresh_time < min_interval then
            return
        end
    end
    self.last_refresh_time = now
    UIManager:setDirty(self.show_parent or self, "fast", self.dimen)
end

function FrontlightSlider:setLevelFromPosition(pos, force_refresh)
    if not self.enabled then
        return true
    end

    local level = self:getLevelFromPosition(pos)
    if level == nil then
        return true
    end

    if level ~= self.value then
        local ok = pcall(function()
            -- KOReader reserves the minimum frontlight level (normally zero)
            -- for toggling the light, which lets device-specific PowerD
            -- implementations use their proper on/off path.
            if level == self.minimum and type(self.powerd.toggleFrontlight) == "function" then
                self.powerd:toggleFrontlight()
            else
                self.powerd:setIntensity(level)
            end
            self.powerd:updateResumeFrontlightState()
        end)
        if ok then
            self:syncFromPower(true)
        end
    end
    self:refreshSlider(force_refresh)
    return true
end

function FrontlightSlider:onTapFrontlightSlider(_arg, gesture)
    return self:setLevelFromPosition(gesture and gesture.pos, true)
end

function FrontlightSlider:onPanFrontlightSlider(_arg, gesture)
    return self:setLevelFromPosition(gesture and gesture.pos, false)
end

function FrontlightSlider:onPanReleaseFrontlightSlider(_arg, gesture)
    return self:setLevelFromPosition(gesture and (gesture.pos or gesture.end_pos), true)
end

function FrontlightSlider:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    self:syncFromPower()

    local border = Size.border.button
    local radius = Size.radius.button
    local background = Blitbuffer.COLOR_WHITE
    local paint_rounded_rect = Blitbuffer.isColor8(background) and bb.paintRoundedRect or bb.paintRoundedRectRGB32
    paint_rounded_rect(bb, x, y, self.width, self.height, background, radius + border)
    bb:paintBorder(
        x,
        y,
        self.width,
        self.height,
        border,
        Blitbuffer.COLOR_BLACK,
        radius,
        G_reader_settings:nilOrTrue("anti_alias_ui")
    )

    local track_top, track_bottom = self:getTrackBounds()
    local track_height = math_max(1, track_bottom - track_top)
    local percentage = (self.value - self.minimum) / (self.maximum - self.minimum)
    local knob_y = y + track_bottom - math_floor(percentage * track_height + 0.5)
    local center_x = x + math_floor(self.width / 2)
    local track_x = center_x - math_floor(FRONTLIGHT_TRACK_WIDTH / 2)

    local track_color = self.enabled and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_LIGHT_GRAY
    local active_color = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    bb:paintRect(track_x, y + track_top, FRONTLIGHT_TRACK_WIDTH, track_height, track_color)
    if knob_y < y + track_bottom then
        bb:paintRect(
            track_x,
            knob_y,
            FRONTLIGHT_TRACK_WIDTH,
            y + track_bottom - knob_y,
            active_color
        )
    end
    bb:paintCircle(center_x, knob_y, FRONTLIGHT_KNOB_RADIUS, active_color)
end

local FrontlightToggleButton = Button:extend({})

function FrontlightToggleButton:paintTo(bb, x, y)
    self.slider:syncFromPower()
    local icon = self.icon_provider(self.slider.enabled)
    if icon then
        if icon ~= self.icon or self.text ~= nil then
            self.text = nil
            self.icon = nil
            self:setIcon(icon, self.width)
        end
    else
        local text = self.slider.enabled and _("On") or _("Off")
        if text ~= self.text or self.icon ~= nil then
            self.icon = nil
            self:setText(text, self.width)
        end
    end
    Button.paintTo(self, bb, x, y)
end

local FloatingControlButtonDialog = ButtonDialog:extend({})

function FloatingControlButtonDialog:init()
    ButtonDialog.init(self)
    if not self.side_button_factory and not self.frontlight_slider_factory then
        return
    end

    local dock_frame = self.movable[1]
    local dock_size = dock_frame:getSize()
    local dock_column = dock_frame
    local side_button
    local frontlight_column
    if self.side_button_factory then
        side_button = self.side_button_factory(dock_size.w, self)
        dock_column = VerticalGroup:new({
            side_button,
            VerticalSpan:new({ width = SIDE_BUTTON_GAP }),
            dock_frame,
        })
    end

    if self.frontlight_slider_factory then
        frontlight_column = self.frontlight_slider_factory(dock_size.h, self)
        local dock_column_height = dock_column:getSize().h
        local slider_height = frontlight_column:getSize().h
        local total_height = math_max(dock_column_height, slider_height)
        local aligned_dock_column = VerticalGroup:new({
            VerticalSpan:new({ width = total_height - dock_column_height }),
            dock_column,
        })
        local aligned_slider = VerticalGroup:new({
            VerticalSpan:new({ width = total_height - slider_height }),
            frontlight_column,
        })
        local columns
        if self.dock_side == "left" then
            columns = {
                aligned_dock_column,
                HorizontalSpan:new({ width = FRONTLIGHT_SLIDER_GAP }),
                aligned_slider,
            }
        else
            columns = {
                aligned_slider,
                HorizontalSpan:new({ width = FRONTLIGHT_SLIDER_GAP }),
                aligned_dock_column,
            }
        end
        -- These are physical screen sides, so bidi mirroring must not swap the
        -- dock and slider after their order has already been selected above.
        columns.allow_mirroring = false
        self.movable[1] = HorizontalGroup:new(columns)
    else
        self.movable[1] = dock_column
    end

    if side_button and Device:hasDPad() and self.layout then
        table.insert(self.layout, 1, { side_button })
    end
    if
        frontlight_column
        and frontlight_column.toggle_button
        and Device:hasDPad()
        and self.layout
    then
        table.insert(self.layout, 1, { frontlight_column.toggle_button })
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
        -- The arg category lets KOReader's gesture manager forward the gesture
        -- object, including its screen position, to onShowShortcutDock().
        category = "arg",
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

function ShortcutDock:getSideMode()
    return G_reader_settings:readSetting(SETTING_SIDE_MODE) == SIDE_MODE_GESTURE
        and SIDE_MODE_GESTURE
        or SIDE_MODE_FIXED
end

function ShortcutDock:setSideMode(mode)
    G_reader_settings:saveSetting(
        SETTING_SIDE_MODE,
        mode == SIDE_MODE_GESTURE and SIDE_MODE_GESTURE or SIDE_MODE_FIXED
    )
end

function ShortcutDock:getGestureSide(gesture)
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

function ShortcutDock:showFrontlightSlider()
    return Device:hasFrontlight()
        and G_reader_settings:readSetting(SETTING_SHOW_FRONTLIGHT_SLIDER) ~= false
end

function ShortcutDock:setShowFrontlightSlider(enabled)
    G_reader_settings:saveSetting(SETTING_SHOW_FRONTLIGHT_SLIDER, enabled and true or false)
end

function ShortcutDock:getFrontlightSliderHeight(dock_height)
    local screen_height = Screen:getHeight()
    dock_height = math_max(1, tonumber(dock_height) or 1)
    if dock_height < screen_height / 3 then
        return math_floor(screen_height / 2)
    end
    return dock_height
end

function ShortcutDock:makeFrontlightToggleButton(width, dialog, slider)
    local powerd = slider.powerd
    local function getStateIcon()
        return self:getIcon(slider.enabled and "light_on" or "light_off")
    end

    local icon = getStateIcon()
    local config = {
        id = "shortcutdock_toggle_frontlight",
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
        slider = slider,
        icon_provider = function()
            return getStateIcon()
        end,
        callback = function()
            local toggled = pcall(function()
                powerd:toggleFrontlight()
                powerd:updateResumeFrontlightState()
            end)
            if toggled then
                slider:syncFromPower(true)
            end
        end,
        hold_callback = function()
            local message = slider.enabled and _("Turn frontlight off") or _("Turn frontlight on")
            UIManager:show(InfoMessage:new({ text = message }))
        end,
    }
    if icon then
        config.icon = icon
    else
        config.text = slider.enabled and _("On") or _("Off")
    end
    return FrontlightToggleButton:new(config)
end

function ShortcutDock:makeFrontlightSlider(dock_height, dialog)
    local column_height = self:getFrontlightSliderHeight(dock_height)
    local slider_height = math_max(
        1,
        column_height - SIDE_BUTTON_OUTER_HEIGHT - SIDE_BUTTON_GAP
    )
    local slider = FrontlightSlider:new({
        width = FRONTLIGHT_SLIDER_WIDTH,
        height = slider_height,
        powerd = Device:getPowerDevice(),
        show_parent = dialog,
    })
    local toggle_button = self:makeFrontlightToggleButton(
        FRONTLIGHT_SLIDER_WIDTH,
        dialog,
        slider
    )
    slider.state_changed_callback = function()
        UIManager:setDirty(dialog, "ui")
    end
    local column = VerticalGroup:new({
        slider,
        VerticalSpan:new({ width = SIDE_BUTTON_GAP }),
        toggle_button,
    })
    column.toggle_button = toggle_button
    return column
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

function ShortcutDock:onShowShortcutDock(gesture)
    self:showDock(1, self:getGestureSide(gesture))
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
    local max_rows = self:getMaxPageRows()
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
            -- The fixed context button belongs only to the first page, which
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
            self:showDock(target_page, self.current_dock_side)
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
    local current_side = self.current_dock_side or self:getSide()
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
                self:showDock(page, target_side)
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

function ShortcutDock:showDock(page, side)
    -- Another UI instance (reader or file browser) may have changed these
    -- shared preferences since this instance was created.
    self.action_contexts = self:loadActionContexts()
    self.auto_visibility = self:loadAutomaticVisibility()
    side = side == "left" and "left" or side == "right" and "right" or self:getSide()
    self.current_dock_side = side
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
    if self.current_page == 1 and self:showContextButton() then
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
    local frontlight_slider_factory
    if self:showFrontlightSlider() then
        frontlight_slider_factory = function(dock_height, parent)
            return self:makeFrontlightSlider(dock_height, parent)
        end
    end
    dialog = FloatingControlButtonDialog:new({
        buttons = rows,
        width = BUTTON_WIDTH + 2 * Size.border.window + 2 * Size.padding.button,
        shrink_unneeded_width = true,
        shrink_min_width = BUTTON_WIDTH,
        dismissable = true,
        side_button_factory = side_button_factory,
        frontlight_slider_factory = frontlight_slider_factory,
        dock_side = side,
        anchor = function()
            local dialog_size = dialog:getContentSize()
            local left
            if side == "left" then
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
    local light_icon_details = _("Frontlight toggle")
        .. "\n\n" .. _("Frontlight on") .. ": light_on.svg / light_on.png"
        .. "\n" .. _("Frontlight off") .. ": light_off.svg / light_off.png"
    local menu = {
        {
            text = _("Frontlight toggle") .. ": light_on.svg / light_off.svg",
            help_text = _("Uses a different icon for the active and inactive frontlight states."),
            callback = function()
                UIManager:show(InfoMessage:new({ text = light_icon_details }))
            end,
        },
    }
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
                text = _("Behavior"),
                sub_item_table = {
                    {
                        text = _("Dock side"),
                        sub_item_table = {
                            {
                                text = _("Left"),
                                checked_func = function()
                                    return self:getSideMode() == SIDE_MODE_FIXED and self:getSide() == "left"
                                end,
                                callback = function(touchmenu_instance)
                                    self:setSide("left")
                                    self:setSideMode(SIDE_MODE_FIXED)
                                    if touchmenu_instance and touchmenu_instance.updateItems then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                                keep_menu_open = true,
                                radio = true,
                            },
                            {
                                text = _("Right"),
                                checked_func = function()
                                    return self:getSideMode() == SIDE_MODE_FIXED and self:getSide() == "right"
                                end,
                                callback = function(touchmenu_instance)
                                    self:setSide("right")
                                    self:setSideMode(SIDE_MODE_FIXED)
                                    if touchmenu_instance and touchmenu_instance.updateItems then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                                keep_menu_open = true,
                                radio = true,
                            },
                            {
                                text = _("Follow gesture side"),
                                help_text = _("Places the dock on the half of the screen where the gesture started. Uses the fixed side when no gesture position is available."),
                                checked_func = function()
                                    return self:getSideMode() == SIDE_MODE_GESTURE
                                end,
                                callback = function(touchmenu_instance)
                                    self:setSideMode(SIDE_MODE_GESTURE)
                                    if touchmenu_instance and touchmenu_instance.updateItems then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                                keep_menu_open = true,
                                radio = true,
                            },
                        },
                    },
                    {
                        text = _("Show frontlight slider"),
                        help_text = _("Shows a vertical brightness slider beside the dock on devices with a frontlight."),
                        enabled_func = function()
                            return Device:hasFrontlight()
                        end,
                        checked_func = function()
                            return self:showFrontlightSlider()
                        end,
                        callback = function(touchmenu_instance)
                            self:setShowFrontlightSlider(not self:showFrontlightSlider())
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
