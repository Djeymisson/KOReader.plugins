local History = {}

function History.getLocationPage(ui, location)
	if not ui or not location then
		return nil
	end
	if ui.rolling and location.xpointer and ui.document then
		local ok, page = pcall(ui.document.getPageFromXPointer, ui.document, location.xpointer)
		if ok then
			return tonumber(page)
		end
	elseif ui.paging and location[1] then
		return tonumber(location[1].page)
	end
	return nil
end

function History.getCurrentLocation(ui)
	if not ui or not ui.link or type(ui.link.getCurrentLocation) ~= "function" then
		return nil
	end
	local ok, location = pcall(ui.link.getCurrentLocation, ui.link)
	return ok and location or nil
end

-- Returns 1 when target is later in the document, -1 when it is earlier,
-- 0 when it is the same location, and nil when the order is unavailable.
-- XPointer comparison keeps reflowable locations accurate even when two
-- positions happen to share the same rendered page number.
function History.compareLocationToCurrent(ui, target)
	local current = History.getCurrentLocation(ui)
	if not current or not target then
		return nil
	end

	if current.xpointer and target.xpointer and ui.document
			and type(ui.document.compareXPointers) == "function" then
		local ok, comparison = pcall(
			ui.document.compareXPointers,
			ui.document,
			current.xpointer,
			target.xpointer
		)
		if ok and tonumber(comparison) then
			comparison = tonumber(comparison)
			if comparison > 0 then
				return 1
			elseif comparison < 0 then
				return -1
			end
			return 0
		end
	end

	local current_page = History.getLocationPage(ui, current)
	local target_page = History.getLocationPage(ui, target)
	if current_page and target_page then
		if target_page > current_page then
			return 1
		elseif target_page < current_page then
			return -1
		end
		return 0
	end
	return nil
end

function History.isCurrentLocation(ui, location)
	if not ui or not ui.link or type(ui.link.compareLocationToCurrent) ~= "function" then
		return false
	end
	local ok, same = pcall(ui.link.compareLocationToCurrent, ui.link, location)
	return ok and same == true
end

function History.getPageLabel(ui, location)
	local page = History.getLocationPage(ui, location)
	if not page then
		return "?"
	end

	local ok, label = pcall(function()
		if ui.pagemap and ui.pagemap:wantsPageLabels() then
			local xpointer = location.xpointer
			if not xpointer and ui.document.getPageXPointer then
				xpointer = ui.document:getPageXPointer(page)
			end
			if xpointer then
				return ui.pagemap:getXPointerPageLabel(xpointer, true)
			end
		elseif ui.document.hasHiddenFlows and ui.document:hasHiddenFlows() then
			local flow = ui.document:getPageFlow(page)
			local page_in_flow = ui.document:getPageNumberInFlow(page)
			if flow == 0 then
				return tostring(page_in_flow)
			end
			return ("[%d]%d"):format(page_in_flow, flow)
		end
		return tostring(page)
	end)

	return ok and label and tostring(label) or tostring(page)
end

-- Total book page count, or nil when the document can't report one.
function History.getBookPageCount(ui)
	if not ui or not ui.document or type(ui.document.getPageCount) ~= "function" then
		return nil
	end
	local ok, page_count = pcall(ui.document.getPageCount, ui.document)
	page_count = ok and tonumber(page_count) or nil
	if not page_count or page_count <= 0 then
		return nil
	end
	return page_count
end

-- Raw 0-100 percentage through the whole book, or nil when it can't be
-- computed -- kept separate from getPercentageLabel so callers that need
-- the number itself (e.g. to build a chapter-aware sentence) don't have to
-- parse a pre-formatted "78.00%" string back apart.
function History.getBookPercentage(ui, location)
	local page = History.getLocationPage(ui, location)
	local page_count = History.getBookPageCount(ui)
	if not page or not page_count then
		return nil
	end
	return math.max(0, math.min(100, page / page_count * 100))
end

function History.getPercentageLabel(ui, location)
	local percentage = History.getBookPercentage(ui, location)
	if not percentage then
		return History.getPageLabel(ui, location)
	end
	return string.format("%.2f%%", percentage)
end

local function safeCall(callback, fallback)
	local ok, result = pcall(callback)
	if ok then
		return result
	end
	return fallback
end

-- Chapter title plus the current position within that chapter (not the
-- whole book). Adapted from Quick Dock's own chapter-progress math
-- (quickdock.koplugin/modules/info_panel.lua's getChapterData) -- same
-- pagemap-vs-not branching, since ReaderToc's chapter-boundary lookups
-- behave differently for documents using page labels (e.g. some PDF/CBZ
-- setups) than for reflowable ones. Returns nil when there's no usable
-- chapter title, e.g. a document with no table of contents, so callers can
-- fall back to the plain page/percentage label.
function History.getChapterInfo(ui, location)
	local page = History.getLocationPage(ui, location)
	if not page or not ui or not ui.toc then
		return nil
	end

	local title = tostring(safeCall(function()
		return ui.toc:getTocTitleByPage(page)
	end, "") or "")
	if title == "" then
		return nil
	end

	local book_total = History.getBookPageCount(ui) or page
	local uses_page_labels = safeCall(function()
		return ui.pagemap and ui.pagemap:wantsPageLabels()
	end, false)

	local chapter_page, chapter_total
	if uses_page_labels then
		local chapter_start = safeCall(function()
			if ui.toc:isChapterStart(page) then
				return page
			end
			return ui.toc:getPreviousChapter(page)
		end, nil) or 1
		local next_chapter = safeCall(function()
			return ui.toc:getNextChapter(page)
		end, nil) or (book_total + 1)
		chapter_page = page - chapter_start + 1
		chapter_total = math.max(1, next_chapter - chapter_start)
	else
		local pages_done = safeCall(function()
			return ui.toc:getChapterPagesDone(page)
		end, nil)
		chapter_page = math.max(1, (tonumber(pages_done) or (page - 1)) + 1)
		chapter_total = math.max(1, tonumber(safeCall(function()
			return ui.toc:getChapterPageCount(page)
		end, book_total)) or book_total)
	end

	return {
		title = title,
		page = chapter_page,
		total = chapter_total,
		percentage = math.max(0, math.min(100, chapter_page / chapter_total * 100)),
	}
end

return History
