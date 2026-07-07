local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
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
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Screen = Device.screen
local IS_TOUCH_DEVICE = Device:isTouchDevice()
local HAS_KEYS = Device:hasKeys()

local TranslatorPreview = WidgetContainer:extend({
	name = "translatorpreview",
	is_doc_only = true,
})

local PLUGIN_VERSION = "v1.0.1"

local UI_FONT_FACE = "Noto Sans"
local UI_FONT_SIZE = 20
local PREVIEW_FONT_SIZE = Screen:scaleBySize(UI_FONT_SIZE)
local DEFAULT_HTML_FONT_SIZE = Screen:scaleBySize(18)

local BUTTON_FONT_SIZE = math.max(12, UI_FONT_SIZE - 3)
local BUTTON_TEXT_FACE = Font:getFace("cfont", BUTTON_FONT_SIZE)

local SCROLL_BAR_WIDTH = Screen:scaleBySize(6)
local TEXT_SCROLL_SPAN = Screen:scaleBySize(8)

local PANEL_MAX_HEIGHT_RATIO = 0.38
local MIN_CONTENT_WIDTH = Screen:scaleBySize(120)
local BUTTON_HEIGHT = Screen:scaleBySize(40)

local BUTTON_SEPARATOR_WIDTH = math.max(1, Screen:scaleBySize(1))
local HEADER_CONTENT_GAP = Screen:scaleBySize(6)
local HEADER_SEPARATOR_HEIGHT = math.max(1, Screen:scaleBySize(1))
local HEADER_SEPARATOR_GAP = Screen:scaleBySize(6)
local LANGUAGE_FONT_SIZE = math.max(12, UI_FONT_SIZE - 3)
local LANGUAGE_TEXT_FACE = Font:getFace("cfont", LANGUAGE_FONT_SIZE)
local LANGUAGE_TEXT_PADDING_H = Screen:scaleBySize(4)
local LANGUAGE_TEXT_PADDING_V = Screen:scaleBySize(1)

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

local PANEL_TOP_BORDER_SIZE = Size.line.thick
local PANEL_PADDING_TOP = Screen:scaleBySize(8)
local PANEL_PADDING_BOTTOM = Screen:scaleBySize(6)
local TEXT_BUTTON_GAP = Screen:scaleBySize(10)

local HTML_BOTTOM_SAFETY = Screen:scaleBySize(6)

local CONTENT_PADDING_LEFT = Screen:scaleBySize(16)
local CONTENT_PADDING_RIGHT = Screen:scaleBySize(12)

local FLOATING_SIDE_MARGIN = Screen:scaleBySize(10)
local FLOATING_EDGE_MARGIN = Screen:scaleBySize(10)
local FLOATING_CARD_BORDER_SIZE = Size.border.thin
local FLOATING_CARD_RADIUS = Screen:scaleBySize(14)
local FLOATING_SELECTION_GAP = Screen:scaleBySize(8)
local FLOATING_PADDING_TOP = Screen:scaleBySize(10)
local FLOATING_PADDING_BOTTOM = Screen:scaleBySize(6)
local FLOATING_TEXT_BUTTON_GAP = Screen:scaleBySize(10)

local SETTING_ENABLED = "translatorpreview_enabled"
local SETTING_FLOATING_PREVIEW = "translatorpreview_floating_preview"
local SETTING_SHOW_SOURCE = "translatorpreview_show_source"
local SETTING_SHOW_COPY_BUTTON = "translatorpreview_show_copy_button"
local SETTING_SHOW_NOTE_BUTTON = "translatorpreview_show_note_button"

local function trim(text)
	return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function htmlEscape(text)
	text = tostring(text or "")
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	text = text:gsub('"', "&quot;")
	return text
end

local function plainTextToHtml(text)
	text = htmlEscape(text)
	text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
	text = text:gsub("\n\n+", "</p><p>"):gsub("\n", "<br/>")
	return "<p>" .. text .. "</p>"
end

local function isResultValid(res)
	return res and type(res) == "table" and #res > 0
