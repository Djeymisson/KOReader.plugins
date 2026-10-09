-- ShadowedButtonDialog: the ButtonDialog the toolbar is shown in, with its shadow, its
-- shape and border, and the gestures it passes on to the selection handles.

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local LineWidget = require("ui/widget/linewidget")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")

local Screen = Device.screen
local math_floor = math.floor
local math_min = math.min

local lib = select(2, ...)
local ShadowedPopup = lib.ShadowedPopup

local ShadowedButtonDialog = ButtonDialog:extend({})

function ShadowedButtonDialog:init()
    ButtonDialog.init(self)
    if self.hide_row_separators then
        -- Like a hidden vertical separator: keep the line's height, draw it in the
        -- background color.
        for _, widget in ipairs(self.buttontable.container) do
            if getmetatable(widget) == LineWidget then
                widget.background = Blitbuffer.COLOR_WHITE
            end
        end
    end
    local style = self.frame_style
    if style then
        -- ButtonDialog's frame has fixed border, radius and padding: apply the chosen ones.
        local frame = self.movable[1]
        frame.bordersize = style.border
        frame.padding_left = style.padding_h
        frame.padding_right = style.padding_h
        -- Corners are not drawn at all with a radius over half the height, so the
        -- predicted capsule radius is checked against the actual height.
        frame.radius = math_min(style.radius, math_floor(frame:getSize().h / 2))
    end
    if self.shadow then
        local frame = self.movable[1]
        self.movable[1] = ShadowedPopup:new({
            shadow = self.shadow,
            shadow_radius = frame.radius,
            frame,
        })
    end
    -- While the toolbar is shown it is the top widget and swallows every gesture, so the
    -- selection handles must be dragged through it. Ranges cover the whole screen; the
    -- controller only consumes gestures that start on a handle.
    if self.handle_controller and Device:isTouchDevice() then
        local screen_range = Geom:new({ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
        local rate = self.handle_pan_rate
        self.ges_events.SelectionHandleHold = { GestureRange:new({ ges = "hold", range = screen_range }) }
        self.ges_events.SelectionHandlePan = { GestureRange:new({ ges = "pan", range = screen_range, rate = rate }) }
        self.ges_events.SelectionHandleHoldPan = {
            GestureRange:new({ ges = "hold_pan", range = screen_range, rate = rate }),
        }
        -- A quick flick on a handle is a swipe, or a multiswipe if it changed direction.
        self.ges_events.SelectionHandleSwipe = {
            GestureRange:new({ ges = "swipe", range = screen_range }),
            GestureRange:new({ ges = "multiswipe", range = screen_range }),
        }
    end
end

-- WidgetContainer hands gestures to the children before our own ges_events, and the
-- MovableContainer child grabs any pan passing over the toolbar (even while it is hidden),
-- which would move the toolbar instead of the handle. Gestures that belong to a handle
-- are therefore dispatched to our own ges_events first, without reaching the children.
function ShadowedButtonDialog:handleEvent(event)
    if self.handle_controller and event.handler == "onGesture" then
        local ges = event.args and event.args[1]
        if ges and self.handle_controller:endsDrag(self, ges) then
            return true
        end
        if ges and self.handle_controller:claimsGesture(self, ges) then
            self:onGesture(ges)
            return true
        end
    end
    return ButtonDialog.handleEvent(self, event)
end

function ShadowedButtonDialog:paintTo(...)
    if self.content_hidden then
        return
    end
    return ButtonDialog.paintTo(self, ...)
end

function ShadowedButtonDialog:onTapClose(arg, ges)
    if self.handle_controller and self.handle_controller:handleAt(ges.pos) then
        return true
    end
    return ButtonDialog.onTapClose(self, arg, ges)
end

function ShadowedButtonDialog:onCloseWidget()
    -- ButtonDialog flashes its area on close. A hidden toolbar left nothing there
    -- (its area was repainted when it was hidden), so skip that flash refresh. One
    -- replaced by a new toolbar at about the same place (More, Fewer) needs no flash
    -- either: a plain refresh of its area is enough, the new one refreshes its own.
    if not self.content_hidden then
        local dimen = self.movable and self.movable.dimen
        if not self.replaced then
            ButtonDialog.onCloseWidget(self)
        elseif dimen then
            UIManager:setDirty(nil, "ui", dimen)
        end
    end
    if self.handle_controller then
        self.handle_controller:onToolbarClosed(self)
    end
end

function ShadowedButtonDialog:onSelectionHandleHold(_, ges)
    return self.handle_controller:onHandleHold(self, ges)
end

function ShadowedButtonDialog:onSelectionHandlePan(_, ges)
    return self.handle_controller:onHandlePan(self, ges)
end

function ShadowedButtonDialog:onSelectionHandleHoldPan(_, ges)
    return self.handle_controller:onHandleHoldPan(ges)
end

function ShadowedButtonDialog:onSelectionHandleSwipe(_, ges)
    return self.handle_controller:onHandleSwipe(self, ges)
end

return {
    ShadowedButtonDialog = ShadowedButtonDialog,
}
