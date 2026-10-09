-- The Page Anchor menu: the on/off switch, what to do with the current
-- anchor, three groups of settings (buttons, auto-hide, navigation), then
-- restoring the defaults and About -- the same layout as the other plugins
-- in this repository.

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("pageanchor_l10n")
local T = require("ffi/util").template

local C = ...
local lib = select(2, ...)
local notify = lib.notify

local PageAnchor = {}

local function findOption(options, value)
	for i = 1, #options do
		if options[i].value == value then
			return options[i]
		end
	end
end

-- Radio items for a {value, label} option list.
local function optionItems(options, get_value, set_value)
	local items = {}
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

-- A setting with a list of options: its title shows the current choice
-- ("Size: Small"), and it opens the options.
local function optionSetting(label, help_text, options, get_value, set_value)
	return {
		text_func = function()
			local option = findOption(options, get_value())
			return T(_("%1: %2"), label, option and _(option.label) or "")
		end,
		help_text = help_text,
		sub_item_table = optionItems(options, get_value, set_value),
	}
end

-- One word for the current anchor, for the "Current anchor" group title.
function PageAnchor:getAnchorStatusText()
	if not self:hasTargets() then
		return _("None")
	elseif self:areControlsHidden() then
		return _("Hidden")
	elseif self.pinned_location then
		return _("Pinned")
	end
	return _("Active")
end

