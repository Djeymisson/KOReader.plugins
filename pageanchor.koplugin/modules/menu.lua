-- The Page Anchor menu.

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("pageanchor_l10n")
local T = require("ffi/util").template

local C = ...
local lib = select(2, ...)
local notify = lib.notify

local PageAnchor = {}

-- Builds a set of mutually exclusive radio sub-items from a list of
-- {value, label} options, shared by the two option lists below. An optional
-- caption is inserted first as a plain, non-interactive line (no callback,
-- disabled so it reads as a label rather than a dead button) -- context
-- shown right above the options themselves, without needing help_text.
local function buildValueRadioItems(options, get_value, set_value, caption)
	local items = {}
	if caption then
		items[#items + 1] = { text = caption, enabled = false }
	end
	-- Indexed (not "for _, option"): "_" would shadow the gettext function
	-- used as `_(option.label)` below for the rest of this loop body.
	for i = 1, #options do
		local option = options[i]
		items[#items + 1] = {
			text = _(option.label),
			radio = true,
			checked_func = function()
				return get_value() == option.value
			end,
			callback = function()
				set_value(option.value)
			end,
		}
	end
	return items
end

function PageAnchor:addToMainMenu(menu_items)
	menu_items.pageanchor = {
		text = _("Page Anchor"),
		sorting_hint = "navi",
		sub_item_table = {
			{
				-- Static text (the checkmark alone shows current state) --
				-- reuses KOReader's own "Enable" string (already translated
				-- into every language it supports) instead of a
				-- plugin-specific phrase, so only "Page Anchor" itself (a
				-- proper noun) needs no translation at all.
				text = _("Enable") .. " " .. _("Page Anchor"),
				help_text = _("Turns Page Anchor off entirely, without losing the navigation history it uses."),
				checked_func = function()
					return self:isEnabled()
				end,
				callback = function()
					self:setEnabled(not self:isEnabled())
				end,
			},
			{
				-- Three predefined scales, same idea as Quick Dock's own
				-- dock-size setting -- affects both segments' width and
				-- height together, so the pill grows as one shape rather
				-- than the icon and its box drifting apart.
				text = _("Button size"),
				help_text = _("Scales the floating buttons up for an easier target, without changing their shape."),
				sub_item_table = buildValueRadioItems(
					C.BUTTON_SIZE_OPTIONS,
					function() return self:getButtonSize() end,
					function(value) self:setButtonSize(value) end
				),
			},
			{
				text = _("Button position"),
				help_text = _("Where on the screen the floating buttons sit: at the bottom (the default), in the middle, or at the top. They always stay on the side that leads to the destination."),
				sub_item_table = buildValueRadioItems(
					C.VERTICAL_POSITION_OPTIONS,
					function() return self:getVerticalPosition() end,
					function(value) self:setVerticalPosition(value) end
				),
			},
			{
				text = _("Show destination on button"),
				help_text = _("Writes where the arrow leads next to it, so you don't have to hold the button to find out: the destination page, or how many pages away it is."),
				sub_item_table = buildValueRadioItems(
					C.INLINE_LABEL_OPTIONS,
					function() return self:getInlineLabelMode() end,
					function(value) self:setInlineLabelMode(value) end
				),
			},
			{
				-- One flat list instead of a "Format" screen plus a
				-- separately nested, sometimes-disabled "Relative to"
				-- screen: each option already names both what it shows and
				-- what it's measured against, so there's nothing left to
				-- combine in your head across two menus.
				text = _("Position hint"),
				help_text = _("Chooses what the text shown when you hold down a navigation button says."),
				sub_item_table = buildValueRadioItems(
					C.DESTINATION_FORMAT_OPTIONS,
					function() return self:getDestinationFormat() end,
					function(value) self:setDestinationFormat(value) end
				),
			},
			{
				-- Groups both ways the floating buttons can disappear on
				-- their own (a shared parent screen instead of two
				-- unrelated-looking top-level items, per touchmenu.lua's
				-- own nesting) -- neither child repeats "Auto-dismiss" in
				-- its own text since the parent screen's title already says
				-- it.
				text = _("Auto-dismiss"),
				help_text = _("Controls when the floating buttons disappear on their own, both from inactivity and after you've returned to the anchor."),
				sub_item_table = {
					{
						text = _("Timeout"),
						help_text = _("Hides the floating buttons after this much time without navigation activity. The anchor is kept: tap the anchor tab (or use the show/hide gesture action) to bring them back."),
						sub_item_table = buildValueRadioItems(
							C.AUTO_DISMISS_OPTIONS,
							function() return self:getAutoDismissSeconds() end,
							function(value) self:setAutoDismissSeconds(value) end
						),
					},
					{
						text = _("When hiding"),
						help_text = _("What the timeout (or the show/hide gesture action) leaves on screen: a small anchor tab that brings the buttons back with one tap, or nothing."),
						sub_item_table = buildValueRadioItems(
							C.HIDE_MODE_OPTIONS,
							function() return self:getHideMode() end,
							function(value) self:setHideMode(value) end
						),
					},
					{
						text = _("Discard when hidden for"),
						help_text = _("If the buttons stay hidden (or parked as a tab) this long, the anchor is discarded and the current page becomes your reading position, as if you had tapped the anchor button. Never keeps them waiting until you dismiss them yourself."),
						sub_item_table = buildValueRadioItems(
							C.HIDDEN_EXPIRY_OPTIONS,
							function() return self:getHiddenExpirySeconds() end,
							function(value) self:setHiddenExpirySeconds(value) end
						),
					},
					{
						text = _("After returning to anchor"),
						help_text = _("Auto-dismisses the floating button once you've read this many pages past the anchor. Off keeps it until you dismiss it yourself."),
						sub_item_table = buildValueRadioItems(
							C.FORWARD_DISMISS_PAGE_OPTIONS,
							function() return self:getForwardDismissPages() end,
							function(value) self:setForwardDismissPages(value) end,
							_("Auto-dismiss after:")
						),
					},
				},
			},
			{
				text = _("Re-reading tolerance"),
				help_text = _("How many page turns back still count as re-reading instead of a jump, for tools that move without telling KOReader. Standard navigation (table of contents, go to page, links...) always offers the way back."),
				sub_item_table = buildValueRadioItems(
					C.REREAD_TURNS_OPTIONS,
					function() return self:getRereadTurns() end,
					function(value) self:setRereadTurns(value) end
				),
			},
			{
				text = _("Pin anchor here"),
				help_text = _("Marks the current position as the anchor before you go exploring. A pinned anchor stays, through any number of trips away and back, until you discard it."),
				callback = function()
					if self:pinHere() then
						notify(_("Anchor pinned here"))
					end
				end,
			},
			{
				-- Only enabled while the inactivity timeout has hidden the
				-- buttons and there is still somewhere to go.
				text = _("Show floating buttons"),
				help_text = _("Brings back floating buttons hidden by the inactivity timeout, with the anchor and the way back still in place."),
				enabled_func = function()
					return self:areControlsHidden()
				end,
				callback = function()
					self:showControls()
				end,
			},
			{
				-- Named after what it actually drops -- Page Anchor's own
				-- targets -- so it isn't mistaken for clearing KOReader's
				-- native location history, which it never touches.
				text = _("Discard anchor and return point"),
				help_text = _("Forgets the anchor and the return point and keeps reading from the current position. KOReader's own location history is not affected."),
				enabled_func = function()
					return self:hasTargets()
				end,
				callback = function()
					UIManager:show(ConfirmBox:new({
						text = _("Discard anchor and return point?"),
						ok_text = _("Discard"),
						ok_callback = function()
							self:clearHistory()
						end,
					}))
				end,
			},
			{
				text = _("Restore discarded anchor"),
				help_text = _("Brings back the anchor and return point you last discarded, as long as no new anchor has been set since."),
				separator = true,
				enabled_func = function()
					return self:canRestoreDiscarded()
				end,
				callback = function()
					self:restoreDiscarded()
				end,
			},
			{
				-- Reuses KOReader's own "Version: %1" string (see
				-- common_info_menu_table.lua) instead of a plugin-specific
				-- one, so this line is already translated everywhere
				-- KOReader is.
				text_func = function()
					return T(_("Version: %1"), C.PLUGIN_VERSION)
				end,
				callback = function()
					UIManager:show(InfoMessage:new({
						text = _("Page Anchor") .. "\n" .. T(_("Version: %1"), C.PLUGIN_VERSION),
					}))
				end,
			},
		},
	}
end

return PageAnchor
