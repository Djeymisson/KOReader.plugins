-- Lookup Preview shared context.
-- Auto-split from the original main.lua; keep this file beside main.lua.
local ctx = setmetatable({}, { __index = _G })
setfenv(1, ctx)

Device = require("device")
Blitbuffer = require("ffi/blitbuffer")
BottomContainer = require("ui/widget/container/bottomcontainer")
TopContainer = require("ui/widget/container/topcontainer")
LeftContainer = require("ui/widget/container/leftcontainer")
CenterContainer = require("ui/widget/container/centercontainer")
Font = require("ui/font")
IconWidget = require("ui/widget/iconwidget")
TextWidget = require("ui/widget/textwidget")
FrameContainer = require("ui/widget/container/framecontainer")
Geom = require("ui/geometry")
GestureRange = require("ui/gesturerange")
HorizontalGroup = require("ui/widget/horizontalgroup")
HorizontalSpan = require("ui/widget/horizontalspan")
InputContainer = require("ui/widget/container/inputcontainer")
LineWidget = require("ui/widget/linewidget")
Notification = require("ui/widget/notification")
ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
Size = require("ui/size")
UIManager = require("ui/uimanager")
VerticalGroup = require("ui/widget/verticalgroup")
VerticalSpan = require("ui/widget/verticalspan")
WidgetContainer = require("ui/widget/container/widgetcontainer")
Event = require("ui/event")
Translator = require("ui/translator")
util = require("util")
logger = require("logger")
_ = require("gettext")
C_ = _.pgettext or function(_context, text)
	return _(text)
end

Screen = Device.screen
IS_TOUCH_DEVICE = Device:isTouchDevice()
HAS_KEYS = Device:hasKeys()

LookupPreview = WidgetContainer:extend({
	name = "lookuppreview",
	is_doc_only = true,
})

PLUGIN_VERSION = "v0.1.0"

UI_FONT_FACE = "Noto Sans"
UI_FONT_SIZE = 20
TITLE_FONT_SIZE = math.max(16, UI_FONT_SIZE - 1)
SUBTITLE_FONT_SIZE = math.max(14, UI_FONT_SIZE - 3)
HEADER_MENU_FONT_SIZE = math.max(14, UI_FONT_SIZE - 4)
HEADER_BUTTON_FONT_SIZE = math.max(18, UI_FONT_SIZE)
BODY_FONT_SIZE = Screen:scaleBySize(18)

function getUIFontFace(names, size, fallback_name)
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

TITLE_FACE = Font:getFace("cfont", TITLE_FONT_SIZE)
SUBTITLE_FACE = getUIFontFace({
	"NotoSans-Italic.ttf",
	"NotoSans-Italic",
	"Noto Sans Italic",
	"cfonti",
}, SUBTITLE_FONT_SIZE, "cfont")
HEADER_MENU_FACE = Font:getFace("cfont", HEADER_MENU_FONT_SIZE)
HEADER_BUTTON_FACE = Font:getFace("cfont", HEADER_BUTTON_FONT_SIZE)
DICTIONARY_BUTTON_FONT_SIZE = math.max(13, UI_FONT_SIZE - 5)
DICTIONARY_BUTTON_FACE = Font:getFace("cfont", DICTIONARY_BUTTON_FONT_SIZE)
TRANSLATION_BUTTON_FONT_SIZE = math.max(13, UI_FONT_SIZE - 5)
TRANSLATION_BUTTON_FACE = Font:getFace("cfont", TRANSLATION_BUTTON_FONT_SIZE)