function PageAnchor:addToMainMenu(menu_items)
	local function isEnabled()
		return self:isEnabled()
	end

	local anchor_items = {
		{
			text = _("Pin anchor here"),
			help_text = _("Marks this page as the anchor before you go exploring. A pinned anchor stays through any number of trips away and back, until you discard it."),
			callback = function()
				if self:pinHere() then
					notify(_("Anchor pinned here"))
				end
			end,
		},
		{
			text = _("Show floating buttons"),
			help_text = _("Brings back the buttons after auto-hide put them away. The anchor and the way back are still there."),
			enabled_func = function()
				return self:areControlsHidden()
			end,
			callback = function()
				self:showControls()
			end,
		},
		{
			-- Named after what it drops -- Page Anchor's own targets -- so it
			-- isn't mistaken for clearing KOReader's location history,
			-- which it never touches.
			text = _("Discard anchor and return point"),
			help_text = _("Forgets the anchor and the return point and keeps reading from this page. KOReader's own location history is not affected."),
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
			help_text = _("Brings back the anchor and return point you discarded last, as long as no new anchor has been set since."),
			enabled_func = function()
				return self:canRestoreDiscarded()
			end,
			callback = function()
				self:restoreDiscarded()
			end,
		},
	}

	local button_items = {
		optionSetting(_("Size"),
			_("Choose how big the floating buttons are. Bigger buttons are easier to tap."),
			C.BUTTON_SIZE_OPTIONS,
			function() return self:getButtonSize() end,
			function(value) self:setButtonSize(value) end),
		optionSetting(_("Position"),
			_("Choose where on the screen the buttons sit. They always stay on the side the arrow leads to."),
			C.VERTICAL_POSITION_OPTIONS,
			function() return self:getVerticalPosition() end,
			function(value) self:setVerticalPosition(value) end),
		optionSetting(_("Destination on button"),
			_("Choose what is written next to the arrow: the page it leads to, how many pages away that is, or nothing."),
			C.INLINE_LABEL_OPTIONS,
			function() return self:getInlineLabelMode() end,
			function(value) self:setInlineLabelMode(value) end),
		optionSetting(_("Hold hint"),
			_("Choose what the hint says when you hold the arrow: the chapter title with a page number or percentage, in the book or in the chapter."),
			C.DESTINATION_FORMAT_OPTIONS,
			function() return self:getDestinationFormat() end,
			function(value) self:setDestinationFormat(value) end),
	}

	local auto_hide_items = {
		optionSetting(_("Hide after"),
			_("Choose how long the buttons stay up without navigating before they hide. Hiding never loses the anchor."),
			C.AUTO_DISMISS_OPTIONS,
			function() return self:getAutoDismissSeconds() end,
			function(value) self:setAutoDismissSeconds(value) end),
		optionSetting(_("When hidden"),
			_("Choose what stays on screen while the buttons are hidden: a small anchor tab that brings them back with a tap, or nothing (bring them back from the menu or a gesture)."),
			C.HIDE_MODE_OPTIONS,
			function() return self:getHideMode() end,
			function(value) self:setHideMode(value) end),
		optionSetting(_("Discard after hidden for"),
			_("Choose how long hidden buttons wait. After that the anchor is discarded and this page becomes your reading position. A pinned anchor never expires."),
			C.HIDDEN_EXPIRY_OPTIONS,
			function() return self:getHiddenExpirySeconds() end,
			function(value) self:setHiddenExpirySeconds(value) end),
	}

	local navigation_items = {
		optionSetting(_("Forget return point after"),
			_("After going back to the anchor, the button can take you back out to where you were. Choose after how many pages of reading on that return point is forgotten."),
			C.FORWARD_DISMISS_PAGE_OPTIONS,
			function() return self:getForwardDismissPages() end,
			function(value) self:setForwardDismissPages(value) end),
		optionSetting(_("Re-reading tolerance"),
			_("Choose how many page turns back still count as re-reading rather than a jump. Only matters for tools that move without telling KOReader: the table of contents, Go to page, links and other standard navigation always offer the way back."),
			C.REREAD_TURNS_OPTIONS,
			function() return self:getRereadTurns() end,
			function(value) self:setRereadTurns(value) end),
	}

	menu_items.pageanchor = {
		text = _("Page Anchor"),
		sorting_hint = "navi",
		sub_item_table = {
			{
				-- KOReader's own "Enable" plus the plugin's name (a proper
				-- noun): already translated everywhere KOReader is.
				text = _("Enable") .. " " .. _("Page Anchor"),
				help_text = _("Shows floating buttons after a jump so you can go back to where you were reading. Turning it off keeps the anchor; the buttons come back when you turn it on again."),
				checked_func = isEnabled,
				callback = function(touchmenu_instance)
					self:setEnabled(not self:isEnabled())
					if touchmenu_instance and touchmenu_instance.updateItems then
						touchmenu_instance:updateItems()
					end
				end,
				keep_menu_open = true,
				separator = true,
			},
			{
				text_func = function()
					return T(_("%1: %2"), _("Current anchor"), self:getAnchorStatusText())
				end,
				help_text = _("Pin an anchor before exploring, bring back hidden buttons, or discard the anchor (and undo that)."),
				enabled_func = isEnabled,
				sub_item_table = anchor_items,
				separator = true,
			},
			{
				text = _("Buttons"),
				help_text = _("Choose the size and position of the floating buttons and what they show."),
				enabled_func = isEnabled,
				sub_item_table = button_items,
			},
			{
				text = _("Auto-hide"),
				help_text = _("Choose when the buttons hide on their own, what stays on screen, and how long a hidden anchor is kept."),
				enabled_func = isEnabled,
				sub_item_table = auto_hide_items,
			},
			{
				text = _("Navigation"),
				help_text = _("Choose how long the way back out is kept after returning to the anchor, and what counts as a jump."),
				enabled_func = isEnabled,
				sub_item_table = navigation_items,
				separator = true,
			},
			{
				text = _("Restore all defaults"),
				help_text = _("Restores every Page Anchor setting. Page Anchor stays turned on or off as it is, and the current anchor is kept."),
				keep_menu_open = true,
				callback = function(touchmenu_instance)
					UIManager:show(ConfirmBox:new({
						text = _("Restore all Page Anchor settings to their defaults?"),
						ok_text = _("Restore"),
						ok_callback = function()
							self:resetAllSettings()
							if touchmenu_instance and touchmenu_instance.updateItems then
								touchmenu_instance:updateItems()
							end
						end,
					}))
				end,
			},
			{
				text = _("About"),
				keep_menu_open = true,
				callback = function()
					UIManager:show(InfoMessage:new({
						text = _("Page Anchor")
							.. "\n"
							.. T(_("Version: %1"), C.PLUGIN_VERSION)
							.. "\n\n"
							.. _("Shows floating back and forward buttons so you can review another part of a book without losing either reading position."),
					}))
				end,
			},
		},
	}
end

return PageAnchor
