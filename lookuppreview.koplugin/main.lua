local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
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
local Notification = require("ui/widget/notification")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local Translator = require("ui/translator")
local util = require("util")
local logger = require("logger")
local _ = require("gettext")
local C_ = _.pgettext or function(_context, text)
	return _(text)
end

local Screen = Device.screen
local IS_TOUCH_DEVICE = Device:isTouchDevice()
local HAS_KEYS = Device:hasKeys()

local LookupPreview = WidgetContainer:extend({
	name = "lookuppreview",
	is_doc_only = true,
})

local PLUGIN_VERSION = "v0.1.0"

local UI_FONT_FACE = "Noto Sans"
local UI_FONT_SIZE = 20
local TITLE_FONT_SIZE = math.max(16, UI_FONT_SIZE - 1)
local SUBTITLE_FONT_SIZE = math.max(14, UI_FONT_SIZE - 3)
local HEADER_MENU_FONT_SIZE = math.max(14, UI_FONT_SIZE - 4)
local HEADER_BUTTON_FONT_SIZE = math.max(18, UI_FONT_SIZE)
local BODY_FONT_SIZE = Screen:scaleBySize(18)

local function getUIFontFace(names, size, fallback_name)
	if type(names) ~= "table" then
		names = { names }
	end

	for _, name in ipairs(names) do
		local ok, face = pcall(function()
			return Font:getFace(name, size)
		end)

		if ok and face then
			return face
		end
	end

	return Font:getFace(fallback_name or "cfont", size)
end

local TITLE_FACE = Font:getFace("cfont", TITLE_FONT_SIZE)
local SUBTITLE_FACE = getUIFontFace({
	"NotoSans-Italic.ttf",
	"NotoSans-Italic",
	"Noto Sans Italic",
	"cfonti",
}, SUBTITLE_FONT_SIZE, "cfont")
local HEADER_MENU_FACE = Font:getFace("cfont", HEADER_MENU_FONT_SIZE)
local HEADER_BUTTON_FACE = Font:getFace("cfont", HEADER_BUTTON_FONT_SIZE)
local DICTIONARY_BUTTON_FONT_SIZE = math.max(13, UI_FONT_SIZE - 5)
local DICTIONARY_BUTTON_FACE = Font:getFace("cfont", DICTIONARY_BUTTON_FONT_SIZE)
local TRANSLATION_BUTTON_FONT_SIZE = math.max(13, UI_FONT_SIZE - 5)
local TRANSLATION_BUTTON_FACE = Font:getFace("cfont", TRANSLATION_BUTTON_FONT_SIZE)

local CARD_WIDTH_RATIO = 0.92
local CARD_HEIGHT_RATIO = 0.38
local CARD_MIN_WIDTH = Screen:scaleBySize(220)
local CARD_GAP = Screen:scaleBySize(8)
local CARD_EDGE_MARGIN = Screen:scaleBySize(10)
local CARD_BORDER_SIZE = math.max(Size.border.thin, Screen:scaleBySize(2))
local CARD_BORDER_COLOR = Blitbuffer.COLOR_BLACK
local CARD_SHADOW_ENABLED = false
local CARD_SHADOW_OFFSET = Screen:scaleBySize(3)
local CARD_SHADOW_COLOR = Blitbuffer.COLOR_DARK_GRAY
local CARD_RADIUS = nil
local CARD_PADDING_H = Screen:scaleBySize(14)
local CARD_PADDING_TOP = Screen:scaleBySize(6)
local CARD_PADDING_BOTTOM = Screen:scaleBySize(8)
local HEADER_GAP = Screen:scaleBySize(2)
local HEADER_SEPARATOR_GAP = Screen:scaleBySize(3)
local HEADER_MENU_WIDTH = Screen:scaleBySize(40)
local HEADER_MENU_HEIGHT = Screen:scaleBySize(30)
local HEADER_MENU_PADDING_H = Screen:scaleBySize(5)
local HEADER_MENU_PADDING_V = Screen:scaleBySize(0)
local HEADER_TITLE_MENU_GAP = Screen:scaleBySize(6)
local DICTIONARY_BUTTON_HEIGHT = Screen:scaleBySize(30)
local DICTIONARY_ICON_SIZE = Screen:scaleBySize(20)
local DICTIONARY_BUTTON_GAP = Screen:scaleBySize(4)
local DICTIONARY_BUTTON_SEPARATOR_WIDTH = math.max(1, Screen:scaleBySize(1))
local TRANSLATION_BUTTON_HEIGHT = Screen:scaleBySize(30)
local TRANSLATION_BUTTON_GAP = Screen:scaleBySize(4)
local TRANSLATION_BUTTON_SEPARATOR_WIDTH = math.max(1, Screen:scaleBySize(1))
local PAGE_MENU_WIDTH = Screen:scaleBySize(220)
local PAGE_MENU_ITEM_HEIGHT = Screen:scaleBySize(34)
local PAGE_MENU_GAP = Screen:scaleBySize(8)
local PAGE_MENU_PADDING_H = Screen:scaleBySize(12)
local SCROLL_BAR_WIDTH = Screen:scaleBySize(6)
local TEXT_SCROLL_SPAN = Screen:scaleBySize(8)
local FLOATING_SELECTION_GAP = Screen:scaleBySize(8)
local MIN_HTML_HEIGHT = Screen:scaleBySize(72)
local EMPTY_TEXT = "—"

local SETTING_ENABLED = "lookuppreview_enabled"
local SETTING_WIKI_LANG = "lookuppreview_wikipedia_lang"
local SETTING_LEFT_ACTION = "lookuppreview_dictionary_left_action"
local SETTING_TRANSLATION_SHOW_SOURCE = "lookuppreview_translation_show_source"
local SETTING_TRANSLATION_SHOW_COPY_BUTTON = "lookuppreview_translation_show_copy_button"
local SETTING_TRANSLATION_SHOW_NOTE_BUTTON = "lookuppreview_translation_show_note_button"

local LEFT_ACTION_HIGHLIGHT = "highlight"
local LEFT_ACTION_SEARCH_BOOK = "search_book"
local DEFAULT_LEFT_ACTION = LEFT_ACTION_SEARCH_BOOK

local LEFT_ACTIONS = {
	{ id = LEFT_ACTION_HIGHLIGHT, label = _("Highlight") },
	{ id = LEFT_ACTION_SEARCH_BOOK, label = _("Fulltext search") },
}

local LEFT_ACTION_BY_ID = {}
for _, action in ipairs(LEFT_ACTIONS) do
	LEFT_ACTION_BY_ID[action.id] = action
end

local PLUGIN_ICON_EXTENSIONS = { ".svg", ".png" }
local PLUGIN_LEFT_ICON_CANDIDATES = {
	[LEFT_ACTION_HIGHLIGHT] = { "highlight", "lookuppreview.highlight", "dictionarypreview.highlight" },
}

local ICON_SEARCH = "appbar.search"
local ICON_PREVIOUS = "chevron.left"
local ICON_NEXT = "chevron.right"
local ICON_DETAILS = "chevron.up"

local COMMON_TARGET_LANGUAGES = {
	"en",
	"pt",
	"es",
	"fr",
	"de",
	"it",
	"nl",
	"ru",
	"ja",
	"ko",
	"zh",
	"ar",
	"hi",
	"tr",
	"pl",
	"sv",
	"da",
	"fi",
	"no",
	"el",
	"cs",
	"ro",
	"uk",
	"vi",
}

local PAGE_DICTIONARY = 1
local PAGE_TRANSLATION = 2
local PAGE_WIKIPEDIA = 3

local PAGE_TITLES = {
	[PAGE_DICTIONARY] = _("Dictionary"),
	[PAGE_TRANSLATION] = _("Translate"),
	[PAGE_WIKIPEDIA] = _("Wikipedia"),
}

local FALLBACK_CSS = [[
@page {
    margin: 0;
    font-family: ']] .. UI_FONT_FACE .. [[';
}
body {
    margin: 0;
    padding: 0;
    line-height: 1.32;
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
.lp-muted {
    color: #666666;
    font-size: 0.88em;
}
.lp-title {
    font-weight: bold;
    font-size: 1.05em;
    margin-bottom: 0.25em;
}
.lp-source {
    margin-top: 0.5em;
    color: #555555;
    font-size: 0.86em;
}
.lp-source-label {
    margin-top: 0.45em;
    margin-bottom: 0.12em;
    color: #777777;
    font-size: 0.78em;
    font-weight: bold;
}
.lp-translation {
    font-size: 1em;
}
]]

local CLASS_STYLE_CACHE = {}
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

local function appendStyleAttr(attrs, style)
	attrs = attrs or ""
	if attrs:find("style%s*=") then
		return attrs:gsub('style%s*=%s*"([^"]*)"', 'style="%1; ' .. style .. '"', 1)
	end
	return attrs .. ' style="' .. style .. '"'
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

local function buildStyleFromClassList(classes)
	classes = tostring(classes or "")
	local cached = CLASS_STYLE_CACHE[classes]
	if cached ~= nil then
		return cached or nil
	end
	local style_parts = {}
	for class_name in classes:gmatch("%S+") do
		local style = dictionary_class_styles[class_name]
		if style then
			style_parts[#style_parts + 1] = style
		end
	end
	local result = #style_parts > 0 and table.concat(style_parts, " ") or false
	CLASS_STYLE_CACHE[classes] = result
	return result or nil
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
]]
	if result and result.css and result.css ~= "" then
		css = css .. "\n" .. result.css
	end
	return css
end

local function hasDictionaryCss(result)
	return result and result.css and result.css ~= "" and looksLikeHtml(result.definition)
end

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

local function estimateHtmlHeight(html, content_width, font_size, max_height)
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
	lines = math.max(1, lines)
	local line_height = math.ceil(font_size * 1.30)
	local safety = lines <= 2 and Screen:scaleBySize(8) or Screen:scaleBySize(18)
	local estimated_height = math.ceil(lines * line_height + safety)
	local height = math.max(MIN_HTML_HEIGHT, estimated_height)
	if max_height and max_height > 0 then
		height = math.max(1, math.min(max_height, height))
	end
	return height
end

local function getSelectionBounds(boxes)
	if type(boxes) ~= "table" or #boxes == 0 then
		return nil
	end
	local top
	local bottom
	for _, box in ipairs(boxes) do
		if type(box) == "table" and box.y and box.h then
			local box_top = tonumber(box.y)
			local box_height = tonumber(box.h)
			local box_bottom = box_top and box_height and (box_top + box_height)
			if box_top and box_bottom then
				top = top and math.min(top, box_top) or box_top
				bottom = bottom and math.max(bottom, box_bottom) or box_bottom
			end
		end
	end
	if not top or not bottom then
		return nil
	end
	return { top = top, bottom = bottom }
end

