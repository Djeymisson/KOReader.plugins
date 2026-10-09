local WidgetContainer = require("ui/widget/container/widgetcontainer")

local PLUGIN_VERSION = "v1.15.6"

local function pluginDir()
    local source = debug.getinfo(1, "S").source or ""
    local path = source:match("^@(.*/)") or source:match("^(.*/)")
    return path or "plugins/selectiontoolbar.koplugin/"
end

local PLUGIN_DIR = pluginDir()

-- Modules are loaded by path rather than required, so their generic names (settings,
-- menu, ...) cannot clash with other plugins' modules. Each one gets the constants and
-- the shared helpers as arguments.
local function loadModule(name, ...)
    return assert(loadfile(PLUGIN_DIR .. "modules/" .. name .. ".lua"))(...)
end

local C = loadModule("constants")
C.PLUGIN_VERSION = PLUGIN_VERSION

-- Helpers and widgets used by more than one module, in loading order: a module may use
-- what the ones before it shared.
local lib = { pluginDir = pluginDir }
for _, name in ipairs({
    "helpers", -- multiple-choice settings, live selection, screen refresh
    "metrics", -- button and handle sizes
    "shadow", -- toolbar shadow and ShadowedPopup
    "toolbar_dialog", -- ShadowedButtonDialog
    "handle_shapes", -- handle shapes, for the marks and their preview
}) do
    for key, value in pairs(loadModule(name, C, lib)) do
        assert(lib[key] == nil, "selectiontoolbar: " .. key .. " is shared twice")
        lib[key] = value
    end
end

local SelectionToolbar = WidgetContainer:extend({
    name = "selectiontoolbar",
    is_doc_only = true,
})

-- Each of these modules adds its methods to SelectionToolbar. This file keeps the
-- plugin lifecycle.
for _, name in ipairs({
    "settings", -- saved settings, presets and resets
    "icons", -- icon lookup and the IconWidget patch
    "toolbar", -- the toolbar, its buttons and the ReaderHighlight patch
    "placement", -- where the toolbar goes on screen
    "marks", -- selection handles and line marker
    "handle_drag", -- dragging the handles
    "preview", -- live preview in the settings menu
    "marks_preview", -- the selection marks in that preview
    "menu", -- settings menu
}) do
    for method, fn in pairs(loadModule(name, C, lib)) do
        assert(rawget(SelectionToolbar, method) == nil, "selectiontoolbar: " .. method .. " is defined twice")
        SelectionToolbar[method] = fn
    end
end

function SelectionToolbar:init()
    -- The plugin is developed for EPUB (crengine) documents only. In PDF, DjVu and other
    -- paged documents it stays inactive and KOReader's native selection menu is used.
    if not (self.ui and self.ui.rolling) then
        return
    end

    self.plugin_path = PLUGIN_DIR
    self.icons_path = self.plugin_path .. "icons/"
    self.icon_cache = {}
    self.qr_message_checked = false
    self.qr_message_class = nil

    self:patchIconWidget()
    if self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    if self.ui.highlight then
        self:patchHighlight(self.ui.highlight)
    end
    if self.ui.view and self.ui.view.registerViewModule then
        local plugin = self
        self.ui.view:registerViewModule(C.MARKS_VIEW_MODULE, {
            paintTo = function(_, bb, x, y)
                plugin:paintSelectionMarks(bb, x, y)
            end,
        })
    end
end

function SelectionToolbar:onClose()
    if self.ui and self.ui.highlight and self.ui.highlight._selectiontoolbar_original_onShowHighlightMenu then
        self.ui.highlight.onShowHighlightMenu = self.ui.highlight._selectiontoolbar_original_onShowHighlightMenu
        self.ui.highlight._selectiontoolbar_original_onShowHighlightMenu = nil
        self.ui.highlight._selectiontoolbar_patched = nil
    end
    if self.ui and self.ui.view and self.ui.view.view_modules then
        self.ui.view.view_modules[C.MARKS_VIEW_MODULE] = nil
    end
    self.marks_dialog = nil
    self.marks_highlight = nil
    self.marks = nil
    self.drag = nil

    if self.preview then
        self:closePreview(self.preview)
    end
    self:unpatchIconWidget()
    lib.clearToolbarShadowCache()
end

return SelectionToolbar
