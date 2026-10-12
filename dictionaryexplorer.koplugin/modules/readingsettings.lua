--[[
The dictionary's appearance, set by the user (shown as "Dictionary
appearance"): the font size, the line height, the side margins, whether the
text is justified, and whether the header is the compact one-line one.

Each is kept in KOReader's settings; unset means the default it follows:

  font size      the system's: KOReader's dictionary popup's (dict_font_size)
  line height    1.3
  margins        the book's being read (only crengine documents have some),
                 or a small default
  justified      the system's: KOReader's dictionary popup's (dict_justify)
  compact header no: the usual three-line header

  ReadingSettings.get()     the values in use: { font_size, line_height,
                            margin (unscaled pixels, or nil for the book's),
                            justify, compact_header }
  ReadingSettings.showDialog({ on_apply = function() })
                            one dialog for all of them. Changing a value only
                            redraws the dialog; nothing else happens until
                            Apply, which saves them and calls on_apply (the
                            viewer then lays its page out once again).
]]

local ButtonDialog = require("ui/widget/buttondialog")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local _ = require("dictionaryexplorer_l10n")
local T = require("ffi/util").template

local DEFAULT_FONT_SIZE = 20 -- the dictionary popup's default
local DEFAULT_LINE_HEIGHT = 1.3
local DEFAULT_MARGIN = 16 -- unscaled pixels, when the book has no margins to follow
local FONT_SIZE = { min = 12, max = 40, step = 1 }
local LINE_HEIGHT = { min = 1.0, max = 2.0, step = 0.1 }
local MARGIN = { min = 0, max = 60, step = 2 }

local KEYS = {
	font_size = "dictionaryexplorer_font_size",
	line_height = "dictionaryexplorer_line_height",
	margin = "dictionaryexplorer_margin",
	justify = "dictionaryexplorer_justify",
	compact_header = "dictionaryexplorer_compact_header",
}

local ReadingSettings = {
	DEFAULT_LINE_HEIGHT = DEFAULT_LINE_HEIGHT,
	DEFAULT_MARGIN = DEFAULT_MARGIN,
	KEYS = KEYS,
}

-- What is saved: nil for the ones that follow their default.
local function readSaved()
	local saved = {}
	for name, key in pairs(KEYS) do
		saved[name] = G_reader_settings:readSetting(key)
	end
	return saved
end

local function popupFontSize()
	return G_reader_settings:readSetting("dict_font_size") or DEFAULT_FONT_SIZE
end

-- The values in use for what is saved (or drafted).
local function effective(saved)
	local justify = saved.justify
	if justify == nil then
		justify = G_reader_settings:nilOrTrue("dict_justify")
	end
	return {
		font_size = saved.font_size or popupFontSize(),
		line_height = saved.line_height or DEFAULT_LINE_HEIGHT,
		margin = saved.margin, -- nil: the book's
		justify = justify,
		compact_header = saved.compact_header == true,
	}
end

--- The values in use (see the top of this file).
function ReadingSettings.get()
	return effective(readSaved())
end

local function save(draft)
	for name, key in pairs(KEYS) do
		if draft[name] == nil then
			G_reader_settings:delSetting(key)
		else
			G_reader_settings:saveSetting(key, draft[name])
		end
	end
end

local function clamp(value, range)
	return math.min(math.max(value, range.min), range.max)
end

-- One decimal for the line height (0.1 steps that add up exactly).
local function round(value)
	return math.floor(value * 10 + 0.5) / 10
end

-- The rows of the dialog for `draft`; `redraw(draft)` shows it again.
local function rows(draft, redraw, apply, cancel)
	local values = effective(draft)
	local step_width = Screen:scaleBySize(70)
	local function stepper(label, minus, plus)
		return {
			{ text = label, callback = function() end },
			{ text = "−", width = step_width, callback = minus },
			{ text = "+", width = step_width, callback = plus },
		}
	end
	local function change(name, value)
		draft[name] = value
		redraw(draft)
	end

	local font_label = draft.font_size and T(_("Font size: %1"), values.font_size)
		or T(_("Font size: %1 (follows the system)"), values.font_size)
	local line_label = T(_("Line height: %1"), string.format("%.1f", values.line_height))
	local margin_label = draft.margin and T(_("Margins: %1"), draft.margin) or _("Margins: follow the book")
	local justify_label
	if draft.justify == nil then
		justify_label = values.justify and _("Justified: yes (follows the system)") or _("Justified: no (follows the system)")
	else
		justify_label = draft.justify and _("Justified: yes") or _("Justified: no")
	end

	return {
		stepper(font_label, function()
			change("font_size", clamp(values.font_size - FONT_SIZE.step, FONT_SIZE))
		end, function()
			change("font_size", clamp(values.font_size + FONT_SIZE.step, FONT_SIZE))
		end),
		stepper(line_label, function()
			change("line_height", round(clamp(values.line_height - LINE_HEIGHT.step, LINE_HEIGHT)))
		end, function()
			change("line_height", round(clamp(values.line_height + LINE_HEIGHT.step, LINE_HEIGHT)))
		end),
		stepper(margin_label, function()
			change("margin", clamp((draft.margin or DEFAULT_MARGIN) - MARGIN.step, MARGIN))
		end, function()
			change("margin", clamp((draft.margin or DEFAULT_MARGIN) + MARGIN.step, MARGIN))
		end),
		{
			{
				-- As the popup, then yes, then no, then as the popup again.
				text = justify_label,
				callback = function()
					if draft.justify == nil then
						change("justify", true)
					elseif draft.justify then
						change("justify", false)
					else
						change("justify", nil)
					end
				end,
			},
		},
		{
			{
				text = values.compact_header and _("Header: compact (one line)") or _("Header: full"),
				callback = function()
					change("compact_header", not values.compact_header or nil)
				end,
			},
		},
		{
			{
				text = _("Defaults"),
				callback = function()
					redraw({})
				end,
			},
			{ text = _("Cancel"), callback = cancel },
			{ text = _("Apply"), callback = apply },
		},
	}
end

--- The dialog (see the top of this file).
function ReadingSettings.showDialog(options)
	options = options or {}
	local dialog
	local quiet = false
	local function close()
		if dialog then
			UIManager:close(dialog)
		end
	end
	local show
	local function redraw(draft)
		-- The dialog again, in its place: the old one goes without a refresh
		-- of its own, and one refresh covers both their areas.
		local old = dialog
		local offset = old and old.movable:getMovedOffset()
		local old_area = old and old.movable.dimen and old.movable.dimen:copy()
		quiet = true
		close()
		quiet = false
		show(draft, offset)
		local new = dialog
		UIManager:setDirty(nil, function()
			local area = new.movable.dimen
			if old_area and area then
				return "ui", old_area:combine(area)
			end
			return "ui", old_area or area
		end)
	end
	show = function(draft, offset)
		dialog = ButtonDialog:new({
			title = _("Dictionary appearance"),
			title_align = "center",
			buttons = rows(draft, redraw, function()
				save(draft)
				-- The page laid out again covers the dialog: no refresh of its own.
				quiet = options.on_apply ~= nil
				close()
				quiet = false
				if options.on_apply then
					options.on_apply(ReadingSettings.get())
				end
			end, close),
		})
		dialog.draft = draft
		if offset then
			dialog.movable:setMovedOffset(offset)
		end
		dialog.onCloseWidget = function(this)
			if not quiet then
				UIManager:setDirty(nil, function()
					return "ui", this.movable.dimen
				end)
			end
		end
		ReadingSettings.shown = dialog
		UIManager:show(dialog)
	end
	show(readSaved())
	return dialog
end

return ReadingSettings
