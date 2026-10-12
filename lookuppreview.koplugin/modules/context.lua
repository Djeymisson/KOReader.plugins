-- Shared module context for Lookup Preview.
--
-- The other modules are loaded with this table as their environment, so this
-- file intentionally exposes KOReader dependencies, constants, and shared
-- helpers as fields on ctx.
local ctx = setmetatable({}, { __index = _G })
setfenv(1, ctx)

-- KOReader dependencies -----------------------------------------------------
Device = require("device")
Blitbuffer = require("ffi/blitbuffer")
BottomContainer = require("ui/widget/container/bottomcontainer")
TopContainer = require("ui/widget/container/topcontainer")
LeftContainer = require("ui/widget/container/leftcontainer")
CenterContainer = require("ui/widget/container/centercontainer")
Font = require("ui/font")
IconWidget = require("ui/widget/iconwidget")
TextWidget = require("ui/widget/textwidget")
TextBoxWidget = require("ui/widget/textboxwidget")
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

-- The plugin's own translations, falling back to KOReader's catalog.
_ = require("lookuppreview_l10n")
C_ = _.pgettext or function(_context, text)
	return _(text)
end

-- Device shortcuts ----------------------------------------------------------
Screen = Device.screen
IS_TOUCH_DEVICE = Device:isTouchDevice()
HAS_KEYS = Device:hasKeys()

local function scaleBySize(size)
	return Screen:scaleBySize(size)
end

-- Plugin object -------------------------------------------------------------
LookupPreview = WidgetContainer:extend({
	name = "lookuppreview",
	is_doc_only = true,
})

-- Fonts ---------------------------------------------------------------------
UI_FONT_FACE = "Noto Sans"
UI_FONT_SIZE = 20
TITLE_FONT_SIZE = math.max(16, UI_FONT_SIZE - 1)
SUBTITLE_FONT_SIZE = math.max(14, UI_FONT_SIZE - 3)
HEADER_MENU_FONT_SIZE = math.max(14, UI_FONT_SIZE - 4)
HEADER_BUTTON_FONT_SIZE = math.max(18, UI_FONT_SIZE)
DICTIONARY_BUTTON_FONT_SIZE = math.max(13, UI_FONT_SIZE - 5)

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
HINT_FACE = Font:getFace("x_smallinfofont")
HEADER_MENU_FACE = Font:getFace("cfont", HEADER_MENU_FONT_SIZE)
HEADER_BUTTON_FACE = Font:getFace("cfont", HEADER_BUTTON_FONT_SIZE)
DICTIONARY_BUTTON_FACE = Font:getFace("cfont", DICTIONARY_BUTTON_FONT_SIZE)

-- Layout --------------------------------------------------------------------
CARD_WIDTH_RATIO = 0.92
CARD_HEIGHT_RATIO = 0.38
CARD_EXPANDED_HEIGHT_RATIO = 0.75

CARD_HEIGHT_COMPACT = "compact"
CARD_HEIGHT_EXPANDED = "expanded"
DEFAULT_CARD_HEIGHT = CARD_HEIGHT_COMPACT

-- Text size of the cards' content, before scaling to the screen.
TEXT_SIZES = { 14, 16, 18, 20, 22, 24 }
DEFAULT_TEXT_SIZE = 18
CARD_MIN_WIDTH = scaleBySize(220)
CARD_GAP = scaleBySize(8)
CARD_EDGE_MARGIN = scaleBySize(10)
CARD_BORDER_SIZE = math.max(Size.border.thin, scaleBySize(2))
CARD_BORDER_COLOR = Blitbuffer.COLOR_BLACK
CARD_RADIUS = nil
CARD_ROUNDED_RADIUS = scaleBySize(14)

SIDE_PREVIEW_FULL_CARDS = "full_cards"
SIDE_PREVIEW_TABS = "tabs"
DEFAULT_SIDE_PREVIEW_MODE = SIDE_PREVIEW_FULL_CARDS

ONLINE_CARD_LOAD_AUTOMATIC = "automatic"
ONLINE_CARD_LOAD_MANUAL_ONLY = "manual_only"
DEFAULT_ONLINE_CARD_LOAD_MODE = ONLINE_CARD_LOAD_AUTOMATIC

DICTIONARY_HTML_FORMATTED = "formatted"
DICTIONARY_HTML_FAST_RAW = "fast_raw"
DEFAULT_DICTIONARY_HTML_MODE = DICTIONARY_HTML_FORMATTED
SIDE_TAB_HEIGHT = scaleBySize(28)
SIDE_TAB_GAP = scaleBySize(0)
SIDE_TAB_PADDING_H = scaleBySize(8)
SIDE_TAB_PADDING_V = scaleBySize(4)
SIDE_TAB_BORDER_SIZE = Size.border.thin

