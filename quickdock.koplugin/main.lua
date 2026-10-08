local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local _ = require("quickdock_l10n")

local PLUGIN_VERSION = "v0.26.1"

local function pluginDir()
    local source = debug.getinfo(1, "S").source or ""
    local path = source:match("^@(.*/)") or source:match("^(.*/)")
    return path or "plugins/quickdock.koplugin/"
end

local PLUGIN_DIR = pluginDir()

-- Modules are loaded by path rather than required, so their generic names
-- (widgets, settings, ...) cannot clash with other plugins' modules.
local function loadModule(name)
    return dofile(PLUGIN_DIR .. "modules/" .. name .. ".lua")
end

local C = loadModule("constants")
C.PLUGIN_VERSION = PLUGIN_VERSION
local Prefs = loadModule("preferences")(C)
local Layout = loadModule("dock_layout")(C)
local DockWidgets = loadModule("widgets")(C)
local InfoPanel = loadModule("info_panel")(loadModule)

local QuickDock = WidgetContainer:extend({
    name = "quickdock",
})

-- Each of these modules adds its methods to QuickDock. This file keeps the
-- plugin lifecycle and the dock orchestration (showing, paging, closing).
local lib = {
    Prefs = Prefs,
    Layout = Layout,
    widgets = DockWidgets,
    ArcDock = loadModule("arc_dock")(DockWidgets),
    InfoPanel = InfoPanel,
}
for _index, name in ipairs({
    "actions",        -- configured actions and their visibility
    "context",        -- reader / file browser / Bookshelf context
    "icons",          -- icon lookup
    "controls",       -- buttons and lighting controls
    "status_panel",   -- status block and button help
    "inline_actions", -- Wi-Fi and night mode without closing the dock
    "column_layout",  -- the column dock
    "arc_layout",     -- the arc dock
    "menu",           -- settings menu
}) do
    loadModule(name)(QuickDock, C, lib)
