--[[
Page Anchor plugin for KOReader.

Shows floating back/forward buttons after a jump (footnote, internal link,
table of contents, etc.) so you can review another part of the book without
losing your reading position, then return to it with a tap.
]]

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local PLUGIN_VERSION = "v1.15.4"

local function pluginDir()
	local source = debug.getinfo(1, "S").source or ""
	local path = source:match("^@(.*/)") or source:match("^(.*/)")
	return path or "plugins/pageanchor.koplugin/"
end

local PLUGIN_DIR = pluginDir()

-- Modules are loaded by path rather than required, so their generic names
-- (history, settings, menu...) can't clash with other plugins' modules in
-- KOReader's shared package.loaded. Each one gets the constants and the
-- shared helpers as arguments.
local function loadModule(name, ...)
	return assert(loadfile(PLUGIN_DIR .. "modules/" .. name .. ".lua"))(...)
end

local C = loadModule("constants")
C.PLUGIN_VERSION = PLUGIN_VERSION
C.ICONS_DIR = PLUGIN_DIR .. "icons/"

-- Helpers and widgets used by more than one module, in loading order: a
-- module may use what the ones before it shared.
local lib = { History = loadModule("history") }
for _, name in ipairs({
	"helpers", -- notifications, anchor icon for a state, metric scaling
	"overlay", -- the pill and the minimized tab
	"hint_toast", -- hold hints and the undo notice
}) do
	for key, value in pairs(loadModule(name, C, lib)) do
		assert(lib[key] == nil, "pageanchor: " .. key .. " is shared twice")
		lib[key] = value
	end
end

local PageAnchor = WidgetContainer:extend({
	name = "pageanchor",
	is_doc_only = true,
})

-- Each of these modules adds its methods to PageAnchor. This file keeps the
-- plugin lifecycle and the reader events.
for _, name in ipairs({
	"settings", -- saved settings and button metrics
	"icons", -- the IconWidget patch for the plugin's own SVGs
	"controls", -- what the floating control shows, hiding/showing, repaint
	"hints", -- hold hints and the undo notice
	"trail", -- places visited during a trip
	"zones", -- view paint hook and touch zones
	"jumps", -- jump detection and going to a location
	"tracking", -- anchors, back/forward, pinned anchors, clearing
	"undo", -- discarding with undo
	"actions", -- gesture actions
	"menu", -- the Page Anchor menu
}) do
	for method, fn in pairs(loadModule(name, C, lib)) do
		assert(rawget(PageAnchor, method) == nil, "pageanchor: " .. method .. " is defined twice")
		PageAnchor[method] = fn
	end
end

function PageAnchor:init()
	self.overlay = lib.FloatingHistoryOverlay:new({ owner = self })
	self.reference_page = nil
	self.reference_location = nil
	self.anchor = nil
	self.forward_target = nil
	self.return_baseline_location = nil
	self.controls_hidden = false
	self.pending_jump_origin = nil
	self.auto_dismiss_fn = nil
	self.hidden_expiry_fn = nil
	self.pinned_location = nil
	self.last_discarded = nil
	self.discard_location = nil
	self.trail = {}
	self.button_specs = nil
	self.button_specs_computed = false
	self.hint_widget = nil
	self.hint_dismiss_fn = nil
	self._installed = false

	self:patchIconWidget()
	self:onDispatcherRegisterActions()

	if self.ui and self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end
	self.ui:registerPostInitCallback(function()
		self:installOverlay()
	end)
end

function PageAnchor:onReaderReady()
	-- After every module's own ReaderReady handling, so zones registered
	-- there are known too (see registerOverlayZones).
	UIManager:nextTick(function()
		if self._installed then
			self:registerOverlayZones()
		end
	end)
	self:trackPage(self.ui:getCurrentPage())
end

function PageAnchor:onPageUpdate(page)
	self:trackPage(page)
end

function PageAnchor:onPosUpdate(_pos, page)
	if page then
		self:trackPage(page)
	end
end

-- Sent after a font/margin/orientation change re-paginated the book (after
-- the PageUpdate for the new layout). Locations are unaffected, but page
-- numbers and chapter positions in the hint text are not.
function PageAnchor:onDocumentRerendered()
	-- Page numbers changed: the next update must be evaluated in full.
	self.last_tracked_page = nil
	self:getReferencePage()
	self:invalidateButtonSpecs()
	self:refresh()
end

-- Everything the plugin hooked or scheduled, undone.
function PageAnchor:teardown()
	self:cancelAutoDismiss()
	self:cancelHiddenExpiry()
	self:uninstallOverlay()
	self:unpatchIconWidget()
end

function PageAnchor:onCloseDocument()
	self:teardown()
end

-- Disabled from plugin management while a book is open: also wipe the
-- control off the page, from where it was painted.
function PageAnchor:stopPlugin()
	local before = self.overlay.pill_dimen
	self:teardown()
	self:refresh(nil, before)
	return true
end

return PageAnchor
