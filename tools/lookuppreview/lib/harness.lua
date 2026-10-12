--[[
Shared helpers for the Lookup Preview suites.

It is loaded, inside KOReader, by lib/launcher.lua, and every suite receives
it as its first argument. It offers:

  - reporting:      H.say(), H.check(), H.skip(), H.finish()
  - sequencing:     H.step(delay, fn): steps run one after the other on
                    KOReader's event loop, so the UI gets to run in between
  - the book:       H.wordCenter(), H.holdWord(), H.lookUpWord()
  - the carousel:   H.popup(), H.activeHtml(), H.findButton(), H.tapButton(),
                    H.closeCarousel(), H.nativeWindows()
  - stand-ins:      H.stubOnline(): the translation service and Wikipedia
                    answer from here, and the device counts as online
]]

local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")

local H = { passed = 0, failed = 0, skipped = 0, clock = 0 }

function H.init(ui)
	H.ui = ui
	H.plugin = ui.lookuppreview
	H.out_dir = assert(os.getenv("LP_OUT"), "LP_OUT is not set: run the suites with run.sh")
	H.report = assert(io.open(H.out_dir .. "/report.txt", "w"))
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
-- The book
-- ---------------------------------------------------------------------------

--- Sends a gesture down the real path a finger takes.
function H.gesture(kind, x, y, extra)
	local gesture = { ges = kind, pos = Geom:new({ x = x, y = y, w = 0, h = 0 }), time = require("ui/time").now() }
	for key, value in pairs(extra or {}) do
		gesture[key] = value
	end
	UIManager:sendEvent(Event:new("Gesture", gesture))
end

--- The centre of `word` on the page shown, in screen coordinates.
function H.wordCenter(word)
	local document = H.ui.document
	local hits = document:findAllText(word, false, 0, 1)
	local hit = hits and hits[1]
	assert(hit, "the book has no " .. word)
	local boxes = document:getScreenBoxesFromPositions(hit.start, hit["end"], true)
	local box = assert(boxes and boxes[1], "no box for " .. word)
	return box.x + math.floor(box.w / 2), box.y + math.floor(box.h / 2)
end

--- Selects `word` with a long press, as a finger does, without lifting it:
-- ReaderHighlight then has the word selected, ready for Translate or Wikipedia.
function H.holdWord(word)
	local x, y = H.wordCenter(word)
	H.gesture("hold", x, y)
	return x, y
end

--- A long press on `word` and its release: KOReader looks it up in the
-- dictionary, as when reading.
function H.lookUpWord(word)
	local x, y = H.holdWord(word)
	H.gesture("hold_release", x, y)
end

-- ---------------------------------------------------------------------------
-- The carousel
-- ---------------------------------------------------------------------------

function H.findWidget(predicate)
	for index = #UIManager._window_stack, 1, -1 do
		local widget = UIManager._window_stack[index].widget
		if predicate(widget) then
			return widget
		end
	end
end

--- The carousel on screen, if any.
function H.popup()
	return H.findWidget(function(widget)
		return widget.card_container ~= nil and widget.plugin == H.plugin
	end)
end

--- The HTML widget of the active card, or of card `index` when it is built.
function H.cardHtml(index)
	local popup = H.popup()
	local row = popup and popup.card_container
	if not row then
		return nil
	end
	local card = index and row.cards[index] or row.active_card
	return card and card.html_widget
end

function H.activeHtml()
	return H.cardHtml(nil)
end

--- The page of the active card's content shown, and how many there are.
function H.activePage()
	local html = H.activeHtml()
	local box = html and html.htmlbox_widget
	return box and box.page_number, box and box.page_count
end

local function walk(widget, visit, seen)
	if type(widget) ~= "table" or seen[widget] then
		return nil
	end
	seen[widget] = true
	if visit(widget) then
		return widget
	end
	for index = 1, #widget do
		local found = walk(widget[index], visit, seen)
		if found then
			return found
		end
	end
	return nil
end

--- The button of the active card whose hint is `hint`.
function H.findButton(hint)
	local popup = H.popup()
	local card = popup and popup.card_container.active_card
	if not card then
		return nil
	end
	return walk(card, function(widget)
		return widget.hint == hint and widget.onTapDictionaryButton ~= nil
	end, {})
end

--- Taps the button of the active card whose hint is `hint`, with a real tap.
function H.tapButton(hint)
	local button = H.findButton(hint)
	if not button then
		return false
	end
	local dimen = button.dimen
	H.gesture("tap", dimen.x + math.floor(dimen.w / 2), dimen.y + math.floor(dimen.h / 2))
	return true
end

--- The hints of the active card's buttons, in order.
function H.buttonHints()
	local hints = {}
	local popup = H.popup()
	local card = popup and popup.card_container.active_card
	if card then
		walk(card, function(widget)
			if widget.onTapDictionaryButton and widget.hint then
				hints[#hints + 1] = widget.hint
			end
			return false
		end, {})
	end
	return hints
end

--- Closes the carousel with a tap outside it, as a finger does.
function H.closeCarousel()
	local popup = H.popup()
	if not popup then
		return
	end
	local area = popup.visible_dimen
	local y = area.y > 40 and 10 or (area.y + area.h + 10)
	H.gesture("tap", 10, y)
end

--- KOReader's own dictionary windows on screen.
function H.nativeWindows()
	return #require("ui/widget/dictquicklookup").window_list
end

--- The status of card `page` in the open lookup.
function H.status(page)
	local state = H.plugin.current_state
	local load = state and state.load and state.load[page]
	return load and load.status or "idle", load and load.message
end

-- ---------------------------------------------------------------------------
-- Stand-ins for the network
-- ---------------------------------------------------------------------------

--- The translation service and Wikipedia answer from here. `translate(text,
-- target)` returns the translated text; `wikipedia(text, lang)` returns a list
-- of { title = , extract = }. H.calls counts the queries.
function H.stubOnline(translate, wikipedia)
	H.calls = { translation = 0, wikipedia = 0 }
	local NetworkMgr = require("ui/network/manager")
	NetworkMgr.isOnline = function()
		return true
	end

	local Translator = require("ui/translator")
	Translator.loadPage = function(_self, text, target_lang)
		H.calls.translation = H.calls.translation + 1
		H.calls.last_translation = text
		return { { { translate(text, target_lang), text } }, nil, "pt" }
	end

	local Wikipedia = require("ui/wikipedia")
	Wikipedia.searchAndGetIntros = function(_self, text, lang)
		H.calls.wikipedia = H.calls.wikipedia + 1
		H.calls.last_wikipedia = text
		local pages = {}
		for index, page in ipairs(wikipedia(text, lang) or {}) do
			pages[page.title] = { title = page.title, extract = page.extract, index = index }
		end
		return pages
	end
end

return H
