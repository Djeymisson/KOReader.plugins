--[[
What the viewer's page says about a word, above the entries or in its header.

  Notices.cut(text)              a word as shown in a notice or a title: cut to
                                 MAX_CHARS characters, so a pasted paragraph
                                 can't crowd out the page
  Notices.missText(miss)         the line for a word with no entry of its own
                                 here (miss: { word, shown, from, found }, see
                                 the viewer's _missFrom())
  Notices.build(text, width, left)
                                 that line as a widget: a gap above it, at most
                                 MAX_LINES lines, `left` pixels in
  Notices.headerMark(index, count)
                                 "· ‹ 2/3 ›", after the dictionary's name
]]

local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("dictionaryexplorer_l10n")
local T = require("ffi/util").template

local MAX_CHARS = 60
local MAX_LINES = 2

local Notices = {}

--- `text` cut to MAX_CHARS characters (not bytes), with "…" when cut.
function Notices.cut(text)
	local characters = 0
	for position in text:gmatch("()[%z\1-\127\194-\244]") do
		characters = characters + 1
		if characters > MAX_CHARS then
			return text:sub(1, position - 1) .. "…"
		end
	end
	return text
end

--- The line for a word with no entry of its own here: the dictionary it was
-- found in instead (just said: the word was found), or the spelling shown
-- instead, or that the closest entry is shown; and, for those two, that
-- tapping it gives suggestions.
function Notices.missText(miss)
	local cut = Notices.cut
	local text
	if miss.from and miss.shown then
		return T(_("No entry for “%1” in %2. Showing “%3” from %4."), cut(miss.word), miss.from, cut(miss.shown), miss.found)
	elseif miss.from then
		return T(_("No entry for “%1” in %2. Found in %3."), cut(miss.word), miss.from, miss.found)
	elseif miss.shown then
		text = T(_("No entry for “%1”. Showing “%2”."), cut(miss.word), cut(miss.shown))
	else
		text = T(_("No entry for “%1”. Showing the closest one."), cut(miss.word))
	end
	return text .. " " .. _("Tap here for suggestions.")
end

--- A notice as a widget: `gap` pixels above it, `left` pixels in, `width`
-- wide, at most MAX_LINES lines (the last one ending in "…" if it is cut).
function Notices.build(text, width, left, gap)
	local face = Font:getFace("NotoSans-Italic.ttf", 16)
	local line_px = math.floor((1 + TextBoxWidget.line_height) * face.size + 0.5)
	return VerticalGroup:new({
		align = "left",
		VerticalSpan:new({ width = gap }),
		HorizontalGroup:new({
			HorizontalSpan:new({ width = left }),
			TextBoxWidget:new({
				text = text,
				face = face,
				width = width,
				height = MAX_LINES * line_px,
				height_adjust = true, -- a single line takes one line's height
				height_overflow_show_ellipsis = true,
			}),
		}),
	})
end

--- The header's mark: which of the dictionaries that have the word the page
-- is about this one is ("· ‹ 2/3 ›"; tapping the line goes to the previous or
-- the next). Smaller than
-- the dictionary's name, so it never makes the header taller (the viewer also
-- keeps the line's height).
function Notices.headerMark(index, count)
	return TextWidget:new({
		text = string.format("  ·  ‹ %d/%d ›", index, count),
		face = Font:getFace("NotoSans-Bold.ttf", 15),
	})
end

return Notices
