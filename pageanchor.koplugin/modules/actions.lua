-- Gesture/hotkey actions (Dispatcher) and what each one does.

local Dispatcher = require("dispatcher")
local _ = require("pageanchor_l10n")

local C = ...
local lib = select(2, ...)
local notify = lib.notify

local PageAnchor = {}

-- Gesture/hotkey actions (and, through them, Quick Dock buttons): a way to
-- bring hidden buttons back, or to act on the anchor directly, without
-- opening the Page Anchor menu. Reader-only, like the plugin itself.
function PageAnchor:onDispatcherRegisterActions()
	Dispatcher:registerAction("pageanchor_toggle_buttons", {
		category = "none",
		event = "PageAnchorToggleButtons",
		title = _("Page Anchor: show/hide buttons"),
		reader = true,
	})
	Dispatcher:registerAction("pageanchor_switch", {
		category = "none",
		event = "PageAnchorSwitch",
		title = _("Page Anchor: go to anchor / return point"),
		reader = true,
	})
	Dispatcher:registerAction("pageanchor_trail", {
		category = "none",
		event = "PageAnchorShowTrail",
		title = _("Page Anchor: show trail"),
		reader = true,
	})
	Dispatcher:registerAction("pageanchor_pin", {
		category = "none",
		event = "PageAnchorPin",
		title = _("Page Anchor: pin anchor here"),
		reader = true,
	})
	Dispatcher:registerAction("pageanchor_discard", {
		category = "none",
		event = "PageAnchorDiscard",
		title = _("Page Anchor: discard anchor"),
		reader = true,
	})
	Dispatcher:registerAction("pageanchor_undo", {
		category = "none",
		event = "PageAnchorUndo",
		title = _("Page Anchor: restore discarded anchor"),
		reader = true,
		separator = true,
	})
end

function PageAnchor:onPageAnchorToggleButtons()
	if not self:hasTargets() then
		notify(_("No anchor to show"))
	elseif self.controls_hidden then
		self:showControls()
	else
		self:hideControls()
	end
	return true
end

-- Back to the anchor while away from it; back out to the return point once
-- there -- the same thing the arrow segment does, from any gesture.
function PageAnchor:onPageAnchorSwitch()
	if self.anchor then
		self:activate(C.ACTION_BACK)
	elseif self.forward_target then
		self:activate(C.ACTION_FORWARD)
	else
		notify(_("No anchor to show"))
	end
	return true
end

function PageAnchor:onPageAnchorDiscard()
	if self:hasTargets() then
		self:discardWithUndo()
	else
		notify(_("No anchor to show"))
	end
	return true
end

function PageAnchor:onPageAnchorShowTrail()
	if not self:showTrailDialog() then
		notify(_("No other places visited yet"))
	end
	return true
end

function PageAnchor:onPageAnchorPin()
	if self:pinHere() then
		notify(_("Anchor pinned here"))
	end
	return true
end

function PageAnchor:onPageAnchorUndo()
	if not self:restoreDiscarded() then
		notify(_("Nothing to restore"))
	end
	return true
end

return PageAnchor
