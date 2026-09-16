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

-- ReaderLink may keep the current location on top of a stack. Its native
-- back/forward handlers skip that entry, so the floating label must do the
-- same to advertise the location that will actually be restored.
function History.getEffectiveTarget(ui, stack)
	if type(stack) ~= "table" then
		return nil
	end
	for index = #stack, 1, -1 do
		local location = stack[index]
		if not History.isCurrentLocation(ui, location) then
			return location
		end
	end
	return nil
end

function History.stackContainsPage(ui, stack, page)
	if type(stack) ~= "table" or type(page) ~= "number" then
		return false
	end
	for _, location in ipairs(stack) do
		if History.getLocationPage(ui, location) == page then
			return true
		end
	end
	return false
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

function History.getPercentageLabel(ui, location)
	local page = History.getLocationPage(ui, location)
	if not page or not ui or not ui.document
			or type(ui.document.getPageCount) ~= "function" then
		return History.getPageLabel(ui, location)
	end

	local ok, page_count = pcall(ui.document.getPageCount, ui.document)
	page_count = ok and tonumber(page_count) or nil
	if not page_count or page_count <= 0 then
		return History.getPageLabel(ui, location)
	end

	local percentage = math.floor(page / page_count * 100 + 0.5)
	percentage = math.max(0, math.min(100, percentage))
	return tostring(percentage) .. "%"
end

return History
