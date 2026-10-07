local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local time = require("ui/time")
local util = require("util")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local function firstCharacters(text, count)
    local characters = util.splitToChars(text or "")
    local result = {}
    for index = 1, math_min(count, #characters) do
        result[#result + 1] = characters[index]
    end
    return table.concat(result)
end

-- A short label for a button without an icon: the initials of its first two
-- words, the first two letters of a single word, or of the action id.
local function makeFallbackLabel(text, action_id)
    local words = {}
    for word in tostring(text or ""):gmatch("%S+") do
        words[#words + 1] = word
        if #words == 2 then
            break
        end
    end

    if #words >= 2 then
        return string.upper(firstCharacters(words[1], 1) .. firstCharacters(words[2], 1))
    elseif #words == 1 then
        return string.upper(firstCharacters(words[1], 2))
    end

    local readable_id = tostring(action_id or "?"):gsub("_", " ")
    return string.upper(firstCharacters(readable_id, 2))
end

-- On screens with a low pan rate, a dragged slider repaints at most three
-- times a second; forced refreshes (taps, releases) always go through.
-- owner.last_refresh_time keeps the time of the last allowed refresh.
local function allowSliderRefresh(owner, force)
    local now = time.now()
    if Screen.low_pan_rate and not force and now - owner.last_refresh_time < time.s(1 / 3) then
        return false
    end
    owner.last_refresh_time = now
    return true
end

return function(C)

    local LightSlider = InputContainer:extend({})

    function LightSlider:init()
        self.width = self.width or Screen:scaleBySize(54)
        self.height = math_max(1, self.height or Screen:getHeight() / 2)
        self.slider_padding = self.slider_padding or C.BASE_FRONTLIGHT_SLIDER_PADDING
        self.track_width = self.track_width or C.BASE_FRONTLIGHT_TRACK_WIDTH
        self.knob_radius = self.knob_radius or C.BASE_FRONTLIGHT_KNOB_RADIUS
        self.powerd = self.powerd or Device:getPowerDevice()
        self.minimum = tonumber(self.minimum)
            or tonumber(self.powerd and self.powerd.fl_min)
            or 0
        self.maximum = tonumber(self.maximum)
            or tonumber(self.powerd and self.powerd.fl_max)
            or 100
        if self.maximum <= self.minimum then
            self.maximum = self.minimum + 1
        end

        self.value = self.minimum
        self.enabled = false
        self:syncFromPower()
        self.last_refresh_time = 0
        self.dimen = Geom:new({ x = 0, y = 0, w = self.width, h = self.height })

        if Device:isTouchDevice() then
            self.ges_events = {
                TapFrontlightSlider = {
                    GestureRange:new({ ges = "tap", range = self.dimen }),
                },
                PanFrontlightSlider = {
                    GestureRange:new({ ges = "pan", range = self.dimen }),
                },
                PanReleaseFrontlightSlider = {
                    GestureRange:new({ ges = "pan_release", range = self.dimen }),
                },
            }
        end
    end

    function LightSlider:syncFromPower(notify_state_change)
        local was_enabled = self.enabled
        local level_ok, level
        if self.value_reader then
            level_ok, level = pcall(self.value_reader, self.powerd)
        else
            level_ok, level = pcall(self.powerd.frontlightIntensity, self.powerd)
        end
        if level_ok then
            self.value = tonumber(level) or self.minimum
            self.value = math_max(self.minimum, math_min(self.maximum, self.value))
        end

        -- Avoids allocating a wrapper closure on every paint: this call runs on
        -- each repaint of the slider, including every step of an active drag.
        local state_ok, light_on = pcall(self.powerd.isFrontlightOn, self.powerd)
        if state_ok then
            self.enabled = light_on == true
        else
            self.enabled = self.value > self.minimum
        end
        if
            notify_state_change
            and was_enabled ~= self.enabled
            and self.state_changed_callback
        then
            self.state_changed_callback(self.enabled)
        end
        return self.enabled
    end

    function LightSlider:getSize()
        return self.dimen
    end

    function LightSlider:getTrackBounds()
        local inset = self.slider_padding + self.knob_radius
        local top = inset
        local bottom = math_max(top + 1, self.height - inset)
        return top, bottom
    end

    function LightSlider:getLevelFromPosition(pos)
        if not pos or not self.dimen then
            return nil
        end

        local track_top, track_bottom = self:getTrackBounds()
        local relative_y = math_max(track_top, math_min(track_bottom, pos.y - (self.dimen.y or 0)))
        local percentage = (track_bottom - relative_y) / math_max(1, track_bottom - track_top)
        return math_floor(self.minimum + percentage * (self.maximum - self.minimum) + 0.5)
    end

    -- Whether the screen still shows another level or on/off state. Compared
    -- with what was last painted rather than with the previous event, so a
    -- refresh skipped by the pan-rate limit is still caught up later.
    function LightSlider:differsFromPainted()
        return self.value ~= self.painted_value or self.enabled ~= self.painted_enabled
    end

    function LightSlider:markPainted()
        self.painted_value = self.value
        self.painted_enabled = self.enabled
    end

    function LightSlider:refreshSlider(force)
        if not allowSliderRefresh(self, force) then
            return
        end
        UIManager:setDirty(self.show_parent or self, "fast", self.dimen)
    end

    function LightSlider:setLevelFromPosition(pos, force_refresh)
        if not self.enabled then
            return true
        end

        local level = self:getLevelFromPosition(pos)
        if level == nil then
            return true
        end

        if level ~= self.value then
            local ok = pcall(function()
                if self.value_writer then
                    self.value_writer(self.powerd, level)
                else
                    -- KOReader reserves the minimum frontlight level (normally
                    -- zero) for toggling the light, which lets device-specific
                    -- PowerD implementations use their proper on/off path.
                    if level == self.minimum and type(self.powerd.toggleFrontlight) == "function" then
                        self.powerd:toggleFrontlight()
                    else
                        self.powerd:setIntensity(level)
                    end
                    self.powerd:updateResumeFrontlightState()
                end
            end)
            if ok then
                self:syncFromPower(true)
            end
        end
        -- A drag within one level, or a tap on the current one, would repaint
        -- an identical slider and cost an e-ink refresh for nothing.
        if self:differsFromPainted() then
            self:refreshSlider(force_refresh)
        end
        return true
    end

    function LightSlider:onTapFrontlightSlider(_arg, gesture)
        return self:setLevelFromPosition(gesture and gesture.pos, true)
    end

    function LightSlider:onPanFrontlightSlider(_arg, gesture)
        return self:setLevelFromPosition(gesture and gesture.pos, false)
    end

    function LightSlider:onPanReleaseFrontlightSlider(_arg, gesture)
        return self:setLevelFromPosition(gesture and (gesture.pos or gesture.end_pos), true)
    end

    function LightSlider:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        self:syncFromPower()

        local border = Size.border.button
        local radius = Size.radius.button
        local background = Blitbuffer.COLOR_WHITE
        local paint_rounded_rect = Blitbuffer.isColor8(background)
            and bb.paintRoundedRect
            or bb.paintRoundedRectRGB32
        paint_rounded_rect(bb, x, y, self.width, self.height, background, radius + border)
        bb:paintBorder(
            x,
            y,
            self.width,
            self.height,
            border,
            Blitbuffer.COLOR_BLACK,
            radius,
            G_reader_settings:nilOrTrue("anti_alias_ui")
        )

        local track_top, track_bottom = self:getTrackBounds()
        local track_height = math_max(1, track_bottom - track_top)
        local percentage = (self.value - self.minimum) / (self.maximum - self.minimum)
        local knob_y = y + track_bottom - math_floor(percentage * track_height + 0.5)
        local center_x = x + math_floor(self.width / 2)
        local track_x = center_x - math_floor(self.track_width / 2)

        local track_color = self.enabled and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_LIGHT_GRAY
        local active_color = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
        bb:paintRect(track_x, y + track_top, self.track_width, track_height, track_color)
        if knob_y < y + track_bottom then
            bb:paintRect(
                track_x,
                knob_y,
                self.track_width,
                y + track_bottom - knob_y,
                active_color
            )
        end
        bb:paintCircle(center_x, knob_y, self.knob_radius, active_color)
        self:markPainted()
    end

    -- A button whose label follows some state: display_provider() returns the
    -- icon to show or, without one, the text. Checked on every repaint, so a
    -- refresh of the dock is enough to update it.
    local DynamicLabelButton = Button:extend({})

    function DynamicLabelButton:paintTo(bb, x, y)
        local icon, text = self.display_provider()
        if icon then
            if icon ~= self.icon or self.text ~= nil then
                self.text = nil
                self.icon = nil
                self:setIcon(icon, self.width)
            end
        elseif text ~= self.text or self.icon ~= nil then
            self.icon = nil
            self:setText(text, self.width)
        end
        Button.paintTo(self, bb, x, y)
    end

    local FloatingControlButtonDialog = ButtonDialog:extend({})

    function FloatingControlButtonDialog:onCloseWidget()
        if self._quickdock_suppress_close_refresh then
            return
        end
        ButtonDialog.onCloseWidget(self)
    end

    function FloatingControlButtonDialog:onClose()
        if self.close_all_callback then
            if self.close_all_callback() ~= false then
                return true
            end
        end
        return ButtonDialog.onClose(self)
    end

    -- The information panel is a non-modal overlay, so taps on it arrive here
    -- as taps outside the dock. Let an interactive panel handle them before the
    -- dock closes.
    function FloatingControlButtonDialog:onTapClose(arg, ges)
        if
            self.outside_tap_callback
            and ges and ges.pos
            and ges.pos:notIntersectWith(self.movable.dimen)
            and self.outside_tap_callback(ges.pos)
        then
            return true
        end
        return ButtonDialog.onTapClose(self, arg, ges)
    end

    function FloatingControlButtonDialog:init()
        ButtonDialog.init(self)

        -- Keep ButtonDialog's anchor positioning but disable movement gestures,
        -- allowing touches to reach dock buttons and both lighting sliders.
        self.movable.unmovable = true
        self.movable.is_movable_with_keys = false
        if self.movable.ges_events then
            self.movable.ges_events.MovableTouch = nil
            self.movable.ges_events.MovableSwipe = nil
            self.movable.ges_events.MovableHold = nil
            self.movable.ges_events.MovableHoldPan = nil
            self.movable.ges_events.MovableHoldRelease = nil
            self.movable.ges_events.MovablePan = nil
            self.movable.ges_events.MovablePanRelease = nil
        end
        if self.movable.key_events then
            self.movable.key_events.MovePositionTop = nil
            self.movable.key_events.MovePositionBottom = nil
        end

        -- Buttons stacked above the dock, from the top.
        local dock_frame = self.movable[1]
        local dock_size = dock_frame:getSize()
        local function makeButton(factory)
            return factory and factory(dock_size.w, self) or nil
        end
        local close_button = makeButton(self.close_button_factory)
        local side_button = makeButton(self.side_button_factory)
        local info_panel_toggle_button = makeButton(self.info_panel_toggle_button_factory)
        self.info_panel_toggle_button = info_panel_toggle_button

        local dock_column = dock_frame
        local stacked = {}
        local gap = self.side_button_gap or C.BASE_SIDE_BUTTON_GAP
        for _index, button in ipairs({ close_button or false, side_button or false, info_panel_toggle_button or false }) do
            if button then
                stacked[#stacked + 1] = button
                stacked[#stacked + 1] = VerticalSpan:new({ width = gap })
            end
        end
        if #stacked > 0 then
            stacked[#stacked + 1] = dock_frame
            dock_column = VerticalGroup:new(stacked)
        end

        -- Lighting columns beside the dock, all bottom-aligned with it.
        local function makeColumn(factory)
            return factory and factory(dock_size.h, self) or nil
        end
        local frontlight_column = makeColumn(self.frontlight_slider_factory)
        local warmth_column = makeColumn(self.warmth_slider_factory)
        local accessory_columns = {}
        for _index, column in ipairs({ frontlight_column or false, warmth_column or false }) do
            if column then
                accessory_columns[#accessory_columns + 1] = column
            end
        end
        if #accessory_columns > 0 then
            local total_height = dock_column:getSize().h
            for _index, column in ipairs(accessory_columns) do
                total_height = math_max(total_height, column:getSize().h)
            end
            local function bottomAligned(column)
                return VerticalGroup:new({
                    VerticalSpan:new({ width = total_height - column:getSize().h }),
                    column,
                })
            end
            local columns = {}
            local function addColumn(column)
                if #columns > 0 then
                    columns[#columns + 1] = HorizontalSpan:new({
                        width = self.frontlight_slider_gap or C.BASE_FRONTLIGHT_SLIDER_GAP,
                    })
                end
                columns[#columns + 1] = bottomAligned(column)
            end
            -- The dock stays next to its screen edge.
            if self.dock_side == "left" then
                addColumn(dock_column)
                for index = 1, #accessory_columns do
                    addColumn(accessory_columns[index])
                end
            else
                for index = #accessory_columns, 1, -1 do
                    addColumn(accessory_columns[index])
                end
                addColumn(dock_column)
            end
            columns.allow_mirroring = false
            self.movable[1] = HorizontalGroup:new(columns)
        else
            self.movable[1] = dock_column
        end

        -- Each extra control is focusable on its own row before the actions,
        -- the last one listed here first.
        if Device:hasDPad() and self.layout then
            local focusable = {
                side_button or false,
                close_button or false,
                info_panel_toggle_button or false,
                frontlight_column and frontlight_column.button or false,
                warmth_column and warmth_column.button or false,
            }
            for _index, button in ipairs(focusable) do
                if button then
                    table.insert(self.layout, 1, { button })
                end
            end
        end
    end

    return {
        LightSlider = LightSlider,
        DynamicLabelButton = DynamicLabelButton,
        FloatingControlButtonDialog = FloatingControlButtonDialog,
        makeFallbackLabel = makeFallbackLabel,
        allowSliderRefresh = allowSliderRefresh,
    }

end