local function extractMainTranslation(result)
	if not (result and type(result) == "table" and type(result[1]) == "table") then
		return ""
	end
	local translated = {}
	for _, r in ipairs(result[1]) do
		if type(r) == "table" and type(r[1]) == "string" and r[1] ~= "" then
			translated[#translated + 1] = r[1]
		end
	end
	return trim(table.concat(translated, " "))
end

local function getWidgetSize(widget)
	local ok, size = pcall(function()
		return widget:getSize()
	end)
	if ok and size then
		return size
	end
	return Geom:new({ w = 0, h = 0 })
end

local HeaderSubtitleButton = InputContainer:extend({
	text = nil,
	face = nil,
	width = nil,
	height = nil,
	callback = nil,
	show_parent = nil,
})

function HeaderSubtitleButton:init()
	local outer_w = self.width or Screen:scaleBySize(240)
	local label = TextWidget:new({
		text = self.text or "",
		face = self.face or SUBTITLE_FACE,
		max_width = outer_w,
	})
	local label_size = getWidgetSize(label)
	local outer_h = self.height or math.max(1, label_size.h or Screen:scaleBySize(14))

	self.frame = FrameContainer:new({
		show_parent = self.show_parent,
		bordersize = 0,
		background = Blitbuffer.COLOR_WHITE,
		padding = 0,
		label,
	})

	self.dimen = Geom:new({ x = 0, y = 0, w = outer_w, h = outer_h })
	self[1] = self.frame
	self.ges_events = {
		TapHeaderSubtitle = {
			GestureRange:new({
				ges = "tap",
				range = self.dimen,
			}),
		},
	}
end

function HeaderSubtitleButton:onTapHeaderSubtitle()
	if self.callback then
		return self.callback()
	end
	return true
end

local HeaderPageButton = InputContainer:extend({
	text = nil,
	width = nil,
	callback = nil,
	show_parent = nil,
})

function HeaderPageButton:init()
	local outer_w = self.width or HEADER_MENU_WIDTH
	local label = TextWidget:new({
		text = self.text or "",
		face = HEADER_BUTTON_FACE,
		bold = true,
		max_width = math.max(1, outer_w - 2 * HEADER_MENU_PADDING_H),
	})

	self.frame = FrameContainer:new({
		show_parent = self.show_parent,
		bordersize = 0,
		background = Blitbuffer.COLOR_WHITE,
		padding_left = HEADER_MENU_PADDING_H,
		padding_right = HEADER_MENU_PADDING_H,
		padding_top = HEADER_MENU_PADDING_V,
		padding_bottom = HEADER_MENU_PADDING_V,
		CenterContainer:new({
			dimen = Geom:new({
				w = math.max(1, outer_w - 2 * HEADER_MENU_PADDING_H),
				h = math.max(1, HEADER_MENU_HEIGHT - 2 * HEADER_MENU_PADDING_V),
			}),
			label,
		}),
	})

	self.dimen = Geom:new({
		x = 0,
		y = 0,
		w = outer_w,
		h = HEADER_MENU_HEIGHT,
	})
	self[1] = self.frame

	self.ges_events = {
		TapHeaderPageMenu = {
			GestureRange:new({
				ges = "tap",
				range = self.dimen,
			}),
		},
	}
end

function HeaderPageButton:onTapHeaderPageMenu()
	if self.callback then
		return self.callback()
	end
	return true
end

local DictionaryCardButton = InputContainer:extend({
	text = nil,
	icon = nil,
	icon_file = nil,
	width = nil,
	height = DICTIONARY_BUTTON_HEIGHT,
	icon_width = DICTIONARY_ICON_SIZE,
	icon_height = DICTIONARY_ICON_SIZE,
	callback = nil,
	show_parent = nil,
})

function DictionaryCardButton:init()
	local outer_w = self.width or Screen:scaleBySize(64)
	local outer_h = self.height or DICTIONARY_BUTTON_HEIGHT
	local padding_h = math.max(1, math.floor(Size.padding.button * 0.55))
	local padding_v = math.max(0, math.floor(Size.padding.button * 0.25))
	local inner_w = math.max(1, outer_w - 2 * padding_h)
	local inner_h = math.max(1, outer_h - 2 * padding_v)
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
			face = DICTIONARY_BUTTON_FACE,
			bold = true,
			max_width = inner_w,
		})
	end

	self.frame = FrameContainer:new({
		show_parent = self.show_parent,
		bordersize = 0,
		background = Blitbuffer.COLOR_WHITE,
		padding_left = padding_h,
		padding_right = padding_h,
		padding_top = padding_v,
		padding_bottom = padding_v,
		CenterContainer:new({
			dimen = Geom:new({ w = inner_w, h = inner_h }),
			label,
		}),
	})

	self.dimen = Geom:new({ x = 0, y = 0, w = outer_w, h = outer_h })
	self[1] = self.frame
	self.ges_events = {
		TapDictionaryButton = {
			GestureRange:new({
				ges = "tap",
				range = self.dimen,
			}),
		},
	}
end

function DictionaryCardButton:onTapDictionaryButton()
	if self.callback then
		return self.callback()
	end
	return true
end

local SimplePageMenu = InputContainer:extend({
	parent_popup = nil,
	active_index = PAGE_DICTIONARY,
	anchor_dimen = nil,
	visible_dimen = nil,
	container = nil,
})

function SimplePageMenu:makeRow(page_index, width)
	local is_active = page_index == self.active_index
	local label = TextWidget:new({
		text = (is_active and "• " or "  ") .. PAGE_TITLES[page_index],
		face = HEADER_MENU_FACE,
		bold = is_active,
		max_width = math.max(1, width - 2 * PAGE_MENU_PADDING_H),
	})

	return LeftContainer:new({
		allow_mirroring = false,
		dimen = Geom:new({
			w = width,
			h = PAGE_MENU_ITEM_HEIGHT,
		}),
		HorizontalGroup:new({
			HorizontalSpan:new({ width = PAGE_MENU_PADDING_H }),
			label,
		}),
	})
end

function SimplePageMenu:init()
	local screen_width = Screen:getWidth()
	local screen_height = Screen:getHeight()
	local parent = self.parent_popup
	local parent_dimen = parent and parent.visible_dimen
	local anchor = self.anchor_dimen
	local border_size = Size.border.thin
	local content_width = math.min(PAGE_MENU_WIDTH, screen_width - 2 * CARD_EDGE_MARGIN - 2 * border_size)

	self.container = FrameContainer:new({
		background = Blitbuffer.COLOR_WHITE,
		bordersize = border_size,
		color = Blitbuffer.COLOR_DARK_GRAY,
		margin = 0,
		padding = 0,
		VerticalGroup:new({
			self:makeRow(PAGE_DICTIONARY, content_width),
			self:makeRow(PAGE_TRANSLATION, content_width),
			self:makeRow(PAGE_WIKIPEDIA, content_width),
		}),
	})

	local container_size = getWidgetSize(self.container)
	local width = container_size.w and container_size.w > 0 and container_size.w or (content_width + 2 * border_size)
	local height = container_size.h and container_size.h > 0 and container_size.h
		or (PAGE_MENU_ITEM_HEIGHT * 3 + 2 * border_size)
	local x
	local y

	if anchor then
		x = anchor.x + anchor.w - width
	else
		x = math.floor((screen_width - width) / 2)
	end

	local min_x = CARD_EDGE_MARGIN
	local max_x = screen_width - width - CARD_EDGE_MARGIN
	x = math.max(min_x, math.min(max_x, x))

	if anchor then
		-- Keep the selector over the active card instead of placing it above
		-- the popup on top of the reader page.
		y = anchor.y + anchor.h + PAGE_MENU_GAP
	elseif parent_dimen then
		y = parent_dimen.y + CARD_BORDER_SIZE + CARD_PADDING_TOP
	else
		y = math.floor((screen_height - height) / 2)
	end

	if parent_dimen then
		local min_y = parent_dimen.y + CARD_BORDER_SIZE
		local max_y = parent_dimen.y + parent_dimen.h - height - CARD_BORDER_SIZE
		if max_y >= min_y then
			y = math.max(min_y, math.min(max_y, y))
		else
			y = math.max(CARD_EDGE_MARGIN, math.min(screen_height - height - CARD_EDGE_MARGIN, y))
		end
	else
		y = math.max(CARD_EDGE_MARGIN, math.min(screen_height - height - CARD_EDGE_MARGIN, y))
	end

	self.visible_dimen = Geom:new({ x = x, y = y, w = width, h = height })
	self.dimen = Screen:getSize()

	self[1] = TopContainer:new({
		dimen = Screen:getSize(),
		VerticalGroup:new({
			VerticalSpan:new({ width = y }),
			HorizontalGroup:new({
				HorizontalSpan:new({ width = x }),
				self.container,
			}),
		}),
	})

	if IS_TOUCH_DEVICE then
		self.ges_events = {
			TapPageMenu = {
				GestureRange:new({
					ges = "tap",
					range = self.dimen,
				}),
			},
		}
	end

	if HAS_KEYS then
		self.key_events = {
			Close = { { Device.input.group.Back } },
		}
	end
end

function SimplePageMenu:onShow()
	UIManager:setDirty(self.parent_popup and self.parent_popup.dialog or self, function()
		return "ui", self.visible_dimen or Screen:getSize()
	end)
end

function SimplePageMenu:onCloseWidget()
	UIManager:setDirty(self.parent_popup and self.parent_popup.dialog or self, function()
		return "partial", self.visible_dimen or Screen:getSize()
	end)
end

function SimplePageMenu:onClose()
	if self.parent_popup then
		self.parent_popup.page_menu = nil
	end
	UIManager:close(self)
	return true
end

function SimplePageMenu:onTapPageMenu(_arg, ges)
	if not ges or not ges.pos or not self.visible_dimen then
		return false
	end

	if ges.pos:notIntersectWith(self.visible_dimen) then
		if self.parent_popup then
			self.parent_popup:closePageMenu()
		else
			UIManager:close(self)
		end
		return true
	end

	local relative_y = ges.pos.y - self.visible_dimen.y
	local item_index = math.floor(relative_y / PAGE_MENU_ITEM_HEIGHT) + 1
	local page_index = PAGE_DICTIONARY
	if item_index == 2 then
		page_index = PAGE_TRANSLATION
	elseif item_index >= 3 then
		page_index = PAGE_WIKIPEDIA
	end

	local parent = self.parent_popup
	if parent then
		parent:closePageMenu()
		return parent.plugin:switchToPage(page_index)
	end

	UIManager:close(self)
	return true
end

local CarouselRow = InputContainer:extend({
	popup = nil,
	active_index = PAGE_DICTIONARY,
	screen_width = nil,
	card_width = nil,
	card_height = nil,
	cards = nil,
	active_card = nil,
	active_container = nil,
	positions = nil,
	shadow_widgets = nil,
})

function CarouselRow:init()
	self.screen_width = self.screen_width or Screen:getWidth()
	self.card_width = self.card_width or math.floor(self.screen_width * CARD_WIDTH_RATIO)
	self.card_height = self.card_height or math.floor(Screen:getHeight() * CARD_HEIGHT_RATIO)
	self.active_index = self.active_index or PAGE_DICTIONARY
	self.dimen = Geom:new({ x = 0, y = 0, w = self.screen_width, h = self.card_height })
	self.cards = {}
	self.shadow_widgets = {}

	local popup = self.popup
	if popup then
		for index = PAGE_DICTIONARY, PAGE_WIKIPEDIA do
			if math.abs(index - self.active_index) <= 1 then
				local payload = popup.plugin:getPagePayload(popup.state, index, index == self.active_index)
				local card = popup:makeCard(payload, self.card_width, self.card_height)
				self.cards[index] = card

				if CARD_SHADOW_ENABLED and CARD_SHADOW_OFFSET > 0 then
					self.shadow_widgets[index] = LineWidget:new({
						background = CARD_SHADOW_COLOR,
						dimen = Geom:new({ w = self.card_width, h = self.card_height }),
					})
				end

				if index == self.active_index then
					self.active_card = card
				end
			end
		end
	end

	local active_x = math.floor((self.screen_width - self.card_width) / 2)
	self.positions = {
		[self.active_index - 1] = active_x - self.card_width - CARD_GAP,
		[self.active_index] = active_x,
		[self.active_index + 1] = active_x + self.card_width + CARD_GAP,
	}

	-- The centered card must also be part of the widget tree, otherwise
	-- widgets inside it (notably ScrollHtmlWidget) are painted but don't
	-- reliably receive touch/pan events.
	if self.active_card then
		self.active_container = CenterContainer:new({
			dimen = self.dimen,
			self.active_card,
		})
		self[1] = self.active_container
	end
end
function CarouselRow:getSize()
	return self.dimen
end

function CarouselRow:paintCardShadow(bb, base_x, base_y, index)
	if not CARD_SHADOW_ENABLED or CARD_SHADOW_OFFSET <= 0 then
		return
	end

	local shadow = self.shadow_widgets and self.shadow_widgets[index]
	local card_x = self.positions and self.positions[index]
	if not shadow or not card_x then
		return
	end

	local x = (base_x or 0) + card_x + CARD_SHADOW_OFFSET
	local y = (base_y or 0) + CARD_SHADOW_OFFSET

	if shadow.dimen then
		shadow.dimen.x = x
		shadow.dimen.y = y
		shadow.dimen.w = self.card_width
		shadow.dimen.h = self.card_height
	end

	shadow:paintTo(bb, x, y)