end

local function stripHtmlForLineEstimate(html)
	html = tostring(html or "")
	html = html:gsub("<%s*[bB][rR]%s*/?%s*>", "\n")
	html = html:gsub("</%s*[pP]%s*>", "\n")
	html = html:gsub("</%s*[dD][iI][vV]%s*>", "\n")
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
	local min_height = math.max(Screen:scaleBySize(56), estimated_height)

	if max_height and max_height > 0 then
		return math.max(1, math.min(max_height, min_height))
	end

	return min_height
end

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
.translatorpreview-source-label {
    margin-top: 0.45em;
    margin-bottom: 0.12em;
    font-size: 0.78em;
    color: #777777;
    font-weight: bold;
}
.translatorpreview-source {
    font-size: 0.86em;
    color: #555555;
}
.translatorpreview-translation {
    font-size: 1em;
}
]]

local function extractMainTranslation(result)
	if not isResultValid(result and result[1]) then
		return ""
	end

	local translated = {}
	for _, r in ipairs(result[1]) do
		if type(r[1]) == "string" and r[1] ~= "" then
			translated[#translated + 1] = r[1]
		end
	end

	return trim(table.concat(translated, " "))
end

local PreviewButton = InputContainer:extend({
	text = nil,
	width = nil,
	height = BUTTON_HEIGHT,
	callback = nil,
	show_parent = nil,
})

function PreviewButton:init()
	local bordersize = 0
	local padding_h = math.max(2, math.floor(Size.padding.button * 0.75))
	local padding_v = math.max(1, math.floor(Size.padding.button * 0.55))

	local outer_w = self.width or Screen:scaleBySize(80)
	local outer_h = self.height or Screen:scaleBySize(48)
	local inner_w = math.max(1, outer_w - 2 * bordersize - 2 * padding_h)
	local inner_h = math.max(1, outer_h - 2 * bordersize - 2 * padding_v)

	local label = TextWidget:new({
		text = self.text or "",
		face = BUTTON_TEXT_FACE,
		bold = true,
		max_width = inner_w,
	})

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

local ClickableLanguageText = InputContainer:extend({
	text = nil,
	width = nil,
	callback = nil,
	show_parent = nil,
})

function ClickableLanguageText:init()
	local label = TextWidget:new({
		text = self.text or "",
		face = LANGUAGE_TEXT_FACE,
		bold = true,
		max_width = self.width or Screen:scaleBySize(300),
	})

	self.frame = FrameContainer:new({
		show_parent = self.show_parent,
		bordersize = 0,
		background = Blitbuffer.COLOR_WHITE,
		padding_left = LANGUAGE_TEXT_PADDING_H,
		padding_right = LANGUAGE_TEXT_PADDING_H,
		padding_top = LANGUAGE_TEXT_PADDING_V,
		padding_bottom = LANGUAGE_TEXT_PADDING_V,
		label,
	})

	self.dimen = self.frame:getSize()
	self[1] = self.frame

	self.ges_events = {
		TapSelectLanguage = {
			GestureRange:new({
				ges = "tap",
				range = self.dimen,
			}),
		},
	}
end

function ClickableLanguageText:onTapSelectLanguage()
	if self.callback then
		self.callback()
	end
	return true
end

local TranslatorPreviewPopup = InputContainer:extend({
	language_text = nil,
	language_callback = nil,
	html_body = nil,
	css = nil,
	dialog = nil,
	doc_font_size = DEFAULT_HTML_FONT_SIZE,
	floating = false,
	selection_bounds = nil,
	anchor_top = false,
	actions = nil,
	close_preview_callback = nil,
})

function TranslatorPreviewPopup:init()
	local screen_width = Screen:getWidth()
	local screen_height = Screen:getHeight()
	local floating = self.floating == true

	self.width = floating and (screen_width - 2 * FLOATING_SIDE_MARGIN) or screen_width

	local top_border_size = floating and 0 or PANEL_TOP_BORDER_SIZE
	local padding_top = floating and FLOATING_PADDING_TOP or PANEL_PADDING_TOP
	local padding_bottom = floating and FLOATING_PADDING_BOTTOM or PANEL_PADDING_BOTTOM
	local button_gap = floating and FLOATING_TEXT_BUTTON_GAP or TEXT_BUTTON_GAP
	local card_border_size = floating and FLOATING_CARD_BORDER_SIZE or 0
	local max_popup_height = math.floor(screen_height * PANEL_MAX_HEIGHT_RATIO)

	if floating then
		max_popup_height = max_popup_height - FLOATING_EDGE_MARGIN
	end

	if IS_TOUCH_DEVICE then
		local range = Geom:new({ x = 0, y = 0, w = screen_width, h = screen_height })
		self.ges_events = {
			TapClose = { GestureRange:new({ ges = "tap", range = range }) },
			SwipeClose = { GestureRange:new({ ges = "swipe", range = range }) },
		}
	end

	if HAS_KEYS then
		self.key_events = {
			Close = { { Device.input.group.Back } },
		}
	end

	local content_width = math.max(MIN_CONTENT_WIDTH, self.width - CONTENT_PADDING_LEFT - CONTENT_PADDING_RIGHT)
	local header = self:makeHeader(content_width)
	local header_height = header and self:getWidgetHeight(header, Screen:scaleBySize(32)) or 0
	local header_gap = header and HEADER_CONTENT_GAP or 0
	local header_separator_height = header and HEADER_SEPARATOR_HEIGHT or 0
	local header_separator_gap = header and HEADER_SEPARATOR_GAP or 0
	local buttons = self:makeButtons(content_width)
	local buttons_height = self:getWidgetHeight(buttons, BUTTON_HEIGHT)

	local fixed_height = top_border_size
		+ padding_top
		+ header_height
		+ header_gap
		+ header_separator_height
		+ header_separator_gap
		+ button_gap
		+ buttons_height
		+ padding_bottom
		+ 2 * card_border_size
	local max_html_height = math.max(1, max_popup_height - fixed_height)
	local html_height = estimateHtmlHeight(self.html_body, content_width, self.doc_font_size, max_html_height)
	html_height = math.min(max_html_height, html_height + HTML_BOTTOM_SAFETY)

	self.htmlwidget = ScrollHtmlWidget:new({
		html_body = self.html_body,
		is_xhtml = true,
		css = self.css or FALLBACK_CSS,
		default_font_size = self.doc_font_size,
		width = content_width,
		height = html_height,
		scroll_bar_width = SCROLL_BAR_WIDTH,
		text_scroll_span = TEXT_SCROLL_SPAN,
		dialog = self.dialog,
		highlight_text_selection = true,
	})

	self.height = fixed_height + html_height

	local vertical_items = {}
	if top_border_size > 0 then
		table.insert(vertical_items, LineWidget:new({ dimen = Geom:new({ w = self.width, h = top_border_size }) }))
	end

	table.insert(vertical_items, VerticalSpan:new({ width = padding_top }))

	if header then
		table.insert(
			vertical_items,
			HorizontalGroup:new({
				HorizontalSpan:new({ width = CONTENT_PADDING_LEFT }),
				header,
				HorizontalSpan:new({ width = CONTENT_PADDING_RIGHT }),
			})
		)

		table.insert(vertical_items, VerticalSpan:new({ width = header_gap }))

		table.insert(
			vertical_items,
			HorizontalGroup:new({
				HorizontalSpan:new({ width = CONTENT_PADDING_LEFT }),
				LineWidget:new({
					background = Blitbuffer.COLOR_GRAY,
					dimen = Geom:new({
						w = content_width,
						h = HEADER_SEPARATOR_HEIGHT,
					}),
				}),
				HorizontalSpan:new({ width = CONTENT_PADDING_RIGHT }),
			})
		)

		table.insert(vertical_items, VerticalSpan:new({ width = header_separator_gap }))
	end

	table.insert(
		vertical_items,
		HorizontalGroup:new({
			HorizontalSpan:new({ width = CONTENT_PADDING_LEFT }),
			self.htmlwidget,
			HorizontalSpan:new({ width = CONTENT_PADDING_RIGHT }),
		})
	)
	table.insert(vertical_items, VerticalSpan:new({ width = button_gap }))
	table.insert(
		vertical_items,
		HorizontalGroup:new({
			HorizontalSpan:new({ width = CONTENT_PADDING_LEFT }),
			buttons,
			HorizontalSpan:new({ width = CONTENT_PADDING_RIGHT }),
		})
	)
	table.insert(vertical_items, VerticalSpan:new({ width = padding_bottom }))

	self.container = FrameContainer:new({
		background = Blitbuffer.COLOR_WHITE,
		bordersize = card_border_size,
		color = floating and Blitbuffer.COLOR_DARK_GRAY or nil,
		radius = floating and FLOATING_CARD_RADIUS or nil,
		margin = 0,
		padding = 0,
		VerticalGroup:new(vertical_items),
	})

	if floating then
		self.anchor_top = self:shouldAnchorTop(self.height)
		local card_row = HorizontalGroup:new({
			HorizontalSpan:new({ width = FLOATING_SIDE_MARGIN }),
			self.container,
			HorizontalSpan:new({ width = FLOATING_SIDE_MARGIN }),
		})

		if self.anchor_top then
			self[1] = TopContainer:new({
				dimen = Screen:getSize(),
				VerticalGroup:new({
					VerticalSpan:new({ width = FLOATING_EDGE_MARGIN }),
					card_row,
				}),
			})
		else
			self[1] = BottomContainer:new({
				dimen = Screen:getSize(),
				VerticalGroup:new({
					card_row,
					VerticalSpan:new({ width = FLOATING_EDGE_MARGIN }),
				}),
			})
		end
	else
		self[1] = BottomContainer:new({
			dimen = Screen:getSize(),
			self.container,
		})
	end
end

function TranslatorPreviewPopup:shouldAnchorTop(card_height)
	local bounds = self.selection_bounds
	if type(bounds) ~= "table" or not bounds.top or not bounds.bottom then
		return false
	end

	local screen_height = Screen:getHeight()
	local top_card_bottom = FLOATING_EDGE_MARGIN + card_height
	local bottom_card_top = screen_height - FLOATING_EDGE_MARGIN - card_height

	if bottom_card_top > bounds.bottom + FLOATING_SELECTION_GAP then
		return false
	end

	if top_card_bottom < bounds.top - FLOATING_SELECTION_GAP then
		return true
	end

	local space_above = math.max(0, bounds.top - FLOATING_EDGE_MARGIN - FLOATING_SELECTION_GAP)
	local space_below = math.max(0, screen_height - bounds.bottom - FLOATING_EDGE_MARGIN - FLOATING_SELECTION_GAP)
	return space_above > space_below
end

function TranslatorPreviewPopup:makeHeader(width)
	if not self.language_text then
		return nil
	end

	return ClickableLanguageText:new({
		text = self.language_text,
		width = width,
		show_parent = self,
		callback = self.language_callback,
	})
end

function TranslatorPreviewPopup:makeButtons(width)
	local actions = self.actions or {}
	local button_count = math.max(1, #actions)
	local separator_count = math.max(0, button_count - 1)
	local available_button_width = math.max(1, width - BUTTON_SEPARATOR_WIDTH * separator_count)
	local button_width = math.floor(available_button_width / button_count)
	local remainder = available_button_width - (button_width * button_count)

	local function makeSeparator()
		return LineWidget:new({
			background = Blitbuffer.COLOR_GRAY,
			dimen = Geom:new({
				w = BUTTON_SEPARATOR_WIDTH,
				h = BUTTON_HEIGHT,
			}),
		})
	end

	local widgets = {}
	for index, action in ipairs(actions) do
		if index > 1 then
			table.insert(widgets, makeSeparator())
		end

		table.insert(
			widgets,
			PreviewButton:new({
				text = action.text,
				width = button_width + (index <= remainder and 1 or 0),
				height = BUTTON_HEIGHT,
				show_parent = self,
				callback = action.callback,
			})
		)
	end

	return HorizontalGroup:new(widgets)
end

function TranslatorPreviewPopup:getWidgetHeight(widget, fallback)
	local ok, size = pcall(function()
		return widget:getSize()
	end)

	if ok and size and size.h then
		return size.h
	end

	return fallback
end

function TranslatorPreviewPopup:onShow()
	UIManager:setDirty(self.dialog or self, function()
		return "ui", self.container.dimen
	end)
end

function TranslatorPreviewPopup:onCloseWidget()
	UIManager:setDirty(self.dialog or self, function()
		return "partial", self.container.dimen
	end)
end

function TranslatorPreviewPopup:onClose()
	UIManager:close(self)
	if self.close_preview_callback then
		return self.close_preview_callback()
	end
	return true
end

function TranslatorPreviewPopup:onClosePreview()
	return self:onClose()
end

function TranslatorPreviewPopup:onTapClose(_arg, ges)
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

function TranslatorPreviewPopup:onSwipeClose(_arg, ges)
	if not ges or not ges.direction then
		return false
	end

	if ges.direction == "south" and not self.anchor_top then
		return self:onClosePreview()
	elseif ges.direction == "north" and self.anchor_top then
		return self:onClosePreview()
	end

	return false
end

function TranslatorPreview:init()
	self.current_popup = nil
	self.language_menu = nil
	self.original_showTranslation = nil
	self.opening_original_popup = false
	self.reader_ui = nil
	self.clipboard_available = Device:hasClipboard()

	if self.ui and self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end

	self:patchTranslator()
end

function TranslatorPreview:addToMainMenu(menu_items)
	menu_items.translatorpreview = {
		text = _("Translator preview"),
		sorting_hint = "tools",
		sub_item_table = {
			{
				text = _("Enable translator preview"),
				checked_func = function()
					return self:isPreviewEnabled()
				end,
				callback = function()
					self:setPreviewEnabled(not self:isPreviewEnabled())
				end,
			},
			{
				text = _("Floating preview"),
				checked_func = function()
					return self:isFloatingPreviewEnabled()
				end,
				callback = function()
					self:setFloatingPreviewEnabled(not self:isFloatingPreviewEnabled())
				end,
			},
			{
				text = _("Show source text"),
				checked_func = function()
					return self:showSourceText()
				end,
				callback = function()
					G_reader_settings:saveSetting(SETTING_SHOW_SOURCE, not self:showSourceText())
				end,
			},
			{
				text = _("Buttons"),
				sub_item_table = {
					{
						text = _("Show copy button"),
						checked_func = function()
							return self:showCopyButton()
						end,
						callback = function()
							G_reader_settings:saveSetting(SETTING_SHOW_COPY_BUTTON, not self:showCopyButton())
						end,
					},
					{
						text = _("Show note button"),
						checked_func = function()
							return self:showNoteButton()
						end,
						callback = function()
							G_reader_settings:saveSetting(SETTING_SHOW_NOTE_BUTTON, not self:showNoteButton())
						end,
					},
				},
			},
			{
				text = string.format("%s: %s", _("Version"), PLUGIN_VERSION),
				callback = function()
					self:notify(string.format("%s %s", _("Translator Preview"), PLUGIN_VERSION))
				end,
				separator = true,
			},
		},
	}
end

function TranslatorPreview:closeCurrentPopup()
	if self.current_popup then
		UIManager:close(self.current_popup)
		self.current_popup = nil
	end
end

function TranslatorPreview:destroy()
	self:closeLanguageMenu()
	self:closeCurrentPopup()

	if Translator._translatorpreview_owner == self and self.original_showTranslation then
		Translator.showTranslation = self.original_showTranslation
		Translator._translatorpreview_owner = nil
		Translator._translatorpreview_patched = nil
	end

	self.original_showTranslation = nil
	self.reader_ui = nil

	if WidgetContainer.destroy then
		WidgetContainer.destroy(self)
	end
end

function TranslatorPreview:isPreviewEnabled()
	return G_reader_settings:nilOrTrue(SETTING_ENABLED)
end

function TranslatorPreview:setPreviewEnabled(enabled)
	G_reader_settings:saveSetting(SETTING_ENABLED, enabled and true or false)
end

function TranslatorPreview:isFloatingPreviewEnabled()
	return G_reader_settings:readSetting(SETTING_FLOATING_PREVIEW) == true
end

function TranslatorPreview:setFloatingPreviewEnabled(enabled)
	G_reader_settings:saveSetting(SETTING_FLOATING_PREVIEW, enabled and true or false)
end

function TranslatorPreview:showSourceText()
	return G_reader_settings:readSetting(SETTING_SHOW_SOURCE) == true
end

function TranslatorPreview:showCopyButton()
	return G_reader_settings:nilOrTrue(SETTING_SHOW_COPY_BUTTON)
end

function TranslatorPreview:showNoteButton()
	return G_reader_settings:nilOrTrue(SETTING_SHOW_NOTE_BUTTON)
end

function TranslatorPreview:notify(message)
	UIManager:show(Notification:new({ text = message }))
	return true
end

function TranslatorPreview:showInfoMessage(message)
	local InfoMessage = require("ui/widget/infomessage")
	UIManager:show(InfoMessage:new({ text = message }))
	return true
end

function TranslatorPreview:patchTranslator()
	if Translator._translatorpreview_patched then
		logger.warn("TranslatorPreview: Translator is already patched.")
		return
	end

	self.original_showTranslation = Translator.showTranslation
	local plugin = self

	Translator.showTranslation = function(
		translator_self,
		text,
		detailed_view,
		source_lang,
		target_lang,
		from_highlight,
		index
	)
		if plugin.opening_original_popup or not plugin:isPreviewEnabled() then
			return plugin.original_showTranslation(
				translator_self,
				text,
				detailed_view,
				source_lang,
				target_lang,
				from_highlight,
				index
			)
		end

		return plugin:showTranslationPreview(
			translator_self,
			text,
			detailed_view,
			source_lang,
			target_lang,
			from_highlight,
			index
		)
	end

	Translator._translatorpreview_owner = self
	Translator._translatorpreview_patched = true
end

function TranslatorPreview:showOriginalTranslation(
	translator_self,
	text,
	detailed_view,
	source_lang,
	target_lang,
	from_highlight,
	index
)
	if not self.original_showTranslation then
		return true
	end

	self:closeCurrentPopup()

	self.opening_original_popup = true
	local ok, err = pcall(function()
		self.original_showTranslation(
			translator_self,
			text,
			detailed_view,
			source_lang,
			target_lang,
			from_highlight,
			index
		)
	end)
	self.opening_original_popup = false

	if not ok then
		logger.warn("TranslatorPreview: failed to open original translator popup:", err)
		self:notify(_("Could not open the original translator."))
	end

	return true
end

function TranslatorPreview:showTranslationPreview(
	translator_self,
	text,
	detailed_view,
	source_lang,
	target_lang,
	from_highlight,
	index
)
	if self.clipboard_available then
		Device.input.setClipboardText(text)
	end

	local NetworkMgr = require("ui/network/manager")
	if
		NetworkMgr:willRerunWhenOnline(function()
			translator_self:showTranslation(text, detailed_view, source_lang, target_lang, from_highlight, index)
		end)
	then
		return
	end

	local Trapper = require("ui/trapper")
	Trapper:wrap(function()
		self:_showTranslationPreview(
			translator_self,
			text,
			detailed_view,
			source_lang,
			target_lang,
			from_highlight,
			index
		)
	end)
end

function TranslatorPreview:_showTranslationPreview(
	translator_self,
	text,
	detailed_view,
	source_lang,
	target_lang,
	from_highlight,
	index
)
	target_lang = target_lang or translator_self:getTargetLanguage()
	source_lang = source_lang or translator_self:getSourceLanguage()

	local Trapper = require("ui/trapper")
	local completed, result = Trapper:dismissableRunInSubprocess(function()
		return translator_self:loadPage(text, target_lang, source_lang)
	end, _("Querying translation service…"))

	if not completed then
		return self:showInfoMessage(_("Translation interrupted."))
	end

	if not result or type(result) ~= "table" then
		return self:showInfoMessage(_("Translation failed."))
	end

	if result[3] then
		source_lang = result[3]
	end

	local text_main = extractMainTranslation(result)
	if text_main == "" then
		text_main = _("No translation found.")
	end

	return self:showPreviewPopup({
		translator = translator_self,
		source_text = text,
		text_main = text_main,
		source_lang = source_lang,
		target_lang = target_lang,
		detailed_view = detailed_view,
		from_highlight = from_highlight,
		index = index,
	})
end

function TranslatorPreview:getReaderUI()
	if self.reader_ui then
		return self.reader_ui
	end

	local ok, readerui = pcall(function()
		return require("apps/reader/readerui").instance
	end)

	if ok and readerui then
		self.reader_ui = readerui
		return readerui
	end

	return nil
end

function TranslatorPreview:getReaderDialog()
	local ui = self:getReaderUI()
	if ui and ui.highlight and ui.highlight.dialog then
		return ui.highlight.dialog
	end
	return nil
end

function TranslatorPreview:getSelectionBounds()
	local ui = self:getReaderUI()
	local highlight = ui and ui.highlight
	if not highlight then
		return nil
	end

	local screen_height = Screen:getHeight()
	local top
	local bottom

	local function addPosition(pos)
		local y = type(pos) == "table" and tonumber(pos.y)
		if y and y >= 0 and y <= screen_height then
			top = top and math.min(top, y) or y
			bottom = bottom and math.max(bottom, y) or y
		end
	end

	addPosition(highlight.hold_pos)
	if highlight.selected_text then
		addPosition(highlight.selected_text.pos0)
		addPosition(highlight.selected_text.pos1)
	end

	if top and bottom then
		return { top = top, bottom = bottom }
	end

	return nil
end

function TranslatorPreview:copyMainTranslation(text_main)
	if not self.clipboard_available then
		return self:notify(_("Clipboard is not available."))
	end

	Device.input.setClipboardText(text_main or "")
	return self:notify(_("Translation copied to clipboard."))
end

function TranslatorPreview:saveMainTranslationToNote(text_main, index)
	local ui = self:getReaderUI()
	local highlight = ui and ui.highlight

	if not highlight then
		return self:notify(_("No highlight available."))
	end

	self:closeCurrentPopup()

	if highlight.highlight_dialog then
		UIManager:close(highlight.highlight_dialog)
		highlight.highlight_dialog = nil
	end

	if index then
		highlight:editNote(index, false, text_main)
	else
		highlight:addNote(text_main)
	end

	return true
end

function TranslatorPreview:closeHighlightIfNeeded(from_highlight)
	if not from_highlight then
		return true
	end

	local ui = self:getReaderUI()
	local highlight = ui and ui.highlight
	if highlight and not highlight.highlight_dialog and type(highlight.clear) == "function" then
		highlight:clear()
	end

	return true
end

function TranslatorPreview:getTargetLanguageLabel(translator_self, lang)
	lang = lang or translator_self:getTargetLanguage()
	local name = translator_self:getLanguageName(lang, lang and lang:upper() or "?")
	return name or tostring(lang or "?")
end

function TranslatorPreview:closeLanguageMenu()
	if self.language_menu then
		pcall(function()
			UIManager:close(self.language_menu)
		end)
		self.language_menu = nil
	end
end

function TranslatorPreview:refreshTranslationWithTarget(data, target_lang)
	self:closeLanguageMenu()

	self:closeCurrentPopup()

	G_reader_settings:saveSetting("translator_to_language", target_lang)

	return self:showTranslationPreview(
		data.translator,
		data.source_text,
		data.detailed_view,
		data.source_lang,
		target_lang,
		data.from_highlight,
		data.index
	)
end

function TranslatorPreview:getTargetLanguageMenuItems(data)
	local translator_self = data.translator
	local items = {}

	local ok, settings_menu = pcall(function()
		return translator_self:genSettingsMenu()
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
				table.insert(items, {
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

						local selected_lang = translator_self:getTargetLanguage()
						return self:refreshTranslationWithTarget(data, selected_lang)
					end,
				})
			end
		end
	end

	if #items > 0 then
		return items
	end

	for _, lang in ipairs(COMMON_TARGET_LANGUAGES) do
		local lang_key = lang
		table.insert(items, {
			text = string.format("%s (%s)", self:getTargetLanguageLabel(translator_self, lang_key), lang_key),
			checked_func = function()
				return translator_self:getTargetLanguage() == lang_key
			end,
			radio = true,
			callback = function()
				return self:refreshTranslationWithTarget(data, lang_key)
			end,
		})
	end

	return items
end

function TranslatorPreview:showTargetLanguageMenu(data)
	local Menu = require("ui/widget/menu")
	self:closeLanguageMenu()

	self.language_menu = Menu:new({
		title = _("Translate to"),
		item_table = self:getTargetLanguageMenuItems(data),
		width = Screen:getWidth() - Screen:scaleBySize(80),
		height = math.floor(Screen:getHeight() * 0.8),
		show_parent = self.current_popup,
	})

	UIManager:show(self.language_menu)
	return true
end

function TranslatorPreview:buildPreviewPayload(data)
	local parts = {
		'<div class="translatorpreview-translation">' .. plainTextToHtml(data.text_main) .. "</div>",
	}

	if self:showSourceText() then
		table.insert(parts, '<div class="translatorpreview-source-label">' .. htmlEscape(_("Source")) .. "</div>")
		table.insert(parts, '<div class="translatorpreview-source">' .. plainTextToHtml(data.source_text) .. "</div>")
	end

	return table.concat(parts, "\n")
end

function TranslatorPreview:showPreviewPopup(data)
	local source_name = self:getTargetLanguageLabel(data.translator, data.source_lang)
	local target_name = self:getTargetLanguageLabel(data.translator, data.target_lang)
	local language_text = string.format("%s → %s ▾", source_name, target_name)
	self:closeCurrentPopup()

	local actions = {}

	if self.clipboard_available and self:showCopyButton() then
		table.insert(actions, {
			text = _("Copy"),
			callback = function()
				return self:copyMainTranslation(data.text_main)
			end,
		})
	end

	if data.from_highlight and self:showNoteButton() then
		table.insert(actions, {
			text = _("Note"),
			callback = function()
				return self:saveMainTranslationToNote(data.text_main, data.index)
			end,
		})
	end

	table.insert(actions, {
		text = _("•••"),
		callback = function()
			return self:showOriginalTranslation(
				data.translator,
				data.source_text,
				true,
				data.source_lang,
				data.target_lang,
				data.from_highlight,
				data.index
			)
		end,
	})

	local popup = TranslatorPreviewPopup:new({
		language_text = language_text,
		language_callback = function()
			return self:showTargetLanguageMenu(data)
		end,
		html_body = self:buildPreviewPayload(data),
		css = FALLBACK_CSS,
		doc_font_size = PREVIEW_FONT_SIZE,
		dialog = self:getReaderDialog(),
		floating = self:isFloatingPreviewEnabled(),
		selection_bounds = self:isFloatingPreviewEnabled() and self:getSelectionBounds() or nil,
		actions = actions,
		close_preview_callback = function()
			self.current_popup = nil
			return self:closeHighlightIfNeeded(data.from_highlight)
		end,
	})

	self.current_popup = popup
	UIManager:show(popup)
	return true
end

return TranslatorPreview
