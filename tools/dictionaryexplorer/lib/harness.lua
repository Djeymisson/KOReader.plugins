--[[
Shared helpers for the Dictionary Explorer suites.

It is loaded, inside KOReader, by lib/launcher.lua, and every suite receives
it as its first argument. It offers:

  - reporting:      H.say(), H.check(), H.skip(), H.finish()
  - sequencing:     H.step(delay, fn): steps run one after the other on
                    KOReader's event loop, so the UI gets to run in between
  - dictionaries:   H.dictionaries() and the H.profiles the suites look for
  - UI driving:     H.gesture(), H.findWidget(), H.tapButton(), H.newViewer()
  - measuring:      H.instrument(), H.measure(), H.profile()

The instrumentation wraps some of the plugin's private functions
(Viewer._buildHtmlWidget, StarDict.readDefinition, ...): if they are renamed,
update it here, in one place.
]]

local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")

local H = { passed = 0, failed = 0, skipped = 0, clock = 0 }

-- The dictionaries the suites know about, found by a part of their name. The
-- words are ones each of them has (or has something close to).
H.profiles = {
	pt = { match = "Portuguesa", open = "livro", walk = { "livro", "amor", "correr", "constitucionalmente", "responsabilidade", "gato", "mesa", "extraordinariamente" } },
	en = { match = "English - Port", open = "house", walk = { "apple", "run", "zebra", "cat" } },
	ox = { match = "Oxford", open = "example", walk = { "love", "run", "table", "tree" } },
	-- type "x" (text with a tag or two), plain and dictzip
	da = { match = "DicAberto", open = "casa", walk = { "sol", "mesa", "luz" } },
	pe = { match = "Portuguese-English", open = "casa", walk = { "disco", "casaco", "casado" } },
	-- type "h" (HTML), dictzip
	wk = { match = "WikDict", open = "house", walk = { "apple", "cat", "dog" } },
}

function H.init(ui)
	H.ui = ui
	H.out_dir = assert(os.getenv("DE_OUT"), "DE_OUT is not set: run the suites with run.sh")
	H.report = assert(io.open(H.out_dir .. "/report.txt", "w"))
	H.StarDict = require("modules/stardict")
	H.Viewer = require("modules/viewer")
	H.Inflate = require("modules/inflate")
end

-- ---------------------------------------------------------------------------
-- Reporting
-- ---------------------------------------------------------------------------

function H.say(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(index, ...)))
	end
	H.report:write(table.concat(parts, " "), "\n")
	H.report:flush()
end

function H.check(name, ok, detail)
	if ok then
		H.passed = H.passed + 1
	else
		H.failed = H.failed + 1
	end
	H.say(string.format("%s  %s%s", ok and "PASS" or "FAIL", name, detail ~= nil and (" -- " .. tostring(detail)) or ""))
end

function H.skip(name, reason)
	H.skipped = H.skipped + 1
	H.say(string.format("SKIP  %s -- %s", name, reason))
end

--- Ends the run: writes the result line run.sh looks for and quits KOReader.
function H.finish()
	H.step(0.3, function()
		H.say(string.format("\nRESULT passed=%d failed=%d skipped=%d", H.passed, H.failed, H.skipped))
		UIManager:quit(0)
	end)
end

-- ---------------------------------------------------------------------------
-- Sequencing
-- ---------------------------------------------------------------------------

--- Runs `fn` `delay` seconds after the previous step. An error in a step is
-- reported as a failed check and does not stop the ones after it.
function H.step(delay, fn)
	H.clock = H.clock + delay
	UIManager:scheduleIn(H.clock, function()
		local ok, err = pcall(fn)
		if not ok then
			H.check("no error in step", false, err)
		end
	end)
end

--- Closes the notices a fresh profile shows at start; they would swallow events.
function H.closeStartupMessages()
	for index = #UIManager._window_stack, 1, -1 do
		local widget = UIManager._window_stack[index].widget
		if widget.text and widget.timeout ~= nil then
			UIManager:close(widget)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Dictionaries
-- ---------------------------------------------------------------------------