end

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
    self.action_contexts = Prefs.readActionContexts()
    -- Set by Dispatcher's actions menu when the user changes the actions,
    -- so they are saved on the next settings flush.
    self.updated = false
    self.dialog = nil
    self.info_panel_widget = nil
    self.info_panel_data = nil
    self.current_info_panel_kind = nil
    self.info_panel_cover_cache = nil
    self.recent_cover_cache = nil
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
    Dispatcher:registerAction(C.ACTION_SEARCH, {
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
    InfoPanel.clearRecentCoverCache(self)
    self:savePendingActions()
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
    else
        self:cancelDockTimers()
    end
end

function QuickDock:onFlushSettings()
    self:savePendingActions()
end

function QuickDock:onShowQuickDock(gesture)
    self:showDock(1, self:getGestureSide(gesture))
    return true
end

function QuickDock:getGestureSide(gesture)
    if Prefs.getSideMode() ~= C.SIDE_MODE_GESTURE or type(gesture) ~= "table" then
        return nil
    end

    local pos = gesture.pos or gesture.start_pos or gesture.end_pos
    local x = pos and tonumber(pos.x)
    if not x then
        return nil
    end
    return x < Device.screen:getWidth() / 2 and "left" or "right"
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

-- Dock geometry

function QuickDock:getDockMetrics()
    return Layout.metrics(C.DOCK_SIZE_FACTORS[Prefs.getDockSize()])
end

-- Splits action_count actions into pages of at most max_rows buttons (by
-- default, as many as the column dock fits).
function QuickDock:getPages(action_count, metrics, max_rows)
    return Layout.paginate(
        action_count,
        max_rows or self:getMaxPageRows(metrics),
        Prefs.showContextButton() and 1 or 0
    )
end

-- Information panel

function QuickDock:getInfoPanelMode(kind)
    return C.INFO_PANEL_MODES_BY_KIND[kind]
end

-- The panel kind to show: the current one while it stays enabled.
function QuickDock:getInfoPanelKind()
    if Prefs.isInfoPanelKindEnabled(self.current_info_panel_kind) then
        return self.current_info_panel_kind
    end
    return Prefs.getEnabledInfoPanelKinds()[1]
end

function QuickDock:getNextInfoPanelKind()
    local kinds = Prefs.getEnabledInfoPanelKinds()
    for index, kind in ipairs(kinds) do
        if kind == self.current_info_panel_kind then
            return kinds[index % #kinds + 1]
        end
    end
    return kinds[1]
end

-- Disabling a mode frees the caches only it used.
function QuickDock:setInfoPanelKindEnabled(kind, enabled)
    Prefs.setInfoPanelKindEnabled(kind, enabled)
    if not enabled then
        InfoPanel.release(kind, self)
    end
end

function QuickDock:setShowInfoPanelCover(enabled)
    Prefs.setShowInfoPanelCover(enabled)
    if not enabled then
        InfoPanel.clearCoverCache(self)
    end
end

-- Beside the column dock, the panel takes the opposite screen edge.
function QuickDock:getInfoPanelSide()
    return self.current_dock_side == "left" and "right" or "left"
end

function QuickDock:collectInfoPanelData(kind, metrics)
    -- The arc dock shows a wide panel along the top edge, with a smaller
    -- cover beside the text instead of above it.
    local horizontal = Prefs.isArcLayout()
    local data = InfoPanel.collect(kind, self, {
        metrics = metrics,
        screen_margin = C.DOCK_MARGIN,
        include_cover = Prefs.showInfoPanelCover(),
        horizontal = horizontal,
        recent_count = Prefs.getRecentDocumentsCount(),
    })
    data.horizontal = horizontal
    return data
end

-- Where the information panel and the status block go: along the top of
-- the screen (with the arc dock), or on the edge opposite the column dock.
function QuickDock:getPanelView(metrics, top)
    local view = {
        metrics = metrics or self:getDockMetrics(),
        screen_margin = C.DOCK_MARGIN,
        text_alignment = Prefs.getInfoPanelTextAlignment(),
    }
    if top then
        view.placement = "top"
    else
        view.panel_side = self:getInfoPanelSide()
        -- Always the side opposite the dock, so it can collide with a sibling
        -- overlay sitting there even when the dock itself is on the other side.
        view.extra_bottom_margin = self:getSiblingOverlayClearance(view.panel_side)
    end
    return view
end

-- The placement follows the data, which was collected for it.
function QuickDock:createInfoPanelOverlay(data, metrics)
    return InfoPanel.createOverlay(self, data, self:getPanelView(metrics, data.horizontal))
end

function QuickDock:replaceInfoPanel(kind, metrics, data)
    metrics = metrics or self:getDockMetrics()
    local previous_widget = self.info_panel_widget
    data = data or self:collectInfoPanelData(kind, metrics)
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
        or not Prefs.isInfoPanelKindEnabled(kind)
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

-- Taps outside the dock reach the information panel first: the recent
-- documents panel opens a document or turns its page, and keeps the dock
-- open for any other tap on it.
function QuickDock:handleInfoPanelTap(pos)
    local widget = self.info_panel_widget
    if not widget or type(widget.handleTap) ~= "function" then
        return false
    end
    return widget:handleTap(pos) == true
end

function QuickDock:setRecentDocumentsPage(page)
    local data = self.info_panel_data
    if not self.dialog or not data or data.kind ~= "recent" or data.page == page then
        return
    end
    data.page = page
    self:closeStatusPanel()
    self:replaceInfoPanel("recent", nil, data)
end

function QuickDock:openRecentDocument(file)
    if not file then
        return
    end
    if lfs.attributes(file, "mode") ~= "file" then
        UIManager:show(InfoMessage:new({ text = _("This document is no longer available.") }))
        return
    end
    self:closeDock()
    local ui = self.ui
    UIManager:scheduleIn(C.DISPATCH_DELAY, function()
        -- The same path as KOReader's History: switch documents inside the
        -- reader, or open the reader from the file browser.
        local ok, err = pcall(function()
            require("apps/filemanager/filemanagerutil").openFile(ui, file, nil, true)
        end)
        if not ok then
            logger.warn("QuickDock: could not open recent document:", err)
            require("apps/reader/readerui"):showReader(file)
        end
    end)
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

    -- NetworkMgr broadcasts its events before updating pending_connection,
    -- so the state that triggered this refresh takes precedence while the
    -- panel data is collected.
    self.network_state_hint = network_state
    local ok, err = pcall(self.replaceInfoPanel, self, "network")
    self.network_state_hint = nil
    if not ok then
        error(err, 0)
    end
    self.network_info_refresh_state = network_state
    return true
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

-- Reuses the panel data kept while paging or switching sides, unless the
-- panel kind or the dock shape (which sizes the cover) changed meanwhile.
function QuickDock:resolveInfoPanelData(info_panel_data, metrics)
    local info_panel_kind = self:getInfoPanelKind()
    self.current_info_panel_kind = info_panel_kind
    if not info_panel_kind then
        InfoPanel.clearCoverCache(self)
        return nil
    end
    if
        not info_panel_data
        or info_panel_data.kind ~= info_panel_kind
        or info_panel_data.horizontal ~= Prefs.isArcLayout()
    then
        info_panel_data = self:collectInfoPanelData(info_panel_kind, metrics)
    end
    return info_panel_data
end

-- Showing and closing the dock

-- The screen area a widget covers, or nil when it has not been laid out.
local function getWidgetRegion(widget)
    local dimen = widget.dimen or (widget.movable and widget.movable.dimen)
    if dimen and dimen.x and dimen.y and dimen.w and dimen.h then
        return Geom:new({ x = dimen.x, y = dimen.y, w = dimen.w, h = dimen.h })
    end
end

-- rebuilding: the dock is about to be shown again (paging, switching sides),
-- so a pending Wi-Fi check still has a dock to report to.
function QuickDock:closeDock(rebuilding)
    local dialog = self.dialog
    self:cancelDockTimers(rebuilding)
    if not Prefs.closeDockTogether() then
        self.dialog = nil
        self:closeStatusPanel()
        self:closeInfoPanel()
        if dialog then
            UIManager:close(dialog)
        end
        return
    end

    local widgets = { self.status_panel_widget, self.info_panel_widget, dialog }
    self.dialog = nil
    self.info_panel_widget = nil
    self.info_panel_data = nil
    self.network_info_refresh_state = nil
    self.status_panel_widget = nil
    self.status_panel_text = nil

    local update_region
    for index = 1, 3 do
        local widget = widgets[index]
        if widget then
            local region = getWidgetRegion(widget)
            if region then
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

function QuickDock:attachDockCallbacks(dialog)
    dialog.outside_tap_callback = function(pos)
        return self.dialog == dialog and self:handleInfoPanelTap(pos)
    end
end

function QuickDock:presentDock(dialog, info_panel_data, metrics)
    self.dialog = dialog
    self.info_panel_data = info_panel_data
    self:attachDockCallbacks(dialog)
    if info_panel_data then
        self.info_panel_widget = self:createInfoPanelOverlay(info_panel_data, metrics)
        UIManager:show(self.info_panel_widget, "[ui]")
    end
    UIManager:show(dialog, "[ui]")
end

-- Opens the dock (closing any open one) on the given page and side, the
-- saved side by default. info_panel_data keeps the panel's content when the
-- dock is rebuilt in place.
function QuickDock:showDock(page, side, info_panel_data)
    self:reloadSharedSettings()
    side = side == "left" and "left" or side == "right" and "right" or Prefs.getSide()
    self.current_dock_side = side
    local metrics = self:getDockMetrics()
    local actions = self:getDockActions()
    if not actions then
        UIManager:show(InfoMessage:new({ text = _("No Quick Dock actions are configured.") }))
        return
    end

    self:closeDock(true)
    -- Resolved before the dock is built: the panel switch button shows the
    -- panel kind chosen here.
    info_panel_data = self:resolveInfoPanelData(info_panel_data, metrics)
    local dialog
    if Prefs.isArcLayout() then
        dialog = self:buildArcDock(actions, metrics, page, side)
    else
        dialog = self:buildColumnDialog(actions, metrics, page, side)
    end
    self:presentDock(dialog, info_panel_data, metrics)
end

return QuickDock