CARD_WIDTH_RATIO = 0.92
CARD_HEIGHT_RATIO = 0.38
CARD_MIN_WIDTH = Screen:scaleBySize(220)
CARD_GAP = Screen:scaleBySize(8)
CARD_EDGE_MARGIN = Screen:scaleBySize(10)
CARD_BORDER_SIZE = math.max(Size.border.thin, Screen:scaleBySize(2))
CARD_BORDER_COLOR = Blitbuffer.COLOR_BLACK
CARD_SHADOW_ENABLED = false
CARD_SHADOW_OFFSET = Screen:scaleBySize(3)
CARD_SHADOW_COLOR = Blitbuffer.COLOR_DARK_GRAY
CARD_RADIUS = nil
CARD_PADDING_H = Screen:scaleBySize(14)
CARD_PADDING_TOP = Screen:scaleBySize(6)
CARD_PADDING_BOTTOM = Screen:scaleBySize(8)
HEADER_GAP = Screen:scaleBySize(2)
HEADER_SEPARATOR_GAP = Screen:scaleBySize(3)
HEADER_MENU_WIDTH = Screen:scaleBySize(40)
HEADER_MENU_HEIGHT = Screen:scaleBySize(30)
HEADER_MENU_PADDING_H = Screen:scaleBySize(5)
HEADER_MENU_PADDING_V = Screen:scaleBySize(0)
HEADER_TITLE_MENU_GAP = Screen:scaleBySize(6)
DICTIONARY_BUTTON_HEIGHT = Screen:scaleBySize(30)
DICTIONARY_ICON_SIZE = Screen:scaleBySize(20)
DICTIONARY_BUTTON_GAP = Screen:scaleBySize(4)
DICTIONARY_BUTTON_SEPARATOR_WIDTH = math.max(1, Screen:scaleBySize(1))
TRANSLATION_BUTTON_HEIGHT = Screen:scaleBySize(30)
TRANSLATION_BUTTON_GAP = Screen:scaleBySize(4)
TRANSLATION_BUTTON_SEPARATOR_WIDTH = math.max(1, Screen:scaleBySize(1))
PAGE_MENU_WIDTH = Screen:scaleBySize(220)
PAGE_MENU_ITEM_HEIGHT = Screen:scaleBySize(34)
PAGE_MENU_GAP = Screen:scaleBySize(8)
PAGE_MENU_PADDING_H = Screen:scaleBySize(12)
SCROLL_BAR_WIDTH = Screen:scaleBySize(6)
TEXT_SCROLL_SPAN = Screen:scaleBySize(8)
FLOATING_SELECTION_GAP = Screen:scaleBySize(8)
MIN_HTML_HEIGHT = Screen:scaleBySize(72)
EMPTY_TEXT = "—"

SETTING_ENABLED = "lookuppreview_enabled"
SETTING_WIKI_LANG = "lookuppreview_wikipedia_lang"
SETTING_LEFT_ACTION = "lookuppreview_dictionary_left_action"
SETTING_TRANSLATION_SHOW_SOURCE = "lookuppreview_translation_show_source"
SETTING_TRANSLATION_SHOW_COPY_BUTTON = "lookuppreview_translation_show_copy_button"
SETTING_TRANSLATION_SHOW_NOTE_BUTTON = "lookuppreview_translation_show_note_button"

LEFT_ACTION_HIGHLIGHT = "highlight"
LEFT_ACTION_SEARCH_BOOK = "search_book"
DEFAULT_LEFT_ACTION = LEFT_ACTION_SEARCH_BOOK

LEFT_ACTIONS = {
	{ id = LEFT_ACTION_HIGHLIGHT, label = _("Highlight") },
	{ id = LEFT_ACTION_SEARCH_BOOK, label = _("Fulltext search") },
}

LEFT_ACTION_BY_ID = {}
for _, action in ipairs(LEFT_ACTIONS) do
	LEFT_ACTION_BY_ID[action.id] = action
end

PLUGIN_ICON_EXTENSIONS = { ".svg", ".png" }
PLUGIN_LEFT_ICON_CANDIDATES = {
	[LEFT_ACTION_HIGHLIGHT] = { "highlight", "lookuppreview.highlight", "dictionarypreview.highlight" },
}

ICON_SEARCH = "appbar.search"
ICON_PREVIOUS = "chevron.left"
ICON_NEXT = "chevron.right"
ICON_DETAILS = "chevron.up"

COMMON_TARGET_LANGUAGES = {
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

PAGE_DICTIONARY = 1
PAGE_TRANSLATION = 2
PAGE_WIKIPEDIA = 3

PAGE_TITLES = {
	[PAGE_DICTIONARY] = _("Dictionary"),
	[PAGE_TRANSLATION] = _("Translate"),
	[PAGE_WIKIPEDIA] = _("Wikipedia"),
}

FALLBACK_CSS = [[
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

CLASS_STYLE_CACHE = {}
dictionary_class_styles = {
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


return ctx
