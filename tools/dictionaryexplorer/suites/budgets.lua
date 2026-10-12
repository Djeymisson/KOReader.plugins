--[[
Performance budgets for paging: 150 page turns per dictionary, from five
starting points, measuring what the plugin does per turn; with the default
dictionary appearance, and again with a large font, a small one, and the
compact header (see VARIANTS).

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

-- The dictionary appearance the turns are measured with (see
-- readingsettings.lua): the defaults, and settings far from them, so that a
-- change to the layout that only works for the defaults shows. Each variant
-- starts with its own fit model (the font size and line height are part of
-- its key), so it also measures how fast a model learns.
--
-- Counts per turn grow with how many entries fit a page, so beside the
-- defaults they are checked per entry shown: definitions read per entry is
-- about 1 whatever the font (1.00 to 1.08 measured), and above
-- READS_PER_ENTRY when the read cache stops working (every layout tried then
-- reads the page again). The fill of the pages is lower with a large font
-- (each entry is a bigger slice of the page, and the room left at its foot,
-- since entries are never cut, counts more): `fill_allowance` points less.
-- Measured (desktop, 2026-10), layouts per turn and fill:
--   large   pt 1.73 81%   en 1.31 88%   ox 1.15 67%   fixtures 1.1-1.2 68-76%
--   small   pt 1.79 94%   en 1.69 96%   ox 1.31 83%   fixtures 1.4-1.5 89-94%
--   compact pt 1.70 88%   en 1.48 94%   ox 1.20 75%   fixtures 1.2-1.4 85-87%
local VARIANTS = {
	{ name = "default", settings = {} },
	{ name = "large", settings = { font_size = 28, line_height = 1.6 }, fill_allowance = 10 },
	{ name = "small", settings = { font_size = 14, line_height = 1.0, margin = 4 } },
	{ name = "compact", settings = { compact_header = true } },
}
local READS_PER_ENTRY = 1.2

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
			if candidate == dictionary and BUDGETS[key] then
				return BUDGETS[key], key
			end
		end
		return GENERAL, "general"
	end

	local ReadingSettings = require("modules/readingsettings")
	local function useSettings(settings)
		for name, setting in pairs(ReadingSettings.KEYS) do
			if settings[name] == nil then
				G_reader_settings:delSetting(setting)
			else
				G_reader_settings:saveSetting(setting, settings[name])
			end
		end
	end

	for _variant_index, variant in ipairs(VARIANTS) do
	H.step(1, function()
		useSettings(variant.settings)
		for _index, dictionary in ipairs(dictionaries.list) do
			local budget, key = budgetFor(dictionary)
			local turns, cpu, layouts, reads, opens, entries = 0, 0, 0, 0, 0, 0
			local fills, scrolling, broken = {}, 0, 0

			for _index2, fraction in ipairs(START_POINTS) do
				local viewer = H.Viewer:new({
					dictionary = dictionary,
					position = math.floor(dictionary:getCount() * fraction),
					side_margins = { left = 30, right = 30 },
				})
				for _turn = 1, TURNS do
					local previous_last = viewer.last
					local moved
					local seconds, _, delta = H.measure(function()
						moved = viewer:showNext()
					end)
					if not moved then
						break -- the end of a small dictionary (the fixtures), not a break
					end
					turns, cpu = turns + 1, cpu + seconds
					layouts, reads, opens = layouts + delta.layouts, reads + delta.reads, opens + delta.opens
					if viewer.first ~= previous_last + 1 then
						broken = broken + 1
					end
					entries = entries + viewer.last - viewer.first + 1
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
			local name = string.format("%s [%s, %s]", dictionary.name:sub(1, 30), key, variant.name)
			H.say(string.format("%s: %d turns, %.2f ms CPU per turn (not checked)", name, turns, cpu / turns * 1000))
			H.check(name .. ": layouts per turn", layouts / turns <= budget.layouts, string.format("%.2f (limit %.1f)", layouts / turns, budget.layouts))
			H.check(name .. ": files opened per turn", opens / turns <= budget.opens, string.format("%.2f (limit %.1f)", opens / turns, budget.opens))
			if variant.name == "default" then
				H.check(name .. ": definitions read per turn", reads / turns <= budget.reads, string.format("%.1f (limit %d)", reads / turns, budget.reads))
			end
			H.check(name .. ": definitions read per entry shown", reads / entries <= READS_PER_ENTRY, string.format("%.2f (limit %.1f)", reads / entries, READS_PER_ENTRY))
			local least_fill = budget.fill - (variant.fill_allowance or 0)
			H.check(name .. ": average fill of the pages", fill >= least_fill, string.format("%.0f%% (at least %d%%; %d of %d pages are a single scrolling entry)", fill, least_fill, scrolling, turns))
			H.check(name .. ": no entry skipped or repeated", broken == 0, broken .. " breaks")
		end
		useSettings({})
	end)
	end

	H.finish()
end
