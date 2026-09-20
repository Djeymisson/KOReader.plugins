--[[
What each operation costs: CPU time, memory allocated and what the plugin did
(entries read, inflated chunks, MuPDF layouts, files opened).

  S1  opening the viewer at a word          S5  loading the index cache; rebuilding the index
  S2  turning a page                        S6  the first dictionary popup (scanning the folders)
  S3  turning a page with the trail shown   S7  the selection dock
  S4  loading the plugin's modules

Times are CPU seconds of this machine (a desktop, not an e-reader): compare runs
on the same machine, before and after a change, not with the device. Nothing
here fails a run.
]]

local WORDS = {
	pt = { "livro", "mesa", "correr", "amor", "casa" },
	ox = { "example", "house", "table", "love", "run" },
	en = { "house", "example", "apple", "zebra", "run" },
	da = { "casa", "sol", "mesa", "luz", "docel" },
	pe = { "casa", "disco", "casaco", "casado", "gripe" },
	wk = { "house", "apple", "cat", "dog", "run" },
}

return function(H, ui)
	H.instrument()
	local dictionaries = H.dictionaries()

	local function describe(cpu, allocated, delta)
		return string.format(
			"cpu %6.1f ms | alloc %7.0f KB | reads %3.0f (%5.0f KB) inflates %2.0f layouts %2.0f opens %3.0f",
			cpu * 1000, allocated, delta.reads, delta.read_bytes / 1024, delta.inflates, delta.layouts, delta.opens
		)
	end
	local function average(delta, divisor)
		local averaged = {}
		for key, value in pairs(delta) do
			averaged[key] = value / divisor
		end
		return averaged
	end

	H.step(1, function()
		for key, dictionary in pairs(dictionaries.by) do
			local label = dictionary.name:sub(1, 34)
			local words = WORDS[key]

			-- S1: opening at a word, averaged over several words
			local cpu, allocated, total = 0, 0, { reads = 0, read_bytes = 0, inflates = 0, layouts = 0, opens = 0 }
			for _index, word in ipairs(words) do
				local viewer
				local seconds, kilobytes, delta = H.measure(function()
					viewer = H.newViewer(dictionary, word)
				end)
				cpu, allocated = cpu + seconds, allocated + kilobytes
				for counter, value in pairs(delta) do
					total[counter] = total[counter] + value
				end
				viewer:onCloseWidget()
			end
			H.say(string.format("S1 open      %-34s %s", label, describe(cpu / #words, allocated / #words, average(total, #words))))

			-- S2: 20 page turns
			local viewer = H.newViewer(dictionary, words[1])
			local seconds, kilobytes, delta = H.measure(function()
				for _turn = 1, 20 do
					viewer:showNext()
				end
			end)
			H.say(string.format("S2 page turn %-34s %s", label, describe(seconds / 20, kilobytes / 20, average(delta, 20))))

			-- S3: 20 page turns once the breadcrumb and the back / forward buttons are there
			for _index, word in ipairs(H.profiles[key].walk) do
				viewer:goToWord(word)
				if viewer.trail_index >= 5 then
					break
				end
			end
			seconds, kilobytes, delta = H.measure(function()
				for _turn = 1, 20 do
					viewer:showNext()
				end
			end)
			H.say(string.format("S3 turn+trail %-34s %s", label, describe(seconds / 20, kilobytes / 20, average(delta, 20))))
			viewer:onCloseWidget()
		end
	end)

	H.step(2, function()
		-- S4: loading the plugin's modules (parsing them), and the memory they keep
		local names = {
			"modules/inflate", "modules/stardict", "modules/fitmodel",
			"modules/dock", "modules/breadcrumb", "modules/viewer",
		}
		local kept = {}
		for _index, name in ipairs(names) do
			kept[name] = package.loaded[name]
			package.loaded[name] = nil
		end
		collectgarbage("collect")
		local memory, started = collectgarbage("count"), os.clock()
		for _index, name in ipairs(names) do
			require(name)
		end
		local cpu = os.clock() - started
		collectgarbage("collect")
		H.say(string.format("S4 load %d modules: cpu %.1f ms | retained %.0f KB", #names, cpu * 1000, collectgarbage("count") - memory))
		for _index, name in ipairs(names) do
			package.loaded[name] = kept[name]
		end
	end)

	H.step(2, function()
		-- S5: the index cache of each dictionary, and a full rebuild
		local lfs = require("libs/libkoreader-lfs")
		local module_path = os.getenv("DE_TOOLS") .. "/../../dictionaryexplorer.koplugin/modules/stardict.lua"
		for _index, dictionary in ipairs(dictionaries.list) do
			local fresh = dofile(module_path).get(dictionary.ifo_path) -- a copy that has not loaded the cache yet
			collectgarbage("collect")
			local memory, started = collectgarbage("count"), os.clock()
			local loaded = fresh:isIndexed()
			local cpu = os.clock() - started
			collectgarbage("collect")
			H.say(string.format(
				"S5 cache load %-34s %s: cpu %6.1f ms | retained %6.0f KB | file %6.0f KB | %d pages",
				dictionary.name:sub(1, 34), loaded and "ok" or "MISSING", cpu * 1000, collectgarbage("count") - memory,
				(lfs.attributes(fresh.cache_path, "size") or 0) / 1024, fresh.offsets and #fresh.offsets or 0
			))
			started = os.clock()
			fresh.offsets = nil
			fresh:buildIndex()
			H.say(string.format("S5 rebuild    %-34s cpu %6.1f ms (scanning the .idx and writing the cache)", dictionary.name:sub(1, 34), (os.clock() - started) * 1000))
		end
	end)

	H.step(2, function()
		-- S6: the first dictionary popup scans the folders and parses every .ifo
		local plugin = ui.dictionaryexplorer
		if not plugin then
			H.skip("S6 first popup", "the plugin is not active (it needs KOReader v2026.07 or newer)")
			return
		end
		local any = dictionaries.list[1]
		plugin.ifo_by_name, plugin.resolved = nil, nil
		local cpu, allocated, delta = H.measure(function()
			plugin:getDictionary(any.name)
		end)
		H.say("S6 first popup (dictionary scan): " .. describe(cpu, allocated, delta))
		local later = H.measure(function()
			for _index = 1, 100 do
				plugin:getDictionary(any.name)
			end
		end)
		H.say(string.format("S6 later popups (show_func x100): cpu %.2f ms in total", later * 1000))
	end)

	H.step(2, function()
		-- S7: the selection dock
		local first = dictionaries.list[1]
		local viewer = H.newViewer(first, H.profiles.pt.open)
		require("ui/uimanager"):show(viewer)
		local Geom = require("ui/geometry")
		local cpu, allocated = H.measure(function()
			for _index = 1, 10 do
				viewer.html_widget.htmlbox_widget.highlight_rects = { Geom:new({ x = 60, y = 100, w = 80, h = 26 }) }
				viewer:onTextSelected("word")
				viewer:_closeSelectionDock()
			end
		end)
		H.say(string.format("S7 selection dock (create and close): cpu %.2f ms | alloc %.0f KB each", cpu * 100, allocated / 10))
		viewer:onClose()
		H.say(string.format("memory in use by KOReader: %.1f MB", collectgarbage("count") / 1024))
	end)

	H.finish()
end
