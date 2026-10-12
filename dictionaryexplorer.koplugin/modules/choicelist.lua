--[[
A list of choices shown on top of the viewer: the suggestions for a word, the
other dictionaries, the results of a search.

It never fills the screen: LIST_ROWS_PER_PAGE choices at a time, with a row
at its foot that pages through it (‹ ›) and closes it (✕), so leaving it
doesn't take a choice. Every page has as many rows (the last one is filled
with blank ones), so turning a page refreshes only the list's own area, and a
list the user dragged keeps its place. Closing it clears its area without the
flash ButtonDialog uses, and does nothing at all when a choice was made: the
page shown next covers it.

  ChoiceList.show({ title =, rows = { { button }, ... }, on_show =, on_close = })
      shows the first page; on_show(dialog) is told each page's dialog (the
      shown one changes as pages turn), on_close(dialog) when it goes
  ChoiceList.closeForChoice(dialog)
      closes it because a choice was made in it (no refresh of its own)

Each dialog keeps all the choices as `choices`, whatever the page, and its
`page` and `pages`.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template

local LIST_ROWS_PER_PAGE = 6

local ChoiceList = {
	ROWS_PER_PAGE = LIST_ROWS_PER_PAGE,
}

-- Shows page `page` of the list described by `list` (see ChoiceList.show()).
-- `offset` is where the user had dragged it to, if anywhere.
local function showPage(list, page, offset)
	local rows = list.rows
	local pages = math.max(1, math.ceil(#rows / LIST_ROWS_PER_PAGE))
	local shown = {}
	for index = (page - 1) * LIST_ROWS_PER_PAGE + 1, page * LIST_ROWS_PER_PAGE do
		shown[#shown + 1] = rows[index] or (pages > 1 and { { text = "", enabled = false } }) or nil
	end
	local dialog
	local close = {
		icon = "close",
		callback = function()
			UIManager:close(dialog)
		end,
	}
	if pages > 1 then
		local function turnTo(target)
			return function()
				ChoiceList._turn(dialog, target)
			end
		end
		table.insert(shown, {
			{ icon = "chevron.left", enabled = page > 1, callback = turnTo(page - 1) },
			{ icon = "chevron.right", enabled = page < pages, callback = turnTo(page + 1) },
			close,
		})
	else
		table.insert(shown, { close })
	end
	dialog = ButtonDialog:new({
		-- list.title itself stays as given, for the next page.
		title = pages > 1 and T("%1 (%2/%3)", list.title, page, pages) or list.title,
		title_align = "center",
		buttons = shown,
	})
	if offset then
		dialog.movable:setMovedOffset(offset)
	end
	dialog._list = list
	dialog.choices, dialog.page, dialog.pages = {}, page, pages
	for _index, row in ipairs(rows) do
		dialog.choices[#dialog.choices + 1] = row[1]
	end
	dialog.onCloseWidget = function(this)
		if list.on_close then
			list.on_close(this)
		end
		if not list.quiet then
			UIManager:setDirty(nil, function()
				return "ui", this.movable.dimen
			end)
		end
	end
	if list.on_show then
		list.on_show(dialog)
	end
	UIManager:show(dialog)
	return dialog
end

--- Shows a list (see the top of this file).
-- @treturn ButtonDialog the first page
function ChoiceList.show(list)
	return showPage(list, 1)
end

--- Closes a list because a choice was made in it: the page shown next
-- covers it, so it has no refresh of its own.
function ChoiceList.closeForChoice(dialog)
	local list = dialog._list
	list.quiet = true
	UIManager:close(dialog)
	list.quiet = nil
end

-- Shows another page in place of the one shown, where the user may have
-- dragged it. The old one goes without a refresh of its own; one refresh
-- covers both areas, which are the same unless something moved it (KOReader
-- merges it with the new page's own).
function ChoiceList._turn(dialog, page)
	local list = dialog._list
	local offset = dialog.movable:getMovedOffset()
	local old_area = dialog.movable.dimen and dialog.movable.dimen:copy()
	list.quiet = true
	UIManager:close(dialog)
	list.quiet = nil
	local new = showPage(list, page, offset)
	UIManager:setDirty(nil, function()
		local area = new.movable.dimen
		if old_area and area then
			return "ui", old_area:combine(area)
		end
		return "ui", old_area or area
	end)
end

return ChoiceList