end

function CarouselRow:paintCard(bb, base_x, base_y, index)
	local card = self.cards and self.cards[index]
	local card_x = self.positions and self.positions[index]
	if not card or not card_x then
		return
	end

	local x = (base_x or 0) + card_x
	local y = base_y or 0

	self:paintCardShadow(bb, base_x, base_y, index)

	if card.dimen then
		card.dimen.x = x
		card.dimen.y = y
		card.dimen.w = self.card_width
		card.dimen.h = self.card_height
	end

	card:paintTo(bb, x, y)
end

function CarouselRow:paintTo(bb, x, y)
	x = x or (self.dimen and self.dimen.x) or 0
	y = y or (self.dimen and self.dimen.y) or 0

	-- Draw side cards first. They keep their full size and are simply clipped
	-- by the screen edge. The active card is painted through active_container
	-- so it remains a real child widget and can handle scrolling.
	self:paintCard(bb, x, y, self.active_index - 1)
	self:paintCard(bb, x, y, self.active_index + 1)

	if self.active_container then
		self:paintCardShadow(bb, x, y, self.active_index)
		self.active_container:paintTo(bb, x, y)
	else
		self:paintCard(bb, x, y, self.active_index)
	end
end
local LookupPreviewPopup = InputContainer:extend({
	plugin = nil,
	state = nil,
	active_index = PAGE_DICTIONARY,
	selection_bounds = nil,
	dialog = nil,
	anchor_top = false,
	card_container = nil,
	visible_dimen = nil,
	page_menu = nil,
})

function LookupPreviewPopup:shouldAnchorTop(row_height)
	local bounds = self.selection_bounds
	if type(bounds) ~= "table" or not bounds.top or not bounds.bottom then
		return false
	end

	local screen_height = Screen:getHeight()
	local top_card_bottom = CARD_EDGE_MARGIN + row_height
	local bottom_card_top = screen_height - CARD_EDGE_MARGIN - row_height

	if bottom_card_top > bounds.bottom + FLOATING_SELECTION_GAP then
		return false
	end
	if top_card_bottom < bounds.top - FLOATING_SELECTION_GAP then
		return true
	end

	local space_above = math.max(0, bounds.top - CARD_EDGE_MARGIN - FLOATING_SELECTION_GAP)
	local space_below = math.max(0, screen_height - bounds.bottom - CARD_EDGE_MARGIN - FLOATING_SELECTION_GAP)
	return space_above > space_below
end

