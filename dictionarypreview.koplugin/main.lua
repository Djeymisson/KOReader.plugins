local Device = require("device")
local Event = require("ui/event")
local FootnoteWidget = require("ui/widget/footnotewidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Screen = Device.screen

local DictionaryPreview = WidgetContainer:extend({
	name = "dictionarypreview",
	is_doc_only = true,
})

local function htmlEscape(text)
	text = tostring(text or "")
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	text = text:gsub('"', "&quot;")
	return text
end

local function looksLikeHtml(text)
	text = tostring(text or "")
	return text:find("<%s*[%a/][^>]*>") ~= nil
end

local function plainTextToHtml(text)
	text = tostring(text or "")
	text = htmlEscape(text)

	text = text:gsub("\r\n", "\n")
	text = text:gsub("\r", "\n")
	text = text:gsub("\n\n+", "</p><p>")
	text = text:gsub("\n", "<br/>")

	return "<p>" .. text .. "</p>"
end

local function normalizeDictionaryHtml(definition)
	definition = tostring(definition or "")

	if definition == "" then
		return "<p>" .. htmlEscape(_("No definition.")) .. "</p>"
	end

	-- Alguns dicionários já retornam HTML.
	-- Nesse caso, preservamos a formatação original:
	-- negrito, itálico, listas, exemplos, quebras etc.
	if looksLikeHtml(definition) then
		return definition
	end

	-- Caso venha texto puro, convertemos apenas quebras de linha.
	return plainTextToHtml(definition)
end

local function appendStyleAttr(attrs, style)
	attrs = attrs or ""

	if attrs:find("style%s*=") then
		attrs = attrs:gsub('style%s*=%s*"([^"]*)"', 'style="%1; ' .. style .. '"', 1)
		return attrs
	end

	return attrs .. ' style="' .. style .. '"'
end

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
		local style = dictionary_class_styles[class_name]
		if style then
			table.insert(style_parts, style)
		end
	end

	if #style_parts == 0 then
		return nil
	end

	return table.concat(style_parts, " ")
end

local function normalizeHeadingTags(html)
	-- Alguns dicionários usam <h2> para blocos longos de pronúncia/flexão.
	-- No FootnoteWidget, o tamanho padrão de h1-h6 pode ficar exagerado.
	-- Por isso, convertemos h1-h6 em div, preservando atributos e conteúdo.
	html = html:gsub("<%s*[hH][1-6]([^>]*)>", function(attrs)
		return "<div"
			.. appendStyleAttr(
				attrs,
				"font-size:1em; line-height:1.25; margin:0.35em 0 0.25em 0; font-weight:normal;"
			)
			.. ">"
	end)

	html = html:gsub("</%s*[hH][1-6]%s*>", "</div>")

	return html
end

local function normalizeDictionaryClasses(html)
	-- Versão otimizada: em vez de fazer um gsub para cada classe,
	-- percorremos as tags com class="..." uma única vez.
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

	html = html:gsub("<%s*[lL][iI]([^>]*)>", function(attrs)
		return "<li" .. appendStyleAttr(attrs, "margin:0.18em 0;") .. ">"
	end)

	return html
end

local function shouldNormalizeDictionaryPreviewHtml(html)
	-- Evita processamento desnecessário em dicionários simples.
	-- A normalização mais custosa só roda quando há sinais dos padrões problemáticos.
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
	html = normalizeDictionaryLists(html)

	return html
end

function DictionaryPreview:init()
	self.enabled = G_reader_settings:nilOrTrue("dictionarypreview_enabled")
	self.current_popup = nil
	self.original_showDict = nil
	self.patched_dictionary = nil
	self.opening_original_popup = false

	if self.ui and self.ui.menu then
		self.ui.menu:registerToMainMenu(self)
	end

	self:patchDictionary()
end

function DictionaryPreview:addToMainMenu(menu_items)
	menu_items.dictionarypreview = {
		text = _("Dictionary preview"),
		sorting_hint = "more_tools",

		checked_func = function()
			return self.enabled
		end,

		callback = function()
			self.enabled = not self.enabled
			G_reader_settings:saveSetting("dictionarypreview_enabled", self.enabled)
		end,
	}
end

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
		if
			not plugin.enabled
			or plugin.opening_original_popup
			or not results
			or not results[1]
			or results[1].no_result
		then
			return plugin.original_showDict(dict_self, word, results, boxes, link, dict_close_callback)
		end

		if dict_self.dismissLookupInfo then
			pcall(function()
				dict_self:dismissLookupInfo()
			end)
		end

		return plugin:showFootnotePreview(dict_self, word, results, boxes, link, dict_close_callback)
	end

	dictionary._dictionarypreview_patched = true
end

function DictionaryPreview:showOriginalDictionaryPopup(dict_self, word, results, boxes, link, dict_close_callback)
	if not self.original_showDict then
		return
	end

	self.opening_original_popup = true

	local ok, err = pcall(function()
		self.original_showDict(dict_self, word, results, boxes, link, dict_close_callback)
	end)

	self.opening_original_popup = false

	if not ok then
		logger.warn("DictionaryPreview: failed to open original dictionary popup:", err)
	end
end

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

function DictionaryPreview:getDocumentFontName(dict_self)
	if dict_self and dict_self.ui and dict_self.ui.font and dict_self.ui.font.font_face then
		return dict_self.ui.font.font_face
	end

	return "Noto Sans"
end

function DictionaryPreview:getDocumentFontSize(dict_self)
	if
		dict_self
		and dict_self.ui
		and dict_self.ui.document
		and dict_self.ui.document.configurable
		and dict_self.ui.document.configurable.font_size
	then
		return Screen:scaleBySize(dict_self.ui.document.configurable.font_size)
	end

	return Screen:scaleBySize(18)
end

function DictionaryPreview:getDocumentMargins(dict_self)
	if dict_self and dict_self.ui and dict_self.ui.document and dict_self.ui.document.getPageMargins then
		local ok, margins = pcall(function()
			return dict_self.ui.document:getPageMargins()
		end)

		if ok and margins then
			return margins
		end
	end

	return {
		left = Screen:scaleBySize(20),
		right = Screen:scaleBySize(20),
		top = Screen:scaleBySize(10),
		bottom = Screen:scaleBySize(10),
	}
end

function DictionaryPreview:buildPreviewHtml(word, result)
	result = result or {}

	local shown_word = result.word or word or _("Dictionary")
	local dict_name = result.dict or _("Dictionary")
	local definition_html = normalizeDictionaryPreviewHtml(result.definition)

	return table.concat({
		"<html>",
		'<body style="margin:0; padding:0; font-size:1em; line-height:1.25;">',

		'<div style="margin-bottom:0.45em; font-size:0.92em; font-weight:bold;">',
		htmlEscape(shown_word),
		" — ",
		htmlEscape(dict_name),
		"</div>",

		'<div style="border-top:1px solid #888; margin:0.3em 0 0.45em 0;"></div>',

		definition_html,

		'<div style="border-top:1px solid #888; margin:0.55em 0 0.35em 0;"></div>',

		'<div style="font-weight:bold; font-size:0.92em; margin-top:0.35em;">',
		htmlEscape(_("Toque aqui para ver mais")),
		"</div>",

		"</body>",
		"</html>",
	}, "\n")
end

function DictionaryPreview:showFootnotePreview(dict_self, word, results, boxes, link, dict_close_callback)
	local result = results and results[1] or {}

	if self.current_popup then
		UIManager:close(self.current_popup)
		self.current_popup = nil
	end

	local popup
	local opened_full_popup = false

	local function closePreviewOnly()
		if popup then
			UIManager:close(popup)
			popup = nil
		end

		self.current_popup = nil
		self:clearOriginalHighlight(dict_self)
		self:clearSelection()

		if dict_close_callback then
			pcall(dict_close_callback)
		end

		return true
	end

	local function openFullPopup()
		opened_full_popup = true

		if popup then
			UIManager:close(popup)
			popup = nil
		end

		self.current_popup = nil

		self:showOriginalDictionaryPopup(dict_self, word, results, boxes, link, dict_close_callback)

		return true
	end

	local html = self:buildPreviewHtml(word, result)

	popup = FootnoteWidget:new({
		html = html,

		doc_font_name = self:getDocumentFontName(dict_self),
		doc_font_size = self:getDocumentFontSize(dict_self),
		doc_margins = self:getDocumentMargins(dict_self),

		dialog = dict_self and dict_self.dialog,

		-- Mantém o comportamento típico do FootnoteWidget:
		-- o gesto de "seguir/abrir" também chama o popup completo.
		follow_callback = function()
			return openFullPopup()
		end,
	})

	local original_on_close_widget = popup.onCloseWidget

	popup.onTapClose = function(footnote_self, arg, ges)
		-- Toque fora do painel: fecha o preview.
		if
			ges
			and ges.pos
			and footnote_self.container
			and footnote_self.container.dimen
			and ges.pos:notIntersectWith(footnote_self.container.dimen)
		then
			return closePreviewOnly()
		end

		-- Toque dentro do painel: abre o popup original completo.
		return openFullPopup()
	end

	popup.onCloseWidget = function(footnote_self)
		self.current_popup = nil

		if not opened_full_popup then
			self:clearOriginalHighlight(dict_self)
		end

		if original_on_close_widget then
			return original_on_close_widget(footnote_self)
		end
	end

	self.current_popup = popup
	UIManager:show(popup)

	return true
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

	if WidgetContainer.destroy then
		WidgetContainer.destroy(self)
	end
end

return DictionaryPreview
