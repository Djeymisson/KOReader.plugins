--[[
Breadcrumb of the words the user has walked through with "Go to word".

One line across the whole width, oldest word on the left and the latest on the
right, with the word the user is on in bold (the latest, until they tap an
earlier one):  … › casa › **livro** › amor. It sits at the top of the viewer,
right under the header (whose rule is the one above it), with a thick rule below
it that separates it from the entries.
Words that don't fit are replaced by "…". Swiping right shows the earlier words
(swiping left goes back towards the latest), and tapping a word selects it.
The trail itself lives in the viewer, and so do the buttons that step back and
forward along it; this widget only draws the trail and reports taps and scrolling.
]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")

local Screen = Device.screen

local FONT_FACE = "infofont"
local FONT_SIZE = 18
-- What the user sees is a gap of GAP_AROUND_TEXT (unscaled pixels) between the
-- header's rule and the words, and the same between the words and the rule
-- below them. The font leaves some room of its own above and below the letters
-- (as fractions of the line height, measured on this font), which is taken off
-- so the two gaps look equal.
local GAP_AROUND_TEXT = 12
local FONT_ROOM_ABOVE = 0.24
local FONT_ROOM_BELOW = 0.14

local SEPARATOR = " › "
local ELLIPSIS = "…"

local Breadcrumb = InputContainer:extend({
	trail = nil, -- array of { word = string }
	current_index = nil, -- the word the user is on, shown in bold; the last when nil
	width = 0,
	end_index = nil, -- rightmost word to show; the last one when nil
	on_select = nil, -- function(index): a word was tapped
	on_scroll = nil, -- function(end_index): the user asked to see other words
})

local text_height
local function measure()
	if not text_height then
		local probe = TextWidget:new({ text = "Ag", face = Font:getFace(FONT_FACE, FONT_SIZE) })
		text_height = probe:getSize().h
		probe:free()
	end
	local gap = Screen:scaleBySize(GAP_AROUND_TEXT)
	local gap_above = math.max(0, gap - math.floor(FONT_ROOM_ABOVE * text_height + 0.5))
	local gap_below = math.max(0, gap - math.floor(FONT_ROOM_BELOW * text_height + 0.5))
	return {
		text_height = text_height,
		gap_above = gap_above,
		gap_below = gap_below,
		band = gap_above + text_height + gap_below, -- what lies between the header's rule and the one below
	}
end

--- Height of the breadcrumb: the band with the words, and the rule below.
function Breadcrumb.getHeight()
	return measure().band + Size.line.thick
end

function Breadcrumb:init()
	self.face = Font:getFace(FONT_FACE, FONT_SIZE)
	self.padding_h = Size.padding.large
	self.dimen = Geom:new({ w = self.width, h = Breadcrumb.getHeight() })

	self:_layout()
	self.ges_events = {
		CrumbTap = {
			GestureRange:new({
				ges = "tap",
				range = function()
					return self.dimen
				end,
			}),
		},
		CrumbSwipe = {
			GestureRange:new({
				ges = "swipe",
				range = function()
					return self.dimen
				end,
			}),
		},
	}
end

function Breadcrumb:_text(text, bold, color, max_width)
	return TextWidget:new({ text = text, face = self.face, bold = bold, fgcolor = color, max_width = max_width })
end

-- Decides which words are shown, and where. The word at `end_index` goes at
-- the right end and earlier ones are added towards the left while they fit,
-- keeping room for a "…" when some are left out.
function Breadcrumb:_layout()
	local trail = self.trail
	local count = #trail
	local last = math.min(math.max(self.end_index or count, 1), count)
	local current = self.current_index or count
	local available = self.width - 2 * self.padding_h

	local separator = self:_text(SEPARATOR, false, Blitbuffer.COLOR_DARK_GRAY)
	local ellipsis = self:_text(ELLIPSIS)
	local separator_width, ellipsis_width = separator:getSize().w, ellipsis:getSize().w
	local room_for_ellipsis = separator_width + ellipsis_width

	-- Which words fit is decided with every word's bold width, the widest it can
	-- be, so that changing which word is in bold never changes which words show.
	-- The words themselves are drawn at their real width.
	local function crumb(index, max_width)
		local bold = self:_text(trail[index].word, true, nil, max_width)
		local fit_width = bold:getSize().w
		if index == current then
			return bold, fit_width
		end
		bold:free()
		return self:_text(trail[index].word, false, nil, max_width), fit_width
	end

	-- A "…" is needed on each side that has words left out.
	local function reserve(first, last)
		return (first > 1 and room_for_ellipsis or 0) + (last < count and room_for_ellipsis or 0)
	end

	-- The word at `last` always shows, cut short if it has to be.
	local crumbs = {}
	local last_fit_width
	crumbs[last], last_fit_width = crumb(last, math.max(available - reserve(last, last), ellipsis_width))
	local total = last_fit_width -- the words shown and the separators between them

	-- Add earlier words while they fit...
	local first = last
	while first > 1 do
		local candidate, candidate_fit_width = crumb(first - 1)
		local needed = total + candidate_fit_width + separator_width
		if needed + reserve(first - 1, last) > available then
			candidate:free()
			break
		end
		first = first - 1
		crumbs[first] = candidate
		total = needed
	end

	-- ...and once the first word of the trail is reached (the user has swiped
	-- back to the start), use what is left of the line for the words that come
	-- after, so no room is wasted before the closing "…".
	if first == 1 then
		while last < count do
			local candidate, candidate_fit_width = crumb(last + 1)
			local needed = total + candidate_fit_width + separator_width
			if needed + reserve(first, last + 1) > available then
				candidate:free()
				break
			end
			last = last + 1
			crumbs[last] = candidate
			total = needed
		end
	end
	local more_after = last < count

	-- Lay everything out left to right.
	local items, x = {}, 0
	local function add(widget, kind, index)
		local width = widget:getSize().w
		items[#items + 1] = { widget = widget, kind = kind, index = index, x = x, w = width }
		x = x + width
	end
	local function addSeparator()
		add(self:_text(SEPARATOR, false, Blitbuffer.COLOR_DARK_GRAY), "separator")
	end
	if first > 1 then
		add(self:_text(ELLIPSIS), "before")
		addSeparator()
	end
	for index = first, last do
		if index > first then
			addSeparator()
		end
		add(crumbs[index], "crumb", index)
	end
	if more_after then
		addSeparator()
		add(self:_text(ELLIPSIS), "after")
	end
	separator:free()
	ellipsis:free()

	-- Tapping just beside a word counts as tapping the word.
	for position, item in ipairs(items) do
		if item.kind ~= "separator" then
			local before, after = items[position - 1], items[position + 1]
			item.hit_from = before and (before.x + before.w / 2) or 0
			item.hit_to = after and (after.x + after.w / 2) or math.huge
		end
	end

	self.items = items
	self.first_visible, self.last_visible = first, last
end

function Breadcrumb:paintTo(bb, x, y)
	self.dimen.x, self.dimen.y = x, y
	local m = measure()
	for _index, item in ipairs(self.items) do
		item.widget:paintTo(bb, x + self.padding_h + item.x, y + m.gap_above)
	end
	bb:paintRect(x, y + m.band, self.width, Size.line.thick, Blitbuffer.COLOR_BLACK)
end

function Breadcrumb:free()
	for _index, item in ipairs(self.items or {}) do
		item.widget:free()
	end
	self.items = nil
end

function Breadcrumb:onCloseWidget()
	self:free()
end

-- Where to move the window of visible words. One word stays in view across
-- the move, so the user keeps their bearings.
function Breadcrumb:_scrollTo(direction)
	local visible = self.last_visible - self.first_visible + 1
	local target
	if direction == "earlier" and self.first_visible > 1 then
		target = visible > 1 and self.first_visible or self.first_visible - 1
	elseif direction == "later" and self.last_visible < #self.trail then
		target = math.min(#self.trail, self.last_visible + math.max(1, visible - 1))
	end
	if target and self.on_scroll then
		self.on_scroll(target)
	end
	return target ~= nil
end

function Breadcrumb:onCrumbTap(_arg, ges)
	local x = ges.pos.x - self.dimen.x - self.padding_h
	for _index, item in ipairs(self.items) do
		if item.hit_from and x >= item.hit_from and x < item.hit_to then
			if item.kind == "crumb" then
				if self.on_select then
					self.on_select(item.index)
				end
			elseif item.kind == "before" then
				self:_scrollTo("earlier")
			else
				self:_scrollTo("later")
			end
			return true
		end
	end
	return true
end

function Breadcrumb:onCrumbSwipe(_arg, ges)
	local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
	if direction == "east" then
		self:_scrollTo("earlier")
		return true
	elseif direction == "west" then
		self:_scrollTo("later")
		return true
	end
	return false
end

return Breadcrumb