CARD_SHADOW_WIDTH = scaleBySize(24)
CARD_SHADOW_OVERLAP = scaleBySize(12)
CARD_SHADOW_EXTENT = math.max(0, CARD_SHADOW_WIDTH - CARD_SHADOW_OVERLAP)

CARD_PADDING_H = scaleBySize(14)
CARD_PADDING_TOP = scaleBySize(6)
CARD_PADDING_BOTTOM = scaleBySize(8)

HEADER_GAP = scaleBySize(2)
HEADER_SEPARATOR_GAP = scaleBySize(3)
HEADER_MENU_WIDTH = scaleBySize(40)
HEADER_MENU_HEIGHT = scaleBySize(30)
HEADER_MENU_PADDING_H = scaleBySize(5)
HEADER_MENU_PADDING_V = scaleBySize(0)
HEADER_TITLE_MENU_GAP = scaleBySize(6)

DICTIONARY_BUTTON_HEIGHT = scaleBySize(30)
DICTIONARY_ICON_SIZE = scaleBySize(20)
DICTIONARY_BUTTON_GAP = scaleBySize(4)
DICTIONARY_BUTTON_SEPARATOR_WIDTH = math.max(1, scaleBySize(1))

TRANSLATION_BUTTON_HEIGHT = scaleBySize(30)
TRANSLATION_BUTTON_GAP = scaleBySize(4)

PAGE_MENU_WIDTH = scaleBySize(220)
PAGE_MENU_ITEM_HEIGHT = scaleBySize(34)
PAGE_MENU_GAP = scaleBySize(8)
PAGE_MENU_PADDING_H = scaleBySize(12)

SCROLL_BAR_WIDTH = scaleBySize(6)
TEXT_SCROLL_SPAN = scaleBySize(8)
FLOATING_SELECTION_GAP = scaleBySize(8)
MIN_HTML_HEIGHT = scaleBySize(72)
EMPTY_TEXT = "—"

-- Settings ------------------------------------------------------------------
SETTING_ENABLED = "lookuppreview_enabled"
SETTING_CARD_ROUNDED = "lookuppreview_card_rounded"
SETTING_CARD_SHADOWS = "lookuppreview_card_shadows"
SETTING_CARD_HEIGHT = "lookuppreview_card_height"
SETTING_CARD_ORDER = "lookuppreview_card_order"
SETTING_HIDDEN_CARDS = "lookuppreview_hidden_cards"
SETTING_OPEN_CARD = "lookuppreview_open_card"
SETTING_LAST_CARD = "lookuppreview_last_card"
SETTING_TEXT_SIZE = "lookuppreview_text_size"
SETTING_SIDE_PREVIEW_MODE = "lookuppreview_side_preview_mode"
SETTING_ONLINE_CARD_LOAD_MODE = "lookuppreview_online_card_load_mode"
SETTING_DICTIONARY_HTML_MODE = "lookuppreview_dictionary_html_mode"
SETTING_WIKI_LANG = "lookuppreview_wikipedia_lang"
SETTING_DICTIONARY_DETAILS_BUTTONS = "lookuppreview_dictionary_details_buttons"
SETTING_DICTIONARY_VOCABULARY_BUTTON = "lookuppreview_dictionary_vocabulary_button"
SETTING_TRANSLATION_SHOW_SOURCE = "lookuppreview_translation_show_source"
SETTING_TRANSLATION_SHOW_COPY_BUTTON = "lookuppreview_translation_show_copy_button"
SETTING_TRANSLATION_SHOW_NOTE_BUTTON = "lookuppreview_translation_show_note_button"

-- Actions and icons ---------------------------------------------------------
-- Which buttons open the full dictionary from the dictionary card: KOReader's
-- original popup, Dictionary Explorer's "go to word", or both.
DETAILS_BUTTONS_BOTH = "both"
DETAILS_BUTTONS_KOREADER = "koreader"
DETAILS_BUTTONS_EXPLORER = "explorer"
DEFAULT_DETAILS_BUTTONS = DETAILS_BUTTONS_BOTH

-- How long the hint shown by holding a button stays on screen, and how far it
-- is from the card it is about.
BUTTON_HINT_TIMEOUT = 5
BUTTON_HINT_GAP = scaleBySize(6)

