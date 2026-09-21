--[[
Dictionary Explorer plugin for KOReader.

Adds a "Go to dictionary" button to the dictionary popup. It opens the
dictionary at the looked-up word in a full-screen viewer that pages through
neighbouring entries, like the Kindle's "go to dictionary". The viewer is
not a document, so the dictionary never appears in the reading history.

It can also be opened from a starting word without a lookup: from its menu, or
from a gesture, profile or Quick Dock button, through a Dispatcher action.
]]

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local _ = require("dictionaryexplorer_l10n")
local ffiUtil = require("ffi/util")
local T = ffiUtil.template

local Dock = require("modules/dock")
local StarDict = require("modules/stardict")
local Viewer = require("modules/viewer")

local PLUGIN_VERSION = "v1.0.0"

local SETTING_START_DICTIONARY = "dictionaryexplorer_start_dictionary" -- a dictionary name; unset means automatic
local ACTION_OPEN_AT_WORD = "dictionaryexplorer_open_at_word"

local DictionaryExplorer = WidgetContainer:extend({
	name = "dictionaryexplorer",
})

function DictionaryExplorer:init()
	-- Needs the dictionary button API added in KOReader v2026.07 (koreader#15184).
	local dictionary = self.ui and self.ui.dictionary
	if not (dictionary and dictionary.addToDictButtons) then
		logger.warn("DictionaryExplorer: needs KOReader v2026.07 or newer, not adding the button")
		return
	end
	dictionary:addToDictButtons({
		id = "dictionaryexplorer_open",
		menu_text = _("Go to dictionary"),
		text = _("Go to dictionary"),
		show_func = function(popup)
			return self:getDictionary(popup.dictionary) ~= nil
		end,
		callback = function(popup)
			self:open(popup)
		end,
	})

	self:onDispatcherRegisterActions()

	if self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end
end

-- Registers the "open at a word" action with KOReader's Dispatcher, which makes
-- it available in the gesture manager, in profiles, and in the action picker
-- of Quick Dock.
function DictionaryExplorer:onDispatcherRegisterActions()
	Dispatcher:registerAction(ACTION_OPEN_AT_WORD, {
		category = "none",
		event = "OpenDictionaryExplorer",
		title = _("Dictionary Explorer: open at a word"),
		general = true,
	})
end

function DictionaryExplorer:onOpenDictionaryExplorer()
	self:showStartWordDialog()
	return true
end

function DictionaryExplorer:addToMainMenu(menu_items)
	menu_items.dictionaryexplorer = {
		text = _("Dictionary Explorer"),
		sorting_hint = "tools",
		sub_item_table = {
			{
				text = _("Open dictionary at a word…"),
				help_text = _(
					"Asks for a word and opens the dictionary at it, without looking it up in a book first. The same action can be assigned to a gesture or added to Quick Dock: look for “Dictionary Explorer: open at a word” in the list of actions."
				),
				callback = function()
					self:showStartWordDialog()
				end,
			},
			{
				text = _("Starting dictionary"),
				help_text = _("Which dictionary “Open dictionary at a word” opens."),
				sub_item_table_func = function()
					return self:getStartDictionaryMenu()
				end,
				separator = true,
			},
			{
				text = _("Show dock shadow"),
				help_text = _(
					"Show a small dithered shadow along the right and bottom edges of the dock that appears next to selected text in the dictionary viewer."
				),
				checked_func = function()
					return Dock.showShadow()
				end,
				callback = function()
					Dock.setShadow(not Dock.showShadow())
				end,
				keep_menu_open = true,
				separator = true,
			},
			{
				text = T(_("Version: %1"), PLUGIN_VERSION),
				callback = function()
					UIManager:show(InfoMessage:new({
						text = _("Dictionary Explorer") .. "\n" .. T(_("Version: %1"), PLUGIN_VERSION),
					}))
				end,
			},
		},
	}
end

-- The dictionaries that can be opened, in the order KOReader itself uses for
-- its dictionaries (the user's own ordering first, then by name).
function DictionaryExplorer:getSupportedDictionaries()
	local order = self.ui.dictionary.dicts_order or {}
	local supported = {}
	for name, file in pairs(self:getIfoFiles()) do
		local dictionary = self:getDictionary(name)
		if dictionary then
			table.insert(supported, { name = name, file = file, dictionary = dictionary })
		end
	end
	table.sort(supported, function(left, right)
		local left_order, right_order = order[left.file], order[right.file]
		if left_order == right_order then
			return ffiUtil.strcoll(left.name, right.name)
		end
		return left_order ~= nil and (right_order == nil or left_order < right_order)
	end)
	return supported
end

--- The dictionary "open at a word" uses: the one chosen in the menu, or else the
-- first that can be opened and isn't disabled in KOReader's dictionary settings.
function DictionaryExplorer:getStartDictionary()
	local chosen = G_reader_settings:readSetting(SETTING_START_DICTIONARY)
	if chosen and self:getDictionary(chosen) then
		return self:getDictionary(chosen)
	end
	local supported = self:getSupportedDictionaries()
	local disabled = self.ui.dictionary.dicts_disabled or {}
	for _index, entry in ipairs(supported) do
		if not disabled[entry.file] then
			return entry.dictionary
		end
	end
	return supported[1] and supported[1].dictionary
end

function DictionaryExplorer:getStartDictionaryMenu()
	local items = {
		{
			text = _("Automatic (first in KOReader's dictionary order)"),
			radio = true,
			checked_func = function()
				return G_reader_settings:readSetting(SETTING_START_DICTIONARY) == nil
			end,
			callback = function()
				G_reader_settings:delSetting(SETTING_START_DICTIONARY)
			end,
			separator = true,
		},
	}
	for _index, entry in ipairs(self:getSupportedDictionaries()) do
		table.insert(items, {
			text = entry.name,
			radio = true,
			checked_func = function()
				return G_reader_settings:readSetting(SETTING_START_DICTIONARY) == entry.name
			end,
			callback = function()
				G_reader_settings:saveSetting(SETTING_START_DICTIONARY, entry.name)
			end,
		})
	end
	return items
end

--- Asks for a word and opens the starting dictionary there.
function DictionaryExplorer:showStartWordDialog()
	local dictionary = self:getStartDictionary()
	if not dictionary then
		UIManager:show(InfoMessage:new({ text = _("No dictionary that can be opened was found.") }))
		return
	end
	local dialog
	dialog = InputDialog:new({
		title = _("Open dictionary at a word"),
		description = dictionary.name,
		input_hint = _("Word to start from"),
		buttons = {
			{
				{
					text = _("Cancel"),
					id = "close",
					callback = function()
						UIManager:close(dialog)
					end,
				},
				{
					text = _("Open"),
					is_enter_default = true,
					callback = function()
						local word = util.trim(dialog:getInputText())
						UIManager:close(dialog)
						if word ~= "" then
							self:openAt(dictionary, word)
						end
					end,
				},
			},
		},
	})
	UIManager:show(dialog)
	dialog:onShowKeyboard()
end

function DictionaryExplorer:openAt(dictionary, word)
	self:withIndex(dictionary, function()
		local position, exact = dictionary:locateText(word)
		if not exact then
			Notification:notify(T(_("No entry for “%1”. Showing the closest one."), word))
		end
		self:showViewer(dictionary, position)
	end)
end

function DictionaryExplorer:showViewer(dictionary, position)
	UIManager:show(Viewer:new({
		ui = self.ui, -- for the vocabulary builder
		dictionary = dictionary,
		position = position,
		side_margins = self:getSideMargins(),
	}))
end

-- Maps dictionary names (as shown in the popup) to their .ifo files. Scanned
-- once per session, like KOReader does for its own dictionary list.
function DictionaryExplorer:getIfoFiles()
	if not self.ifo_by_name then
		self.ifo_by_name = {}
		local data_dir = self.ui.dictionary.data_dir
		for _index, directory in ipairs({ data_dir, data_dir .. "_ext" }) do
			for _index2, found in ipairs(StarDict.scan(directory)) do
				self.ifo_by_name[found.name] = self.ifo_by_name[found.name] or found.file
			end
		end
	end
	return self.ifo_by_name
end

--- Returns the StarDict object for a dictionary name, or nil when the
-- dictionary isn't installed as StarDict or has a format we can't page through.
function DictionaryExplorer:getDictionary(name)
	if not name then
		return nil
	end
	self.resolved = self.resolved or {}
	if self.resolved[name] == nil then
		local ifo_file = self:getIfoFiles()[name]
		local dictionary = ifo_file and StarDict.get(ifo_file)
		self.resolved[name] = dictionary or false
	end
	return self.resolved[name] or nil
end

--- Whether the dictionary called `name` (as KOReader shows it in a lookup
-- result) can be opened in the viewer. Other plugins use this to decide
-- whether to offer a button that calls openWord().
function DictionaryExplorer:canOpen(name)
	return self:getDictionary(name) ~= nil
end

--- Opens the dictionary called `name` at `word`, centred and highlighted, as
-- the "Go to dictionary" button of the popup does. `hint` is the definition
-- that was shown for it, used to pick between entries with the same headword.
-- Returns false, after saying so, if the dictionary can't be opened.
function DictionaryExplorer:openWord(name, word, hint)
	local dictionary = self:getDictionary(name)
	if not dictionary then
		UIManager:show(InfoMessage:new({ text = _("This dictionary can't be opened as a book.") }))
		return false
	end
	self:withIndex(dictionary, function()
		self:showViewer(dictionary, (dictionary:locate(word, hint)))
	end)
	return true
end

function DictionaryExplorer:open(popup)
	-- Read what we need before the popup goes away.
	local name = popup.dictionary
	local word = popup.lookupword or popup.word
	local hint = popup.definition
	if not self:canOpen(name) then
		UIManager:show(InfoMessage:new({ text = _("This dictionary can't be opened as a book.") }))
		return
	end
	popup:onClose()
	self:openWord(name, word, hint)
end

-- Left and right page margins (in pixels) of the book being read, so the
-- dictionary text lines up with it. Only crengine documents (EPUB, TXT, ...)
-- have such margins; for anything else the viewer uses its own default.
function DictionaryExplorer:getSideMargins()
	local document = self.ui.document
	if document and document.getPageMargins then
		local margins = document:getPageMargins()
		return { left = margins.left, right = margins.right }
	end
end

-- Runs `callback` once the dictionary's page index is available, building it
-- first (with a notice, since big dictionaries take a moment) if needed.
function DictionaryExplorer:withIndex(dictionary, callback)
	if dictionary:isIndexed() then
		callback()
		return
	end

	local notice = InfoMessage:new({
		text = _("Preparing the dictionary index…\nThis is only needed once."),
	})
	UIManager:show(notice)
	UIManager:forceRePaint()
	UIManager:scheduleIn(0.1, function()
		local ok, err = dictionary:buildIndex()
		UIManager:close(notice)
		if ok then
			callback()
		else
			logger.warn("DictionaryExplorer: could not index", dictionary.name, err)
			UIManager:show(InfoMessage:new({ text = _("Could not open the dictionary.") }))
		end
	end)
end

return DictionaryExplorer