function LookupPreviewPopup:makeHeader(payload, content_width)
	local menu_button = HeaderPageButton:new({
		text = "☰",
		width = HEADER_MENU_WIDTH,
		show_parent = self,
		callback = function()
			return self:showPageMenu()
		end,
	})

	local menu_width = HEADER_MENU_WIDTH
	local text_width = math.max(1, content_width - menu_width - HEADER_TITLE_MENU_GAP)

	local function makeLeftText(text, face, bold, callback)
		local widget
		if callback then
			widget = HeaderSubtitleButton:new({
				text = text or EMPTY_TEXT,
				face = face,
				width = text_width,
				show_parent = self,
				callback = callback,
			})
		else
			widget = TextWidget:new({
				text = text or EMPTY_TEXT,
				face = face,
				bold = bold and true or false,
				max_width = text_width,
			})
		end
		local size = getWidgetSize(widget)
		return LeftContainer:new({
			allow_mirroring = false,
			dimen = Geom:new({
				w = text_width,
				h = math.max(1, size.h or Screen:scaleBySize(14)),
			}),
			widget,
		})
	end

	local text_items = {
		makeLeftText(payload.title or EMPTY_TEXT, TITLE_FACE, true),
	}

	if payload.subtitle and payload.subtitle ~= "" then
		text_items[#text_items + 1] = VerticalSpan:new({ width = HEADER_GAP })
		text_items[#text_items + 1] = makeLeftText(payload.subtitle, SUBTITLE_FACE, false, payload.subtitle_callback)
	end

	local text_block = VerticalGroup:new(text_items)
	local text_height = getWidgetSize(text_block).h or Screen:scaleBySize(24)
	local menu_height = getWidgetSize(menu_button).h or HEADER_MENU_HEIGHT
	local row_height = math.max(text_height, menu_height)

	local items = {
		HorizontalGroup:new({
			LeftContainer:new({
				allow_mirroring = false,
				dimen = Geom:new({ w = text_width, h = row_height }),
				text_block,
			}),
			HorizontalSpan:new({ width = HEADER_TITLE_MENU_GAP }),
			CenterContainer:new({
				dimen = Geom:new({ w = menu_width, h = row_height }),
				menu_button,
			}),
		}),
		VerticalSpan:new({ width = HEADER_SEPARATOR_GAP }),
		LineWidget:new({
			background = Blitbuffer.COLOR_GRAY,
			dimen = Geom:new({ w = content_width, h = math.max(1, Screen:scaleBySize(1)) }),
		}),
		VerticalSpan:new({ width = HEADER_SEPARATOR_GAP }),
	}

	return VerticalGroup:new(items)
end

function LookupPreviewPopup:makeDictionaryButtons(payload, content_width)
	local button_specs = payload and (payload.card_buttons or payload.dictionary_buttons)
	if type(button_specs) ~= "table" or #button_specs == 0 then
		return nil
	end

	local separator_count = math.max(0, #button_specs - 1)
	local available_width = math.max(1, content_width - DICTIONARY_BUTTON_SEPARATOR_WIDTH * separator_count)
	local weights = {}
	local total_weight = 0

	for index, item in ipairs(button_specs) do
		local weight = tonumber(item.weight) or 1
		if weight <= 0 then
			weight = 1
		end
		weights[index] = weight
		total_weight = total_weight + weight
	end

	local used_width = 0
	local widgets = {}
	for index, item in ipairs(button_specs) do
		if index > 1 then
			widgets[#widgets + 1] = LineWidget:new({
				background = Blitbuffer.COLOR_GRAY,
				dimen = Geom:new({
					w = DICTIONARY_BUTTON_SEPARATOR_WIDTH,
					h = DICTIONARY_BUTTON_HEIGHT,
				}),
			})
		end

		local button_width
		if index == #button_specs then
			button_width = math.max(1, available_width - used_width)
		else
			button_width = math.max(1, math.floor(available_width * weights[index] / total_weight))
			used_width = used_width + button_width
		end

		local spec = item.spec or {}
		widgets[#widgets + 1] = DictionaryCardButton:new({
			text = spec.text,
			icon = spec.icon,
			icon_file = spec.icon_file,
			width = button_width,
			height = DICTIONARY_BUTTON_HEIGHT,
			icon_width = DICTIONARY_ICON_SIZE,
			icon_height = DICTIONARY_ICON_SIZE,
			show_parent = self,
			callback = item.callback,
		})
	end

	return HorizontalGroup:new(widgets)
end

function LookupPreviewPopup:makeCard(payload, card_width, card_height)
	local content_width = math.max(1, card_width - 2 * CARD_PADDING_H - 2 * CARD_BORDER_SIZE)
	local header = self:makeHeader(payload, content_width)
	local header_height = getWidgetSize(header).h or Screen:scaleBySize(46)
	local dictionary_buttons = self:makeDictionaryButtons(payload, content_width)
	local action_button_height = payload and payload.page_type == PAGE_TRANSLATION and TRANSLATION_BUTTON_HEIGHT
		or DICTIONARY_BUTTON_HEIGHT
	local action_button_gap = payload and payload.page_type == PAGE_TRANSLATION and TRANSLATION_BUTTON_GAP
		or DICTIONARY_BUTTON_GAP
	local dictionary_buttons_height = dictionary_buttons
			and (getWidgetSize(dictionary_buttons).h or action_button_height)
		or 0
	local dictionary_buttons_gap = dictionary_buttons and action_button_gap or 0
	local html_height = math.max(
		MIN_HTML_HEIGHT,
		card_height
			- header_height
			- dictionary_buttons_height
			- dictionary_buttons_gap
			- CARD_PADDING_TOP
			- CARD_PADDING_BOTTOM
			- 2 * CARD_BORDER_SIZE
	)

	local html_widget = ScrollHtmlWidget:new({
		html_body = payload.html_body or "",
		is_xhtml = true,
		css = payload.css or FALLBACK_CSS,
		html_resource_directory = payload.html_resource_directory,
		default_font_size = BODY_FONT_SIZE,
		width = content_width,
		height = html_height,
		scroll_bar_width = SCROLL_BAR_WIDTH,
		text_scroll_span = TEXT_SCROLL_SPAN,
		dialog = self.dialog,
		highlight_text_selection = false,
	})

	local content_items = {
		VerticalSpan:new({ width = CARD_PADDING_TOP }),
		HorizontalGroup:new({
			HorizontalSpan:new({ width = CARD_PADDING_H }),
			header,
			HorizontalSpan:new({ width = CARD_PADDING_H }),
		}),
		HorizontalGroup:new({
			HorizontalSpan:new({ width = CARD_PADDING_H }),
			html_widget,
			HorizontalSpan:new({ width = CARD_PADDING_H }),
		}),
	}

	if dictionary_buttons then
		content_items[#content_items + 1] = VerticalSpan:new({ width = dictionary_buttons_gap })
		content_items[#content_items + 1] = HorizontalGroup:new({
			HorizontalSpan:new({ width = CARD_PADDING_H }),
			dictionary_buttons,
			HorizontalSpan:new({ width = CARD_PADDING_H }),
		})
	end

	content_items[#content_items + 1] = VerticalSpan:new({ width = CARD_PADDING_BOTTOM })

	local content = VerticalGroup:new(content_items)

	local card = FrameContainer:new({
		background = Blitbuffer.COLOR_WHITE,
		bordersize = CARD_BORDER_SIZE,
		color = CARD_BORDER_COLOR,
		radius = CARD_RADIUS,
		margin = 0,
		padding = 0,
		content,
	})

	return card, Geom:new({ w = card_width, h = card_height })
end

function LookupPreviewPopup:makeRow(card_width, card_height)
	local row = CarouselRow:new({
		popup = self,
		active_index = self.active_index or PAGE_DICTIONARY,
		screen_width = Screen:getWidth(),
		card_width = card_width,
		card_height = card_height,
	})

	return row, card_height
end

function LookupPreviewPopup:init()
	local screen_width = Screen:getWidth()
	local screen_height = Screen:getHeight()
	local card_height = math.floor(screen_height * CARD_HEIGHT_RATIO)
	local card_width = math.max(CARD_MIN_WIDTH, math.floor(screen_width * CARD_WIDTH_RATIO))
	card_width = math.min(card_width, screen_width - 2 * CARD_EDGE_MARGIN)
	self.card_width = card_width
	self.card_height = card_height

	if IS_TOUCH_DEVICE then
		local range = Geom:new({ x = 0, y = 0, w = screen_width, h = screen_height })
		self.ges_events = {
			TapClose = { GestureRange:new({ ges = "tap", range = range }) },
			SwipePage = { GestureRange:new({ ges = "swipe", range = range }) },
		}
	end

	if HAS_KEYS then
		self.key_events = {
			Close = { { Device.input.group.Back } },
		}
	end

	local row, row_height = self:makeRow(card_width, card_height)
	self.card_container = row
	self.anchor_top = self:shouldAnchorTop(row_height)

	local y
	if self.anchor_top then
		y = CARD_EDGE_MARGIN
		self[1] = TopContainer:new({
			dimen = Screen:getSize(),
			VerticalGroup:new({
				VerticalSpan:new({ width = CARD_EDGE_MARGIN }),
				row,
			}),
		})
	else
		y = screen_height - CARD_EDGE_MARGIN - row_height
		self[1] = BottomContainer:new({
			dimen = Screen:getSize(),
			VerticalGroup:new({
				row,
				VerticalSpan:new({ width = CARD_EDGE_MARGIN }),
			}),
		})
	end

	local visible_height = row_height + (CARD_SHADOW_ENABLED and CARD_SHADOW_OFFSET or 0)
	self.visible_dimen = Geom:new({ x = 0, y = y, w = screen_width, h = visible_height })
end

function LookupPreviewPopup:closePageMenu()
	if self.page_menu then
		pcall(function()
			UIManager:close(self.page_menu)
		end)
		self.page_menu = nil
	end
end
function LookupPreviewPopup:getPageMenuAnchor()
	local screen_width = Screen:getWidth()
	local card_width = self.card_width or math.max(CARD_MIN_WIDTH, math.floor(screen_width * CARD_WIDTH_RATIO))
	card_width = math.min(card_width, screen_width - 2 * CARD_EDGE_MARGIN)

	local active_x = math.floor((screen_width - card_width) / 2)
	local content_width = math.max(1, card_width - 2 * CARD_PADDING_H - 2 * CARD_BORDER_SIZE)
	local x = active_x + CARD_BORDER_SIZE + CARD_PADDING_H + content_width - HEADER_MENU_WIDTH
	local y = ((self.visible_dimen and self.visible_dimen.y) or CARD_EDGE_MARGIN) + CARD_BORDER_SIZE + CARD_PADDING_TOP

	return Geom:new({
		x = x,
		y = y,
		w = HEADER_MENU_WIDTH,
		h = HEADER_MENU_HEIGHT,
	})
end

function LookupPreviewPopup:showPageMenu()
	self:closePageMenu()
	self.page_menu = SimplePageMenu:new({
		parent_popup = self,
		active_index = self.active_index or PAGE_DICTIONARY,
		anchor_dimen = self:getPageMenuAnchor(),
	})
	UIManager:show(self.page_menu)
	return true
end

function LookupPreviewPopup:onShow()
	UIManager:setDirty(self.dialog or self, function()
		return "ui", self.visible_dimen or Screen:getSize()
	end)
end

function LookupPreviewPopup:onCloseWidget()
	UIManager:setDirty(self.dialog or self, function()
		return "partial", self.visible_dimen or Screen:getSize()
	end)
end

function LookupPreviewPopup:onClose()
	self:closePageMenu()
	UIManager:close(self)
	if not self.skip_close_callback and self.plugin then
		return self.plugin:closePreview(false)
	end
	return true
end

function LookupPreviewPopup:onTapClose(_arg, ges)
	if ges and ges.pos and self.visible_dimen and ges.pos:notIntersectWith(self.visible_dimen) then
		return self:onClose()
	end
	return false
end

function LookupPreviewPopup:onSwipePage(_arg, ges)
	if not ges or not ges.direction then
		return false
	end

	if ges.direction == "west" then
		return self.plugin:switchToPage(math.min(PAGE_WIKIPEDIA, self.active_index + 1))
	elseif ges.direction == "east" then
		return self.plugin:switchToPage(math.max(PAGE_DICTIONARY, self.active_index - 1))
	end

	-- Do not close on vertical swipes. Vertical movement must remain available
	-- to ScrollHtmlWidget so dictionary/translation/Wikipedia content can scroll.
	return false
end

function LookupPreviewPopup:onNextPage()
	return self.plugin:switchToPage(math.min(PAGE_WIKIPEDIA, self.active_index + 1))
end

function LookupPreviewPopup:onPrevPage()
	return self.plugin:switchToPage(math.max(PAGE_DICTIONARY, self.active_index - 1))
end

function LookupPreview:init()
	self.current_popup = nil
	self.current_state = nil
	self.original_showDict = nil
	self.patched_dictionary = nil
	self.patched_highlight = nil
	self.original_highlight_lookupDict = nil
	self.original_highlight_translate = nil
	self.original_highlight_lookupWikipedia = nil
	self.opening_original_popup = false
	self.native_dict_popup_active = false
	self.native_dict_popup_count = 0
	self.selection_snapshot = nil
	self.plugin_icon_cache = {}
	self.language_menu = nil
	self.clipboard_available = Device:hasClipboard()

	if self.ui and self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end

	self:patchDictionary()
	self:patchHighlightActions()
end

function LookupPreview:addToMainMenu(menu_items)
	menu_items.lookuppreview = {
		text = _("Lookup preview"),
		sorting_hint = "tools",
		sub_item_table = {
			{
				text = _("Enable lookup preview"),
				checked_func = function()
					return self:isPreviewEnabled()
				end,
				callback = function()
					self:setPreviewEnabled(not self:isPreviewEnabled())
				end,
			},
			{
				text = string.format("%s: %s", _("Wikipedia language"), self:getWikipediaLang()),
				sub_item_table_func = function()
					return self:getWikipediaLanguageMenuItems(self.current_state)
				end,
			},
			{
				text = _("Translation"),
				sub_item_table = {
					{
						text = _("Show source text"),
						checked_func = function()
							return self:showTranslationSourceText()
						end,
						callback = function()
							G_reader_settings:saveSetting(
								SETTING_TRANSLATION_SHOW_SOURCE,
								not self:showTranslationSourceText()
							)
							if self.current_state and self.current_state.translation_text_main then
								self.current_state.translation_payload =
									self:buildTranslationPayload(self.current_state)
								self:refreshCurrentPage(PAGE_TRANSLATION)
							end
						end,
					},
					{
						text = _("Buttons"),
						sub_item_table = {
							{
								text = _("Show copy button"),
								checked_func = function()
									return self:showTranslationCopyButton()
								end,
								callback = function()
									G_reader_settings:saveSetting(
										SETTING_TRANSLATION_SHOW_COPY_BUTTON,
										not self:showTranslationCopyButton()
									)
									self:refreshCurrentPage(PAGE_TRANSLATION)
								end,
							},
							{
								text = _("Show note button"),
								checked_func = function()
									return self:showTranslationNoteButton()
								end,
								callback = function()
									G_reader_settings:saveSetting(
										SETTING_TRANSLATION_SHOW_NOTE_BUTTON,
										not self:showTranslationNoteButton()
									)
									self:refreshCurrentPage(PAGE_TRANSLATION)
								end,
							},
						},
					},
				},
			},
			{
				text = string.format("%s: %s", _("Version"), PLUGIN_VERSION),
				callback = function()
					self:notify(string.format("%s %s", _("Lookup Preview"), PLUGIN_VERSION))
				end,
				separator = true,
			},
		},
	}
end

function LookupPreview:isPreviewEnabled()
	return G_reader_settings:nilOrTrue(SETTING_ENABLED)
end

function LookupPreview:setPreviewEnabled(enabled)
	G_reader_settings:saveSetting(SETTING_ENABLED, enabled and true or false)
end

function LookupPreview:showTranslationSourceText()
	return G_reader_settings:readSetting(SETTING_TRANSLATION_SHOW_SOURCE) == true
end

function LookupPreview:showTranslationCopyButton()
	return G_reader_settings:nilOrTrue(SETTING_TRANSLATION_SHOW_COPY_BUTTON)
end

function LookupPreview:showTranslationNoteButton()
	return G_reader_settings:nilOrTrue(SETTING_TRANSLATION_SHOW_NOTE_BUTTON)
end

function LookupPreview:getWikipediaLang()
	local lang = G_reader_settings:readSetting(SETTING_WIKI_LANG)
		or G_reader_settings:readSetting("wikipedia_language")
		or G_reader_settings:readSetting("wikipedia_lang")
		or G_reader_settings:readSetting("translator_to_language")
		or "en"
	lang = tostring(lang or "en"):lower()
	if lang == "" then
		lang = "en"
	end
	return lang
end

function LookupPreview:getLeftButtonAction()
	local action = G_reader_settings:readSetting(SETTING_LEFT_ACTION) or DEFAULT_LEFT_ACTION
	if not LEFT_ACTION_BY_ID[action] then
		action = DEFAULT_LEFT_ACTION
	end
	return action
end

function LookupPreview:setLeftButtonAction(action)
	if not LEFT_ACTION_BY_ID[action] then
		action = DEFAULT_LEFT_ACTION
	end
	G_reader_settings:saveSetting(SETTING_LEFT_ACTION, action)
end

function LookupPreview:getPluginIconFile(action_id)
	self.plugin_icon_cache = self.plugin_icon_cache or {}
	if self.plugin_icon_cache[action_id] ~= nil then
		return self.plugin_icon_cache[action_id] or nil
	end

	local candidates = PLUGIN_LEFT_ICON_CANDIDATES[action_id]
	if not candidates or not self.path or self.path == "" then
		self.plugin_icon_cache[action_id] = false
		return nil
	end

	local icons_dir = self.path .. "/icons"
	for _, basename in ipairs(candidates) do
		for _, ext in ipairs(PLUGIN_ICON_EXTENSIONS) do
			local path = icons_dir .. "/" .. basename .. ext
			if fileExists(path) then
				self.plugin_icon_cache[action_id] = path
				return path
			end
		end
	end

	self.plugin_icon_cache[action_id] = false
	return nil
end

function LookupPreview:getLeftButtonSpec(action_id)
	action_id = LEFT_ACTION_BY_ID[action_id] and action_id or self:getLeftButtonAction()
	local action = LEFT_ACTION_BY_ID[action_id] or LEFT_ACTION_BY_ID[DEFAULT_LEFT_ACTION]

	if action_id == LEFT_ACTION_SEARCH_BOOK then
		return { icon = ICON_SEARCH }
	end

	local plugin_icon = self:getPluginIconFile(action_id)
	if plugin_icon then
		return { icon_file = plugin_icon }
	end

	return { text = action.label }
end

function LookupPreview:genLeftButtonActionMenu()
	local items = {}
	for _, action in ipairs(LEFT_ACTIONS) do
		items[#items + 1] = {
			text = action.label,
			radio = true,
			checked_func = function()
				return self:getLeftButtonAction() == action.id
			end,
			callback = function()
				self:setLeftButtonAction(action.id)
			end,
		}
	end
	return items
end

function LookupPreview:notify(message)
	UIManager:show(Notification:new({ text = message }))
	return true
end

function LookupPreview:destroy()
	self:closeLanguageMenu()
	self:closeCurrentPopup(true)

	if self.patched_highlight and self.patched_highlight._lookuppreview_highlight_patched == self then
		if self.original_highlight_lookupDict then
			self.patched_highlight.lookupDict = self.original_highlight_lookupDict
		end
		if self.original_highlight_translate then
			self.patched_highlight.translate = self.original_highlight_translate
		end
		if self.original_highlight_lookupWikipedia then
			self.patched_highlight.lookupWikipedia = self.original_highlight_lookupWikipedia
		end
		self.patched_highlight._lookuppreview_highlight_patched = nil
	end

	if self.patched_dictionary and self.original_showDict and self.patched_dictionary._lookuppreview_patched then
		self.patched_dictionary.showDict = self.original_showDict
		self.patched_dictionary._lookuppreview_patched = nil
	end

	self.original_showDict = nil
	self.patched_dictionary = nil
	self.patched_highlight = nil
	self.original_highlight_lookupDict = nil
	self.original_highlight_translate = nil
	self.original_highlight_lookupWikipedia = nil
	self.selection_snapshot = nil
	self.current_state = nil
	self.plugin_icon_cache = nil
	self:resetNativeDictionaryPopupGuard()

	if WidgetContainer.destroy then
		WidgetContainer.destroy(self)
	end
end

function LookupPreview:patchDictionary()
	local dictionary = self.ui and self.ui.dictionary
	if not dictionary then
		logger.warn("LookupPreview: ReaderDictionary not available.")
		return
	end
	if dictionary._lookuppreview_patched then
		return
	end

	self.original_showDict = dictionary.showDict
	self.patched_dictionary = dictionary
	local plugin = self

	dictionary.showDict = function(dict_self, word, results, boxes, link, dict_close_callback)
		if not plugin:isPreviewEnabled() or plugin.opening_original_popup or not results or not results[1] then
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

	dictionary._lookuppreview_patched = true
end


function LookupPreview:patchHighlightActions()
	local highlight = self.ui and self.ui.highlight
	if not highlight then
		logger.warn("LookupPreview: ReaderHighlight not available.")
		return
	end
	if highlight._lookuppreview_highlight_patched then
		return
	end

	self.patched_highlight = highlight
	self.original_highlight_lookupDict = highlight.lookupDict
	self.original_highlight_translate = highlight.translate
	self.original_highlight_lookupWikipedia = highlight.lookupWikipedia

	local plugin = self

	if self.original_highlight_lookupDict then
		highlight.lookupDict = function(highlight_self, ...)
			if plugin:isPreviewEnabled() and not plugin.opening_original_popup then
				plugin:rememberSelection(highlight_self)
			end
			return plugin.original_highlight_lookupDict(highlight_self, ...)
		end
	end

	if self.original_highlight_translate then
		highlight.translate = function(highlight_self, ...)
			if not plugin:isPreviewEnabled() or plugin.opening_original_popup then
				return plugin.original_highlight_translate(highlight_self, ...)
			end

			if plugin:showSelectionPreviewFromHighlight(highlight_self, PAGE_TRANSLATION) then
				return true
			end

			return plugin.original_highlight_translate(highlight_self, ...)
		end
	end

	if self.original_highlight_lookupWikipedia then
		highlight.lookupWikipedia = function(highlight_self, ...)
			if not plugin:isPreviewEnabled() or plugin.opening_original_popup then
				return plugin.original_highlight_lookupWikipedia(highlight_self, ...)
			end

			if plugin:showSelectionPreviewFromHighlight(highlight_self, PAGE_WIKIPEDIA) then
				return true
			end

			return plugin.original_highlight_lookupWikipedia(highlight_self, ...)
		end
	end

	highlight._lookuppreview_highlight_patched = self
end

function LookupPreview:getHighlightSelectionText(highlight)
	local selected_text = highlight and highlight.selected_text
	local text = ""

	if type(selected_text) == "table" then
		text = selected_text.text or selected_text.word or ""
	elseif type(selected_text) == "string" then
		text = selected_text
	end

	if text == "" and highlight and type(highlight.getSelectedText) == "function" then
		local ok, selected = pcall(function()
			return highlight:getSelectedText()
		end)
		if ok and selected then
			text = selected
		end
	end

	if util and util.cleanupSelectedText then
		local ok, cleaned = pcall(function()
			return util.cleanupSelectedText(text)
		end)
		if ok and cleaned then
			text = cleaned
		end
	end

	return trim(text)
end

function LookupPreview:getHighlightSelectionBounds(highlight)
	if not highlight then
		return nil
	end

	local screen_height = Screen:getHeight()
	local top
	local bottom

	local function addY(y)
		y = tonumber(y)
		if not y or y < 0 or y > screen_height then
			return
		end
		top = top and math.min(top, y) or y
		bottom = bottom and math.max(bottom, y) or y
	end

	local function addPosition(pos)
		if type(pos) ~= "table" then
			return
		end
		addY(pos.y)
	end

	local function addBox(box)
		if type(box) ~= "table" then
			return
		end
		if box.rect then
			box = box.rect
		end
		local y = tonumber(box.y)
		local h = tonumber(box.h)
		if y and h then
			addY(y)
			addY(y + h)
		end
	end

	addPosition(highlight.hold_pos)

	local selected_text = highlight.selected_text
	if type(selected_text) == "table" then
		addPosition(selected_text.pos0)
		addPosition(selected_text.pos1)
		if type(selected_text.boxes) == "table" then
			for _, box in ipairs(selected_text.boxes) do
				addBox(box)
			end
		end
	end

	if top and bottom then
		return { top = top, bottom = bottom }
	end

	return nil
end

function LookupPreview:buildSelectionStateFromHighlight(highlight)
	local text = self:getHighlightSelectionText(highlight)
	if text == "" then
		return nil
	end

	self:rememberSelection(highlight)

	local state = {
		dict_self = nil,
		highlight_self = highlight,
		word = text,
		results = {
			{
				word = text,
				no_result = true,
			},
		},
		preview_results = {},
		boxes = nil,
		link = nil,
		preview_count = 0,
		dictionary_index = 1,
		search_text = text,
		dictionary_search_text = text,
		translation_source_text = text,
		selection_bounds = self:getHighlightSelectionBounds(highlight),
		dialog = highlight and highlight.dialog or (self.ui and self.ui.highlight and self.ui.highlight.dialog),
	}

	state.dict_close_callback = function()
		if highlight and type(highlight.clear) == "function" then
			pcall(function()
				highlight:clear()
			end)
		end
	end

	state.dictionary_payload = self:buildDictionaryPayload(text, state.results[1], 1, 0)
	return state
end

function LookupPreview:showSelectionPreviewFromHighlight(highlight, active_index)
	local state = self:buildSelectionStateFromHighlight(highlight)
	if not state then
		return false
	end

	if highlight and type(highlight.onClose) == "function" then
		pcall(function()
			highlight:onClose(true)
		end)
	end

	self:showCarousel(state, active_index or PAGE_DICTIONARY, false)

	if active_index == PAGE_TRANSLATION then
		UIManager:scheduleIn(0.05, function()
			self:loadTranslation(state)
		end)
	elseif active_index == PAGE_WIKIPEDIA then
		UIManager:scheduleIn(0.05, function()
			self:loadWikipedia(state)
		end)
	end

	return true
end

function LookupPreview:beginNativeDictionaryPopup(dict_close_callback)
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

function LookupPreview:resetNativeDictionaryPopupGuard()
	self.native_dict_popup_count = 0
	self.native_dict_popup_active = false
end

function LookupPreview:showOriginalDictionaryPopup(dict_self, word, results, boxes, link, dict_close_callback)
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
		logger.warn("LookupPreview: failed to open original dictionary popup:", err)
	end

	return true
end

function LookupPreview:closeCurrentPopup(preserve_state)
	self:closeLanguageMenu()
	if self.current_popup then
		if self.current_popup.closePageMenu then
			self.current_popup:closePageMenu()
		end
		self.current_popup.skip_close_callback = true
		pcall(function()
			UIManager:close(self.current_popup)
		end)
		self.current_popup = nil
	end
	if not preserve_state then
		self.current_state = nil
	end
end

function LookupPreview:clearOriginalHighlight(dict_self)
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

function LookupPreview:clearSelection()
	if self.ui and self.ui.handleEvent then
		pcall(function()
			self.ui:handleEvent(Event:new("ClearSelection"))
		end)
	end
end

function LookupPreview:getActiveHighlight(dict_self)
	local candidates = {}
	if dict_self and dict_self.highlight then
		candidates[#candidates + 1] = dict_self.highlight
	end
	if self.ui and self.ui.highlight then
		candidates[#candidates + 1] = self.ui.highlight
	end
	if dict_self and dict_self.ui and dict_self.ui.highlight then
		candidates[#candidates + 1] = dict_self.ui.highlight
	end

	local fallback
	for _, highlight in ipairs(candidates) do
		if highlight then
			if highlight.selected_text or highlight.hold_pos then
				return highlight
			end
			if
				not fallback
				and (
					type(highlight.showHighlightPrompt) == "function"
					or type(highlight.lookupWikipedia) == "function"
					or type(highlight.clear) == "function"
				)
			then
				fallback = highlight
			end
		end
	end
	return fallback
end

function LookupPreview:rememberSelection(dict_self)
	local highlight = self:getActiveHighlight(dict_self)
	if not highlight then
		self.selection_snapshot = nil
		return nil
	end

	if not highlight.selected_text and highlight.hold_pos and type(highlight.highlightFromHoldPos) == "function" then
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

function LookupPreview:restoreSelection(dict_self)
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
		highlight.is_word_selection = false
	end

	if not highlight.selected_text and highlight.hold_pos and type(highlight.highlightFromHoldPos) == "function" then
		pcall(function()
			highlight:highlightFromHoldPos()
		end)
	end

	return highlight
end

function LookupPreview:getSearchText(word, result)
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

function LookupPreview:showSearchDialog(search_text)
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
			logger.warn("LookupPreview: direct search input failed:", err)
		end

		if self.ui and self.ui.handleEvent then
			local ok, err = pcall(function()
				self.ui:handleEvent(Event:new("ShowFulltextSearchInput", search_text))
			end)
			if ok then
				return true
			end
			logger.warn("LookupPreview: search input event failed:", err)
		end

		if self.ui and self.ui.search and type(self.ui.search.searchText) == "function" then
			local ok, err = pcall(function()
				self.ui.search:searchText(search_text)
			end)
			if ok then
				return true
			end
			logger.warn("LookupPreview: direct search execution failed:", err)
		end

		if self.ui and self.ui.handleEvent then
			local ok, err = pcall(function()
				self.ui:handleEvent(Event:new("ShowSearchDialog", search_text, 0, false, true))
			end)
			if not ok then
				logger.warn("LookupPreview: search dialog fallback failed:", err)
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

function LookupPreview:highlightSelection(dict_self, dict_close_callback)
	local highlight = self:restoreSelection(dict_self)

	if not highlight then
		return self:notify(_("No selection to highlight."))
	end

	if not highlight.selected_text and highlight.hold_pos and type(highlight.highlightFromHoldPos) == "function" then
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
			logger.warn("LookupPreview: highlight action failed:", err)
		end
	end)

	return true
end

function LookupPreview:lookupWikipedia(dict_self, search_text)
	local highlight = self:restoreSelection(dict_self)

	if
		highlight
		and type(highlight.lookupWikipedia) == "function"
		and (highlight.selected_text or highlight.hold_pos)
	then
		UIManager:scheduleIn(0.05, function()
			local ok, err = pcall(function()
				if
					not highlight.selected_text
					and highlight.hold_pos
					and type(highlight.highlightFromHoldPos) == "function"
				then
					highlight:highlightFromHoldPos()
				end
				highlight:lookupWikipedia()
				self.selection_snapshot = nil
			end)

			if not ok then
				logger.warn("LookupPreview: Wikipedia action failed:", err)
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

function LookupPreview:runLeftButtonAction(action, state, search_text)
	if not state then
		return true
	end

	action = LEFT_ACTION_BY_ID[action] and action or DEFAULT_LEFT_ACTION
	self:closeCurrentPopup(true)
	self.current_state = nil

	if action == LEFT_ACTION_HIGHLIGHT then
		return self:highlightSelection(state.dict_self, state.dict_close_callback)
	end

	self.selection_snapshot = nil
	self:clearOriginalHighlight(state.dict_self)
	self:clearSelection()
	if state.dict_close_callback then
		pcall(state.dict_close_callback)
	end
	return self:showSearchDialog(search_text)
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
	if type(results) ~= "table" then
		return results
	end

	local count = #results
	if count <= 1 or index == 1 then
		return results
	end

	local reordered = {}
	for i = index, count do
		reordered[#reordered + 1] = results[i]
	end
	for i = 1, index - 1 do
		reordered[#reordered + 1] = results[i]
	end
	return reordered
end

local function buildPreviewResults(results)
	local preview_results = {}
	if type(results) ~= "table" then
		return preview_results
	end
	for index, result in ipairs(results) do
		if result and not result.no_result then
			preview_results[#preview_results + 1] = {
				result = result,
				source_index = index,
			}
		end
	end
	if #preview_results == 0 and results[1] then
		preview_results[#preview_results + 1] = {
			result = results[1],
			source_index = 1,
		}
	end
	return preview_results
end

function LookupPreview:buildDictionaryPayload(word, result, result_index, result_count)
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

	local count_label = ""
	if not result.no_result and result_count and result_count > 1 then
		count_label = string.format("%d/%d", result_index or 1, result_count)
	end

	local subtitle = dict_name
	if count_label ~= "" then
		subtitle = string.format("%s · %s ▾", dict_name, count_label)
	end

	return {
		page_type = PAGE_DICTIONARY,
		title = tostring(shown_word or _("Dictionary")),
		subtitle = subtitle,
		html_body = definition_html,
		css = css,
		html_resource_directory = result.dictionary_resource_directory,
	}
end

function LookupPreview:buildDictionaryButtons(state, search_text)
	if not state then
		return nil
	end

	search_text = search_text or state.dictionary_search_text or state.search_text or ""

	local button_specs = {
		{
			spec = self:getLeftButtonSpec(LEFT_ACTION_HIGHLIGHT),
			callback = function()
				self:closeCurrentPopup(true)
				self.current_state = nil
				return self:highlightSelection(state.dict_self, state.dict_close_callback)
			end,
		},
		{
			spec = self:getLeftButtonSpec(LEFT_ACTION_SEARCH_BOOK),
			callback = function()
				self:closeCurrentPopup(true)
				self.current_state = nil
				self.selection_snapshot = nil
				self:clearOriginalHighlight(state.dict_self)
				self:clearSelection()
				if state.dict_close_callback then
					pcall(state.dict_close_callback)
				end
				return self:showSearchDialog(search_text)
			end,
		},
	}

	if state.preview_count and state.preview_count > 1 then
		button_specs[#button_specs + 1] = {
			spec = { icon = ICON_PREVIOUS },
			callback = function()
				return self:switchDictionaryResult((state.dictionary_index or 1) - 1)
			end,
		}
		button_specs[#button_specs + 1] = {
			spec = { icon = ICON_NEXT },
			callback = function()
				return self:switchDictionaryResult((state.dictionary_index or 1) + 1)
			end,
		}
	end

	button_specs[#button_specs + 1] = {
		spec = { icon = ICON_DETAILS },
		callback = function()
			return self:openOriginalDictionaryFromState(state)
		end,
	}

	return button_specs
end

function LookupPreview:updateDictionaryPayload(state, index)
	if not state then
		return nil
	end

	local preview_count = state.preview_count or #(state.preview_results or {})
	state.dictionary_index = normalizeResultIndex(index or state.dictionary_index or 1, preview_count)

	local preview_entry = state.preview_results and state.preview_results[state.dictionary_index] or nil
	local result = preview_entry and preview_entry.result or (state.results and state.results[1]) or {}

	state.dictionary_search_text = self:getSearchText(state.word, result)
	state.dictionary_payload = self:buildDictionaryPayload(state.word, result, state.dictionary_index, preview_count)
	return state.dictionary_payload
end

function LookupPreview:switchDictionaryResult(index)
	local state = self.current_state
	if not state then
		return true
	end

	self:updateDictionaryPayload(state, index)
	return self:showCarousel(state, PAGE_DICTIONARY, true)
end

function LookupPreview:getDictionaryMenuItems(state)
	local items = {}
	local preview_results = state and state.preview_results or {}
	local active_index = state and (state.dictionary_index or 1) or 1

	local function getFoundWord(result)
		local found_word = result and result.word or ""
		if type(found_word) == "table" then
			found_word = found_word.text or found_word.word or ""
		end

		found_word = trim(found_word)
		if found_word == "" then
			found_word = self:getSearchText(state and state.word or "", result)
		end
		if found_word == "" and state then
			found_word = trim(state.search_text or "")
		end

		return found_word
	end

	for index, entry in ipairs(preview_results) do
		local result = entry and entry.result or {}
		local dict_name = trim(result.dict or "")
		if dict_name == "" then
			dict_name = string.format("%s %d", _("Dictionary"), index)
		end

		local found_word = getFoundWord(result)
		local item_text = dict_name
		if found_word ~= "" then
			item_text = string.format("%s · %s", found_word, dict_name)
		end

		items[#items + 1] = {
			text = item_text,
			radio = true,
			checked_func = function()
				return (state and (state.dictionary_index or 1) or active_index) == index
			end,
			callback = function()
				self:closeLanguageMenu()
				return self:switchDictionaryResult(index)
			end,
		}
	end

	if #items == 0 then
		items[1] = {
			text = _("No definition found."),
			enabled_func = function()
				return false
			end,
		}
	end

	return items
end

function LookupPreview:showDictionaryMenu(state)
	local Menu = require("ui/widget/menu")
	self:closeLanguageMenu()

	self.language_menu = Menu:new({
		title = _("Dictionary"),
		item_table = self:getDictionaryMenuItems(state),
		width = Screen:getWidth() - Screen:scaleBySize(80),
		height = math.floor(Screen:getHeight() * 0.8),
	})

	UIManager:show(self.language_menu)
	return true
end

function LookupPreview:openOriginalDictionaryFromState(state)
	state = state or self.current_state
	if not state then
		return true
	end

	local preview_count = state.preview_count or #(state.preview_results or {})
	local preview_index = normalizeResultIndex(state.dictionary_index or 1, preview_count)
	local preview_entry = state.preview_results and state.preview_results[preview_index] or nil
	local source_index = preview_entry and preview_entry.source_index or 1
	local selected_results = reorderResultsFromIndex(state.results, source_index)

	self:closeCurrentPopup(true)
	self.current_state = nil
	return self:showOriginalDictionaryPopup(
		state.dict_self,
		state.word,
		selected_results,
		state.boxes,
		state.link,
		state.dict_close_callback
	)
end

function LookupPreview:makeLoadingPayload(title, message)
	return {
		title = title,
		subtitle = self.current_state and self.current_state.search_text or "",
		html_body = '<p class="lp-muted">' .. htmlEscape(message or _("Loading…")) .. "</p>",
		css = FALLBACK_CSS,
	}
end

function LookupPreview:getPagePayload(state, index, is_active)
	state = state or self.current_state or {}
	if is_active == nil then
		is_active = true
	end

	if index == PAGE_DICTIONARY then
		local payload = state.dictionary_payload or self:makeLoadingPayload(_("Dictionary"), _("No definition found."))
		if is_active then
			payload = copyTable(payload)
			if state.preview_count and state.preview_count > 1 then
				payload.subtitle_callback = function()
					return self:showDictionaryMenu(state)
				end
			end
			payload.dictionary_buttons =
				self:buildDictionaryButtons(state, state.dictionary_search_text or state.search_text or "")
		end
		return payload
	end

	if index == PAGE_TRANSLATION then
		if state.translation_payload then
			local payload = state.translation_payload
			if is_active then
				payload = copyTable(payload)
				payload.card_buttons = self:buildTranslationButtons(state)
			end
			return payload
		end
		if state.translation_error then
			return {
				page_type = PAGE_TRANSLATION,
				title = _("Translate"),
				subtitle = state.search_text or "",
				html_body = plainTextToHtml(state.translation_error),
				css = FALLBACK_CSS,
			}
		end
		if is_active then
			local payload = self:makeLoadingPayload(_("Translate"), _("Querying translation service…"))
			payload.page_type = PAGE_TRANSLATION
			return payload
		end
		local payload = self:makeLoadingPayload(_("Translate"), _("Swipe to open translation."))
		payload.page_type = PAGE_TRANSLATION
		return payload
	end

	if index == PAGE_WIKIPEDIA then
		if state.wikipedia_payload then
			local payload = state.wikipedia_payload
			if is_active then
				payload = copyTable(payload)
				payload.card_buttons = self:buildWikipediaButtons(state)
			end
			return payload
		end
		if state.wikipedia_error then
			local payload = {
				page_type = PAGE_WIKIPEDIA,
				title = _("Wikipedia"),
				subtitle = state.search_text or "",
				subtitle_callback = function()
					return self:showWikipediaLanguageMenu(state)
				end,
				html_body = plainTextToHtml(state.wikipedia_error),
				css = FALLBACK_CSS,
			}
			if is_active then
				payload.card_buttons = self:buildWikipediaLanguageButton(state)
			end
			return payload
		end
		if is_active then
			local payload = self:makeLoadingPayload(_("Wikipedia"), _("Querying Wikipedia…"))
			payload.page_type = PAGE_WIKIPEDIA
			payload.subtitle_callback = function()
				return self:showWikipediaLanguageMenu(state)
			end
			payload.card_buttons = self:buildWikipediaLanguageButton(state)
			return payload
		end
		local payload = self:makeLoadingPayload(_("Wikipedia"), _("Swipe to open Wikipedia."))
		payload.page_type = PAGE_WIKIPEDIA
		return payload
	end

	return self:makeLoadingPayload(_("Lookup"), _("No content."))
end

function LookupPreview:closeLanguageMenu()
	if self.language_menu then
		pcall(function()
			UIManager:close(self.language_menu)
		end)
		self.language_menu = nil
	end
end

function LookupPreview:buildTranslationPayload(state)
	state = state or self.current_state or {}
	local text_main = state.translation_text_main or _("No translation found.")
	local source_text = state.translation_source_text or state.search_text or ""
	local source_lang = state.translation_source_lang or "auto"
	local target_lang = state.translation_target_lang or G_reader_settings:readSetting("translator_to_language") or "en"
	local source_name = self:getTranslatorLanguageLabel(Translator, source_lang)
	local target_name = self:getTranslatorLanguageLabel(Translator, target_lang)
	local parts = {
		'<div class="lp-translation">' .. plainTextToHtml(text_main) .. "</div>",
	}

	if self:showTranslationSourceText() then
		parts[#parts + 1] = '<div class="lp-source-label">' .. htmlEscape(_("Source")) .. "</div>"
		parts[#parts + 1] = '<div class="lp-source">' .. plainTextToHtml(source_text) .. "</div>"
	end

	return {
		page_type = PAGE_TRANSLATION,
		title = _("Translate"),
		subtitle = string.format("%s → %s ▾", source_name, target_name),
		subtitle_callback = function()
			return self:showTargetLanguageMenu(state)
		end,
		html_body = table.concat(parts, "\n"),
		css = FALLBACK_CSS,
	}
end

function LookupPreview:buildTranslationButtons(state)
	if not state or not state.translation_text_main then
		return nil
	end

	local button_specs = {}

	if self.clipboard_available and self:showTranslationCopyButton() then
		button_specs[#button_specs + 1] = {
			spec = { text = _("Copy") },
			callback = function()
				return self:copyMainTranslation(state.translation_text_main)
			end,
		}
	end

	if self:showTranslationNoteButton() then
		button_specs[#button_specs + 1] = {
			spec = { text = _("Note") },
			callback = function()
				return self:saveMainTranslationToNote(state.translation_text_main)
			end,
		}
	end

	button_specs[#button_specs + 1] = {
		spec = { icon = ICON_DETAILS },
		callback = function()
			return self:openOriginalTranslationFromState(state)
		end,
	}

	return button_specs
end

function LookupPreview:copyMainTranslation(text_main)
	if not self.clipboard_available then
		return self:notify(_("Clipboard is not available."))
	end

	Device.input.setClipboardText(text_main or "")
	return self:notify(_("Translation copied to clipboard."))
end

function LookupPreview:saveMainTranslationToNote(text_main)
	local state = self.current_state
	local highlight = state and self:getActiveHighlight(state.dict_self) or nil

	if not highlight then
		return self:notify(_("No highlight available."))
	end

	self:closeCurrentPopup(true)
	self.current_state = nil

	if highlight.highlight_dialog then
		UIManager:close(highlight.highlight_dialog)
		highlight.highlight_dialog = nil
	end

	if type(highlight.addNote) == "function" then
		highlight:addNote(text_main or "")
		return true
	end

	return self:notify(_("Could not create note."))
end

function LookupPreview:openOriginalTranslationFromState(state)
	state = state or self.current_state
	if not state then
		return true
	end

	local text = state.translation_source_text or state.search_text or ""
	local source_lang = state.translation_source_lang
		or G_reader_settings:readSetting("translator_from_language")
		or "auto"
	local target_lang = state.translation_target_lang or G_reader_settings:readSetting("translator_to_language") or "en"
	local cleanup_state = state

	self:closeCurrentPopup(true)
	self.current_state = nil

	local ok, err = pcall(function()
		Translator:showTranslation(text, true, source_lang, target_lang, false, nil)
	end)

	if not ok then
		logger.warn("LookupPreview: failed to open original translation widget:", err)
		return self:notify(_("Could not open the original translator."))
	end

	-- The native translator widget does not receive the dictionary close
	-- callback, unlike the native dictionary widget. If we leave the original
	-- selection alive here, the next tap may re-trigger showDict() and reopen
	-- the Lookup Preview carousel. Clear the selection after the translator has
	-- been opened so closing the native widget returns to a clean reader state.
	UIManager:scheduleIn(0.05, function()
		if cleanup_state ~= nil then
			self.selection_snapshot = nil
			self:clearOriginalHighlight(cleanup_state.dict_self)
			self:clearSelection()
			if cleanup_state.dict_close_callback then
				pcall(cleanup_state.dict_close_callback)
			end
		end
	end)

	return true
end

function LookupPreview:getTargetLanguageMenuItems(state)
	local translator = Translator
	local items = {}

	local ok, settings_menu = pcall(function()
		return translator:genSettingsMenu()
	end)

	if ok and settings_menu and type(settings_menu.sub_item_table) == "table" then
		local target_sub_items

		for i = #settings_menu.sub_item_table, 1, -1 do
			local item = settings_menu.sub_item_table[i]
			if type(item) == "table" and type(item.sub_item_table) == "table" then
				target_sub_items = item.sub_item_table
				break
			end
		end

		if target_sub_items then
			for _, item in ipairs(target_sub_items) do
				local menu_item = item
				items[#items + 1] = {
					text = menu_item.text,
					text_func = menu_item.text_func,
					checked_func = menu_item.checked_func,
					enabled_func = menu_item.enabled_func,
					radio = menu_item.radio,
					separator = menu_item.separator,
					callback = function()
						if menu_item.callback then
							menu_item.callback()
						end

						local selected_lang = translator:getTargetLanguage()
						return self:refreshTranslationWithTarget(state, selected_lang)
					end,
				}
			end
		end
	end

	if #items > 0 then
		return items
	end

	for _, lang in ipairs(COMMON_TARGET_LANGUAGES) do
		local lang_key = lang
		items[#items + 1] = {
			text = string.format("%s (%s)", self:getTranslatorLanguageLabel(translator, lang_key), lang_key),
			checked_func = function()
				return translator:getTargetLanguage() == lang_key
			end,
			radio = true,
			callback = function()
				return self:refreshTranslationWithTarget(state, lang_key)
			end,
		}
	end

	return items
end

function LookupPreview:showTargetLanguageMenu(state)
	if not state then
		return true
	end

	local Menu = require("ui/widget/menu")
	self:closeLanguageMenu()

	self.language_menu = Menu:new({
		title = _("Translate to"),
		item_table = self:getTargetLanguageMenuItems(state),
		width = Screen:getWidth() - Screen:scaleBySize(80),
		height = math.floor(Screen:getHeight() * 0.8),
	})

	UIManager:show(self.language_menu)
	return true
end

function LookupPreview:refreshTranslationWithTarget(state, target_lang)
	self:closeLanguageMenu()

	if not state or state ~= self.current_state then
		return true
	end

	G_reader_settings:saveSetting("translator_to_language", target_lang)
	state.translation_target_lang = target_lang
	state.translation_payload = nil
	state.translation_error = nil
	state.translation_loading = nil
	state.translation_text_main = nil
	state.translation_source_lang = nil

	self:showCarousel(state, PAGE_TRANSLATION, true)
	UIManager:scheduleIn(0.05, function()
		self:loadTranslation(state)
	end)
	return true
end

function LookupPreview:getTranslatorLanguageLabel(translator, lang)
	if translator and type(translator.getLanguageName) == "function" then
		local ok, name = pcall(function()
			return translator:getLanguageName(lang, lang and lang:upper() or "?")
		end)
		if ok and name then
			return name
		end
	end
	return tostring(lang or "?")
end

function LookupPreview:loadTranslation(state)
	if state ~= self.current_state then
		return true
	end
	if not state or state.translation_loading or state.translation_payload or state.translation_error then
		return true
	end

	state.translation_loading = true
	local text = state.search_text or ""
	local translator = Translator

	if text == "" then
		state.translation_error = _("No text to translate.")
		state.translation_loading = false
		return self:refreshCurrentPage(PAGE_TRANSLATION)
	end

	local NetworkMgr = require("ui/network/manager")
	if
		NetworkMgr:willRerunWhenOnline(function()
			state.translation_loading = false
			self:loadTranslation(state)
		end)
	then
		state.translation_error = _("Waiting for network connection.")
		state.translation_loading = false
		return self:refreshCurrentPage(PAGE_TRANSLATION)
	end

	local ok, err = pcall(function()
		local target_lang = state.translation_target_lang
			or (translator.getTargetLanguage and translator:getTargetLanguage())
			or G_reader_settings:readSetting("translator_to_language")
			or "en"
		local source_lang = state.translation_source_lang
			or (translator.getSourceLanguage and translator:getSourceLanguage())
			or G_reader_settings:readSetting("translator_from_language")
			or "auto"
		local Trapper = require("ui/trapper")
		local completed, result = Trapper:dismissableRunInSubprocess(function()
			return translator:loadPage(text, target_lang, source_lang)
		end, _("Querying translation service…"))

		if not completed then
			state.translation_error = _("Translation interrupted.")
			return
		end
		if not result or type(result) ~= "table" then
			state.translation_error = _("Translation failed.")
			return
		end
		if result[3] then
			source_lang = result[3]
		end

		local text_main = extractMainTranslation(result)
		if text_main == "" then
			text_main = _("No translation found.")
		end

		state.translation_text_main = text_main
		state.translation_source_text = text
		state.translation_source_lang = source_lang
		state.translation_target_lang = target_lang
		state.translation_payload = self:buildTranslationPayload(state)
	end)

	if not ok then
		logger.warn("LookupPreview: translation failed:", err)
		state.translation_error = tostring(err or _("Translation failed."))
	end

	state.translation_loading = false
	return self:refreshCurrentPage(PAGE_TRANSLATION)
end

function LookupPreview:getWikipediaLanguageLabel(lang)
	local translator = Translator
	if translator and type(translator.getLanguageName) == "function" then
		local ok, name = pcall(function()
			return translator:getLanguageName(lang, lang and lang:upper() or "?")
		end)
		if ok and name then
			return name
		end
	end
	return tostring(lang or "?")
end

function LookupPreview:getWikipediaLanguageMenuItems(state)
	local items = {}
	local current_lang = self:getWikipediaLang()

	for _, lang in ipairs(COMMON_TARGET_LANGUAGES) do
		local lang_key = lang
		items[#items + 1] = {
			text = string.format("%s (%s)", self:getWikipediaLanguageLabel(lang_key), lang_key),
			checked_func = function()
				return self:getWikipediaLang() == lang_key
			end,
			radio = true,
			callback = function()
				return self:refreshWikipediaWithLanguage(state, lang_key)
			end,
		}
	end

	-- Keep the currently configured language reachable even if it is not in the
	-- compact common list above.
	local found_current = false
	for _, item in ipairs(items) do
		if item.checked_func and item.checked_func() then
			found_current = true
			break
		end
	end
	if not found_current and current_lang ~= "" then
		table.insert(items, 1, {
			text = string.format("%s (%s)", self:getWikipediaLanguageLabel(current_lang), current_lang),
			checked_func = function()
				return self:getWikipediaLang() == current_lang
			end,
			radio = true,
			callback = function()
				return self:refreshWikipediaWithLanguage(state, current_lang)
			end,
		})
	end

	return items
end

function LookupPreview:showWikipediaLanguageMenu(state)
	local Menu = require("ui/widget/menu")
	self:closeLanguageMenu()

	self.language_menu = Menu:new({
		title = _("Wikipedia language"),
		item_table = self:getWikipediaLanguageMenuItems(state),
		width = Screen:getWidth() - Screen:scaleBySize(80),
		height = math.floor(Screen:getHeight() * 0.8),
	})

	UIManager:show(self.language_menu)
	return true
end

function LookupPreview:refreshWikipediaWithLanguage(state, lang)
	self:closeLanguageMenu()
	lang = tostring(lang or "en"):lower()
	if lang == "" then
		lang = "en"
	end

	G_reader_settings:saveSetting(SETTING_WIKI_LANG, lang)

	if not state or state ~= self.current_state then
		return true
	end

	state.wikipedia_lang = lang
	state.wikipedia_payload = nil
	state.wikipedia_error = nil
	state.wikipedia_loading = nil
	state.wikipedia_full_loading = nil
	state.wikipedia_pages = nil
	state.wikipedia_count = nil
	state.wikipedia_index = 1

	self:showCarousel(state, PAGE_WIKIPEDIA, true)
	UIManager:scheduleIn(0.05, function()
		self:loadWikipedia(state)
	end)
	return true
end

function LookupPreview:buildWikipediaResults(pages)
	local results = {}
	if type(pages) ~= "table" then
		return results
	end

	for _, page in pairs(pages) do
		if type(page) == "table" then
			results[#results + 1] = {
				page = page,
				index = tonumber(page.index or 999999) or 999999,
			}
		end
	end

	table.sort(results, function(a, b)
		if a.index == b.index then
			return tostring(a.page and a.page.title or "") < tostring(b.page and b.page.title or "")
		end
		return a.index < b.index
	end)

	return results
end

function LookupPreview:getWikipediaArticleMenuItems(state)
	local items = {}
	local pages = state and state.wikipedia_pages or {}
	local active_index = state and (state.wikipedia_index or 1) or 1

	for index, entry in ipairs(pages) do
		local page = entry and entry.page or {}
		local title = trim(page.title or "")
		if title == "" then
			title = string.format("%s %d", _("Article"), index)
		end

		items[#items + 1] = {
			text = title,
			radio = true,
			checked_func = function()
				return (state and (state.wikipedia_index or 1) or active_index) == index
			end,
			callback = function()
				self:closeLanguageMenu()
				return self:switchWikipediaResult(index)
			end,
		}
	end

	if #items == 0 then
		items[1] = {
			text = _("No Wikipedia article found."),
			enabled_func = function()
				return false
			end,
		}
	end

	return items
end

function LookupPreview:showWikipediaArticleMenu(state)
	local Menu = require("ui/widget/menu")
	self:closeLanguageMenu()

	self.language_menu = Menu:new({
		title = _("Wikipedia"),
		item_table = self:getWikipediaArticleMenuItems(state),
		width = Screen:getWidth() - Screen:scaleBySize(80),
		height = math.floor(Screen:getHeight() * 0.8),
	})

	UIManager:show(self.language_menu)
	return true
end

function LookupPreview:buildWikipediaPayload(state, page, page_index, page_count, is_full_article)
	state = state or self.current_state or {}
	page = page or {}
	local lang = state.wikipedia_lang or self:getWikipediaLang()
	local title = trim(page.title or state.search_text or _("Wikipedia"))
	local extract = trim(page.extract or "")

	if extract == "" then
		extract = is_full_article and _("No full article found.") or _("No introduction found.")
	end

	local subtitle = title .. " · " .. lang
	if page_count and page_count > 1 then
		subtitle = string.format("%s · %d/%d", subtitle, page_index or 1, page_count)
	end
	if is_full_article then
		subtitle = subtitle .. " · " .. _("Full article")
	end
	subtitle = subtitle .. " ▾"

	return {
		page_type = PAGE_WIKIPEDIA,
		title = _("Wikipedia"),
		subtitle = subtitle,
		subtitle_callback = function()
			return self:showWikipediaArticleMenu(state)
		end,
		html_body = '<div class="lp-title">' .. plainTextToHtml(title) .. "</div>" .. plainTextToHtml(extract),
		css = FALLBACK_CSS,
	}
end

function LookupPreview:updateWikipediaPayload(state, index)
	if not state then
		return nil
	end

	local pages = state.wikipedia_pages or {}
	local page_count = state.wikipedia_count or #pages
	state.wikipedia_index = normalizeResultIndex(index or state.wikipedia_index or 1, page_count)

	local entry = pages[state.wikipedia_index]
	local page = entry and entry.page or nil
	if not page then
		return nil
	end

	state.wikipedia_payload = self:buildWikipediaPayload(state, page, state.wikipedia_index, page_count, false)
	return state.wikipedia_payload
end

function LookupPreview:switchWikipediaResult(index)
	local state = self.current_state
	if not state then
		return true
	end

	self:updateWikipediaPayload(state, index)
	return self:showCarousel(state, PAGE_WIKIPEDIA, true)
end

function LookupPreview:buildWikipediaLanguageButton(state)
	state = state or self.current_state
	return {
		{
			spec = { text = tostring((state and state.wikipedia_lang) or self:getWikipediaLang()):upper() },
			weight = 1,
			callback = function()
				return self:showWikipediaLanguageMenu(state)
			end,
		},
	}
end

function LookupPreview:buildWikipediaButtons(state)
	if not state or not state.wikipedia_payload then
		return nil
	end

	local button_specs = {}
	local count = state.wikipedia_count or #(state.wikipedia_pages or {})

	button_specs[#button_specs + 1] = {
		spec = { text = C_("Wikipedia", "Full article") },
		weight = 1.75,
		callback = function()
			return self:openFullWikipediaArticleFromState(state)
		end,
	}

	button_specs[#button_specs + 1] = {
		spec = { text = tostring(state.wikipedia_lang or self:getWikipediaLang()):upper() },
		weight = 0.9,
		callback = function()
			return self:showWikipediaLanguageMenu(state)
		end,
	}

	if count > 1 then
		button_specs[#button_specs + 1] = {
			spec = { icon = ICON_PREVIOUS },
			weight = 0.85,
			callback = function()
				return self:switchWikipediaResult((state.wikipedia_index or 1) - 1)
			end,
		}
		button_specs[#button_specs + 1] = {
			spec = { icon = ICON_NEXT },
			weight = 0.85,
			callback = function()
				return self:switchWikipediaResult((state.wikipedia_index or 1) + 1)
			end,
		}
	end

	button_specs[#button_specs + 1] = {
		spec = { icon = ICON_DETAILS },
		weight = 0.85,
		callback = function()
			return self:openOriginalWikipediaFromState(state)
		end,
	}

	return button_specs
end

function LookupPreview:cleanupSelectionAfterNativeWikipedia(state)
	local cleanup_state = state
	UIManager:scheduleIn(0.05, function()
		if cleanup_state then
			self.selection_snapshot = nil
			self:clearOriginalHighlight(cleanup_state.dict_self)
			self:clearSelection()
			if cleanup_state.dict_close_callback then
				pcall(cleanup_state.dict_close_callback)
			end
		end
	end)
	return true
end

function LookupPreview:openOriginalWikipediaFromState(state)
	state = state or self.current_state
	if not state then
		return true
	end

	local search_text = trim(state.search_text or state.wikipedia_search_text or "")
	if search_text == "" then
		return self:notify(_("No text to search on Wikipedia."))
	end

	local lang = state.wikipedia_lang or self:getWikipediaLang()
	local cleanup_state = state

	self:closeCurrentPopup(true)
	self.current_state = nil

	local ok, err = pcall(function()
		if self.ui and self.ui.handleEvent then
			return self.ui:handleEvent(Event:new("LookupWikipedia", search_text, true, false, false, lang, nil))
		end
	end)

	if not ok then
		logger.warn("LookupPreview: failed to open original Wikipedia widget:", err)
		return self:notify(_("Could not open Wikipedia."))
	end

	return self:cleanupSelectionAfterNativeWikipedia(cleanup_state)
end

function LookupPreview:openFullWikipediaArticleFromState(state)
	state = state or self.current_state
	if not state then
		return true
	end

	local pages = state.wikipedia_pages or {}
	local entry = pages[state.wikipedia_index or 1]
	local title = trim((entry and entry.page and entry.page.title) or state.search_text or "")
	if title == "" then
		return self:notify(_("No Wikipedia article found."))
	end

	local lang = state.wikipedia_lang or self:getWikipediaLang()
	local cleanup_state = state

	self:closeCurrentPopup(true)
	self.current_state = nil

	local ok, err = pcall(function()
		if self.ui and self.ui.handleEvent then
			return self.ui:handleEvent(Event:new("LookupWikipedia", title, true, false, true, lang, nil))
		end
	end)

	if not ok then
		logger.warn("LookupPreview: failed to open full Wikipedia article:", err)
		return self:notify(_("Could not open Wikipedia article."))
	end

	return self:cleanupSelectionAfterNativeWikipedia(cleanup_state)
end

function LookupPreview:loadFullWikipediaArticle(state)
	state = state or self.current_state
	if state ~= self.current_state then
		return true
	end
	if not state or state.wikipedia_full_loading then
		return true
	end

	local pages = state.wikipedia_pages or {}
	local entry = pages[state.wikipedia_index or 1]
	local title = trim((entry and entry.page and entry.page.title) or state.search_text or "")
	if title == "" then
		return self:notify(_("No Wikipedia article found."))
	end

	state.wikipedia_full_loading = true
	local loading_payload = self:buildWikipediaPayload(
		state,
		entry and entry.page or { title = title },
		state.wikipedia_index or 1,
		state.wikipedia_count or #pages,
		false
	)
	loading_payload.html_body = '<p class="lp-muted">' .. htmlEscape(_("Querying full Wikipedia article…")) .. "</p>"
	state.wikipedia_payload = loading_payload
	self:refreshCurrentPage(PAGE_WIKIPEDIA)

	local NetworkMgr = require("ui/network/manager")
	if
		NetworkMgr:willRerunWhenOnline(function()
			state.wikipedia_full_loading = false
			self:loadFullWikipediaArticle(state)
		end)
	then
		state.wikipedia_error = _("Waiting for network connection.")
		state.wikipedia_full_loading = false
		return self:refreshCurrentPage(PAGE_WIKIPEDIA)
	end

	local ok, err = pcall(function()
		local Wikipedia = require("ui/wikipedia")
		local lang = state.wikipedia_lang or self:getWikipediaLang()
		if type(Wikipedia.setTrapWidget) == "function" then
			Wikipedia:setTrapWidget(_("Querying Wikipedia…"))
		end
		local full_pages = Wikipedia:getFullPage(title, lang)
		if type(Wikipedia.resetTrapWidget) == "function" then
			Wikipedia:resetTrapWidget()
		end

		local full_page = self:pickBestWikipediaPage(full_pages)
		if not full_page then
			state.wikipedia_error = _("No Wikipedia article found.")
			return
		end

		state.wikipedia_payload = self:buildWikipediaPayload(
			state,
			full_page,
			state.wikipedia_index or 1,
			state.wikipedia_count or #pages,
			true
		)
	end)

	if not ok then
		logger.warn("LookupPreview: full Wikipedia article lookup failed:", err)
		pcall(function()
			local Wikipedia = require("ui/wikipedia")
			if type(Wikipedia.resetTrapWidget) == "function" then
				Wikipedia:resetTrapWidget()
			end
		end)
		state.wikipedia_error = tostring(err or _("Wikipedia lookup failed."))
	end

	state.wikipedia_full_loading = false
	return self:refreshCurrentPage(PAGE_WIKIPEDIA)
end

function LookupPreview:pickBestWikipediaPage(pages)
	local best
	if type(pages) ~= "table" then
		return nil
	end
	for _, page in pairs(pages) do
		if type(page) == "table" then
			if not best or tonumber(page.index or 999999) < tonumber(best.index or 999999) then
				best = page
			end
		end
	end
	return best
end

function LookupPreview:loadWikipedia(state)
	if state ~= self.current_state then
		return true
	end
	if not state or state.wikipedia_loading or state.wikipedia_payload or state.wikipedia_error then
		return true
	end

	state.wikipedia_loading = true
	local text = state.search_text or ""
	if text == "" then
		state.wikipedia_error = _("No text to search on Wikipedia.")
		state.wikipedia_loading = false
		return self:refreshCurrentPage(PAGE_WIKIPEDIA)
	end

	local NetworkMgr = require("ui/network/manager")
	if
		NetworkMgr:willRerunWhenOnline(function()
			state.wikipedia_loading = false
			self:loadWikipedia(state)
		end)
	then
		state.wikipedia_error = _("Waiting for network connection.")
		state.wikipedia_loading = false
		return self:refreshCurrentPage(PAGE_WIKIPEDIA)
	end

	local ok, err = pcall(function()
		local Wikipedia = require("ui/wikipedia")
		local lang = state.wikipedia_lang or self:getWikipediaLang()
		state.wikipedia_lang = lang
		if type(Wikipedia.setTrapWidget) == "function" then
			Wikipedia:setTrapWidget(_("Querying Wikipedia…"))
		end
		local pages = Wikipedia:searchAndGetIntros(text, lang)
		if type(Wikipedia.resetTrapWidget) == "function" then
			Wikipedia:resetTrapWidget()
		end

		local wikipedia_results = self:buildWikipediaResults(pages)
		if #wikipedia_results == 0 then
			state.wikipedia_error = _("No Wikipedia article found.")
			return
		end

		state.wikipedia_pages = wikipedia_results
		state.wikipedia_count = #wikipedia_results
		state.wikipedia_index = normalizeResultIndex(state.wikipedia_index or 1, state.wikipedia_count)
		self:updateWikipediaPayload(state, state.wikipedia_index)
	end)

	if not ok then
		logger.warn("LookupPreview: Wikipedia lookup failed:", err)
		pcall(function()
			local Wikipedia = require("ui/wikipedia")
			if type(Wikipedia.resetTrapWidget) == "function" then
				Wikipedia:resetTrapWidget()
			end
		end)
		state.wikipedia_error = tostring(err or _("Wikipedia lookup failed."))
	end

	state.wikipedia_loading = false
	return self:refreshCurrentPage(PAGE_WIKIPEDIA)
end

function LookupPreview:refreshCurrentPage(index)
	if not self.current_state then
		return true
	end

	local active_index = self.current_state.active_index or PAGE_DICTIONARY
	if index and index ~= active_index then
		return true
	end

	return self:showCarousel(self.current_state, active_index, true)
end

function LookupPreview:switchToPage(index)
	if not self.current_state then
		return true
	end
	index = math.max(PAGE_DICTIONARY, math.min(PAGE_WIKIPEDIA, index or PAGE_DICTIONARY))
	if index == self.current_state.active_index then
		return true
	end

	self:showCarousel(self.current_state, index, true)

	local state = self.current_state
	if index == PAGE_TRANSLATION then
		UIManager:scheduleIn(0.05, function()
			self:loadTranslation(state)
		end)
	elseif index == PAGE_WIKIPEDIA then
		UIManager:scheduleIn(0.05, function()
			self:loadWikipedia(state)
		end)
	end

	return true
end

function LookupPreview:showCarousel(state, active_index, preserve_state)
	self:closeCurrentPopup(true)
	state.active_index = active_index or PAGE_DICTIONARY
	self.current_state = state

	local popup = LookupPreviewPopup:new({
		plugin = self,
		state = state,
		active_index = state.active_index,
		selection_bounds = state.selection_bounds,
		dialog = state.dialog,
	})

	self.current_popup = popup
	UIManager:show(popup)
	return true
end

function LookupPreview:closePreview(skip_clear)
	local state = self.current_state
	self.current_popup = nil

	if state and not skip_clear then
		self.selection_snapshot = nil
		self:clearOriginalHighlight(state.dict_self)
		self:clearSelection()
		if state.dict_close_callback then
			pcall(state.dict_close_callback)
		end
	end

	self.current_state = nil
	return true
end

function LookupPreview:showPreview(dict_self, word, results, boxes, link, dict_close_callback)
	local preview_results = buildPreviewResults(results)
	if #preview_results <= 0 then
		return true
	end

	local first_entry = preview_results[1] or {}
	local first_result = first_entry.result or results[1] or {}
	local search_text = self:getSearchText(word, first_result)
	local state = {
		dict_self = dict_self,
		word = word,
		results = results,
		preview_results = preview_results,
		boxes = boxes,
		link = link,
		dict_close_callback = dict_close_callback,
		preview_count = #preview_results,
		dictionary_index = 1,
		search_text = search_text,
		dictionary_search_text = search_text,
		translation_source_text = search_text,
		selection_bounds = getSelectionBounds(boxes),
		dialog = dict_self and dict_self.dialog,
	}

	state.dictionary_payload = self:buildDictionaryPayload(word, first_result, 1, #preview_results)

	return self:showCarousel(state, PAGE_DICTIONARY, false)
end

LookupPreview.showFootnotePreview = LookupPreview.showPreview

return LookupPreview