--- All the dictionaries the plugin can open (indexed, so ready to use):
-- { list = {StarDict...}, by = { pt = StarDict, ox = StarDict, en = StarDict } }
function H.dictionaries()
	if H.dicts then
		return H.dicts
	end
	local list, by = {}, {}
	for _index, found in ipairs(H.StarDict.scan(os.getenv("KO_HOME") .. "/data/dict")) do
		local dictionary = H.StarDict.get(found.file)
		if dictionary and (dictionary:isIndexed() or dictionary:buildIndex()) then
			list[#list + 1] = dictionary
			for key, profile in pairs(H.profiles) do
				if found.name:find(profile.match, 1, true) then
					by[key] = dictionary
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	H.dicts = { list = list, by = by }
	return H.dicts
end

-- ---------------------------------------------------------------------------
-- Driving the UI
-- ---------------------------------------------------------------------------

--- Sends a gesture down the real path a finger takes.
function H.gesture(kind, x, y, extra)
	local gesture = { ges = kind, pos = Geom:new({ x = x, y = y, w = 0, h = 0 }), time = require("ui/time").now() }
	for key, value in pairs(extra or {}) do
		gesture[key] = value
	end
	UIManager:sendEvent(Event:new("Gesture", gesture))
end

function H.findWidget(predicate)
	for index = #UIManager._window_stack, 1, -1 do
		local widget = UIManager._window_stack[index].widget
		if predicate(widget) then
			return widget
		end
	end
end

--- The viewer on screen, if any.
function H.findViewer()
	return H.findWidget(function(widget)
		return widget.goToWord ~= nil
	end)
end

--- The dialog that asks for a word, if any.
function H.findInputDialog()
	return H.findWidget(function(widget)
		return widget.getInputText ~= nil
	end)
end

--- Opens a viewer (not shown) centred on `word`.
function H.newViewer(dictionary, word)
	return H.Viewer:new({
		ui = H.ui,
		dictionary = dictionary,
		position = dictionary:locate(word),
		side_margins = { left = 30, right = 30 },
	})
end

--- Taps the button of the footer whose label (or icon name) is `text`, with a
-- real tap. A
-- Button runs its callback on the next tick, so give the UI a step before
-- looking at the result.
function H.tapButton(viewer, text)
	for _index, button in ipairs(viewer.column[#viewer.column].buttons_layout[1]) do
		if button.text == text or button.icon == text then
			local dimen = button.dimen
			H.gesture("tap", dimen.x + dimen.w / 2, dimen.y + dimen.h / 2)
			return true
		end
	end
	return false
end

--- The footer's buttons as { text, icon, enabled } tables, left to right.
function H.footer(viewer)
	local buttons = {}
	for _index, spec in ipairs(viewer.column[#viewer.column].buttons[1]) do
		buttons[#buttons + 1] = { text = spec.text, icon = spec.icon, enabled = spec.enabled ~= false }
	end
	return buttons
end

--- Whether the page fits one screen (or is one entry, which scrolls by design).
function H.fits(viewer)
	local box = viewer.html_widget.htmlbox_widget
	return box.page_count <= 1 or viewer.first == viewer.last
end

--- The words of the viewer's trail, joined with ">".
function H.trailText(viewer)
	local words = {}
	for _index, crumb in ipairs(viewer.trail) do
		words[#words + 1] = crumb.word
	end
	return table.concat(words, ">")
end

--- The word shown in bold in the breadcrumb, if it is in view.
function H.boldWord(viewer)
	for _index, item in ipairs(viewer.breadcrumb.items) do
		if item.kind == "crumb" and item.widget.bold then
			return viewer.trail[item.index].word
		end
	end
end

-- ---------------------------------------------------------------------------
-- Measuring
-- ---------------------------------------------------------------------------

--- Starts counting what the plugin does (idempotent): entries read, bytes,
-- inflated chunks, layouts done by MuPDF, files opened.
function H.instrument()
	if H.counters then
		return H.counters
	end
	local counters = { reads = 0, read_bytes = 0, inflates = 0, layouts = 0, opens = 0 }
	H.counters = counters

	local open = io.open
	io.open = function(...)
		counters.opens = counters.opens + 1
		return open(...)
	end
	local read_definition = H.StarDict.readDefinition
	H.StarDict.readDefinition = function(dictionary, entry)
		counters.reads = counters.reads + 1
		counters.read_bytes = counters.read_bytes + entry.size
		return read_definition(dictionary, entry)
	end
	local inflate = H.Inflate.raw
	H.Inflate.raw = function(...)
		counters.inflates = counters.inflates + 1
		return inflate(...)
	end
	local build = H.Viewer._buildHtmlWidget
	H.Viewer._buildHtmlWidget = function(viewer, ...)
		counters.layouts = counters.layouts + 1
		return build(viewer, ...)
	end
	return counters
end

local function copy(counters)
	local snapshot = {}
	for key, value in pairs(counters) do
		snapshot[key] = value
	end
	return snapshot
end

--- Runs fn() and returns the CPU seconds it took, the KB it allocated (the
-- collector is stopped meanwhile) and the difference of the counters.
function H.measure(fn)
	local counters = H.instrument()
	collectgarbage("collect")
	collectgarbage("stop")
	local before, memory, started = copy(counters), collectgarbage("count"), os.clock()
	fn()
	local cpu, allocated = os.clock() - started, collectgarbage("count") - memory
	local delta = {}
	for key, value in pairs(counters) do
		delta[key] = value - before[key]
	end
	collectgarbage("restart")
	return cpu, allocated, delta
end

--- Makes tbl[name] add the time of each call to H.timers[label].
function H.profile(tbl, name, label)
	H.timers = H.timers or {}
	local original = tbl[name]
	tbl[name] = function(...)
		local started = os.clock()
		local results = table.pack(original(...))
		local timer = H.timers[label] or { seconds = 0, calls = 0 }
		H.timers[label] = timer
		timer.seconds, timer.calls = timer.seconds + (os.clock() - started), timer.calls + 1
		return table.unpack(results, 1, results.n)
	end
end

--- Prints the timers collected by H.profile(), per `divisor` (turns, openings).
function H.printTimers(divisor, unit)
	local labels = {}
	for label in pairs(H.timers or {}) do
		labels[#labels + 1] = label
	end
	table.sort(labels)
	for _index, label in ipairs(labels) do
		local timer = H.timers[label]
		H.say(string.format("  %-52s %8.3f ms/%s   %5.1f calls/%s", label, timer.seconds / divisor * 1000, unit, timer.calls / divisor, unit))
	end
end

function H.resetTimers()
	H.timers = {}
end

return H