PLUGIN_ICON_EXTENSIONS = { ".svg", ".png" }
ICON_HIGHLIGHT = "highlight"
ICON_SEARCH = "appbar.search"
ICON_PREVIOUS = "chevron.left"
ICON_NEXT = "chevron.right"
ICON_DETAILS = "open_popup"
ICON_DETAILS_FALLBACK = "chevron.up"
ICON_GO_TO_DICT = "go_to_dict"
ICON_VOCABULARY = "vocabulary"
ICON_VOCABULARY_FALLBACK = "plus"
ICON_VOCABULARY_ADDED = "check"
ICON_COPY = "copy"
ICON_ADD_NOTE = "add_note"
ICON_WIKIPEDIA = "wikipedia"
ICON_LOADING = "loading"
ICON_EDIT = "edit"
ICON_TRANSLATE_SENTENCE = "translate_sentence"
ICON_TRANSLATE_SELECTION = "translate_selection"
ICON_LOAD = "load_online"
ICON_RETRY = "retry"
ICON_EDIT_FALLBACK = "edit"

PLUGIN_ICON_DEFINITIONS = {
	{
		id = ICON_HIGHLIGHT,
		label = _("Highlight"),
		basenames = { "highlight", "lookuppreview.highlight", "dictionarypreview.highlight" },
	},
	{
		id = ICON_SEARCH,
		label = _("Full-text search"),
		basenames = { "search", "appbar.search" },
	},
	{
		id = ICON_PREVIOUS,
		label = _("Previous result"),
		basenames = { "chevron.left" },
	},
	{
		id = ICON_NEXT,
		label = _("Next result"),
		basenames = { "chevron.right" },
	},
	{
		id = ICON_DETAILS,
		label = _("Open native details"),
		basenames = { "open_popup", "read_more" },
	},
	{
		id = ICON_GO_TO_DICT,
		label = _("Go to word in Dictionary Explorer"),
		basenames = { "go_to_dict" },
	},
	{
		id = ICON_VOCABULARY,
		label = _("Add to vocabulary builder"),
		basenames = { "vocabulary" },
	},
	{
		id = ICON_COPY,
		label = _("Copy translation"),
		basenames = { "copy" },
	},
	{
		id = ICON_ADD_NOTE,
		label = _("Add translation note"),
		basenames = { "add_note" },
	},
	{
		id = ICON_WIKIPEDIA,
		label = C_("Wikipedia", "Full article"),
		basenames = { "wikipedia", "lookuppreview.wikipedia", "dictionarypreview.wikipedia" },
	},
	{
		id = ICON_LOADING,
		label = _("Loading"),
		basenames = { "loading" },
	},
	{
		id = ICON_TRANSLATE_SENTENCE,
		label = _("Translate the whole sentence"),
		basenames = { "translate_sentence" },
	},
	{
		id = ICON_TRANSLATE_SELECTION,
		label = _("Translate only the selected text"),
		basenames = { "translate_selection" },
	},
	{
		id = ICON_LOAD,
		label = _("Load an online card"),
		basenames = { "load_online" },
	},
	{
		id = ICON_RETRY,
		label = _("Retry"),
		basenames = { "retry" },
	},
	{
		id = ICON_EDIT,
		label = _("Edit the looked up text"),
		basenames = { "edit_lookup", "edit" },
	},
}

PLUGIN_ICON_CANDIDATES = {}
for _, definition in ipairs(PLUGIN_ICON_DEFINITIONS) do
	PLUGIN_ICON_CANDIDATES[definition.id] = definition.basenames
end

-- Pages ---------------------------------------------------------------------
PAGE_DICTIONARY = 1
PAGE_TRANSLATION = 2
PAGE_WIKIPEDIA = 3

CARD_IDS = { PAGE_DICTIONARY, PAGE_TRANSLATION, PAGE_WIKIPEDIA }

-- Which card a lookup from the book (a long press on a word) opens on.
OPEN_CARD_DICTIONARY = "dictionary"
OPEN_CARD_LAST = "last"

PAGE_TITLES = {
	[PAGE_DICTIONARY] = _("Dictionary"),
	[PAGE_TRANSLATION] = _("Translate"),
	[PAGE_WIKIPEDIA] = _("Wikipedia"),
}

-- Where the content of a card stands, kept per card in state.load (see
-- getLoadStatus in carousel.lua). Idle is "not looked up yet", which is not the
-- same as empty, "looked up and nothing found".
LOAD_IDLE = "idle"
LOAD_LOADING = "loading"
LOAD_DONE = "done"
LOAD_EMPTY = "empty"
LOAD_ERROR = "error"

-- Languages -----------------------------------------------------------------
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

-- Shared CSS ----------------------------------------------------------------
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

FAST_RAW_DICTIONARY_CSS = [[
@page {
    margin: 0;
}
body {
    margin: 0;
    padding: 0;
    line-height: 1.3;
    font-family: ']] .. UI_FONT_FACE .. [[';
}
a {
    color: black;
}
]]

-- Dictionary HTML normalization --------------------------------------------
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
