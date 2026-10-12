--[[
Full-screen "dictionary as a book" viewer.

Shows a page of consecutive dictionary entries (as many as fill the screen)
and pages through the dictionary in its own order. It is a plain widget on
top of whatever is open: no document is loaded, so nothing is written to the
reading history, the "last book" setting, statistics or a sidecar folder.
]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LineWidget = require("ui/widget/linewidget")
local Notification = require("ui/widget/notification")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("dictionaryexplorer_l10n")
local T = require("ffi/util").template

local Breadcrumb = require("modules/breadcrumb")
local ChoiceList = require("modules/choicelist")
local Library = require("modules/library")
local Notices = require("modules/notices")
local Trail = require("modules/trail")
local Dock = require("modules/dock")
local FitModel = require("modules/fitmodel")
local Text = require("modules/text")

local Screen = Device.screen

local DEFAULT_DICT_FONT_SIZE = 20 -- same default as the dictionary popup
local DEFAULT_SIDE_MARGIN = 16 -- used when the document we came from has no margins to follow

-- Where the fit model (see fitmodel.lua) starts from, as
-- multiples of the font size: the average glyph width, the line height, how
-- many bytes of definition make one letter (markup and multi-byte characters
-- included) and the lines of rule and spacing around an entry.
local AVERAGE_GLYPH_WIDTH = 0.5
local LINE_HEIGHT = 1.3
local BYTES_PER_CHARACTER = 1.2
local ENTRY_GAP_LINES = 2
local HEADING_CHARS_FACTOR = 0.85 -- a bold heading fits this fraction of the letters a line of text does
-- Vertical gaps in the header, in unscaled pixels: entry numbers -> dictionary
-- name -> rule -> first entry.
local GAP_ABOVE_DICTIONARY_NAME = 2
local GAP_BELOW_DICTIONARY_NAME = 8
local GAP_BELOW_RULE = 12
local MAX_FIT_ATTEMPTS = 6
local FOOTER_ICON_BUTTON_WIDTH = 60 -- each narrow button in the footer (unscaled pixels)
-- Room between a text button's label and its edges: roomier than the icon
-- buttons of the other docks, whose side padding is Dock.BUTTON_SIDE_PADDING.
local DOCK_TEXT_SIDE_PADDING = 20
local DOCK_ICON_SIZE = 22 -- as in the selection toolbar (unscaled pixels)
local FILL_BELOW = 0.85 -- a centred page emptier than this gets more entries on whichever side still fits
local MAX_FILL_ATTEMPTS = 4
local HIGHLIGHT_CLASS = "dictionaryexplorer-highlight"
local FILL_TARGET = 0.92 -- stop growing a page once it is this full
local AIM_AT = 0.95 -- how full the first guess for a page tries to make it
local SKIP_MARGIN = 1 -- only entries predicted to fit in the room left are tried (1.2 saved no whitespace and cost more layouts)
-- The "no entry" line: the word asked for is cut to this many characters, and
-- the line to this many lines, so a long pasted phrase can't crowd out the
-- entries.

-- What the viewer has learnt about how tall entries are, for the session and
-- per dictionary, font size and text width.
local fit_models = {}

local function readFile(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content
end

-- Per-dictionary extras KOReader lets users provide next to the .ifo: a
-- stylesheet (.css) and a function that repairs the HTML (.lua).
local assets_cache = {}
local function getDictionaryAssets(dictionary)
	local cached = assets_cache[dictionary.ifo_path]
	if cached then
		return cached
	end

	local directory = util.splitFilePathName(dictionary.ifo_path)
	local assets = {
		css = readFile((dictionary.ifo_path:gsub("%.ifo$", ".css"))),
		directory = directory,
	}
	local fix_path = dictionary.ifo_path:gsub("%.ifo$", ".lua")
	if lfs.attributes(fix_path, "mode") == "file" then
		local ok, fix = pcall(dofile, fix_path)
		if ok and type(fix) == "function" then
			assets.fix_html = fix
		else
			logger.warn("DictionaryExplorer: dictionary's fix function failed:", fix)
		end
	end
	if lfs.attributes(directory .. "res", "mode") == "directory" then
		assets.resource_directory = directory .. "res"
	end
	assets_cache[dictionary.ifo_path] = assets
	return assets
end

local DictionaryExplorerViewer = InputContainer:extend({
	dictionary = nil, -- StarDict object (its index must already be loaded)
	position = 0, -- 0-based number of the entry to open on (it ends up in the middle of the page, highlighted)
	side_margins = nil, -- { left =, right = } in pixels; defaults to a small margin
	ui = nil, -- the ReaderUI (or FileManager) the viewer was opened from; only used to reach the vocabulary builder
	lookup = nil, -- what StarDict:resolve() said about the word `position` was found for, if one was
	resume = nil, -- an exploration to continue (see explorationState()), in place of `position`
	on_explore = nil, -- function(state), told the explorationState() after each page is shown
	-- The other dictionaries, to go to words in them: { list = function()
	-- giving the dictionaries to offer, find = function(name) giving one by its
	-- name, prepare = function(dictionary, callback) running callback once its
	-- index is ready }. Without it the viewer stays in its dictionary.
	library = nil,
	covers_fullscreen = true,
})

function DictionaryExplorerViewer:init()
	self.lib = Library.new(self.library)
	self.dimen = Geom:new({ w = Screen:getWidth(), h = Screen:getHeight() })
	local default_margin = Screen:scaleBySize(DEFAULT_SIDE_MARGIN)
	local margins = self.side_margins or { left = default_margin, right = default_margin }
	-- Guard against a margin so large it would leave no room for text.
	local max_margin = math.floor(self.dimen.w * 0.3)
	self.side_margins = {
		left = math.max(0, math.min(margins.left, max_margin)),
		right = math.max(0, math.min(margins.right, max_margin)),
	}
	self.font_size = G_reader_settings:readSetting("dict_font_size") or DEFAULT_DICT_FONT_SIZE
	local hold_pan_rate = G_reader_settings:readSetting("hold_pan_rate") or (Screen.low_pan_rate and 5.0 or 30.0)
	self.ges_events = {
		Swipe = { GestureRange:new({ ges = "swipe", range = self.dimen }) },
		Tap = { GestureRange:new({ ges = "tap", range = self.dimen }) },
		-- Text selection: HtmlBoxWidget does the work, and calls back on release.
		HoldStartText = { GestureRange:new({ ges = "hold", range = self.dimen }) },
		HoldPanText = { GestureRange:new({ ges = "hold_pan", range = self.dimen, rate = hold_pan_rate }) },
		HoldReleaseText = {
			GestureRange:new({ ges = "hold_release", range = self.dimen }),
			args = function(text)
				self:onTextSelected(text)
			end,
		},
	}
	if Device:hasKeys() then
		self.key_events = {
			Close = { { Device.input.group.Back } },
			ScrollDown = { { Device.input.group.PgFwd } },
			ScrollUp = { { Device.input.group.PgBack } },
		}
	end
	if self.resume then
		if self:_restore(self.resume) then
			return
		end
		-- The dictionary is not the one the exploration was saved from (it was
		-- updated, or replaced): start again from the word it was on.
		if type(self.resume.word) == "string" then
			self.position = self.dictionary:locate(self.resume.word)
		end
	end
	-- The words walked through with "Go to word", starting with the one the
	-- viewer opened on; the breadcrumb only shows once there are two.
	self.trail = { { word = self:_trailWord(self.lookup, self.position), position = self.position, dictionary = self.dictionary } }
	self.trail_index = 1
	self.miss = self:_missFrom(self.lookup)
	if self.miss then
		self.miss.crumb = 1
	end
	self:showAround(self.position)
end

function DictionaryExplorerViewer:_getCss()
	local justify = G_reader_settings:nilOrTrue("dict_justify") and "text-align: justify;" or ""
	local css = [[
		@page {
			margin: 0;
			font-family: 'Noto Sans';
		}

		body {
			margin: 0;
			line-height: 1.3;
			]] .. justify .. [[
		}

		blockquote, dd {
			margin: 0 1em;
		}

		ol, ul, menu {
			margin: 0; padding: 0 1.7em;
		}
	]]
	-- Marks the entry the user came for. A grey block with a heavy bar on the
	-- side stays readable on e-ink and in colour.
	css = css .. "\n." .. HIGHLIGHT_CLASS .. [[ {
		background-color: #d8d8d8;
		border-left: 0.3em solid black;
		padding: 0.2em 0.4em;
	}
	]]
	local extra = getDictionaryAssets(self.dictionary).css
	return extra and (css .. extra) or css
end

-- The HTML of an entry. While a page is being fitted the same entries are laid
-- out several times, so what was read is kept (in _html_cache) meanwhile.
function DictionaryExplorerViewer:_getHtml(position, entry)
	local cache = self._html_cache
	local html = cache and cache[position]
	if not html then
		html = self:_readHtml(entry)
		if cache then
			cache[position] = html
		end
	end
	return html
end

function DictionaryExplorerViewer:_readHtml(entry)
	local definition = self.dictionary:readDefinition(entry)
	if not definition then
		return "<p>" .. _("Could not read this entry.") .. "</p>"
	end
	if self.dictionary.is_html then
		local assets = getDictionaryAssets(self.dictionary)
		if assets.fix_html then
			local ok, fixed = pcall(assets.fix_html, definition, assets.directory)
			if ok then
				return fixed
			end
			logger.warn("DictionaryExplorer: dictionary's fix function failed:", fixed)
		end
		return definition
	end
	if self.dictionary.text_type == "x" then
		return Text.xdxfLiteToHtml(definition, entry.word)
	end
	return Text.plainToHtml(definition)
end

-- Fraction of the bytes of the first few entries from `position` that are
-- letters the reader sees, the rest being markup. The dictionaries differ a lot
-- (Priberam Portuguese is mostly markup), and it is what the first guess for
-- how many entries fit depends on most.
function DictionaryExplorerViewer:_sampleVisibleRatio(position)
	local dictionary = self.dictionary
	local visible, total = 0, 0
	for candidate = position, math.min(position + 3, dictionary:getCount() - 1) do
		local definition = dictionary:readDefinition(dictionary:getEntry(candidate))
		if definition then
			total = total + #definition
			visible = visible + #(definition:gsub("%b<>", ""))
		end
	end
	if total < 200 then
		return nil -- too little to say anything
	end
	return math.min(math.max(visible / total, 0.1), 1)
end

-- The model of how tall entries are: shared by every viewer of the same
-- dictionary, font size and width, so it keeps learning across openings.
function DictionaryExplorerViewer:_getFitModel()
	if not self.fit_model then
		local font_px = Screen:scaleBySize(self.font_size)
		local text_width = self.dimen.w - self.side_margins.left - self.side_margins.right
		local key = table.concat({ self.dictionary.ifo_path, font_px, text_width }, "|")
		self.line_px = LINE_HEIGHT * font_px
		self.columns = text_width / (AVERAGE_GLYPH_WIDTH * font_px)
		if not fit_models[key] then
			local ratio = self:_sampleVisibleRatio(self.position) or (1 / BYTES_PER_CHARACTER)
			fit_models[key] = FitModel.new((ENTRY_GAP_LINES + 0.5) * self.line_px, self.line_px * ratio / self.columns)
		end
		self.fit_model = fit_models[key]
	end
	return self.fit_model
end

-- The heading of a group of entries that share their text lists all their
-- words (see _buildHtmlWidget), and that can take several lines. The first line
-- is part of the fixed cost of an entry; this is how many pixels the rest take.
function DictionaryExplorerViewer:_headingExtra(word_count, letters)
	local lines = math.ceil((letters + 2 * (word_count - 1)) / (self.columns * HEADING_CHARS_FACTOR))
	return math.max(lines - 1, 0) * self.line_px
end

-- Predicted height of an entry, in pixels. Inflected forms are often stored as
-- separate entries with the same text (and so the same size); they are shown
-- once, under a shared heading, so a neighbour of equal size is assumed to add
-- just its word to that heading.
function DictionaryExplorerViewer:_entryCost(entry, neighbour)
	local model = self:_getFitModel()
	if neighbour and neighbour.size == entry.size then
		return self.line_px * (#entry.word + 2) / (self.columns * HEADING_CHARS_FACTOR)
	end
	return model.per_entry + model.per_byte * entry.size
end

-- Last entry of the page that starts at `first`: neighbours are added while
-- they are predicted to still fit. An entry too big to fit always gets a page
-- to itself (and scrolls), never shares one.
function DictionaryExplorerViewer:_lastEntryFrom(first)
	local budget = AIM_AT * self:_getContentHeight()
	local dictionary = self.dictionary
	local last, total = first, self:_entryCost(dictionary:getEntry(first))
	while last + 1 < dictionary:getCount() do
		total = total + self:_entryCost(dictionary:getEntry(last + 1), dictionary:getEntry(last))
		if total > budget then
			break
		end
		last = last + 1
	end
	return last
end

-- First entry of the page that ends at `last`.
function DictionaryExplorerViewer:_firstEntryUntil(last)
	local budget = AIM_AT * self:_getContentHeight()
	local dictionary = self.dictionary
	local first, total = last, self:_entryCost(dictionary:getEntry(last))
	while first > 0 do
		total = total + self:_entryCost(dictionary:getEntry(first - 1), dictionary:getEntry(first))
		if total > budget then
			break
		end
		first = first - 1
	end
	return first
end

function DictionaryExplorerViewer:_freeContent()
	self:_closeSelectionDock()
	local html_widget = self.html_widget
	if html_widget and html_widget.htmlbox_widget then
		html_widget.htmlbox_widget:free()
	end
	self.html_widget = nil
end

function DictionaryExplorerViewer:_buildButtons()
	local icon_width = Screen:scaleBySize(FOOTER_ICON_BUTTON_WIDTH)
	local go_to_word = {
		text = _("Search"),
		font_bold = true, -- the only bold label in the row
		callback = function()
			self:showGoToDialog()
		end,
		hold_callback = function()
			UIManager:show(InfoMessage:new({ text = _("Searches every dictionary for a word, and lists what each one has."), timeout = 3 }))
		end,
	}
	local close = {
		icon = "close",
		width = icon_width,
		callback = function()
			self:onClose()
		end,
	}
	-- Pages have no buttons: they turn by swiping, tapping the sides of the
	-- text, or the page-turn keys. The words walked through are gone back to
	-- by tapping them in the breadcrumb.
	return ButtonTable:new({
		width = self.dimen.w,
		show_parent = self,
		buttons = { { go_to_word, close } },
	})
end

-- Title bar (first and last headword of the page, larger than usual, with the
-- entry numbers under it), then the dictionary's name in italics, then a rule.
function DictionaryExplorerViewer:_buildHeader(first_position, last_position)
	local dictionary = self.dictionary
	local first, last = dictionary:getEntry(first_position), dictionary:getEntry(last_position)
	local title, position_text
	if first_position == last_position then
		title = first.word
		position_text = T(_("Entry %1 of %2"), first_position + 1, dictionary:getCount())
	else
		title = first.word .. " – " .. last.word
		position_text = T(_("Entries %1–%2 of %3"), first_position + 1, last_position + 1, dictionary:getCount())
	end
	local title_bar = TitleBar:new({
		width = self.dimen.w,
		fullscreen = true,
		title = title,
		title_face = Font:getFace("tfont"),
		title_shrink_font_to_fit = true,
		subtitle = position_text,
		subtitle_face = Font:getFace("x_smallinfofont"),
		with_bottom_line = false,
		bottom_v_padding = 0, -- the gaps below are set explicitly
		show_parent = self,
	})
	-- The dictionary's name, and, when other dictionaries have the word the
	-- page is about too, which of them this one is ("· ‹ 1/3 ›", see
	-- _holdersOf()): tapping the name's line goes to the word in the next one
	-- (its left half, the previous one). The name gives way when both don't
	-- fit, not the mark.
	local width = self.dimen.w - 2 * Size.padding.large
	local holders = self._header_holders -- set by _installPage() for the page it shows
	self.header_mark = nil
	if holders and #holders > 1 then
		local index = 1
		for position, holder in ipairs(holders) do
			if holder.dictionary == dictionary then
				index = position
			end
		end
		self.header_mark = Notices.headerMark(index, #holders)
		width = math.max(width - self.header_mark:getSize().w, math.floor(width / 3))
	end
	local dictionary_name = TextWidget:new({
		text = dictionary.name,
		face = Font:getFace("NotoSans-Italic.ttf", 18),
		max_width = width,
	})
	if self.header_mark then
		-- As tall as the name alone: the header's height, which the room for
		-- the entries is worked out from, never changes.
		local line_height = dictionary_name:getSize().h
		dictionary_name = CenterContainer:new({
			dimen = Geom:new({ w = self.dimen.w, h = line_height }),
			HorizontalGroup:new({ align = "center", dictionary_name, self.header_mark }),
		})
	end
	-- Where the name's line is, for taps (the header is at the top of the screen).
	self._name_band = {
		top = title_bar:getSize().h,
		bottom = title_bar:getSize().h + Screen:scaleBySize(GAP_ABOVE_DICTIONARY_NAME) + dictionary_name:getSize().h + Screen:scaleBySize(GAP_BELOW_DICTIONARY_NAME),
	}
	return VerticalGroup:new({
		align = "center",
		title_bar,
		VerticalSpan:new({ width = Screen:scaleBySize(GAP_ABOVE_DICTIONARY_NAME) }),
		dictionary_name,
		VerticalSpan:new({ width = Screen:scaleBySize(GAP_BELOW_DICTIONARY_NAME) }),
		LineWidget:new({
			dimen = Geom:new({ w = self.dimen.w, h = Size.line.medium }),
			background = Blitbuffer.COLOR_BLACK,
		}),
	})
end

-- ScrollHtmlWidget keeps its scroll bar (and a gap before it) inside its own
-- width. Lend it that much of the right margin, so the text itself lines up
-- with the margins of the book we came from and the bar sits in the margin.
function DictionaryExplorerViewer:_getScrollChrome()
	return math.min(self.side_margins.right, ScrollHtmlWidget.scroll_bar_width + ScrollHtmlWidget.text_scroll_span)
end

-- On a page with several entries each one needs its headword in view. Some
-- dictionaries repeat it at the start of the definition (Priberam Portuguese,
-- Oxford), others don't (Priberam English-Portuguese): only add it when missing.
local function startsWithHeadword(html, word)
	local text = html:gsub("%b<>", ""):gsub("^%s+", "")
	return text:sub(1, #word):lower() == word:lower()
end

function DictionaryExplorerViewer:_buildHtmlWidget(first, last, height)
	-- Consecutive entries with identical text are shown once.
	self:_getFitModel() -- sets the line height and columns used below
	local groups = {}
	local bytes = 0 -- of the definitions actually shown, for the fit model
	for position = first, last do
		local entry = self.dictionary:getEntry(position)
		local html = self:_getHtml(position, entry)
		local previous = groups[#groups]
		if previous and previous.html == html then
			table.insert(previous.words, entry.word)
			previous.last = position
		else
			groups[#groups + 1] = { html = html, words = { entry.word }, first = position, last = position }
			bytes = bytes + entry.size
		end
	end

	-- With a single entry on the page there is nothing to tell it apart from,
	-- and the title already names it: only mark the entry among others.
	local parts = {}
	for _index, group in ipairs(groups) do
		local html = group.html
		if last > first and (#group.words > 1 or not startsWithHeadword(html, group.words[1])) then
			html = "<div><b>" .. util.htmlEscape(table.concat(group.words, ", ")) .. "</b></div>" .. html
		end
		local highlighted = self.highlighted
		if last > first and highlighted and highlighted >= group.first and highlighted <= group.last then
			html = '<div class="' .. HIGHLIGHT_CLASS .. '">' .. html .. "</div>"
		end
		parts[#parts + 1] = html
	end
	local margins = self.side_margins
	local widget = ScrollHtmlWidget:new({
		html_body = #parts == 1 and parts[1] or table.concat(parts, "<hr/>"),
		html_resource_directory = getDictionaryAssets(self.dictionary).resource_directory,
		css = self:_getCss(),
		default_font_size = Screen:scaleBySize(self.font_size),
		width = self.dimen.w - margins.left - margins.right + self:_getScrollChrome(),
		height = height,
		dialog = self,
		highlight_text_selection = true,
		html_link_tapped_callback = function(link)
			self:onLinkTapped(link)
		end,
	})
	-- What the fit model is taught: the groups, their bytes, and how tall
	-- their headings are beyond the first line, which it doesn't model.
	local heading_extra = 0
	for _index, group in ipairs(groups) do
		if #group.words > 1 then
			local letters = 0
			for _index2, word in ipairs(group.words) do
				letters = letters + #word
			end
			heading_extra = heading_extra + self:_headingExtra(#group.words, letters)
		end
	end
	widget.fit_groups, widget.fit_bytes, widget.fit_extra = #groups, bytes, heading_extra
	return widget
end

-- How many of the entries that come after the run first..last (which has
-- `entries` entries) are predicted to fit in `remaining` pixels.
function DictionaryExplorerViewer:_entriesThatFit(range, first, _last, entries, max_entries, remaining, spills_at)
	local dictionary = self.dictionary
	local limit = math.min(max_entries, (spills_at or math.huge) - 1)
	local fitted, total = 0, 0
	for candidate = entries + 1, limit do
		local next_first, next_last = range(candidate)
		local added, neighbour = next_last, next_last - 1
		if next_first < first then
			added, neighbour = next_first, next_first + 1
		end
		total = total + self:_entryCost(dictionary:getEntry(added), dictionary:getEntry(neighbour))
		if total > remaining then
			break
		end
		fitted = candidate - entries
		first = next_first -- only where the run starts matters for the next one
	end
	return fitted
end

-- Finds the largest run of entries that fits on one screen and builds its
-- widget. `range(entries)` gives the first and last entry of the run with
-- that many entries, `start_entries` is where the search starts from (a
-- prediction) and `max_entries` how far `range` can go. Each attempt is laid
-- out for real, which is what makes it expensive, so the fit model is taught
-- every height that is measured and asked which further entries are worth
-- trying: the run grows only by entries predicted to fit in the space left,
-- and shrinks, when it spills onto a second screen, by one entry and then by
-- more and more. A single entry longer than the screen is kept as it is and
-- scrolls.
function DictionaryExplorerViewer:_fitPage(range, start_entries, max_entries, height)
	local model = self:_getFitModel()
	local best, best_entries
	local spills_at -- fewest entries known not to fit
	local entries = start_entries
	local step_down = 1
	for _attempt = 1, MAX_FIT_ATTEMPTS do
		local range_first, range_last = range(entries)
		local widget = self:_buildHtmlWidget(range_first, range_last, height)
		local pages = widget.htmlbox_widget.page_count
		local next_entries

		if pages <= 1 then
			if best then
				best.htmlbox_widget:free()
			end
			best, best_entries = widget, entries
			local used = widget.htmlbox_widget:getSinglePageHeight() or height
			model:add(widget.fit_groups, widget.fit_bytes, used - widget.fit_extra)
			if used >= FILL_TARGET * height then
				break
			end
			local more = self:_entriesThatFit(range, range_first, range_last, entries, max_entries, (height - used) * SKIP_MARGIN, spills_at)
			if more == 0 then
				break
			end
			next_entries = entries + more
		elseif range_first == range_last then
			-- One entry taller than the screen.
			if best then
				widget.htmlbox_widget:free()
			else
				best, best_entries = widget, entries
			end
			break
		else
			widget.htmlbox_widget:free()
			spills_at = entries
			if best then
				next_entries = math.floor((best_entries + entries) / 2)
				if next_entries <= best_entries then
					break
				end
			else
				next_entries = math.max(1, entries - step_down)
				if pages > 2 then
					next_entries = math.max(1, math.min(next_entries, math.floor(entries / pages)))
				end
				step_down = step_down * 2
			end
		end
		entries = next_entries
	end

	if not best then
		best_entries = 1
		local range_first, range_last = range(1)
		best = self:_buildHtmlWidget(range_first, range_last, height)
	end

	local best_first, best_last = range(best_entries)
	return best, best_first, best_last
end

-- Height left for the text once the header and the buttons are placed.
function DictionaryExplorerViewer:_getContentHeight()
	-- The header and the row of buttons never change height.
	if not self._content_height then
		self._content_height = self.dimen.h - self:_buildHeader(self.position, self.position):getSize().h - self:_buildButtons():getSize().h
	end
	local height = self._content_height - Screen:scaleBySize(GAP_BELOW_RULE)
	if #self.trail >= 2 then
		height = height - Breadcrumb.getHeight()
	end
	local notice = self:_getMissNotice()
	if notice then
		height = height - notice:getSize().h
	end
	return height
end

-- When the word asked for has no entry, the page around the closest one says
-- so in a line of its own above the entries. It is part of the page, drawn
-- with it, so it costs no refresh of its own (a notification would cost two:
-- showing it and taking it away); the next page or word takes it away.
-- The word the trail shows for a word that was looked up: the word asked for
-- when it only leads to the entry (through the .syn) or has none at all, the
-- entry's own otherwise.
function DictionaryExplorerViewer:_trailWord(lookup, position)
	if lookup and lookup.synonym then
		return lookup.synonym
	end
	if lookup and lookup.kind == "closest" then
		return lookup.word
	end
	return self.dictionary:getEntry(position).word
end

-- What the page says about a word that has no entry of its own here (nil when
-- it has). `crumb` is set to the trail item the word got, if it got one. A
-- word found in another dictionary than the one it was looked for in says
-- both (`from`, `found`: short names). Since every dictionary was asked (see
-- Library:resolve()), a word with nothing but a closest entry has none in
-- any of them.
function DictionaryExplorerViewer:_missFrom(lookup)
	if not lookup then
		return nil
	end
	local shown = lookup.kind == "accent" and self.dictionary:getEntry(lookup.position).word or nil
	if lookup.from and lookup.from ~= self.dictionary then
		return {
			word = lookup.word,
			shown = shown,
			from = self.lib:shortName(lookup.from),
			found = self.lib:shortName(self.dictionary),
		}
	end
	if lookup.kind ~= "exact" then
		return { word = lookup.word, shown = shown }
	end
end

-- See Library:closest().
function DictionaryExplorerViewer:_closestIn(dictionary, word)
	return self.lib:closest(dictionary, word)
end

function DictionaryExplorerViewer:_getMissNotice()
	local miss = self.miss
	if not miss then
		return nil
	end
	local key = table.concat({ miss.word, miss.shown or "", miss.from or "", miss.found or "" }, "\0")
	local cached = self._miss_notice
	if cached and cached.key == key then
		return cached.widget
	end
	if cached then
		cached.widget:free()
	end
	local margins = self.side_margins
	local widget = Notices.build(Notices.missText(miss), self.dimen.w - margins.left - margins.right, margins.left, Screen:scaleBySize(GAP_BELOW_RULE))
	self._miss_notice = { key = key, widget = widget }
	return widget
end

-- Whether a point is on the notice: between what is above it and the entries.
function DictionaryExplorerViewer:_isOnMissNotice(pos)
	local notice, area = self.miss_notice, self.html_widget and self.html_widget.dimen
	if not (notice and area) then
		return false
	end
	local top = area.y - Screen:scaleBySize(GAP_BELOW_RULE) - notice:getSize().h
	return pos.y >= top and pos.y < area.y
end

-- Shows a list of choices (see choicelist.lua), kept in self[field] while it
-- is shown: the dialog of the page shown, as pages turn.
function DictionaryExplorerViewer:_showList(field, title, rows)
	return ChoiceList.show({
		title = title,
		rows = rows,
		on_show = function(dialog)
			self[field] = dialog
		end,
		on_close = function(dialog)
			if self[field] == dialog then
				self[field] = nil
			end
		end,
	})
end

-- Closes the list in self[field] because a choice was made in it.
function DictionaryExplorerViewer:_closeListForChoice(field)
	if self[field] then
		ChoiceList.closeForChoice(self[field])
	end
end

-- Rows of a list, one per word, out of entries found in one dictionary or
-- another ({ dictionary =, entry =, position =, trail = } each, in the order
-- to show them: `entry` the headword shown, `position` where it is, `trail`
-- the word the breadcrumb is to show, the word of the .syn that led to it if
-- one did): a word found in several dictionaries is one row, which names them
-- by their short names ("sofa · EN-PT, EN") when the list has more than one
-- dictionary. Choosing a row calls choose(found) with the entry of the first
-- dictionary that has it (in the order given), as found: its position, not
-- its headword looked for again, which could be another entry (a homograph).
function DictionaryExplorerViewer:_groupedRows(entries, choose)
	local groups, by_word, dictionaries = {}, {}, {}
	for _index, found in ipairs(entries) do
		local group = by_word[found.entry]
		if not group then
			group = { word = found.entry, dictionaries = {}, seen = {} }
			by_word[found.entry] = group
			groups[#groups + 1] = group
		end
		if not group.seen[found.dictionary] then
			group.seen[found.dictionary] = true
			group.dictionaries[#group.dictionaries + 1] = found.dictionary
			group.found = group.found or found
		end
		dictionaries[found.dictionary] = true
	end
	local several = next(dictionaries) ~= nil and next(dictionaries, (next(dictionaries))) ~= nil
	local names = several and self.lib:shortNames() or {}
	local rows = {}
	for _index, group in ipairs(groups) do
		local label = group.word
		if several then
			local tags = {}
			for _index2, dictionary in ipairs(group.dictionaries) do
				tags[#tags + 1] = names[dictionary] or self.lib:shortName(dictionary)
			end
			label = T("%1 · %2", group.word, table.concat(tags, ", "))
		end
		rows[#rows + 1] = {
			{
				text = label,
				callback = function()
					choose(group.found)
				end,
			},
		}
	end
	return rows
end

--- Offers, in a list, the entries a word with no entry may have been meant
-- for, one row per word (see _groupedRows()): its accented spellings here
-- and the entries around where it would be, then the entries closest to it
-- in each other dictionary. The list refreshes only its own area; choosing a word redraws
-- the page once, with the list gone, and the word takes the place of the
-- missed one in the trail.
function DictionaryExplorerViewer:showSuggestions()
	local miss = self.miss
	-- A word found in another dictionary needs none: the others that have it
	-- are a tap away in the header.
	if not miss or miss.from or self.suggestions_dialog then
		return
	end
	local entries = {}
	for _index, position in ipairs(self.dictionary:suggest(miss.word)) do
		entries[#entries + 1] = { dictionary = self.dictionary, entry = self.dictionary:getEntry(position).word, position = position }
	end
	for _index, dictionary in ipairs(self:_otherDictionaries()) do
		if dictionary:isIndexed() then
			for _index2, position in ipairs(self:_closestIn(dictionary, miss.word)) do
				entries[#entries + 1] = { dictionary = dictionary, entry = dictionary:getEntry(position).word, position = position }
			end
		end
	end
	local rows = self:_groupedRows(entries, function(found)
		self:_closeListForChoice("suggestions_dialog")
		self:_goToFound(found, true)
	end)
	if #rows > 0 then
		self:_showList("suggestions_dialog", T(_("Suggestions for “%1”"), Notices.cut(miss.word)), rows)
	end
end

-- Whether the trail is on the item of the word that has no entry, which a
-- suggestion then takes the place of.
function DictionaryExplorerViewer:_isOnMissedCrumb()
	return self.miss ~= nil and self.miss.crumb == self.trail_index
end

-- Adds a word to the trail, or puts it in place of the current item.
-- @treturn bool whether it is a new item of the trail
function DictionaryExplorerViewer:_placeInTrail(word, position, replace)
	if replace then
		Trail.replace(self.trail, self.trail_index, { word = word, position = position, dictionary = self.dictionary })
		return true
	end
	return self:_pushTrail(word, position)
end

-- Puts a finished page on screen: title bar and buttons for the range that
-- finally fitted, the margins around the text, and a repaint.
function DictionaryExplorerViewer:_installPage(html_widget, first, last, at_end)
	self.html_widget = html_widget
	self.first, self.last = first, last
	if at_end then
		html_widget:scrollToBottom()
	end

	local margins = self.side_margins
	self._header_holders = self:_holdersOf(first, last)
	self.header = self:_buildHeader(first, last)
	local children = { align = "left", self.header }
	-- The breadcrumb, once the user has started walking through words, sits
	-- between the header and the entries.
	self.breadcrumb = nil
	if #self.trail >= 2 then
		self.breadcrumb = self:_buildBreadcrumb()
		table.insert(children, self.breadcrumb)
	end
	self.miss_notice = self:_getMissNotice()
	if self.miss_notice then
		table.insert(children, self.miss_notice)
	end
	table.insert(children, VerticalSpan:new({ width = Screen:scaleBySize(GAP_BELOW_RULE) }))
	table.insert(children, HorizontalGroup:new({
		HorizontalSpan:new({ width = margins.left }),
		html_widget,
		HorizontalSpan:new({ width = margins.right - self:_getScrollChrome() }),
	}))
	table.insert(children, self:_buildButtons())
	self.column = VerticalGroup:new(children)
	self[1] = FrameContainer:new({
		width = self.dimen.w,
		height = self.dimen.h,
		background = Blitbuffer.COLOR_WHITE,
		bordersize = 0,
		padding = 0,
		self.column,
	})
	UIManager:setDirty(self, function()
		return "partial", self.dimen
	end)
	if self.on_explore then
		self.on_explore(self:explorationState())
	end
end

--- Where the exploration is, to continue it later: the dictionary and page it
-- is on, the highlighted entry, and the trail (see Trail.save()). Plain values
-- only, so it can be kept in the settings.
function DictionaryExplorerViewer:explorationState()
	local dictionary = self.dictionary
	local trail, trail_index, counts = Trail.save(self.trail, self.trail_index)
	counts[dictionary.name] = dictionary:getCount()
	return {
		dictionary = dictionary.name,
		count = dictionary:getCount(),
		counts = counts,
		first = self.first,
		first_word = dictionary:getEntry(self.first).word,
		highlighted = self.highlighted,
		word = self:_currentWord(),
		trail = trail,
		trail_index = trail_index,
	}
end

-- Reopens a saved exploration (see explorationState()) on the page it was on.
-- @treturn bool false when it doesn't fit this dictionary any more
function DictionaryExplorerViewer:_restore(state)
	local dictionary = self.dictionary
	local first = tonumber(state.first)
	local entry = first and dictionary:getEntry(first)
	if state.count ~= dictionary:getCount() or not entry or entry.word ~= state.first_word or type(state.trail) ~= "table" then
		return false
	end
	local trail, index = Trail.load(state.trail, state.trail_index, state.counts, dictionary, function(name)
		return self.lib:find(name)
	end, state.count)
	if not trail then
		return false
	end
	self.trail, self.trail_index = trail, index
	if self.trail_index < #trail then
		self.crumb_end = self.trail_index -- the current word in view in the breadcrumb
	end
	self.highlighted = tonumber(state.highlighted)
	self:showPage(first, self:_lastEntryFrom(first))
	return true
end

-- A word of the trail restored from a saved exploration: see Trail.check().
function DictionaryExplorerViewer:_checkCrumb(crumb)
	Trail.check(crumb)
end

-- Runs `callback` once `dictionary` can be read: at once for this one or one
-- whose index is ready, after preparing it (with a notice) otherwise.
function DictionaryExplorerViewer:_withDictionary(dictionary, callback)
	if dictionary == self.dictionary then
		callback()
	else
		self.lib:prepare(dictionary, callback)
	end
end

-- Makes `dictionary` the one the viewer shows, at `position`. What was kept
-- for the other one is let go of; the fit model is the new one's own.
function DictionaryExplorerViewer:_switchDictionary(dictionary, position)
	if dictionary == self.dictionary then
		return
	end
	self:_freeContent()
	self.dictionary:releaseCaches()
	self.dictionary = dictionary
	self.position = position
	self.highlighted = nil
	self.fit_model = nil
end

--- Shows entries first..last as one page, rebuilding the whole screen.
-- `first` and `last` are where the fitting starts from; the page shown may
-- have more or fewer entries (see _fitPage).
-- @bool keep_last the page must end at `last` (used when paging backwards)
-- @bool at_end scroll to the end of the page (used when paging back by scrolling)
function DictionaryExplorerViewer:showPage(first, last, keep_last, at_end)
	self:_freeContent()
	self.miss = nil -- turning the page leaves the word behind

	local range, max_entries
	if keep_last then
		max_entries = last + 1
		range = function(entries)
			return last - entries + 1, last
		end
	else
		max_entries = self.dictionary:getCount() - first
		range = function(entries)
			return first, first + entries - 1
		end
	end
	local html_widget
	html_widget, first, last = self:_withEntryCache(function()
		return self:_fitPage(range, last - first + 1, max_entries, self:_getContentHeight())
	end)
	self:_installPage(html_widget, first, last, at_end)
end

-- Runs `fit`, which lays a page out over and over, with what it reads kept:
-- the definitions file is opened once and each entry's HTML is read once.
function DictionaryExplorerViewer:_withEntryCache(fit)
	self.dictionary:beginReading()
	self._html_cache = {}
	local ok, widget, first, last = pcall(fit)
	self._html_cache = nil
	self.dictionary:endReading()
	if not ok then
		error(widget, 0)
	end
	return widget, first, last
end

-- Runs of entries around `target`, growing one entry at a time on whichever
-- side has the least text so far (by estimate), so the target stays near the
-- middle. Returns a function giving the run with a given number of entries,
-- how many entries there can be at most, and how many are estimated to fit.
function DictionaryExplorerViewer:_aroundRanges(target)
	local dictionary = self.dictionary
	local budget = AIM_AT * self:_getContentHeight()
	local first, last = target, target
	local before_cost, after_cost = 0, 0
	local total = self:_entryCost(dictionary:getEntry(target))
	local runs = { { first, last } }
	local fitting = 1
	-- The prediction is rough, so keep going well past one screen's worth: the
	-- real layout decides where to stop.
	while total <= 2 * budget do
		local can_go_before, can_go_after = first > 0, last < dictionary:getCount() - 1
		if not (can_go_before or can_go_after) then
			break
		end
		local take_before = can_go_before and (not can_go_after or before_cost < after_cost)
		local cost
		if take_before then
			cost = self:_entryCost(dictionary:getEntry(first - 1), dictionary:getEntry(first))
			first = first - 1
			before_cost = before_cost + cost
		else
			cost = self:_entryCost(dictionary:getEntry(last + 1), dictionary:getEntry(last))
			last = last + 1
			after_cost = after_cost + cost
		end
		total = total + cost
		runs[#runs + 1] = { first, last }
		if total <= budget then
			fitting = #runs
		end
	end
	return function(entries)
		return runs[entries][1], runs[entries][2]
	end, #runs, fitting
end

-- The balanced growth in _aroundRanges stops as soon as the entry on one side
-- doesn't fit, even if entries on the other side still would. When that
-- leaves a lot of the screen empty, keep adding entries, on the side with
-- fewer of them first, until nothing else fits.
function DictionaryExplorerViewer:_fillRemaining(widget, first, last, height)
	local count = self.dictionary:getCount()
	local blocked = {}
	for _attempt = 1, MAX_FILL_ATTEMPTS do
		local used = widget.htmlbox_widget:getSinglePageHeight()
		if not used or used >= FILL_BELOW * height then
			break
		end
		local before_open = first > 0 and not blocked.before
		local after_open = last < count - 1 and not blocked.after
		if not (before_open or after_open) then
			break
		end
		local side = "after"
		if before_open and (not after_open or self.highlighted - first <= last - self.highlighted) then
			side = "before"
		end
		local candidate_first = side == "before" and first - 1 or first
		local candidate_last = side == "after" and last + 1 or last
		local added, neighbour = candidate_last, last
		if side == "before" then
			added, neighbour = candidate_first, first
		end
		if
			self:_entryCost(self.dictionary:getEntry(added), self.dictionary:getEntry(neighbour))
			> (height - used) * SKIP_MARGIN
		then
			blocked[side] = true -- predicted not to fit: no need to lay it out to find out
		else
			local candidate = self:_buildHtmlWidget(candidate_first, candidate_last, height)
			if candidate.htmlbox_widget.page_count <= 1 then
				widget.htmlbox_widget:free()
				widget, first, last = candidate, candidate_first, candidate_last
				local shown = widget.htmlbox_widget:getSinglePageHeight() or height
				self:_getFitModel():add(widget.fit_groups, widget.fit_bytes, shown - widget.fit_extra)
			else
				candidate.htmlbox_widget:free()
				blocked[side] = true
			end
		end
	end
	return widget, first, last
end

--- Shows a page with entry `target` in the middle, highlighted.
function DictionaryExplorerViewer:showAround(target)
	self:_freeContent()
	self.highlighted = target
	local height = self:_getContentHeight()
	local html_widget, first, last = self:_withEntryCache(function()
		local range, max_entries, fitting = self:_aroundRanges(target)
		local widget, fitted_first, fitted_last = self:_fitPage(range, fitting, max_entries, height)
		return self:_fillRemaining(widget, fitted_first, fitted_last, height)
	end)
	self:_installPage(html_widget, first, last)
end

-- The breadcrumb shows the trail's words; when the trail goes through more
-- than one dictionary, each with its dictionary's short name ("house · EN-PT
-- › casa · PT"), since the viewer goes from one to the other by itself.
function DictionaryExplorerViewer:_buildBreadcrumb()
	local shown = self.trail
	local crossing = false
	for _index, crumb in ipairs(self.trail) do
		crossing = crossing or crumb.dictionary ~= self.trail[1].dictionary
	end
	if crossing then
		local names = self.lib:shortNames()
		shown = {}
		for index, crumb in ipairs(self.trail) do
			shown[index] = { word = T("%1 · %2", crumb.word, names[crumb.dictionary] or self.lib:shortName(crumb.dictionary)) }
		end
	end
	return Breadcrumb:new({
		trail = shown,
		current_index = self.trail_index,
		width = self.dimen.w,
		end_index = self.crumb_end,
		on_select = function(index)
			self:goToCrumb(index)
		end,
		on_scroll = function(end_index)
			self.crumb_end = end_index
			self:_refreshBreadcrumb()
		end,
	})
end

-- Redraws just the breadcrumb, after the user scrolled it.
function DictionaryExplorerViewer:_refreshBreadcrumb()
	local old = self.breadcrumb
	if not old then
		return
	end
	local replacement = self:_buildBreadcrumb()
	for index, child in ipairs(self.column) do
		if child == old then
			self.column[index] = replacement
			break
		end
	end
	self.breadcrumb = replacement
	self.column:resetLayout()
	UIManager:setDirty(self, function()
		return "ui", old.dimen
	end)
	old:free()
end

-- Adds a word to the trail (see Trail.push()).
-- @treturn bool whether the word was added (it isn't when it is the entry the
-- trail is on already)
function DictionaryExplorerViewer:_pushTrail(word, position)
	local added
	self.trail_index, added = Trail.push(self.trail, self.trail_index, { word = word, position = position, dictionary = self.dictionary })
	if added then
		self.crumb_end = nil -- show the latest words again
	end
	return added
end

--- Goes to a word of the trail, leaving the trail as it is. A word of another
-- dictionary takes the viewer there.
function DictionaryExplorerViewer:goToCrumb(index)
	local crumb = self.trail[index]
	if not crumb then
		return
	end
	self:_withDictionary(crumb.dictionary, function()
		self:_checkCrumb(crumb)
		self.miss = nil
		self.trail_index = index
		self:_switchDictionary(crumb.dictionary, crumb.position)
		self:showAround(crumb.position)
	end)
end

--- Shows the page that starts at entry `position` (0-based).
function DictionaryExplorerViewer:goToPosition(position)
	if position < 0 or position >= self.dictionary:getCount() then
		return false
	end
	self:showPage(position, self:_lastEntryFrom(position))
	return true
end

function DictionaryExplorerViewer:showNext()
	if self.last >= self.dictionary:getCount() - 1 then
		return false
	end
	return self:goToPosition(self.last + 1)
end

--- Shows the page before the current one.
-- @bool at_end land at the bottom of it, like paging back through a book
function DictionaryExplorerViewer:showPrevious(at_end)
	if self.first <= 0 then
		return false
	end
	local last = self.first - 1
	self:showPage(self:_firstEntryUntil(last), last, true, at_end)
	return true
end

--- Goes to a word as if all the dictionaries were one (see Library:resolve()):
-- to its entry here, or in the dictionary that has it, saying so. The word
-- selected and gone to from the dock, a link tapped in an entry.
function DictionaryExplorerViewer:goToWord(word)
	word = util.trim(word or "")
	if word == "" then
		return
	end
	self:_goToLookup(self.lib:resolve(word, self.dictionary))
end

--- Jumps to a word in a given dictionary, which becomes the one shown (a
-- dictionary chosen in a list): the trail goes on through it, so going back
-- returns to the dictionary before.
-- @bool instead_of_missed the word takes the place, in the trail, of the word
-- with no entry the page is on (when it was found elsewhere)
function DictionaryExplorerViewer:goToWordIn(dictionary, word, instead_of_missed)
	word = util.trim(word or "")
	if word == "" then
		return
	end
	local replacing = instead_of_missed and self:_isOnMissedCrumb()
	self:_withDictionary(dictionary, function()
		local lookup = dictionary:resolve(word)
		lookup.dictionary = dictionary
		self:_goToLookup(lookup, replacing)
	end)
end

-- Goes to the entry a list row found (see _groupedRows()): its dictionary
-- and position as found, its word of the .syn in the trail.
function DictionaryExplorerViewer:_goToFound(found, instead_of_missed)
	local replacing = instead_of_missed and self:_isOnMissedCrumb()
	self:_withDictionary(found.dictionary, function()
		local entry = found.dictionary:getEntry(found.position).word
		self:_goToLookup({
			dictionary = found.dictionary,
			position = found.position,
			kind = "exact",
			word = found.trail or entry,
			synonym = found.trail ~= entry and found.trail or nil,
		}, replacing)
	end)
end

-- Shows what a lookup found (see Library:resolve()), in its dictionary.
function DictionaryExplorerViewer:_goToLookup(lookup, replacing)
	self:_switchDictionary(lookup.dictionary, lookup.position)
	self.miss = self:_missFrom(lookup) -- said on the page itself, see _getMissNotice
	if self:_placeInTrail(self:_trailWord(lookup, lookup.position), lookup.position, replacing) and self.miss then
		self.miss.crumb = self.trail_index -- the crumb a suggestion will take the place of
	end
	self:showAround(lookup.position)
end

-- The dictionaries that have the highlighted word, this one among them, when
-- it is on the page first..last (nil otherwise): see Library:holders(). Asked
-- once per entry, so turning pages costs nothing.
function DictionaryExplorerViewer:_holdersOf(first, last)
	local highlighted = self.highlighted
	if not (highlighted and highlighted >= first and highlighted <= last and self.lib:hasProvider()) then
		return nil
	end
	self._holders_cache = self._holders_cache or {}
	local key = self.dictionary.name .. "\0" .. highlighted
	if self._holders_cache[key] == nil then
		self._holders_cache[key] = self.lib:holders(self.dictionary:getEntry(highlighted).word, self.dictionary)
	end
	return self._holders_cache[key]
end

--- Goes to the word the page is about in the next dictionary that has it
-- (KOReader's order, from the last back to the first): the same word, so it
-- takes the place of the current item of the trail rather than adding one.
function DictionaryExplorerViewer:showNextDictionary()
	self:_stepDictionary(1)
end

--- The same, to the previous dictionary that has the word (from the first
-- back to the last).
function DictionaryExplorerViewer:showPreviousDictionary()
	self:_stepDictionary(-1)
end

function DictionaryExplorerViewer:_stepDictionary(step)
	local holders = self._header_holders
	if not (holders and #holders > 1) then
		return
	end
	local index = 1
	for position, holder in ipairs(holders) do
		if holder.dictionary == self.dictionary then
			index = position
		end
	end
	local next_holder = holders[(index - 1 + step) % #holders + 1]
	local crumb = self.trail[self.trail_index]
	self:_withDictionary(next_holder.dictionary, function()
		self.miss = nil
		self:_switchDictionary(next_holder.dictionary, next_holder.position)
		Trail.replace(self.trail, self.trail_index, { word = crumb.word, position = next_holder.position, dictionary = next_holder.dictionary })
		self:showAround(next_holder.position)
	end)
end

-- The word the page is about: the highlighted entry when it is on the page,
-- the first one otherwise.
function DictionaryExplorerViewer:_currentWord()
	local highlighted = self.highlighted
	local on_page = highlighted and highlighted >= self.first and highlighted <= self.last
	return self.dictionary:getEntry(on_page and highlighted or self.first).word
end

-- The dictionaries other than this one to offer, in KOReader's order.
function DictionaryExplorerViewer:_otherDictionaries()
	return self.lib:others(self.dictionary)
end

--- Offers the other dictionaries that have `word`, in a list: an English word
-- of a bilingual dictionary looked up in a Portuguese one, for one. Only the
-- dictionaries that have an entry for it are listed (also through another
-- case, the .syn or its accents), with that entry when it is spelled
-- otherwise; a dictionary whose index was never prepared can't be asked, so
-- it is listed as such.
function DictionaryExplorerViewer:showOtherDictionaries(word)
	word = util.trim(word or "")
	if word == "" or self.dictionaries_dialog then
		return
	end
	local rows = {}
	local names = self.lib:shortNames()
	for _index, dictionary in ipairs(self:_otherDictionaries()) do
		local label
		if dictionary:isIndexed() then
			local lookup = dictionary:resolve(word)
			if lookup.kind ~= "closest" then
				-- As in every list: the word, then the dictionary's short name.
				label = T("%1 · %2", dictionary:getEntry(lookup.position).word, names[dictionary] or self.lib:shortName(dictionary))
			end
		else
			label = T(_("%1 (index not prepared yet)"), dictionary.name)
		end
		if label then
			rows[#rows + 1] = {
				{
					text = label,
					callback = function()
						self:_closeListForChoice("dictionaries_dialog")
						self:goToWordIn(dictionary, word)
					end,
				},
			}
		end
	end
	if #rows == 0 then
		UIManager:show(InfoMessage:new({ text = T(_("No other dictionary has “%1”."), Notices.cut(word)) }))
		return
	end
	self:_showList("dictionaries_dialog", T(_("“%1” in other dictionaries"), Notices.cut(word)), rows)
end

function DictionaryExplorerViewer:_anyFound(known)
	return Library.anyFound(known)
end

--- What the other dictionaries say about a selected word, for the dock to
-- offer its button only when there is somewhere to go. It must be quick (it
-- runs between the finger lifting and the dock being drawn): see
-- Library:quick(). A selection comes from the text, spelled right, so the
-- search for accents is left out.
-- @treturn table { [dictionary] = its entry for the word, or false }
-- @treturn bool whether a dictionary not loaded yet might have it
function DictionaryExplorerViewer:_checkSelection(word)
	return self.lib:quick(word, self.dictionary)
end

-- Un-highlights the text the user selected.
function DictionaryExplorerViewer:_clearSelection()
	local htmlbox = self.html_widget and self.html_widget.htmlbox_widget
	if htmlbox and htmlbox:clearHighlight() then
		htmlbox:redrawHighlight()
	end
end

function DictionaryExplorerViewer:_closeSelectionDock()
	local dock = self.selection_dock
	if dock then
		self.selection_dock = nil
		UIManager:close(dock)
	end
end

-- A text button for the selection dock: as tall as the other docks' buttons and
-- as wide as its label plus DOCK_TEXT_SIDE_PADDING on each side (ButtonTable
-- ignores a button's own padding, so the width is set outright).
local function dockButton(text, callback)
	local label = TextWidget:new({ text = text, face = Font:getFace("cfont", 20), bold = true })
	local label_width = label:getSize().w
	label:free()
	return {
		text = text,
		callback = callback,
		height = Dock.BUTTON_HEIGHT,
		width = label_width + 2 * Screen:scaleBySize(DOCK_TEXT_SIDE_PADDING),
	}
end

-- An icon-only button for the selection dock, as wide as the other docks' icon
-- buttons. Holding it says what it does.
local function dockIconButton(icon, hint, callback)
	local icon_size = Screen:scaleBySize(DOCK_ICON_SIZE)
	return {
		icon = icon,
		icon_width = icon_size,
		icon_height = icon_size,
		callback = callback,
		hold_callback = function()
			UIManager:show(InfoMessage:new({ text = hint, timeout = 3 }))
		end,
		height = Dock.BUTTON_HEIGHT,
		width = Dock.BUTTON_HEIGHT + 2 * Dock.BUTTON_SIDE_PADDING,
	}
end

-- The vocabulary builder's database, when KOReader's builder is active (it is
-- loaded along with the plugin, so it is looked up, not loaded).
function DictionaryExplorerViewer:_vocabularyDb()
	local db = package.loaded["db"]
	if self.ui and self.ui.vocabbuilder and type(db) == "table" and db.hasWord and db.remove then
		return db
	end
end

--- Adds a word to KOReader's vocabulary builder, if it is active, the way its
-- "Add to vocabulary builder" dictionary button does: by telling it a word was
-- looked up by hand. It says so itself when the word is already there.
function DictionaryExplorerViewer:addToVocabulary(word)
	local db = self:_vocabularyDb()
	if not db then
		return false
	end
	local ui = self.ui
	local known = db:hasWord(word)
	local title = ui.doc_props and ui.doc_props.display_title or _("Dictionary lookup")
	-- The builder stores the book's own selection as the word's context; that
	-- selection is not this word, so hide it while the builder looks.
	local highlight = ui.highlight
	local book_selection = highlight and highlight.selected_text
	if highlight then
		highlight.selected_text = nil
	end
	local ok, err = pcall(ui.handleEvent, ui, Event:new("WordLookedUp", word, title, true)) -- true: added by hand
	if highlight then
		highlight.selected_text = book_selection
	end
	if not ok then
		error(err, 0)
	end
	if not known then
		Notification:notify(_("Added to vocabulary builder."))
	end
	return true
end

--- Removes a word from the vocabulary builder after asking, like the builder's
-- own dictionary button does.
function DictionaryExplorerViewer:removeFromVocabulary(word)
	local db = self:_vocabularyDb()
	if not db then
		return false
	end
	UIManager:show(ConfirmBox:new({
		text = T(_("Remove word \"%1\" from vocabulary builder?"), word),
		ok_text = _("Remove"),
		ok_callback = function()
			db:remove({ word = word })
			Notification:notify(_("Removed from vocabulary builder."))
		end,
	}))
	return true
end

-- Text selected with a long press: offer to jump to it in the dictionary, or to
-- copy it, in a dock next to the selection that looks like the selection
-- toolbar's. It sits centred below the selection,
-- or above it when there is no room below inside the text.
function DictionaryExplorerViewer:onTextSelected(text)
	local htmlbox = self.html_widget and self.html_widget.htmlbox_widget
	local rects = htmlbox and htmlbox.highlight_rects
	-- Punctuation next to the words ("casa,") isn't part of what to look up.
	local selected = (text or ""):gsub("^[%s%p]+", ""):gsub("[%s%p]+$", "")
	if not (rects and #rects > 0) or selected == "" then
		return
	end

	-- Bounding box of the selection, in screen coordinates.
	local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
	for _index, rect in ipairs(rects) do
		left, top = math.min(left, rect.x), math.min(top, rect.y)
		right, bottom = math.max(right, rect.x + rect.w), math.max(bottom, rect.y + rect.h)
	end
	left, right = left + htmlbox.dimen.x, right + htmlbox.dimen.x
	top, bottom = top + htmlbox.dimen.y, bottom + htmlbox.dimen.y
	local text_bottom = htmlbox.dimen.y + htmlbox.dimen.h

	-- Left to right: the vocabulary builder (one word only, and only when
	-- there is a builder), Copy, Go to word.
	local row = {}
	local db = not selected:find("%s") and self:_vocabularyDb()
	if db then
		-- If the word is in the builder already, the same button takes it out.
		local known = db:hasWord(selected)
		table.insert(row, dockIconButton(
			Dock.iconPath(known and "remove_word" or "add_word"),
			known and _("Remove from vocabulary builder") or _("Add to vocabulary builder"),
			function()
				self:_closeSelectionDock()
				self:_clearSelection()
				if known then
					self:removeFromVocabulary(selected)
				else
					self:addToVocabulary(selected)
				end
			end
		))
	end
	local copied = util.cleanupSelectedText(text)
	table.insert(row, dockButton(_("Copy"), function()
		self:_closeSelectionDock()
		self:_clearSelection()
		Device.input.setClipboardText(copied)
		Notification:notify(_("Selection copied to clipboard."))
	end))
	table.insert(row, dockButton(_("Go to word"), function()
		self:_closeSelectionDock()
		self:goToWord(selected)
	end))

	self:_closeSelectionDock()
	local show_shadow = Dock.showShadow()
	local gap = Size.padding.large
	-- The buttons, the rules between them, and the dialog's frame.
	local dock_width = (#row - 1) * Size.line.medium + 2 * Size.border.window + 2 * Size.padding.button
	for _index, button in ipairs(row) do
		dock_width = dock_width + button.width
	end
	local dock
	dock = Dock.ShadowedButtonDialog:new({
		buttons = { row },
		width = math.min(dock_width, Screen:getWidth() - 2 * gap - (show_shadow and Dock.SHADOW_EXTENT or 0)),
		show_shadow = show_shadow,
		dismissable = true,
		anchor = function()
			local dock_size = dock:getContentSize()
			local anchor_x = math.floor((left + right) / 2 - dock_size.w / 2)
			if anchor_x < gap then
				anchor_x = gap
			elseif anchor_x + dock_size.w > Screen:getWidth() - gap then
				anchor_x = Screen:getWidth() - dock_size.w - gap
			end
			if text_bottom - (bottom + gap) >= dock_size.h then
				return Geom:new({ x = anchor_x, y = bottom + gap, w = 0, h = 0 }), true
			end
			return Geom:new({ x = anchor_x, y = top - gap, w = 0, h = 0 }), false
		end,
		tap_close_callback = function()
			self.selection_dock = nil
			self:_clearSelection()
		end,
	})
	self.selection_dock = dock
	UIManager:show(dock, "[ui]")
end

--- Asks for a word to look for in every dictionary (see searchAll()).
function DictionaryExplorerViewer:showGoToDialog()
	local count = 1 + #self:_otherDictionaries()
	local dialog
	dialog = InputDialog:new({
		title = _("Search all dictionaries"),
		description = T(_("Looks for the word in every dictionary (%1), this one first, and lists what each one has."), count),
		input_hint = _("Word"),
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
					text = _("Search"),
					is_enter_default = true,
					callback = function()
						local word = dialog:getInputText()
						UIManager:close(dialog)
						self:searchAll(word)
					end,
				},
			},
		},
	})
	UIManager:show(dialog)
	dialog:onShowKeyboard()
end

--- Looks for a word in every dictionary, this one first, and lists what each
-- one has (the entry, also through another case, the .syn or the accents),
-- one row per word with the dictionaries that have it (see _groupedRows()),
-- six at a time: choosing one goes there, in the first of them (this one if
-- it has it); the header's "· 1/3 ›" then goes to the others. A dictionary
-- whose index was never prepared can't be asked, so it is listed as such,
-- and choosing it prepares it first. When none has the word, the list has
-- the entries closest to it: this dictionary's suggestions, then the others'.
function DictionaryExplorerViewer:searchAll(word)
	word = util.trim(word or "")
	if word == "" or self.search_dialog then
		return
	end
	local dictionaries = { self.dictionary }
	for _index, dictionary in ipairs(self:_otherDictionaries()) do
		dictionaries[#dictionaries + 1] = dictionary
	end
	local function choose(found)
		self:_closeListForChoice("search_dialog")
		self:_goToFound(found)
	end
	local entries, unprepared = {}, {}
	for _index, dictionary in ipairs(dictionaries) do
		if dictionary == self.dictionary or dictionary:isIndexed() then
			local lookup = dictionary:resolve(word)
			if lookup.kind ~= "closest" then
				entries[#entries + 1] = {
					dictionary = dictionary,
					entry = dictionary:getEntry(lookup.position).word,
					position = lookup.position,
					trail = lookup.synonym,
				}
			end
		else
			unprepared[#unprepared + 1] = {
				{
					text = T(_("%1 (index not prepared yet)"), dictionary.name),
					callback = function()
						-- Not asked yet: once prepared, the word is looked for there.
						self:_closeListForChoice("search_dialog")
						self:goToWordIn(dictionary, word)
					end,
				},
			}
		end
	end
	local title = T(_("Results for “%1”"), Notices.cut(word))
	if #entries == 0 then
		-- Nothing has it: what is spelled most like it, here and elsewhere.
		title = T(_("No entry for “%1”: the closest ones"), Notices.cut(word))
		for _index, position in ipairs(self.dictionary:suggest(word)) do
			entries[#entries + 1] = { dictionary = self.dictionary, entry = self.dictionary:getEntry(position).word, position = position }
		end
		for index = 2, #dictionaries do
			local dictionary = dictionaries[index]
			if dictionary:isIndexed() then
				for _index, position in ipairs(self:_closestIn(dictionary, word)) do
					entries[#entries + 1] = { dictionary = dictionary, entry = dictionary:getEntry(position).word, position = position }
				end
			end
		end
	end
	local rows = self:_groupedRows(entries, choose)
	for _index, row in ipairs(unprepared) do
		rows[#rows + 1] = row
	end
	if #rows == 0 then
		UIManager:show(InfoMessage:new({ text = T(_("Nothing found for “%1”."), Notices.cut(word)) }))
		return
	end
	self:_showList("search_dialog", title, rows)
end

-- Dictionary links are either "bword://word" or just the word.
function DictionaryExplorerViewer:onLinkTapped(link)
	local uri = link and link.uri
	if not uri then
		return
	end
	local prefix = "bword://"
	local word
	if uri:sub(1, #prefix) == prefix then
		word = uri:sub(#prefix + 1)
	elseif not uri:find("://", 1, true) then
		word = uri
	end
	if word then
		self:goToWord(word)
	end
end

-- Page-turn keys and taps scroll the page, and carry on into the neighbouring
-- page once this one is exhausted, like turning pages in a book.
function DictionaryExplorerViewer:onScrollDown()
	if not self.html_widget:onScrollDown() then
		self:showNext()
	end
	return true
end

function DictionaryExplorerViewer:onScrollUp()
	if not self.html_widget:onScrollUp() then
		self:showPrevious(true)
	end
	return true
end

-- The text area, including the side margins that ScrollHtmlWidget doesn't cover.
function DictionaryExplorerViewer:_isInTextBand(pos)
	local area = self.html_widget and self.html_widget.dimen
	return area and pos.y >= area.y and pos.y < area.y + area.h
end

-- Taps on the left/right half turn the page. ScrollHtmlWidget takes the taps
-- it can scroll for itself; the ones it leaves alone, and those in the side
-- margins, get here.
function DictionaryExplorerViewer:onTap(_arg, ges)
	if self:_isOnMissNotice(ges.pos) then
		self:showSuggestions() -- nothing when the line only says where the word was found
		return true
	end
	-- The header, at the top: the dictionary's name goes to the word in the
	-- next dictionary that has it ("‹ 1/3 ›"), its left half to the previous
	-- one (as taps on the text turn pages); the rest lists them.
	if self.header and ges.pos.y < self.header:getSize().h and #self:_otherDictionaries() > 0 then
		local band = self._name_band
		if self.header_mark and band and ges.pos.y >= band.top and ges.pos.y < band.bottom then
			if BD.flipIfMirroredUILayout(ges.pos.x < Screen:getWidth() / 2) then
				self:showPreviousDictionary()
			else
				self:showNextDictionary()
			end
		else
			self:showOtherDictionaries(self:_currentWord())
		end
		return true
	end
	if not self:_isInTextBand(ges.pos) then
		return false
	end
	if BD.flipIfMirroredUILayout(ges.pos.x < Screen:getWidth() / 2) then
		return self:onScrollUp()
	end
	return self:onScrollDown()
end

function DictionaryExplorerViewer:onSwipe(_arg, ges)
	if not self:_isInTextBand(ges.pos) then
		return false
	end
	local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
	if direction == "west" then
		self:showNext()
		return true
	elseif direction == "east" then
		self:showPrevious()
		return true
	end
	return false
end

function DictionaryExplorerViewer:onClose()
	UIManager:close(self, "full")
	return true
end

function DictionaryExplorerViewer:onCloseWidget()
	for _index, field in ipairs({ "suggestions_dialog", "dictionaries_dialog", "search_dialog" }) do
		if self[field] then
			UIManager:close(self[field])
		end
	end
	self:_freeContent()
	if self._miss_notice then
		self._miss_notice.widget:free()
		self._miss_notice = nil
	end
	self.dictionary:releaseCaches()
end

return DictionaryExplorerViewer
