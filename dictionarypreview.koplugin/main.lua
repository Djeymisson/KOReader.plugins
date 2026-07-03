local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local IconWidget = require("ui/widget/iconwidget")
local TextWidget = require("ui/widget/textwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Size = require("ui/size")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Event = require("ui/event")
local util = require("util")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local Notification = require("ui/widget/notification")
local _ = require("gettext")

local Screen = Device.screen

local DictionaryPreview = WidgetContainer:extend({
	name = "dictionarypreview",
	is_doc_only = true,
})

-- UI constants ---------------------------------------------------------------

local UI_FONT_FACE = "Noto Sans"
local UI_FONT_SIZE = 20
local KOREADER_ICON_SIZE = Screen:scaleBySize(28)

local ICON_SEARCH = "appbar.search"
local ICON_PREVIOUS = "chevron.left"
local ICON_NEXT = "chevron.right"
local ICON_DETAILS = "chevron.up"
local ICON_HIGHLIGHT = "dictionarypreview.highlight"
local ICON_WIKIPEDIA = "dictionarypreview.wikipedia"

local PANEL_MAX_HEIGHT_RATIO = 0.38
local MIN_CONTENT_WIDTH = Screen:scaleBySize(120)

local SETTING_ENABLED = "dictionarypreview_enabled"
local SETTING_LEFT_ACTION = "dictionarypreview_left_action"

local LEFT_ACTION_HIGHLIGHT = "highlight"
local LEFT_ACTION_SEARCH_BOOK = "search_book"
local LEFT_ACTION_WIKIPEDIA = "wikipedia"
local DEFAULT_LEFT_ACTION = LEFT_ACTION_SEARCH_BOOK

local LEFT_ACTIONS = {
	{ id = LEFT_ACTION_HIGHLIGHT, label = _("Highlight"), icon = ICON_HIGHLIGHT },
	{ id = LEFT_ACTION_SEARCH_BOOK, label = _("Fulltext search"), icon = ICON_SEARCH },
	{ id = LEFT_ACTION_WIKIPEDIA, label = _("Wikipedia"), icon = ICON_WIKIPEDIA },
}

local LEFT_ACTION_BY_ID = {}
for _, action in ipairs(LEFT_ACTIONS) do
	LEFT_ACTION_BY_ID[action.id] = action
end

local PLUGIN_ICON_EXTENSIONS = { ".svg", ".png" }
local PLUGIN_LEFT_ICON_CANDIDATES = {
	[LEFT_ACTION_HIGHLIGHT] = { "highlight", "dictionarypreview.highlight" },
	[LEFT_ACTION_WIKIPEDIA] = { "wikipedia", "dictionarypreview.wikipedia" },
}

-- Small helpers --------------------------------------------------------------

local function trim(text)
	return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function fileExists(path)
	if not path or path == "" then
		return false
	end

	local file = io.open(path, "rb")
	if file then
		file:close()
		return true
	end

	return false
end

local function copyTable(value, seen)
	if type(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local copy = {}
	seen[value] = copy

	for key, item in pairs(value) do
		copy[copyTable(key, seen)] = copyTable(item, seen)
	end

	return copy
end

local function htmlEscape(text)
	text = tostring(text or "")
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	text = text:gsub('"', "&quot;")
	return text
end

local function looksLikeHtml(text)
	return tostring(text or ""):find("<%s*[%a/][^>]*>") ~= nil
end

local function plainTextToHtml(text)
	text = htmlEscape(text)
	text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	text = text:gsub("\n\n+", "</p><p>"):gsub("\n", "<br/>")
	return "<p>" .. text .. "</p>"
end

local function normalizeDictionaryHtml(definition)
	definition = tostring(definition or "")

	if definition == "" then
		return "<p>" .. htmlEscape(_("No definition.")) .. "</p>"
	end

	if looksLikeHtml(definition) then
		return definition
	end

	return plainTextToHtml(definition)
end

local function appendStyleAttr(attrs, style)
	attrs = attrs or ""

	if attrs:find("style%s*=") then
		return attrs:gsub('style%s*=%s*"([^"]*)"', 'style="%1; ' .. style .. '"', 1)
	end

	return attrs .. ' style="' .. style .. '"'
end

-- Fallback HTML normalization ------------------------------------------------
-- Used only when a dictionary result does not provide its own CSS. Some
-- dictionaries use heading tags for long grammatical forms; without CSS these
-- headings become too large in the preview panel.

local dictionary_class_styles = {
	hw = "font-size:1.15em; font-weight:bold;",
	ctx = "font-size:0.85em; font-style:italic;",
	pron = "font-size:0.9em;",
	gr = "font-size:0.85em; font-style:italic;",
	use = "font-size:0.85em; font-style:italic;",
	ge = "font-size:0.85em; font-style:italic;",
	la = "font-size:0.85em; font-style:italic;",
	d = "font-size:0.85em;",
	num = "font-size:0.95em; font-weight:bold;",
	rm = "font-size:1em; font-weight:bold;",
	s1 = "display:block; margin:0.15em 0 0.35em 0;",
	ib = "display:block; margin:0.25em 0 0.45em 0.8em; font-size:0.92em;",
	ql = "display:inline;",
	q = "display:inline;",
	a = "font-size:0.9em; font-weight:bold;",
	w = "font-size:0.9em; font-style:italic;",
	phg = "display:block; margin-top:0.6em; font-size:0.95em;",
	sub = "display:block; margin-left:0.8em; margin-top:0.15em;",
	et = "display:block; margin-top:0.5em; font-size:0.92em;",
	xr = "font-style:italic;",
}

local function buildStyleFromClassList(classes)
	local style_parts = {}

	for class_name in tostring(classes or ""):gmatch("%S+") do
		if dictionary_class_styles[class_name] then
			table.insert(style_parts, dictionary_class_styles[class_name])
		end
	end

	if #style_parts == 0 then
		return nil
	end

	return table.concat(style_parts, " ")
end

local function normalizeHeadingTags(html)
	html = html:gsub("<%s*[hH][1-6]([^>]*)>", function(attrs)
		return "<div"
			.. appendStyleAttr(attrs, "font-size:1em; line-height:1.25; margin:0.35em 0 0.25em 0; font-weight:normal;")
			.. ">"
	end)

	return html:gsub("</%s*[hH][1-6]%s*>", "</div>")
end

local function normalizeDictionaryClasses(html)
	return html:gsub('(<%w+)([^>]-class%s*=%s*"([^"]*)"[^>]*)(>)', function(tag, attrs, classes, close)
		local style = buildStyleFromClassList(classes)
		if style then
			return tag .. appendStyleAttr(attrs, style) .. close
		end
		return tag .. attrs .. close
	end)
end

local function normalizeDictionaryLists(html)
	html = html:gsub("<%s*[uU][lL]([^>]*)>", function(attrs)
		return "<ul" .. appendStyleAttr(attrs, "margin:0.25em 0 0.35em 1.1em; padding:0;") .. ">"
	end)

	html = html:gsub("<%s*[oO][lL]([^>]*)>", function(attrs)
		return "<ol" .. appendStyleAttr(attrs, "margin:0.25em 0 0.35em 1.1em; padding:0;") .. ">"
	end)

	return html:gsub("<%s*[lL][iI]([^>]*)>", function(attrs)
		return "<li" .. appendStyleAttr(attrs, "margin:0.18em 0;") .. ">"
	end)
end

local function shouldNormalizeDictionaryPreviewHtml(html)
	return html:find("<%s*[hH][1-6]")
		or html:find('class%s*=%s*"hw"')
		or html:find('class%s*=%s*"pron"')
		or html:find('class%s*=%s*"ctx"')
		or html:find('class%s*=%s*"ib"')
		or html:find('class%s*=%s*"ql"')
		or html:find('class%s*=%s*"phg"')
end

local function normalizeDictionaryPreviewHtml(definition)
	local html = normalizeDictionaryHtml(definition)

	if not shouldNormalizeDictionaryPreviewHtml(html) then
		return html
	end

	html = normalizeHeadingTags(html)
	html = normalizeDictionaryClasses(html)
	return normalizeDictionaryLists(html)
end

-- CSS ------------------------------------------------------------------------

local function getBaseCss()
	return [[
@page {
    margin: 0;
    font-family: ']] .. UI_FONT_FACE .. [[';
}
body {
    margin: 0;
    padding: 0;
    line-height: 1.3;
    font-family: ']] .. UI_FONT_FACE .. [[';
}
p, h1, h2, h3, h4, h5, h6, ol, ul, dl, dd {
    margin: 0;
}
ul, ol {
    padding-left: 1.1em;
}
a {
    color: black;
}
.dictionarypreview-header {
    margin-bottom: 0.22em;
    font-size: 0.92em;
    font-weight: bold;
}
.dictionarypreview-separator {
    border-top: 1px solid #888;
    margin: 0.16em 0 0.24em 0;
}
]]
end

local FALLBACK_CSS = getBaseCss()

local function hasDictionaryCss(result)
	return result and result.css and result.css ~= "" and looksLikeHtml(result.definition)
end

local function getDictionaryPanelCss(result)
	local css_justify = G_reader_settings:nilOrTrue("dict_justify") and "text-align: justify;" or ""

	local css = [[
@page {
    margin: 0;
    font-family: ']] .. UI_FONT_FACE .. [[';
}
body {
    margin: 0;
    padding: 0;
    line-height: 1.3;
    font-family: ']] .. UI_FONT_FACE .. [[';
]] .. css_justify .. [[
}
blockquote, dd {
    margin: 0 1em;
}
ol, ul, menu {
    margin: 0;
    padding: 0 1.7em;
}
a {
    color: black;
}
.dictionarypreview-header {
    margin-bottom: 0.22em;
    font-size: 0.92em;
    font-weight: bold;
}
.dictionarypreview-separator {
    border-top: 1px solid #888;
    margin: 0.16em 0 0.24em 0;
}
]]

	if result and result.css and result.css ~= "" then
		css = css .. "\n" .. result.css
	end

	return css
end

-- Height estimation ----------------------------------------------------------

local function stripHtmlForLineEstimate(html)
	html = tostring(html or "")
	html = html:gsub("<%s*[bB][rR]%s*/?%s*>", "\n")
	html = html:gsub("</%s*[pP]%s*>", "\n")
	html = html:gsub("</%s*[dD][iI][vV]%s*>", "\n")
	html = html:gsub("</%s*[lL][iI]%s*>", "\n")
	html = html:gsub("</%s*[uU][lL]%s*>", "\n")
	html = html:gsub("</%s*[oO][lL]%s*>", "\n")
	html = html:gsub("</%s*[hH][1-6]%s*>", "\n")
	html = html:gsub("<[^>]+>", "")
	html = html:gsub("&nbsp;", " ")
	html = html:gsub("&amp;", "&")
	html = html:gsub("&lt;", "<")
	html = html:gsub("&gt;", ">")
	html = html:gsub("&quot;", '"')
	return html
end

local function estimateHtmlLineCount(html, content_width, font_size)
	local text = stripHtmlForLineEstimate(html)
	local average_char_width = math.max(1, font_size * 0.50)
	local chars_per_line = math.max(12, math.floor(content_width / average_char_width))
	local lines = 0

	text = text:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"

	for raw_line in text:gmatch("(.-)\n") do
		local line = trim(raw_line)
		if line ~= "" then
			lines = lines + math.max(1, math.ceil(#line / chars_per_line))
		end
	end

	return math.max(1, lines)
end

local function getAdaptiveMinHtmlHeight(html, content_width, font_size, max_html_height)
	local estimated_lines = estimateHtmlLineCount(html, content_width, font_size)
	local line_height = math.ceil(font_size * 1.30)
	local safety_lines = estimated_lines <= 2 and 0.08 or estimated_lines <= 3 and 0.18 or 0.35
	local estimated_height = math.ceil((estimated_lines + safety_lines) * line_height + Screen:scaleBySize(1))
	local base_height = math.max(Screen:scaleBySize(22), math.ceil(font_size * 1.10))
	local min_height = math.max(base_height, estimated_height)

	if max_html_height and max_html_height > 0 then
		return math.min(max_html_height, min_height)
	end

	return min_height
end

local function getCompactHtmlHeightCap(html, content_width, font_size)
	local estimated_lines = estimateHtmlLineCount(html, content_width, font_size)

	if estimated_lines > 3 then
		return nil
	end

	local line_height = math.ceil(font_size * 1.30)
	return math.ceil((estimated_lines + 0.35) * line_height + Screen:scaleBySize(4))
end

-- Button helpers -------------------------------------------------------------
-- ButtonTable only supports icons from KOReader's global icon search path.
-- This small button keeps the same visual structure but can also render an
-- SVG/PNG from this plugin's own icons/ folder via IconWidget's file field.

local PreviewButton = InputContainer:extend({
	text = nil,
	icon = nil,
	icon_file = nil,
	width = nil,
	height = Screen:scaleBySize(48),
	icon_width = KOREADER_ICON_SIZE,
	icon_height = KOREADER_ICON_SIZE,
	callback = nil,
	show_parent = nil,
})

function PreviewButton:init()
	-- Borderless buttons: keep the touch area, but remove the visible
	-- button frame so the footer looks like a native icon toolbar.
	local bordersize = 0
	local padding_h = Size.padding.button
	local padding_v = Size.padding.button
	local outer_w = self.width or Screen:scaleBySize(80)
	local outer_h = self.height or Screen:scaleBySize(48)
	local inner_w = math.max(1, outer_w - 2 * bordersize - 2 * padding_h)
	local inner_h = math.max(1, outer_h - 2 * bordersize - 2 * padding_v)
	local label

	if self.icon_file then
		label = IconWidget:new({
			file = self.icon_file,
			width = self.icon_width,
			height = self.icon_height,
			alpha = true,
			is_icon = true,
		})
	elseif self.icon then
		label = IconWidget:new({
			icon = self.icon,
			width = self.icon_width,
			height = self.icon_height,
			alpha = true,
		})
	else
		label = TextWidget:new({
			text = self.text or "",
			face = Font:getFace("cfont", UI_FONT_SIZE),
			bold = true,
			max_width = inner_w,
		})
	end

	self.label_widget = label
	self.frame = FrameContainer:new({
		show_parent = self.show_parent,
		bordersize = bordersize,
		background = Blitbuffer.COLOR_WHITE,
		padding_left = padding_h,
		padding_right = padding_h,
		padding_top = padding_v,
		padding_bottom = padding_v,
		CenterContainer:new({
			dimen = Geom:new({
				w = inner_w,
				h = inner_h,
			}),
			label,
		}),
	})

	self.dimen = self.frame:getSize()
	self[1] = self.frame
	self.ges_events = {
		TapSelectButton = {
			GestureRange:new({
				ges = "tap",
				range = self.dimen,
			}),
		},
	}
end

function PreviewButton:onTapSelectButton()
	if self.callback then
		self.callback()
	end
	return true
end

-- Preview popup --------------------------------------------------------------

local DictionaryPreviewPopup = InputContainer:extend({
	html_body = nil,
	css = nil,
	html_resource_directory = nil,
	dialog = nil,
	doc_font_size = Screen:scaleBySize(18),
	open_callback = nil,
	left_callback = nil,
	left_button = nil,
	prev_callback = nil,
	next_callback = nil,
	close_preview_callback = nil,
	result_count = 1,
})

function DictionaryPreviewPopup:init()
	local screen_width = Screen:getWidth()
	local screen_height = Screen:getHeight()

	self.width = screen_width

	local top_border_size = Size.line.thick
	local content_padding_left = Screen:scaleBySize(16)
	local content_padding_right = Screen:scaleBySize(12)
	local padding_top = Screen:scaleBySize(4)
	local padding_bottom = Screen:scaleBySize(4)
	local button_gap = Screen:scaleBySize(2)
	local max_popup_height = math.floor(screen_height * PANEL_MAX_HEIGHT_RATIO)

	if Device:isTouchDevice() then
		local range = Geom:new({ x = 0, y = 0, w = screen_width, h = screen_height })
		self.ges_events = {
			TapClose = { GestureRange:new({ ges = "tap", range = range }) },
			SwipeFollow = { GestureRange:new({ ges = "swipe", range = range }) },
		}
	end

	if Device:hasKeys() then
		self.key_events = {
			Close = { { Device.input.group.Back } },
			Follow = { { "Press" } },
		}
	end

	local content_width = math.max(MIN_CONTENT_WIDTH, self.width - content_padding_left - content_padding_right)
	local buttons = self:makeButtons(content_width)
	local buttons_height = self:getWidgetHeight(buttons, Screen:scaleBySize(48))
	local fixed_height = top_border_size + padding_top + button_gap + buttons_height + padding_bottom
	local max_html_height = max_popup_height - fixed_height
	local min_html_height = getAdaptiveMinHtmlHeight(self.html_body, content_width, self.doc_font_size, max_html_height)
	local compact_html_height_cap = getCompactHtmlHeightCap(self.html_body, content_width, self.doc_font_size)

	if max_html_height < min_html_height then
		max_html_height = min_html_height
	end

	local htmlwidget, htmlwidget_height =
		self:makeSizedHtmlWidget(content_width, max_html_height, min_html_height, compact_html_height_cap)
	self.htmlwidget = htmlwidget
	self.height = fixed_height + htmlwidget_height

	self.container = FrameContainer:new({
		background = Blitbuffer.COLOR_WHITE,
		bordersize = 0,
		margin = 0,
		padding = 0,
		VerticalGroup:new({
			LineWidget:new({ dimen = Geom:new({ w = self.width, h = top_border_size }) }),
			VerticalSpan:new({ width = padding_top }),
			HorizontalGroup:new({
				HorizontalSpan:new({ width = content_padding_left }),
				self.htmlwidget,
				HorizontalSpan:new({ width = content_padding_right }),
			}),
			VerticalSpan:new({ width = button_gap }),
			HorizontalGroup:new({
				HorizontalSpan:new({ width = content_padding_left }),
				buttons,
				HorizontalSpan:new({ width = content_padding_right }),
			}),
			VerticalSpan:new({ width = padding_bottom }),
		}),
	})

	self[1] = BottomContainer:new({
		dimen = Screen:getSize(),
		self.container,
	})
end

function DictionaryPreviewPopup:makeButtons(width)
	local button_height = Screen:scaleBySize(48)
	local separator_width = math.max(1, Screen:scaleBySize(1))
	local button_specs = {
		{
			spec = self.left_button or { icon = ICON_SEARCH },
			callback = function()
				return self:onLeftButton()
			end,
		},
	}

	-- Only show dictionary navigation when there is more than one useful
	-- definition result. When a lookup has a single dictionary hit, or no hit at
	-- all, the footer stays compact: left action + original dictionary popup.
	if self.result_count and self.result_count > 1 then
		table.insert(button_specs, {
			spec = { icon = ICON_PREVIOUS },
			callback = function()
				return self:onPrevDictionary()
			end,
		})
		table.insert(button_specs, {
			spec = { icon = ICON_NEXT },
			callback = function()
				return self:onNextDictionary()
			end,
		})
	end

	table.insert(button_specs, {
		spec = { icon = ICON_DETAILS },
		callback = function()
			return self:onFollow()
		end,
	})

	local button_count = #button_specs
	local separator_count = math.max(0, button_count - 1)
	local available_button_width = math.max(1, width - separator_width * separator_count)
	local button_width = math.floor(available_button_width / button_count)
	local remainder = available_button_width - (button_width * button_count)

	local function makeButton(spec, callback, extra_width)
		spec = spec or {}
		return PreviewButton:new({
			text = spec.text,
			icon = spec.icon,
			icon_file = spec.icon_file,
			width = button_width + (extra_width or 0),
			height = button_height,
			icon_width = KOREADER_ICON_SIZE,
			icon_height = KOREADER_ICON_SIZE,
			show_parent = self,
			callback = callback,
		})
	end

	local function makeSeparator()
		return LineWidget:new({
			background = Blitbuffer.COLOR_GRAY,
			dimen = Geom:new({
				w = separator_width,
				h = button_height,
			}),
		})
	end

	local widgets = {}
	for index, item in ipairs(button_specs) do
		if index > 1 then
			table.insert(widgets, makeSeparator())
		end

		table.insert(widgets, makeButton(
			item.spec,
			item.callback,
			index <= remainder and 1 or 0
		))
	end

	return HorizontalGroup:new(widgets)
end

function DictionaryPreviewPopup:getWidgetHeight(widget, fallback)
	local ok, size = pcall(function()
		return widget:getSize()
	end)

	if ok and size and size.h then
		return size.h
	end

	return fallback
end

function DictionaryPreviewPopup:makeHtmlWidget(content_width, height)
	return ScrollHtmlWidget:new({
		html_body = self.html_body,
		is_xhtml = true,
		css = self.css or FALLBACK_CSS,
		html_resource_directory = self.html_resource_directory,
		default_font_size = self.doc_font_size,
		width = content_width,
		height = height,
		scroll_bar_width = Screen:scaleBySize(6),
		text_scroll_span = Screen:scaleBySize(8),
		dialog = self.dialog,
		highlight_text_selection = true,
	})
end

function DictionaryPreviewPopup:makeSizedHtmlWidget(content_width, max_height, min_height, compact_cap)
	local htmlwidget = self:makeHtmlWidget(content_width, max_height)
	local height = max_height

	local ok, single_page_height = pcall(function()
		return htmlwidget:getSinglePageHeight()
	end)

	if ok and type(single_page_height) == "number" and single_page_height > 0 then
		local measurement_safety = compact_cap and Screen:scaleBySize(2) or math.ceil(self.doc_font_size * 0.45)
		height = math.ceil(single_page_height + measurement_safety)
		height = math.max(min_height, math.min(max_height, height))

		if compact_cap then
			height = math.max(min_height, math.min(height, compact_cap))
		end
	end

	if height < max_height then
		htmlwidget = self:makeHtmlWidget(content_width, height)
	end

	return htmlwidget, height
end

function DictionaryPreviewPopup:onShow()
	UIManager:setDirty(self.dialog, function()
		return "ui", self.container.dimen
	end)
end

function DictionaryPreviewPopup:onCloseWidget()
	UIManager:setDirty(self.dialog, function()
		return "partial", self.container.dimen
	end)
end

function DictionaryPreviewPopup:onClose()
	UIManager:close(self)
	if self.close_preview_callback then
		return self.close_preview_callback()
	end
	return true
end

function DictionaryPreviewPopup:onClosePreview()
	return self:onClose()
end

function DictionaryPreviewPopup:onLeftButton()
	UIManager:close(self)
	if self.left_callback then
		return self.left_callback()
	end
	return true
end

-- Compatibility with older local edits that may still call the old name.
DictionaryPreviewPopup.onSearchDocument = DictionaryPreviewPopup.onLeftButton

function DictionaryPreviewPopup:onPrevDictionary()
	if not self.result_count or self.result_count <= 1 then
		return true
	end

	UIManager:close(self)
	if self.prev_callback then
		return self.prev_callback()
	end
	return true
end

function DictionaryPreviewPopup:onNextDictionary()
	if not self.result_count or self.result_count <= 1 then
		return true
	end

	UIManager:close(self)
	if self.next_callback then
		return self.next_callback()
	end
	return true
end

function DictionaryPreviewPopup:onFollow()
	UIManager:close(self)
	if self.open_callback then
		return self.open_callback()
	end
	return true
end

function DictionaryPreviewPopup:onTapClose(_arg, ges)
	if
		ges
		and ges.pos
		and self.container
		and self.container.dimen
		and ges.pos:notIntersectWith(self.container.dimen)
	then
		return self:onClosePreview()
	end

	return false
end

function DictionaryPreviewPopup:onSwipeFollow(_arg, ges)
	if not ges or not ges.direction then
		return false
	end

	if ges.direction == "west" then
		return self:onNextDictionary()
	elseif ges.direction == "east" then
		return self:onPrevDictionary()
	elseif ges.direction == "south" then
		return self:onClosePreview()
	end

	return false
end

-- Plugin lifecycle -----------------------------------------------------------

function DictionaryPreview:init()
	self.enabled = self:isPreviewEnabled()
	self.left_button_action = self:getLeftButtonAction()
	self.current_popup = nil
	self.original_showDict = nil
	self.patched_dictionary = nil
	self.opening_original_popup = false
	self.native_dict_popup_active = false
	self.native_dict_popup_count = 0
	self.selection_snapshot = nil

	if self.ui and self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end

	self:patchDictionary()
end

function DictionaryPreview:addToMainMenu(menu_items)
	menu_items.dictionarypreview = {
		text = _("Dictionary preview"),
		sorting_hint = "more_tools",
		sub_item_table = {
			{
				text = _("Enable dictionary preview"),
				checked_func = function()
					return self:isPreviewEnabled()
				end,
				callback = function()
					self:setPreviewEnabled(not self:isPreviewEnabled())
				end,
			},
			{
				text = _("Left button action"),
				sub_item_table_func = function()
					return self:genLeftButtonActionMenu()
				end,
				separator = true,
			},
		},
	}
end

function DictionaryPreview:isPreviewEnabled()
	return G_reader_settings:nilOrTrue(SETTING_ENABLED)
end

function DictionaryPreview:setPreviewEnabled(enabled)
	self.enabled = enabled and true or false
	G_reader_settings:saveSetting(SETTING_ENABLED, self.enabled)
end

function DictionaryPreview:getLeftButtonAction()
	local action = G_reader_settings:readSetting(SETTING_LEFT_ACTION) or DEFAULT_LEFT_ACTION
	if not LEFT_ACTION_BY_ID[action] then
		action = DEFAULT_LEFT_ACTION
	end
	return action
end

function DictionaryPreview:setLeftButtonAction(action)
	if not LEFT_ACTION_BY_ID[action] then
		action = DEFAULT_LEFT_ACTION
	end
	self.left_button_action = action
	G_reader_settings:saveSetting(SETTING_LEFT_ACTION, action)
end

function DictionaryPreview:getPluginIconFile(action_id)
	local candidates = PLUGIN_LEFT_ICON_CANDIDATES[action_id]
	if not candidates or not self.path or self.path == "" then
		return nil
	end

	local icons_dir = self.path .. "/icons"

	for _, basename in ipairs(candidates) do
		for _, ext in ipairs(PLUGIN_ICON_EXTENSIONS) do
			local path = icons_dir .. "/" .. basename .. ext
			if fileExists(path) then
				return path
			end
		end
	end

	return nil
end

function DictionaryPreview:getLeftButtonSpec()
	local action_id = self:getLeftButtonAction()
	local action = LEFT_ACTION_BY_ID[action_id] or LEFT_ACTION_BY_ID[DEFAULT_LEFT_ACTION]

	if action_id == LEFT_ACTION_SEARCH_BOOK then
		return { icon = ICON_SEARCH }
	end

	local plugin_icon = self:getPluginIconFile(action_id)
	if plugin_icon then
		return { icon_file = plugin_icon }
	end

	-- Fallback intentionally uses gettext labels from KOReader's catalog.
	-- This avoids showing an untranslated custom English/Portuguese string
	-- when the optional SVG/PNG is not present in icons/.
	return { text = action.label }
end

function DictionaryPreview:genLeftButtonActionMenu()
	local items = {}

	for _, action in ipairs(LEFT_ACTIONS) do
		table.insert(items, {
			text = action.label,
			radio = true,
			checked_func = function()
				return self:getLeftButtonAction() == action.id
			end,
			callback = function()
				self:setLeftButtonAction(action.id)
			end,
		})
	end

	return items
end

function DictionaryPreview:destroy()
	if self.current_popup then
		UIManager:close(self.current_popup)
		self.current_popup = nil
	end

	if self.patched_dictionary and self.original_showDict and self.patched_dictionary._dictionarypreview_patched then
		self.patched_dictionary.showDict = self.original_showDict
		self.patched_dictionary._dictionarypreview_patched = nil
	end

	self.original_showDict = nil
	self.patched_dictionary = nil
	self.selection_snapshot = nil
	self:resetNativeDictionaryPopupGuard()

	if WidgetContainer.destroy then
		WidgetContainer.destroy(self)
	end
end

-- Dictionary interception ----------------------------------------------------

function DictionaryPreview:patchDictionary()
	local dictionary = self.ui and self.ui.dictionary

	if not dictionary then
		logger.warn("DictionaryPreview: ReaderDictionary not available.")
		return
	end

	if dictionary._dictionarypreview_patched then
		return
	end

	self.original_showDict = dictionary.showDict
	self.patched_dictionary = dictionary

	local plugin = self

	dictionary.showDict = function(dict_self, word, results, boxes, link, dict_close_callback)
		plugin.enabled = plugin:isPreviewEnabled()
		if not plugin.enabled or plugin.opening_original_popup or not results or not results[1] then
			return plugin.original_showDict(dict_self, word, results, boxes, link, dict_close_callback)
		end

		if plugin.native_dict_popup_active then
			local wrapped_close_callback = plugin:beginNativeDictionaryPopup(dict_close_callback)
			return plugin.original_showDict(dict_self, word, results, boxes, link, wrapped_close_callback)
		end

		plugin:rememberSelection(dict_self)

		if dict_self.dismissLookupInfo then
			pcall(function()
				dict_self:dismissLookupInfo()
			end)
		end

		return plugin:showPreview(dict_self, word, results, boxes, link, dict_close_callback)
	end

	dictionary._dictionarypreview_patched = true
end

function DictionaryPreview:beginNativeDictionaryPopup(dict_close_callback)
	self.native_dict_popup_count = (self.native_dict_popup_count or 0) + 1
	self.native_dict_popup_active = true

	local plugin = self
	local closed = false

	return function(...)
		if not closed then
			closed = true
			plugin.native_dict_popup_count = math.max(0, (plugin.native_dict_popup_count or 1) - 1)
			plugin.native_dict_popup_active = plugin.native_dict_popup_count > 0
		end

		if dict_close_callback then
			return dict_close_callback(...)
		end
	end
end

function DictionaryPreview:resetNativeDictionaryPopupGuard()
	self.native_dict_popup_count = 0
	self.native_dict_popup_active = false
end

function DictionaryPreview:showOriginalDictionaryPopup(dict_self, word, results, boxes, link, dict_close_callback)
	if not self.original_showDict then
		return true
	end

	self.opening_original_popup = true
	local wrapped_close_callback = self:beginNativeDictionaryPopup(dict_close_callback)

	local ok, err = pcall(function()
		self.original_showDict(dict_self, word, results, boxes, link, wrapped_close_callback)
	end)

	self.opening_original_popup = false

	if not ok then
		self:resetNativeDictionaryPopupGuard()
		logger.warn("DictionaryPreview: failed to open original dictionary popup:", err)
	end

	return true
end

-- Reader interactions --------------------------------------------------------

function DictionaryPreview:clearOriginalHighlight(dict_self)
	local highlight = dict_self and dict_self.highlight
	if not highlight then
		return
	end

	local ok, clear_id = pcall(function()
		return highlight:getClearId()
	end)

	if ok and clear_id then
		pcall(function()
			highlight:clear(clear_id)
		end)
	else
		pcall(function()
			highlight:clear()
		end)
	end

	dict_self.highlight = nil
end

function DictionaryPreview:clearSelection()
	if self.ui and self.ui.handleEvent then
		pcall(function()
			self.ui:handleEvent(Event:new("ClearSelection"))
		end)
	end
end

function DictionaryPreview:getInterfaceFontSize()
	return Screen:scaleBySize(UI_FONT_SIZE)
end

function DictionaryPreview:getSearchText(word, result)
	result = result or {}
	local text = word or result.word or ""

	if type(text) == "table" then
		text = text.text or text.word or ""
	end

	text = tostring(text or "")

	if util and util.stripPunctuation then
		local ok, stripped = pcall(function()
			return util.stripPunctuation(text)
		end)

		if ok and stripped and stripped ~= "" then
			text = stripped
		end
	end

	return trim(text)
end

function DictionaryPreview:showSearchDialog(search_text)
	search_text = trim(search_text)
	if search_text == "" then
		return true
	end

	local function openSearchInput()
		if self.ui and self.ui.search and type(self.ui.search.onShowFulltextSearchInput) == "function" then
			local ok, err = pcall(function()
				self.ui.search:onShowFulltextSearchInput(search_text)
			end)
			if ok then
				return true
			end
			logger.warn("DictionaryPreview: direct search input failed:", err)
		end

		if self.ui and self.ui.handleEvent then
			local ok, err = pcall(function()
				self.ui:handleEvent(Event:new("ShowFulltextSearchInput", search_text))
			end)
			if ok then
				return true
			end
			logger.warn("DictionaryPreview: search input event failed:", err)
		end

		if self.ui and self.ui.search and type(self.ui.search.searchText) == "function" then
			local ok, err = pcall(function()
				self.ui.search:searchText(search_text)
			end)
			if ok then
				return true
			end
			logger.warn("DictionaryPreview: direct search execution failed:", err)
		end

		if self.ui and self.ui.handleEvent then
			local ok, err = pcall(function()
				self.ui:handleEvent(Event:new("ShowSearchDialog", search_text, 0, false, true))
			end)
			if not ok then
				logger.warn("DictionaryPreview: search dialog fallback failed:", err)
			end
		end

		return true
	end

	local ok = pcall(function()
		UIManager:scheduleIn(0.05, openSearchInput)
	end)

	if not ok then
		openSearchInput()
	end

	return true
end


function DictionaryPreview:getActiveHighlight(dict_self)
	-- Depending on the KOReader path that opened the dictionary, the active
	-- ReaderHighlight instance may be stored on ReaderDictionary or only on
	-- the reader UI. Prefer an instance that still has a live selection.
	local candidates = {}
	if dict_self and dict_self.highlight then
		table.insert(candidates, dict_self.highlight)
	end
	if self.ui and self.ui.highlight then
		table.insert(candidates, self.ui.highlight)
	end
	if dict_self and dict_self.ui and dict_self.ui.highlight then
		table.insert(candidates, dict_self.ui.highlight)
	end

	local fallback
	for _, highlight in ipairs(candidates) do
		if highlight then
			if highlight.selected_text or highlight.hold_pos then
				return highlight
			end

			if not fallback
				and (type(highlight.showHighlightPrompt) == "function"
					or type(highlight.lookupWikipedia) == "function") then
				fallback = highlight
			end
		end
	end

	return fallback
end

function DictionaryPreview:rememberSelection(dict_self)
	local highlight = self:getActiveHighlight(dict_self)
	if not highlight then
		self.selection_snapshot = nil
		return nil
	end

	-- In the dictionary-on-single-word flow, KOReader may later clear the
	-- live selection when the dictionary lookup UI is dismissed. Store a copy
	-- now so the configurable Highlight action can restore it when pressed.
	if not highlight.selected_text
		and highlight.hold_pos
		and type(highlight.highlightFromHoldPos) == "function" then
		pcall(function()
			highlight:highlightFromHoldPos()
		end)
	end

	self.selection_snapshot = {
		highlight = highlight,
		selected_text = copyTable(highlight.selected_text),
		hold_pos = copyTable(highlight.hold_pos),
		selected_link = copyTable(highlight.selected_link),
		is_word_selection = highlight.is_word_selection,
	}

	return self.selection_snapshot
end

function DictionaryPreview:restoreSelection(dict_self)
	local snapshot = self.selection_snapshot
	local highlight = snapshot and snapshot.highlight or self:getActiveHighlight(dict_self)

	if not highlight then
		return nil
	end

	if snapshot then
		if snapshot.selected_text then
			highlight.selected_text = copyTable(snapshot.selected_text)
		end
		if snapshot.hold_pos then
			highlight.hold_pos = copyTable(snapshot.hold_pos)
		end
		if snapshot.selected_link then
			highlight.selected_link = copyTable(snapshot.selected_link)
		end

		-- The original lookup may have been a single-word dictionary lookup.
		-- For the highlight action we need to treat the restored selection as a
		-- highlightable text selection, not as another dictionary lookup trigger.
		highlight.is_word_selection = false
	end

	if not highlight.selected_text
		and highlight.hold_pos
		and type(highlight.highlightFromHoldPos) == "function" then
		pcall(function()
			highlight:highlightFromHoldPos()
		end)
	end

	return highlight
end

function DictionaryPreview:hasHighlightSelection(highlight)
	return highlight and (highlight.selected_text or highlight.hold_pos) ~= nil
end

function DictionaryPreview:notify(message)
	UIManager:show(Notification:new({ text = message }))
	return true
end

function DictionaryPreview:highlightSelection(dict_self, dict_close_callback)
	local highlight = self:restoreSelection(dict_self)

	if not highlight then
		return self:notify(_("No selection to highlight."))
	end

	if not highlight.selected_text
		and highlight.hold_pos
		and type(highlight.highlightFromHoldPos) == "function" then
		pcall(function()
			highlight:highlightFromHoldPos()
		end)
	end

	if not (highlight.selected_text and highlight.selected_text.pos0 and highlight.selected_text.pos1) then
		return self:notify(_("No selection to highlight."))
	end

	UIManager:scheduleIn(0.05, function()
		local ok, err = pcall(function()
			if type(highlight.showHighlightPrompt) == "function" then
				highlight:showHighlightPrompt(function(...)
					self.selection_snapshot = nil
					if dict_close_callback then
						pcall(dict_close_callback, ...)
					end
				end)
			elseif type(highlight.saveHighlight) == "function" then
				local index = highlight:saveHighlight(true)
				if type(highlight.clear) == "function" then
					highlight:clear()
				end
				self.selection_snapshot = nil
				if dict_close_callback then
					pcall(dict_close_callback, index)
				end
			end
		end)

		if not ok then
			logger.warn("DictionaryPreview: highlight action failed:", err)
		end
	end)

	return true
end

function DictionaryPreview:lookupWikipedia(dict_self, search_text)
	local highlight = self:restoreSelection(dict_self)

	if highlight and type(highlight.lookupWikipedia) == "function" and self:hasHighlightSelection(highlight) then
		UIManager:scheduleIn(0.05, function()
			local ok, err = pcall(function()
				if not highlight.selected_text
					and highlight.hold_pos
					and type(highlight.highlightFromHoldPos) == "function" then
					highlight:highlightFromHoldPos()
				end
				highlight:lookupWikipedia()
				self.selection_snapshot = nil
			end)

			if not ok then
				logger.warn("DictionaryPreview: Wikipedia action failed:", err)
			end
		end)
		return true
	end

	search_text = trim(search_text)
	if search_text ~= "" and self.ui and self.ui.handleEvent then
		self.ui:handleEvent(Event:new("LookupWikipedia", search_text))
		return true
	end

	return self:notify(_("No selection to look up."))
end

function DictionaryPreview:runLeftButtonAction(action, dict_self, search_text, dict_close_callback)
	action = LEFT_ACTION_BY_ID[action] and action or DEFAULT_LEFT_ACTION
	self.current_popup = nil

	if action == LEFT_ACTION_HIGHLIGHT then
		-- Do not clear the selection before highlighting. ReaderHighlight needs
		-- the original selected_text/hold_pos to create the annotation.
		return self:highlightSelection(dict_self, dict_close_callback)
	elseif action == LEFT_ACTION_WIKIPEDIA then
		return self:lookupWikipedia(dict_self, search_text)
	end

	self.selection_snapshot = nil
	self:clearOriginalHighlight(dict_self)
	self:clearSelection()
	if dict_close_callback then
		pcall(dict_close_callback)
	end
	return self:showSearchDialog(search_text)
end

-- Preview construction -------------------------------------------------------

function DictionaryPreview:buildPreviewPayload(word, result, result_index, result_count)
	result = result or {}

	local shown_word = result.word or word or _("Dictionary")
	local dict_name = result.dict or _("Dictionary")
	local definition_html
	local css

	if result.no_result then
		dict_name = _("Dictionary")
		definition_html = "<p>" .. htmlEscape(_("No definition found.")) .. "</p>"
		css = FALLBACK_CSS
	elseif hasDictionaryCss(result) then
		definition_html = normalizeDictionaryHtml(result.definition)
		css = getDictionaryPanelCss(result)
	else
		definition_html = normalizeDictionaryPreviewHtml(result.definition)
		css = FALLBACK_CSS
	end

	if not result.no_result and result_count and result_count > 1 then
		dict_name = string.format("%s (%d/%d)", dict_name, result_index or 1, result_count)
	end

	return {
		html_body = table.concat({
			'<div class="dictionarypreview-header">',
			htmlEscape(shown_word),
			" — ",
			htmlEscape(dict_name),
			"</div>",
			'<div class="dictionarypreview-separator"></div>',
			definition_html,
		}, "\n"),
		css = css,
		html_resource_directory = result.dictionary_resource_directory,
	}
end

local function getResultCount(results)
	if type(results) ~= "table" then
		return 0
	end
	return #results
end

local function buildPreviewResults(results)
	local preview_results = {}

	if type(results) ~= "table" then
		return preview_results
	end

	-- Ignore no-result placeholders when at least one dictionary has a real
	-- definition. This keeps navigation focused only on usable dictionary hits.
	for index, result in ipairs(results) do
		if result and not result.no_result then
			table.insert(preview_results, {
				result = result,
				source_index = index,
			})
		end
	end

	-- When no dictionary matched, keep a single placeholder preview so the user
	-- can still use the left action or open the original dictionary popup.
	if #preview_results == 0 and results[1] then
		table.insert(preview_results, {
			result = results[1],
			source_index = 1,
		})
	end

	return preview_results
end

local function normalizeResultIndex(index, count)
	if not count or count <= 0 then
		return 1
	end

	index = tonumber(index) or 1

	if index < 1 then
		return count
	elseif index > count then
		return 1
	end

	return index
end

local function reorderResultsFromIndex(results, index)
	local count = getResultCount(results)
	if count <= 1 or index == 1 then
		return results
	end

	local reordered = {}
	for i = index, count do
		table.insert(reordered, results[i])
	end
	for i = 1, index - 1 do
		table.insert(reordered, results[i])
	end
	return reordered
end

function DictionaryPreview:showPreview(dict_self, word, results, boxes, link, dict_close_callback)
	local preview_results = buildPreviewResults(results)
	local preview_count = #preview_results

	if preview_count <= 0 then
		return true
	end

	if self.current_popup then
		UIManager:close(self.current_popup)
		self.current_popup = nil
	end

	local popup
	local opened_full_popup = false
	local current_index = 1

	local function closeCurrentPopup()
		if popup then
			pcall(function()
				UIManager:close(popup)
			end)
			popup = nil
		end
		self.current_popup = nil
	end

	local function openFullPopup(index)
		opened_full_popup = true
		closeCurrentPopup()

		local preview_index = normalizeResultIndex(index or current_index, preview_count)
		local source_index = preview_results[preview_index] and preview_results[preview_index].source_index or 1
		local selected_results = reorderResultsFromIndex(results, source_index)
		return self:showOriginalDictionaryPopup(dict_self, word, selected_results, boxes, link, dict_close_callback)
	end

	local function closePreview()
		if not opened_full_popup then
			self.current_popup = nil
			self.selection_snapshot = nil
			self:clearOriginalHighlight(dict_self)
			self:clearSelection()
			if dict_close_callback then
				pcall(dict_close_callback)
			end
		end
		return true
	end

	local function showResult(index)
		current_index = normalizeResultIndex(index, preview_count)
		local preview_entry = preview_results[current_index] or preview_results[1] or {}
		local result = preview_entry.result or {}
		local search_text = self:getSearchText(word, result)
		local preview_payload = self:buildPreviewPayload(word, result, current_index, preview_count)

		closeCurrentPopup()

		popup = DictionaryPreviewPopup:new({
			html_body = preview_payload.html_body,
			css = preview_payload.css,
			html_resource_directory = preview_payload.html_resource_directory,
			doc_font_size = self:getInterfaceFontSize(),
			dialog = dict_self and dict_self.dialog,
			result_count = preview_count,
			left_button = self:getLeftButtonSpec(),
			open_callback = function()
				return openFullPopup(current_index)
			end,
			left_callback = function()
				return self:runLeftButtonAction(self:getLeftButtonAction(), dict_self, search_text, dict_close_callback)
			end,
			prev_callback = function()
				return showResult(current_index - 1)
			end,
			next_callback = function()
				return showResult(current_index + 1)
			end,
			close_preview_callback = closePreview,
		})

		self.current_popup = popup
		UIManager:show(popup)
		return true
	end

	return showResult(1)
end

-- Backwards-compatible alias for older local edits/references.
DictionaryPreview.showFootnotePreview = DictionaryPreview.showPreview

return DictionaryPreview
