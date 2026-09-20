--[[
Performance budgets for paging: 150 page turns per dictionary, from five
starting points, measuring what the plugin does per turn.

The budgets only cover counts, which do not depend on how fast the machine is:

  layouts/turn   pages laid out by MuPDF (the most expensive step: the fit
                 model exists to keep this low)
  opens/turn     files opened (a page reads its entries in one session)
  reads/turn     definitions read
  fill           how full of text the pages are (whitespace at the bottom)
  contiguity     no entry skipped or repeated between pages

CPU time per turn is printed for reference, but never fails a run: it depends
on the machine.

The limits were set with room above what the author's six dictionaries
measure (see `measured` below). A dictionary that is not one of them is held
to the general limits.
]]

-- What each dictionary measured when the budgets were set (desktop, 2026-09).
--   pt: 1.57 layouts, 1.3 opens, 18 reads, fill 90%    en: 1.55, 1.1, 8, 92%    ox: 1.11, 1.0, 1.8, 65%
--   da: 1.52, 1.1, 5.1, 87%    pe: 1.58, 1.1, 7.8, 93%    wk: 1.23, 1.05, 3.1, 82%
local BUDGETS = {
	pt = { layouts = 2.2, opens = 3, reads = 30, fill = 85 },
	en = { layouts = 2.0, opens = 3, reads = 14, fill = 90 },
	ox = { layouts = 1.6, opens = 2.5, reads = 4, fill = 55 },
	da = { layouts = 2.1, opens = 3, reads = 8, fill = 82 },
	pe = { layouts = 2.1, opens = 3, reads = 11, fill = 88 },
	wk = { layouts = 1.7, opens = 3, reads = 5, fill = 75 },
}
local GENERAL = { layouts = 2.5, opens = 3, reads = 60, fill = 50 }

local START_POINTS = { 0.1, 0.3, 0.5, 0.7, 0.9 }
local TURNS = 30

return function(H, ui)
	H.instrument()
	local dictionaries = H.dictionaries()
	if #dictionaries.list == 0 then
		H.skip("paging budgets", "no dictionary the plugin can open was found")
		H.finish()
		return
	end

	local function budgetFor(dictionary)
		for key, candidate in pairs(dictionaries.by) do
			if candidate == dictionary then
				return BUDGETS[key], key
			end
		end
		return GENERAL, "general"
	end

	H.step(1, function()
		for _index, dictionary in ipairs(dictionaries.list) do
			local budget, key = budgetFor(dictionary)
			local turns, cpu, layouts, reads, opens = 0, 0, 0, 0, 0
			local fills, scrolling, broken = {}, 0, 0

			for _index2, fraction in ipairs(START_POINTS) do
				local viewer = H.Viewer:new({
					dictionary = dictionary,
					position = math.floor(dictionary:getCount() * fraction),
					side_margins = { left = 30, right = 30 },
				})
				for _turn = 1, TURNS do
					local previous_last = viewer.last
					local seconds, _, delta = H.measure(function()
						viewer:showNext()
					end)
					turns, cpu = turns + 1, cpu + seconds
					layouts, reads, opens = layouts + delta.layouts, reads + delta.reads, opens + delta.opens
					if viewer.first ~= previous_last + 1 then
						broken = broken + 1
					end
					local box = viewer.html_widget.htmlbox_widget
					local used = box:getSinglePageHeight()
					if used then
						fills[#fills + 1] = used / box.dimen.h
					else
						scrolling = scrolling + 1
					end
				end
				viewer:onCloseWidget()
			end

			local sum = 0
			for _index2, fill in ipairs(fills) do
				sum = sum + fill
			end
			local fill = 100 * sum / math.max(#fills, 1)
			local name = dictionary.name:sub(1, 30) .. " [" .. key .. "]"
			H.say(string.format("%s: %d turns, %.2f ms CPU per turn (not checked)", name, turns, cpu / turns * 1000))
			H.check(name .. ": layouts per turn", layouts / turns <= budget.layouts, string.format("%.2f (limit %.1f)", layouts / turns, budget.layouts))
			H.check(name .. ": files opened per turn", opens / turns <= budget.opens, string.format("%.2f (limit %.1f)", opens / turns, budget.opens))
			H.check(name .. ": definitions read per turn", reads / turns <= budget.reads, string.format("%.1f (limit %d)", reads / turns, budget.reads))
			H.check(name .. ": average fill of the pages", fill >= budget.fill, string.format("%.0f%% (at least %d%%; %d of %d pages are a single scrolling entry)", fill, budget.fill, scrolling, turns))
			H.check(name .. ": no entry skipped or repeated", broken == 0, broken .. " breaks")
		end
	end)

	H.finish()
end
