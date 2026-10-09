-- Page Anchor behaviour simulation.
--
-- Loads the real pageanchor.koplugin/main.lua with small stand-ins for the
-- KOReader modules it uses (UIManager, ReaderLink, the document, widgets...)
-- and runs scenarios against its logic: when anchors are armed and resolved,
-- the trail, undo, pinned anchors, percentages, touch zones, PDF view state,
-- and so on. It checks behaviour, not looks: the widgets are fakes, so
-- rendering and real touch input still need a device. See README.md.
--
--   lua tools/pageanchor/sim.lua
--
-- Prints one "ok"/"FAIL" line per check, then ALL PASSED or the number of
-- failures; exits 0 when everything passed, 1 otherwise.

local script_dir = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./")
package.path = script_dir .. "../../pageanchor.koplugin/?.lua;" .. package.path
local function class()
	local C = {}
	C.__index = C
	function C:extend(o) o = o or {}; o.__index = o; return setmetatable(o, self) end
	function C:new(o) o = o or {}; setmetatable(o, self); self.__index = self; if o.init then o:init() end; return o end
	return C
end
local Widget = class()
function Widget:getSize() return { w = 10, h = 10 } end
function Widget:free() end
function Widget:paintTo() end
SCHEDULED = {}
SCREEN_BB = setmetatable({}, { __index = function() return function() end end })
local DialogStub = Widget:extend({})
function DialogStub:init() _G.LAST_DIALOG = self end
local TextBoxStub = Widget:extend({})
function TextBoxStub:init() _G.LAST_HINT = self.text end
local IconStub = Widget:extend({})
function IconStub:init() end
local ticks = {}
local UIManager = {
	setDirty = function(_, _w, f) if type(f) == "function" then LAST_DIRTY = f end end, show = function() end, close = function() end,
	scheduleIn = function(_, secs, fn) SCHEDULED[fn] = secs; SCHEDULE_CALLS = (SCHEDULE_CALLS or 0) + 1 end,
	unschedule = function(_, fn) SCHEDULED[fn] = nil; for i, f in ipairs(ticks) do if f == fn then table.remove(ticks, i) end end end,
	nextTick = function(_, fn) ticks[#ticks + 1] = fn end,
}
local function runTicks() local t = ticks; ticks = {}; for _, f in ipairs(t) do f() end end
local Geom = class()
function Geom:contains(p) return p.x >= self.x and p.x <= self.x + self.w and p.y >= self.y and p.y <= self.y + self.h end
function Geom:copy() return Geom:new({ x = self.x, y = self.y, w = self.w, h = self.h }) end
function Geom:combine(b)
	local x, y = math.min(self.x, b.x), math.min(self.y, b.y)
	return Geom:new({ x = x, y = y, w = math.max(self.x + self.w, b.x + b.w) - x, h = math.max(self.y + self.h, b.y + b.h) - y })
end
local stubs = {
	["ui/bidi"] = { mirroredUILayout = function() return false end, ltr = function(t) return t end },
	["ffi/blitbuffer"] = { COLOR_WHITE = "W", COLOR_DARK_GRAY = "G", COLOR_GRAY = "g", COLOR_BLACK = "B" }, ["ui/widget/button"] = Widget, ["ui/widget/container/centercontainer"] = Widget,
	["ui/widget/confirmbox"] = Widget, ["ui/widget/buttondialog"] = DialogStub, ["device"] = { screen = { bb = SCREEN_BB, scaleBySize = function(_, v) return v end, getWidth = function() return 600 end, getHeight = function() return 800 end } },
	["ui/event"] = { new = function(_, name, a) return { name = name, args = { a } } end }, ["ui/font"] = { getFace = function() return {} end },
	["ui/widget/container/framecontainer"] = Widget, ["ui/geometry"] = Geom, ["ui/widget/horizontalgroup"] = Widget, ["ui/widget/horizontalspan"] = Widget,
	["ui/widget/iconwidget"] = IconStub, ["ui/widget/widget"] = Widget, ["ui/widget/infomessage"] = Widget, ["ui/widget/linewidget"] = Widget,
	["libs/libkoreader-lfs"] = { attributes = function() STAT_CALLS = (STAT_CALLS or 0) + 1; return nil end },
	["logger"] = { warn = function(...) print("WARN", ...) end, dbg = function() end },
	["ui/size"] = { padding = { button = 2, large = 10, default = 5, small = 2 }, border = { button = 1, default = 1 }, radius = { button = 5 }, line = { medium = 1 } },
	["ui/widget/textboxwidget"] = TextBoxStub, ["ui/widget/textwidget"] = Widget, ["ui/uimanager"] = UIManager,
	["ui/widget/container/widgetcontainer"] = Widget, ["gettext"] = setmetatable({}, { __call = function(_, s) return s end }),
	["ffi/util"] = { template = function(s) return s end },
	["dispatcher"] = { registerAction = function(_, name, v) _G.ACTIONS = _G.ACTIONS or {}; _G.ACTIONS[name] = v end },
	["ui/widget/notification"] = { SOURCE_DISPATCHER = 0x20, notify = function(_, t) _G.LAST_NOTE = t end },
}
for k, v in pairs(stubs) do package.preload[k] = function() return v end end
local settings = {}
G_reader_settings = { nilOrTrue = function(_, k) return settings[k] ~= false end, readSetting = function(_, k) return settings[k] end, saveSetting = function(_, k, v) settings[k] = v end }

-- Rolling document: an xpointer is a character offset; page = offset // cpp + 1.
local doc = { cpp = 1000, offset = 99000, link_offset = 99000, visible = 1, hidden = false }
local function pageOf(off) return math.floor(off / doc.cpp) + 1 end
local document = {
	getPageFromXPointer = function(_, xp) return pageOf(tonumber(xp:sub(2))) end,
	compareXPointers = function(_, a, b) local x, y = tonumber(a:sub(2)), tonumber(b:sub(2)); return x < y and 1 or (x > y and -1 or 0) end,
	getPageCount = function() return 1000 end,
	getVisiblePageNumberCount = function() return doc.visible end,
	hasHiddenFlows = function() return doc.hidden end,
	-- crengine: already at the new position during PageUpdate.
	getXPointer = function() return "x" .. doc.offset end,
	isXPointerInCurrentPage = function(_, xp)
		local off = tonumber(xp:sub(2))
		if VIEW_MODE_SCROLL then
			-- Scroll mode: what's on screen is the viewport (one page tall)
			-- starting at the current offset, not a whole page.
			return off >= doc.offset and off < doc.offset + doc.cpp
		end
		local p, cur = pageOf(off), pageOf(doc.offset)
		return p >= cur and p < cur + doc.visible
	end,
}
local link = class():new({})
function link:getCurrentLocation() return { xpointer = "x" .. doc.link_offset } end
function link:compareLocationToCurrent(l) return l.xpointer == "x" .. doc.link_offset end
function link:addCurrentLocationToStack() end
local ui = {
	rolling = { getBookLocation = function() return doc.rolling_xp or ("x" .. doc.link_offset) end },
	document = document, link = link, view = { dimen = { w = 600, h = 800 }, view_mode = "page", paintTo = function() VIEW_PAINTS = (VIEW_PAINTS or 0) + 1 end }, dialog = {},
	registerPostInitCallback = function(_, fn) fn() end,
	registerTouchZones = function(self, zones) for _, z in ipairs(zones) do self._zones[z.id] = z end; ZONES_REGISTERED = (ZONES_REGISTERED or 0) + 1 end,
	unRegisterTouchZones = function(self, zones) for _, z in ipairs(zones) do self._zones[z.id] = nil end end,
	_zones = { readerfooter_tap = {} },
	getCurrentPage = function() return pageOf(doc.offset) end,
}
function ui:handleEvent(ev) if ev.name == "RestoreBookLocation" then LAST_RESTORE = ev.args[1]; doc.rolling_xp = nil; doc.offset = tonumber(ev.args[1].xpointer:sub(2)); PA:onPageUpdate(pageOf(doc.offset)); doc.link_offset = doc.offset end end
local original_add = link.addCurrentLocationToStack
local PageAnchor = require("main")
local History = require("modules/history")
local pa = PageAnchor:new({ ui = ui })
PA = pa
local function goPage(p) doc.rolling_xp = nil; doc.offset = (p - 1) * doc.cpp; pa:onPageUpdate(pageOf(doc.offset)); doc.link_offset = doc.offset end
local function jumpTo(p) link:addCurrentLocationToStack(); goPage(p); runTicks() end
local function page() return pageOf(doc.offset) end
local fails = 0
local function check(name, cond) print((cond and "ok   " or "FAIL ") .. name); if not cond then fails = fails + 1 end end
local function reset(p) doc.cpp = 1000; doc.visible = 1; goPage(p); pa:clearHistory(); pa.last_discarded = nil; pa.discard_location = nil end

pa:onReaderReady()
reset(100)
goPage(101); goPage(102)
check("plain reading forward arms nothing", pa.anchor == nil and pa:getButtonSpecs() == nil)

reset(100)
jumpTo(102)
check("explicit 100->102 jump arms anchor", pa.anchor ~= nil and pa:getButtonSpecs() ~= nil)
check("anchor is page 100", pa.anchor and document:getPageFromXPointer(pa.anchor.xpointer) == 100)

reset(100)
jumpTo(50)
pa:hideControls()
check("timeout minimizes buttons", pa:getButtonSpecs().minimized and pa:areControlsHidden())
check("timeout keeps anchor", pa.anchor ~= nil)
goPage(51)
check("page turn while hidden keeps hidden", pa:getButtonSpecs().minimized)
pa:showControls()
check("showControls restores back button", pa:getButtonSpecs() and pa:getButtonSpecs().action == "back")
pa:activate("back")
pa:onPageUpdate(page())
check("back returns to 100", page() == 100 and pa.anchor == nil and pa.forward_target ~= nil)
goPage(99)
check("stepping back one page keeps return point", pa.forward_target ~= nil)
goPage(100); goPage(101)
check("reading forward one page drops return point", pa.forward_target == nil)

reset(100)
jumpTo(50); pa:hideControls(); pa:activate("dismiss")
check("dismiss clears hidden state", not pa.controls_hidden and pa.anchor == nil)

reset(100)
jumpTo(50); pa:hideControls()
goPage(100)
check("arriving back at anchor while hidden shows forward button", pa:getButtonSpecs() and pa:getButtonSpecs().action == "forward")

reset(100)
jumpTo(50); pa:hideControls()
jumpTo(300)
check("explicit jump while hidden brings buttons back", pa:getButtonSpecs() ~= nil and not pa.controls_hidden)
check("anchor kept at 100 after second jump", document:getPageFromXPointer(pa.anchor.xpointer) == 100)

reset(100)
jumpTo(50); pa:hideControls()
goPage(400)
check("unannounced far jump while hidden brings buttons back", pa:getButtonSpecs() ~= nil)

reset(100)
doc.cpp = 666 -- bigger font -> more pages; same offset now lands on a later page
pa:onPageUpdate(page()); pa:onDocumentRerendered()
check("repagination does not arm anchor (now page " .. page() .. ")", pa.anchor == nil)
goPage(page() + 1)
check("reading on after repagination arms nothing", pa.anchor == nil)

reset(100)
doc.visible = 2
goPage(102); goPage(104)
check("two-page mode forward turns arm nothing", pa.anchor == nil)
goPage(102)
check("two-page mode one turn back is tolerated", pa.anchor == nil)
goPage(100)
check("two-page mode second turn back arms anchor", pa.anchor ~= nil)

reset(100)
link:addCurrentLocationToStack(); runTicks() -- manual "add to history", no jump
goPage(101)
check("bare add-to-history does not leak into next turn", pa.anchor == nil)

reset(100)
goPage(50)
check("unannounced far jump still arms anchor (fallback)", pa.anchor ~= nil)

check("ReaderLink patched while installed", link.addCurrentLocationToStack ~= original_add)
reset(100)
pa:uninstallOverlay()
check("ReaderLink restored on uninstall", rawget(link, "addCurrentLocationToStack") == original_add)
pa:installOverlay()
check("ReaderLink patched again after reinstall", link.addCurrentLocationToStack ~= original_add)

-- Minimized tab
reset(100)
jumpTo(50); pa:hideControls()
local spec = pa:getButtonSpecs()
check("minimize is default: tab shown when hidden", spec and spec.minimized and spec.action == "show")
local ops = {}
local bb = setmetatable({}, { __index = function(_, k) return function(_, ...) ops[#ops + 1] = { k, ... } end end })
pa.overlay:paintTo(bb, 0, 0)
local b = pa.overlay.button_dimens
local pill = pa.overlay.pill_dimen
check("tab glued to right screen edge (side " .. tostring(pa.overlay.pill_side) .. ")", pill.x + pill.w == 600)
check("tab narrower than its tap target", pill.w < b[1].dimen.w and b[1].dimen.x + b[1].dimen.w == 600)
local drew_inside = true
for _, op in ipairs(ops) do if op[2] and type(op[2]) == "number" and (op[2] < 0 or (op[4] and op[2] + op[4] > 600)) then drew_inside = false end end
check("tab paints entirely inside the screen", drew_inside and #ops > 0)
check("tab is a single tap target", b and #b == 1 and b[1].action == "show")
pa.overlay:handleTap({ pos = { x = b[1].dimen.x + 1, y = b[1].dimen.y + 1 } })
spec = pa:getButtonSpecs()
check("tapping tab restores full control", spec and not spec.minimized and spec.action == "back")
pa:setHideMode("hide"); pa:hideControls()
check("hide mode 'hide' shows nothing", pa:getButtonSpecs() == nil)
pa:setHideMode("minimize")
check("switching back to minimize shows tab", pa:getButtonSpecs() and pa:getButtonSpecs().minimized)

-- Dispatcher actions
check("three dispatcher actions registered", ACTIONS.pageanchor_toggle_buttons and ACTIONS.pageanchor_switch and ACTIONS.pageanchor_discard)
pa:onPageAnchorToggleButtons()
check("toggle action shows hidden buttons", not pa.controls_hidden and not pa:getButtonSpecs().minimized)
pa:onPageAnchorToggleButtons()
check("toggle action hides visible buttons", pa.controls_hidden)
pa:onPageAnchorSwitch(); pa:onPageUpdate(page())
check("switch action goes back to anchor and shows", page() == 100 and not pa.controls_hidden)
pa:onPageAnchorSwitch(); pa:onPageUpdate(page())
check("switch action again goes to return point", page() == 50 and pa.anchor ~= nil)
pa:onPageAnchorDiscard()
check("discard action clears", not pa:hasTargets() and LAST_NOTE == "Anchor discarded")
LAST_NOTE = nil; pa:onPageAnchorToggleButtons()
check("toggle with no anchor notifies", LAST_NOTE == "No anchor to show")

-- Hidden expiry
local function fire(fn) SCHEDULED[fn] = nil; fn() end
reset(100)
jumpTo(50); pa:hideControls()
check("default 'Never': no expiry timer while hidden", pa.hidden_expiry_fn == nil)
pa:setHiddenExpirySeconds(300)
check("changing setting while hidden starts countdown", pa.hidden_expiry_fn ~= nil and SCHEDULED[pa.hidden_expiry_fn] == 300)
goPage(52)
fire(pa.hidden_expiry_fn)
check("expiry discards anchor", not pa:hasTargets() and not pa.controls_hidden)
check("current page becomes reference", document:getPageFromXPointer(pa.reference_location.xpointer) == 52)
goPage(53)
check("reading on after expiry arms nothing", pa.anchor == nil)

reset(100)
jumpTo(50); pa:hideControls()
local fn = pa.hidden_expiry_fn
pa:showControls()
check("showing buttons cancels expiry", pa.hidden_expiry_fn == nil and SCHEDULED[fn] == nil)
pa:hideControls(); fn = pa.hidden_expiry_fn
jumpTo(300)
check("new jump while hidden cancels expiry", pa.hidden_expiry_fn == nil and SCHEDULED[fn] == nil and pa.anchor ~= nil)
pa:hideControls(); fn = pa.hidden_expiry_fn
pa:activate("dismiss")
check("manual dismiss cancels expiry", pa.hidden_expiry_fn == nil and SCHEDULED[fn] == nil)
jumpTo(50); pa:hideControls()
pa:setHiddenExpirySeconds(0)
check("switching to Never while hidden drops countdown", pa.hidden_expiry_fn == nil)

-- Undo discard
local function paint() local bb = setmetatable({}, { __index = function() return function() end end }); pa.overlay:paintTo(bb, 0, 0) end
reset(100)
jumpTo(50); paint()
local dims = pa.overlay.button_dimens
local dismiss = dims[2].dimen
pa.overlay:handleTap({ pos = { x = dismiss.x + 1, y = dismiss.y + 1 } })
check("tapping anchor button discards", not pa:hasTargets())
local hint = pa.hint_widget
check("undo notice shown in place of the pill", hint and hint.on_tap and hint.dimen.y + hint.dimen.h == dismiss.y + dismiss.h)
check("touch on notice does not close it", (function() hint:onGesture({ ges = "touch", pos = { x = hint.dimen.x + 1, y = hint.dimen.y + 1 } }); return pa.hint_widget == hint end)())
pa.overlay:handleTap({ pos = { x = hint.dimen.x + 1, y = hint.dimen.y + 1 } })
check("tapping notice restores anchor", pa.anchor and document:getPageFromXPointer(pa.anchor.xpointer) == 100 and pa.hint_widget == nil)
check("restored with return point at current page", pa.forward_target and document:getPageFromXPointer(pa.forward_target.xpointer) == 50)

reset(100)
jumpTo(50); pa:onPageAnchorDiscard()
goPage(51) -- one page on: within the reading tolerance, so the undo stays valid
check("undo action after moving: snapshot still restorable", pa.anchor == nil and pa:canRestoreDiscarded())
LAST_NOTE = nil
pa:onPageAnchorUndo()
check("undo action after moving: restore actually happened", LAST_NOTE ~= "Nothing to restore" and pa.last_discarded == nil)
check("undo action after moving: original anchor kept", pa.anchor and document:getPageFromXPointer(pa.anchor.xpointer) == 100)
check("undo action after moving: return point is where you are now", pa.forward_target and document:getPageFromXPointer(pa.forward_target.xpointer) == 51)
pa:clearHistory(); jumpTo(200)
LAST_NOTE = nil; pa:onPageAnchorUndo()
check("new anchor supersedes undo (refused while targets exist)", LAST_NOTE == "Nothing to restore")
pa:clearHistory(); jumpTo(300); pa:clearHistory()
pa:restoreDiscarded()
check("only the latest discard is restorable", document:getPageFromXPointer(pa.anchor.xpointer) == 200 and document:getPageFromXPointer(pa.forward_target.xpointer) == 300)

-- Pinned anchor
reset(100)
pa:onPageAnchorPin()
check("pin: nothing to show while standing on it", pa:getButtonSpecs() == nil and pa:hasTargets() and LAST_NOTE == "Anchor pinned here")
goPage(101)
check("pinned: plain page turn away offers the way back", pa.anchor and pa:getButtonSpecs().action == "back")
goPage(102); goPage(103)
check("pinned: anchor does not advance with reading", document:getPageFromXPointer(pa.anchor.xpointer) == 100)
pa:activate("back"); pa:onPageUpdate(page())
check("pinned: back lands on pin, forward offered", page() == 100 and pa:getButtonSpecs().action == "forward" and pa.pinned_location)
goPage(101)
check("pinned survives returning: leaving again re-offers back", pa.anchor and document:getPageFromXPointer(pa.anchor.xpointer) == 100)
pa:setHiddenExpirySeconds(60); pa:hideControls()
check("pinned: no hidden expiry", pa.hidden_expiry_fn == nil)
pa:setHiddenExpirySeconds(0); pa:showControls()
jumpTo(400)
check("pinned: explicit jump keeps the pin as anchor", document:getPageFromXPointer(pa.anchor.xpointer) == 100)
pa:activate("dismiss")
check("discarding clears the pin", pa.pinned_location == nil and not pa:hasTargets())
pa.overlay:handleTap({ pos = { x = pa.hint_widget.dimen.x + 1, y = pa.hint_widget.dimen.y + 1 } })
check("undo restores the pin", pa.pinned_location and document:getPageFromXPointer(pa.pinned_location.xpointer) == 100)
pa:clearHistory()

-- Regression: pin from the menu, then jump (ReaderLink lagging one move behind)
reset(100)
pa:pinHere()
jumpTo(250)
check("menu pin then jump shows the back button", pa:getButtonSpecs() and pa:getButtonSpecs().action == "back")
check("return point is the jump destination, not the origin", document:getPageFromXPointer(pa.forward_target.xpointer) == 250)
pa:clearHistory()
reset(100)
jumpTo(40)
check("plain jump: return point is the destination", document:getPageFromXPointer(pa.forward_target.xpointer) == 40)
reset(100)
jumpTo(50); pa:activate("dismiss")
check("anchor button notice says anchor set here", pa.hint_widget and LAST_HINT == "Anchor set here" and SCHEDULED[pa.hint_dismiss_fn] == 3)
pa:clearHistory()
reset(100)
jumpTo(50); pa:onPageAnchorDiscard()
check("discard action notice says discarded", LAST_HINT == "Anchor discarded")
pa:clearHistory()

-- Dismiss wording at the anchor
reset(100)
jumpTo(50); pa:activate("back"); pa:onPageUpdate(page()); paint()
pa.overlay:handleSwipe({ direction = "south", pos = { x = pa.overlay.pill_dimen.x + 1, y = pa.overlay.pill_dimen.y + 1 } })
check("swipe-dismiss at the anchor says buttons dismissed", LAST_HINT == "Buttons dismissed" and page() == 100)
pa.overlay:handleTap({ pos = { x = pa.hint_widget.dimen.x + 1, y = pa.hint_widget.dimen.y + 1 } })
check("undo at the anchor restores the return point", pa.forward_target and document:getPageFromXPointer(pa.forward_target.xpointer) == 50 and pa.anchor == nil)
pa:clearHistory()
reset(100)
jumpTo(50); paint()
pa.overlay:handleSwipe({ direction = "south", pos = { x = pa.overlay.pill_dimen.x + 1, y = pa.overlay.pill_dimen.y + 1 } })
check("swipe-dismiss away from the anchor says anchor set here", LAST_HINT == "Anchor set here")
pa:clearHistory()

-- Restore after walking back to the anchor (reported repro)
local function pg(l) return l and document:getPageFromXPointer(l.xpointer) end
reset(100)
jumpTo(101)
check("repro: jump 100->101 arms anchor", pg(pa.anchor) == 100 and pg(pa.forward_target) == 101)
pa:onPageAnchorDiscard()
goPage(100)
pa:restoreDiscarded()
check("restore at the anchor: no pending anchor on this page", pa.anchor == nil)
check("restore at the anchor: return point kept at 101", pg(pa.forward_target) == 101)
check("restore at the anchor: forward button offered", pa:getButtonSpecs() and pa:getButtonSpecs().action == "forward")
pa:activate("forward"); pa:onPageUpdate(page())
check("forward goes to 101 with anchor 100", page() == 101 and pg(pa.anchor) == 100)
pa:clearHistory()

-- Snapshot taken while at the anchor, restored after moving away
reset(100)
jumpTo(50); pa:activate("back"); pa:onPageUpdate(page())
pa:onPageAnchorDiscard()
goPage(99); goPage(98) -- two turns back: protected re-reading, the undo stays valid
check("at-anchor snapshot: still restorable after re-reading back", pa.anchor == nil and pa:canRestoreDiscarded())
local restored = pa:restoreDiscarded()
check("at-anchor snapshot restored elsewhere: restore actually happened", restored == true)
check("at-anchor snapshot restored elsewhere: back leads to the original anchor", pg(pa.anchor) == 100 and pg(pa.forward_target) == 98)
pa:clearHistory()

-- Pinned: restore while standing on the pin
reset(100)
pa:pinHere(); goPage(101); pa:onPageAnchorDiscard(); goPage(100)
pa:restoreDiscarded()
check("pinned restore on the pin: pin kept, no pending anchor, return point 101", pa.pinned_location and pa.anchor == nil and pg(pa.forward_target) == 101)
pa:clearHistory()

-- Inline destination label
reset(100)
jumpTo(50)
check("inline label off by default", pa:getButtonSpecs().inline_text == nil)
pa:setInlineLabelMode("page")
check("page mode shows destination page", pa:getButtonSpecs().inline_text == "100")
paint()
check("labeled pill rebuilt with text in cache key", pa.overlay.dock_key:find(":100:", 1, true) ~= nil)
pa:setInlineLabelMode("distance")
check("distance mode: anchor 50 pages ahead shows +50", pa:getButtonSpecs().inline_text == "+50")
goPage(51)
check("distance updates as you read", pa:getButtonSpecs().inline_text == "+49")
pa:activate("back"); pa:onPageUpdate(page())
check("distance to return point uses a real minus sign", pa:getButtonSpecs().inline_text == "\226\136\146" .. "49")
pa:setInlineLabelMode("off")
check("off again: icon-only", pa:getButtonSpecs().inline_text == nil)
pa:clearHistory()

-- Exact-line markers
-- A link tap on page 100 (line at offset 99500) to a footnote on page 50 (offset 49700).
local function followLink(from_off, to_off)
	link:addCurrentLocationToStack({ xpointer = "x" .. from_off, marker_xpointer = "x" .. from_off })
	doc.offset = math.floor(to_off / doc.cpp) * doc.cpp -- crengine shows the page holding the target
	pa:onPageUpdate(page())
	doc.link_offset = doc.offset
	doc.rolling_xp = "x" .. to_off -- ReaderRolling sets xpointer = target after the event
	runTicks()
end
reset(100)
followLink(99500, 49700)
check("link: anchor keeps the exact link origin", pa.anchor and pa.anchor.marker_xpointer == "x99500")
check("link: return point refined to the exact target", pa.forward_target.xpointer == "x49700" and pa.forward_target.marker_xpointer == "x49700")
pa:onPageUpdate(page()) -- redraw on the same page
check("same-page update keeps the exact return point", pa.forward_target.marker_xpointer == "x49700")
pa:activate("back"); pa:onPageUpdate(page())
check("back: restores with marker at the link origin", page() == 100 and LAST_RESTORE.marker_xpointer == "x99500")
check("back: exact return point survives the round trip", pa.forward_target.marker_xpointer == "x49700")
pa:activate("forward"); pa:onPageUpdate(page())
check("forward: restores with marker at the link target", page() == 50 and LAST_RESTORE.marker_xpointer == "x49700")
check("forward: anchor keeps the exact link origin", pa.anchor.marker_xpointer == "x99500")
goPage(51)
check("page turn: return point back to page level", pa.forward_target.marker_xpointer == nil)
pa:clearHistory()

reset(100)
jumpTo(50)
pa:activate("back"); pa:onPageUpdate(page())
check("page jump: no marker going back (page top only)", LAST_RESTORE.marker_xpointer == nil)
pa:activate("forward"); pa:onPageUpdate(page())
check("page jump: no marker going forward", LAST_RESTORE.marker_xpointer == nil)
pa:clearHistory()

reset(100)
ui.view.view_mode = "scroll"
jumpTo(50)
pa:activate("back"); pa:onPageUpdate(page())
check("scroll mode: marker on the exact view position", LAST_RESTORE.marker_xpointer == LAST_RESTORE.xpointer and LAST_RESTORE.xpointer ~= nil)
followLink(99500, 49700)
pa:activate("forward"); pa:onPageUpdate(page())
check("scroll mode link: goes back to the same view, marks the target", LAST_RESTORE.xpointer == "x49000" and LAST_RESTORE.marker_xpointer == "x49700")
ui.view.view_mode = "page"
pa:clearHistory()

-- Scroll mode: scrolling within the same page must not be undone
reset(100)
ui.view.view_mode = "scroll"
followLink(99500, 49700)
doc.offset = 49300; pa:onPosUpdate(nil, page()); doc.link_offset = doc.offset -- scroll a little, same page
check("scroll within page: return point follows the new view", pa.forward_target.xpointer == "x49300")
pa:activate("back"); pa:onPageUpdate(page())
pa:activate("forward"); pa:onPageUpdate(page())
check("scroll within page: forward restores the view just left", LAST_RESTORE.xpointer == "x49300")
ui.view.view_mode = "page"
pa:clearHistory()

-- PDF (paging): view state includes pan position and zoom
do
	local pdf = { page = 100, pos = 0, zoom = 1 }
	local plink = class():new({})
	function plink:getCurrentLocation() return { { page = pdf.page, pos = pdf.pos, zoom = pdf.zoom } } end
	function plink:compareLocationToCurrent(l) return l[1] and l[1].page == pdf.page end
	function plink:addCurrentLocationToStack() end
	local pui = {
		paging = true, link = plink, view = { dimen = { w = 600, h = 800 }, view_mode = "page" }, dialog = {},
		document = { getPageCount = function() return 500 end },
		registerPostInitCallback = function(_, fn) fn() end, registerTouchZones = function() end, unRegisterTouchZones = function() end,
		getCurrentPage = function() return pdf.page end,
	}
	local ppa
	function pui:handleEvent(ev)
		if ev.name == "RestoreBookLocation" then
			PDF_RESTORE = ev.args[1][1]
			pdf.page, pdf.pos, pdf.zoom = PDF_RESTORE.page, PDF_RESTORE.pos, PDF_RESTORE.zoom
			ppa:onPageUpdate(pdf.page)
		end
	end
	ppa = PageAnchor:new({ ui = pui })
	ppa:onReaderReady()
	plink:addCurrentLocationToStack(); pdf.page = 50; pdf.pos = 0; ppa:onPageUpdate(50); runTicks()
	check("pdf: jump arms anchor", ppa.anchor and ppa.anchor[1].page == 100)
	pdf.pos = 300; pdf.zoom = 2 -- pan and zoom within page 50 (no page change)
	ppa:activate("back")
	check("pdf: back lands on 100", pdf.page == 100)
	check("pdf: return point is the panned/zoomed view just left", ppa.forward_target[1].pos == 300 and ppa.forward_target[1].zoom == 2)
	ppa:activate("forward")
	check("pdf: forward restores the view just left, not the original", PDF_RESTORE.page == 50 and PDF_RESTORE.pos == 300 and PDF_RESTORE.zoom == 2)
	pdf.pos = 0 -- pan back up on page 100? no: we're on 50; pan here, then go back and forth again
	pdf.pos = 120
	ppa:activate("back")
	ppa:activate("forward")
	check("pdf: repeated round trip keeps latest pan", PDF_RESTORE.pos == 120)
	ppa:clearHistory()
	-- Trail keeps the pan/zoom captured at the jump
	ppa:onPageUpdate(pdf.page)
	plink:addCurrentLocationToStack(); pdf.page = 60; pdf.pos = 0; pdf.zoom = 1; ppa:onPageUpdate(60); runTicks()
	pdf.pos = 400; pdf.zoom = 2 -- pan/zoom on 60, then jump on
	plink.addCurrentLocationToStack(plink, { { page = 60, pos = 400, zoom = 2 } }); pdf.page = 70; pdf.pos = 0; pdf.zoom = 1; ppa:onPageUpdate(70); runTicks()
	local entry = ppa:getVisibleTrail()[1]
	check("pdf trail: entry holds the panned/zoomed view", entry and entry[1].page == 60 and entry[1].pos == 400 and entry[1].zoom == 2)
	ppa:goToTrail(entry)
	check("pdf trail: picking it restores that view", PDF_RESTORE.page == 60 and PDF_RESTORE.pos == 400 and PDF_RESTORE.zoom == 2)
	ppa:clearHistory()
	ppa:uninstallOverlay()
end

-- Short step back keeps the way back
reset(100)
jumpTo(50); pa:activate("back"); pa:onPageUpdate(page())
goPage(99); goPage(98)
check("2 turns back after returning: no new anchor", pa.anchor == nil)
check("2 turns back after returning: return point kept", pg(pa.forward_target) == 50)
goPage(97); goPage(96); goPage(95)
check("5 turns back still protected", pa.anchor == nil and pg(pa.forward_target) == 50)
goPage(94)
check("6 turns back arms a new anchor", pa.anchor ~= nil and pg(pa.anchor) == 100)
pa:clearHistory()

reset(100)
jumpTo(50); pa:activate("back"); pa:onPageUpdate(page())
goPage(98)
jumpTo(300)
check("announced jump still arms despite protection", pg(pa.anchor) == 98 and pg(pa.forward_target) == 300)
pa:clearHistory()

reset(100)
jumpTo(101); pa:onPageAnchorDiscard()
goPage(100); goPage(99)
check("after discard: 2 turns back keeps the undo", pa.anchor == nil and pa:canRestoreDiscarded())
pa:restoreDiscarded()
check("after discard: undo still works from 2 turns back", pg(pa.anchor) == 100 and pg(pa.forward_target) == 99)
pa:clearHistory()

reset(100)
jumpTo(150); pa:onPageAnchorDiscard()
goPage(151); goPage(152)
goPage(150)
check("after reading past the discard, normal tolerance returns", pa.anchor ~= nil)
pa:clearHistory()

-- Pinned marker: underlined anchor icon
local function noPreselect(t, seen)
	seen = seen or {}
	if type(t) ~= "table" or seen[t] then return true end
	seen[t] = true
	if t.preselect then return false end
	for _, v in pairs(t) do if not noPreselect(v, seen) then return false end end
	return true
end
local function usesIcon(t, name, seen)
	seen = seen or {}
	if type(t) ~= "table" or seen[t] then return false end
	seen[t] = true
	if type(t.icon) == "string" and t.icon:sub(-#name) == name then return true end
	for _, v in pairs(t) do if usesIcon(v, name, seen) then return true end end
	return false
end
reset(100)
jumpTo(50); paint()
check("plain anchor: regular anchor icon", usesIcon(pa.overlay.dock.widget, "/anchor.svg") and not usesIcon(pa.overlay.dock.widget, "anchor-pinned.svg"))
pa:activate("back"); pa:onPageUpdate(page()); paint()
check("at the anchor (not pinned): circled anchor icon", usesIcon(pa.overlay.dock.widget, "anchor-here.svg") and noPreselect(pa.overlay.dock.widget))
pa:clearHistory()
pa:pinHere(); goPage(101); paint()
check("pinned anchor: underlined icon on the pill", usesIcon(pa.overlay.dock.widget, "anchor-pinned.svg"))
pa:activate("back"); pa:onPageUpdate(page()); paint()
check("pinned anchor at the anchor: circled and underlined", pa:getButtonSpecs().dismiss_marked and usesIcon(pa.overlay.dock.widget, "anchor-here-pinned.svg"))
check("at the anchor: no inverted (preselect) segment", noPreselect(pa.overlay.dock.widget))
goPage(101); pa:hideControls(); paint()
check("pinned anchor: underlined icon on the tab", pa:getButtonSpecs().minimized and usesIcon(pa.overlay.dock.widget, "anchor-pinned.svg"))
pa:clearHistory()

-- Percentages
reset(1)
check("first page is 0%", History.getPercentageLabel(ui, { xpointer = "x0" }) == "0.00%")
check("last page is 100%", History.getPercentageLabel(ui, { xpointer = "x" .. (999 * 1000) }) == "100.00%")
check("middle page is proportional", History.getPercentageLabel(ui, { xpointer = "x" .. (500 * 1000) }) == string.format("%.2f%%", 500 / 999 * 100))

-- Vertical position
reset(100)
jumpTo(50); paint()
local bottom_y = pa.overlay.pill_dimen.y
check("bottom: pill near the bottom edge", bottom_y > 700)
check("bottom: Quick Dock clearance reported", pa:getOverlayClearance(pa.overlay.pill_side) ~= nil)
pa:setVerticalPosition("top"); paint()
check("top: pill near the top edge", pa.overlay.pill_dimen.y < 100)
check("top: zones moved to the top band", ui._zones.pageanchor_tap.screen_zone.ratio_y == 0)
check("top: no Quick Dock clearance", pa:getOverlayClearance(pa.overlay.pill_side) == nil)
pa:setVerticalPosition("middle"); paint()
check("middle: pill centred", math.abs(pa.overlay.pill_dimen.y + pa.overlay.pill_dimen.h / 2 - 400) <= 1)
check("middle: zones in the middle band", ui._zones.pageanchor_tap.screen_zone.ratio_y == 0.35)
pa:setVerticalPosition("bottom")
pa:clearHistory()

-- Zones re-registered once the book is ready, overriding late zones
ui._zones.late_plugin_tap = {}
ZONES_REGISTERED = 0
pa:onReaderReady(); runTicks()
local found = false
for _, id in ipairs(ui._zones.pageanchor_tap.overrides) do if id == "late_plugin_tap" then found = true end end
check("zones re-registered after ReaderReady include late zones", ZONES_REGISTERED == 1 and found)
local self_ref = false
for _, id in ipairs(ui._zones.pageanchor_tap.overrides) do if id:find("^pageanchor_") then self_ref = true end end
check("zones never override themselves", not self_ref)

-- Re-reading tolerance
reset(100)
pa:setRereadTurns(3)
goPage(99); goPage(98); goPage(97)
check("tolerance 3: three turns back is re-reading", pa.anchor == nil)
goPage(96)
check("tolerance 3: fourth turn back arms", pa.anchor ~= nil and pg(pa.anchor) == 100)
pa:setRereadTurns(1)
pa:clearHistory()

-- Trail
reset(100)
jumpTo(50); jumpTo(300); jumpTo(20)
local trail = pa:getVisibleTrail()
check("trail holds the places left, newest first", #trail == 2 and pg(trail[1]) == 300 and pg(trail[2]) == 50)
paint()
LAST_DIALOG = nil
pa:showButtonHint(pa:getButtonSpecs().action)
check("holding the arrow opens the trail dialog", LAST_DIALOG and #LAST_DIALOG.buttons == 3)
LAST_DIALOG.buttons[3][1].callback() -- page 50
pa:onPageUpdate(page())
check("trail pick: goes there, anchor kept", page() == 50 and pg(pa.anchor) == 100 and pg(pa.forward_target) == 50)
trail = pa:getVisibleTrail()
check("trail pick: spot left joins the trail", #trail == 2 and pg(trail[1]) == 20 and pg(trail[2]) == 300)
pa:activate("back"); pa:onPageUpdate(page())
check("back at the anchor: trail still offered", #pa:getVisibleTrail() == 2)
pa:goToTrail(pa:getVisibleTrail()[2]); pa:onPageUpdate(page())
check("trail pick from the anchor: anchor re-armed at 100", page() == 300 and pg(pa.anchor) == 100 and pg(pa.forward_target) == 300)
check("trail pick from the anchor: old return point kept in trail", (function() for _, l in ipairs(pa:getVisibleTrail()) do if pg(l) == 50 then return true end end end)())
local before = #pa.trail
pa:onPageAnchorDiscard()
check("discard clears the trail", #pa.trail == 0)
pa:restoreDiscarded()
check("undo restores the trail", #pa.trail == before)
pa:clearHistory()
reset(100)
jumpTo(50); paint()
LAST_DIALOG = nil; pa:showButtonHint(pa:getButtonSpecs().action)
check("no trail yet: plain hint instead of dialog", LAST_DIALOG == nil and pa.hint_widget ~= nil)
pa:clearHistory()
jumpTo(40)
check("fresh trip starts with an empty trail", #pa.trail == 0)
pa:clearHistory()

-- Thumbnails: the view painted into another buffer gets no overlay
reset(100)
jumpTo(50)
local overlay_paints = 0
local real_overlay_paint = pa.overlay.paintTo
pa.overlay.paintTo = function(...) overlay_paints = overlay_paints + 1; return real_overlay_paint(...) end
local thumb_bb = setmetatable({}, { __index = function() return function() end end })
ui.view:paintTo(thumb_bb, 0, 0)
check("thumbnail buffer: page painted, buttons not", VIEW_PAINTS and VIEW_PAINTS > 0 and overlay_paints == 0)
ui.view:paintTo(SCREEN_BB, 0, 0)
check("screen buffer: buttons painted", overlay_paints == 1)
pa.overlay.paintTo = real_overlay_paint
pa:clearHistory()

-- Show trail works whatever the buttons' state
reset(100)
jumpTo(50); jumpTo(300)
pa:hideControls()
LAST_DIALOG = nil; LAST_NOTE = nil
pa:onPageAnchorShowTrail()
check("show trail with buttons minimized", LAST_DIALOG ~= nil and LAST_NOTE == nil)
pa:setHideMode("hide")
LAST_DIALOG = nil; LAST_NOTE = nil
pa:onPageAnchorShowTrail()
check("show trail with buttons fully hidden", LAST_DIALOG ~= nil and LAST_NOTE == nil and pa:getButtonSpecs() == nil)
LAST_DIALOG.buttons[1][1].callback()
pa:onPageUpdate(page())
check("arrow entry from hidden state goes back and shows buttons", page() == 100 and not pa.controls_hidden)
pa:setHideMode("minimize")
pa:clearHistory()

-- Performance and battery
-- Same-page updates (scroll steps, redraws): no respec, no timer reschedule
reset(100)
jumpTo(50); paint()
local spec_before = pa:getButtonSpecs()
SCHEDULE_CALLS = 0
for _ = 1, 10 do pa:onPosUpdate(nil, 50) end
check("same-page updates keep the cached button spec", pa:getButtonSpecs() == spec_before)
check("same-page updates don't reschedule timers", SCHEDULE_CALLS == 0)
goPage(51)
check("a real page change is still evaluated", pa:getButtonSpecs() ~= spec_before)
pa:clearHistory()

-- Hint labels built only when shown
reset(100)
jumpTo(50)
local label_calls = 0
local real_label = pa.getDestinationLabel
pa.getDestinationLabel = function(...) label_calls = label_calls + 1; return real_label(...) end
for p = 51, 55 do goPage(p); paint() end
check("page turns don't build the hint label", label_calls == 0)
pa:showButtonHint(pa:getButtonSpecs().action)
check("holding the arrow builds it once", label_calls == 1)
pa.getDestinationLabel = nil -- back to the class method
pa:clearHistory()

-- Refresh only the control's area
local function dirtyRegion()
	local f = LAST_DIRTY
	LAST_DIRTY = nil
	if not f then return nil end
	paint()
	local _, region = f()
	return region
end
local function covers(r, box) return r.x <= box.x and r.y <= box.y and r.x + r.w >= box.x + box.w and r.y + r.h >= box.y + box.h end
reset(100)
LAST_DIRTY = nil
jumpTo(50); paint()
local pill_box = pa.overlay.pill_dimen:copy()
LAST_DIRTY = nil
pa:hideControls()
local region = dirtyRegion()
local tab_box = pa.overlay.pill_dimen:copy()
check("hide: refresh covers the pill and the tab", region and covers(region, pill_box) and covers(region, tab_box))
check("hide: refresh is not the whole band", region and region.w < 600)
pa:showControls(); paint()
LAST_DIRTY = nil
pa:setVerticalPosition("top")
region = dirtyRegion()
check("moving the control refreshes its old and new places", region and covers(region, pill_box) and covers(region, pa.overlay.pill_dimen))
pa:setVerticalPosition("bottom"); paint()
pa:clearHistory(); paint()
LAST_DIRTY = nil
pa:clearHistory()
check("nothing shown before or after: no repaint at all", LAST_DIRTY == nil)

-- Icon patch: one stat per own icon, none for other paths
local icons_dir = script_dir .. "../../pageanchor.koplugin/icons/"
STAT_CALLS = 0
IconStub:new({ icon = icons_dir .. "probe.svg" })
IconStub:new({ icon = icons_dir .. "probe.svg" })
check("own icon path: stat once, then cached", STAT_CALLS == 1)
IconStub:new({ icon = "/somewhere/else/other.svg" })
check("other paths: not looked at", STAT_CALLS == 1)

-- Scroll mode: a pinned anchor leaving or re-entering the viewport within
-- the same page number (reported regression)
reset(2)
ui.view.view_mode = "scroll"; VIEW_MODE_SCROLL = true
local function scrollTo(off) doc.offset = off; pa:onPosUpdate(nil, pageOf(off)); doc.link_offset = off end
scrollTo(1500)
pa:pinHere()
scrollTo(1450) -- viewport [1450, 2450): the pin at 1500 is still on screen
check("scroll: pin still in view, nothing to offer", pa.anchor == nil)
pa:clearHistory()
scrollTo(1100)
pa:pinHere()
scrollTo(1900) -- same page 2, pin (1100) now above the viewport
check("scroll: pin leaving the viewport on the same page offers the way back", pa.anchor ~= nil and pa:getButtonSpecs() and pa:getButtonSpecs().action == "back")
scrollTo(1050) -- scroll back up: pin visible again, same page 2
check("scroll: pin back in view on the same page resolves it", pa.anchor == nil)
local spec_same = pa:getButtonSpecs()
SCHEDULE_CALLS = 0
scrollTo(1060); scrollTo(1070)
check("scroll: steps that don't change pin visibility stay on the fast path", pa:getButtonSpecs() == spec_same and SCHEDULE_CALLS == 0)
pa:clearHistory()
-- Plain (unpinned) anchor in scroll mode: scrolling back to it within its page resolves it
scrollTo(1100)
link:addCurrentLocationToStack(); scrollTo(5200); runTicks()
check("scroll: jump arms the anchor", pa.anchor ~= nil and pg(pa.anchor) == 2)
scrollTo(1900) -- unannounced move back to page 2, anchor (1100) not in view
scrollTo(1100)
check("scroll: scrolling the anchor back into view on its page resolves it", pa.anchor == nil)
ui.view.view_mode = "page"; VIEW_MODE_SCROLL = false
pa:clearHistory()

print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
