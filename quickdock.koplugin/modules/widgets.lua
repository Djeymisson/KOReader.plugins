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
local _ = require("quickdock_l10n")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local BASE_SIDE_BUTTON_GAP = Size.padding.default
local BASE_SLIDER_GAP = Size.padding.default
local BASE_SLIDER_PADDING = Screen:scaleBySize(8)
local BASE_TRACK_WIDTH = math_max(2, Screen:scaleBySize(3))
local BASE_KNOB_RADIUS = math_max(5, Screen:scaleBySize(8))

local LightSlider = InputContainer:extend({})

function LightSlider:init()
    self.width = self.width or Screen:scaleBySize(54)
    self.height = math_max(1, self.height or Screen:getHeight() / 2)
    self.slider_padding = self.slider_padding or BASE_SLIDER_PADDING
    self.track_width = self.track_width or BASE_TRACK_WIDTH
    self.knob_radius = self.knob_radius or BASE_KNOB_RADIUS
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

function LightSlider:refreshSlider(force)
    local now = time.now()
    if Screen.low_pan_rate and not force then
        local min_interval = time.s(1 / 3)
        if now - self.last_refresh_time < min_interval then
            return
        end
    end
    self.last_refresh_time = now
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
    self:refreshSlider(force_refresh)
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
end

local FrontlightToggleButton = Button:extend({})

function FrontlightToggleButton:paintTo(bb, x, y)
    self.slider:syncFromPower()
    local icon = self.icon_provider(self.slider.enabled)
    if icon then
        if icon ~= self.icon or self.text ~= nil then
            self.text = nil
            self.icon = nil
            self:setIcon(icon, self.width)
        end
    else
        local text = self.slider.enabled and _("On") or _("Off")
        if text ~= self.text or self.icon ~= nil then
            self.icon = nil
            self:setText(text, self.width)
        end
    end
    Button.paintTo(self, bb, x, y)
end

local InfoPanelToggleButton = Button:extend({})

function InfoPanelToggleButton:paintTo(bb, x, y)
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

    if
        not self.side_button_factory
        and not self.close_button_factory
        and not self.info_panel_toggle_button_factory
        and not self.frontlight_slider_factory
        and not self.warmth_slider_factory
    then
        return
    end

    local dock_frame = self.movable[1]
    local dock_size = dock_frame:getSize()
    local dock_column = dock_frame
    local side_button
    local close_button
    local info_panel_toggle_button
    local frontlight_column
    local warmth_column
    if self.close_button_factory then
        close_button = self.close_button_factory(dock_size.w, self)
    end
    if self.side_button_factory then
        side_button = self.side_button_factory(dock_size.w, self)
    end
    if self.info_panel_toggle_button_factory then
        info_panel_toggle_button = self.info_panel_toggle_button_factory(dock_size.w, self)
        self.info_panel_toggle_button = info_panel_toggle_button
    end
    if close_button or side_button or info_panel_toggle_button then
        local external_buttons = {}
        local gap = self.side_button_gap or BASE_SIDE_BUTTON_GAP
        if close_button then
            external_buttons[#external_buttons + 1] = close_button
            external_buttons[#external_buttons + 1] = VerticalSpan:new({ width = gap })
        end
        if side_button then
            external_buttons[#external_buttons + 1] = side_button
            external_buttons[#external_buttons + 1] = VerticalSpan:new({ width = gap })
        end
        if info_panel_toggle_button then
            external_buttons[#external_buttons + 1] = info_panel_toggle_button
            external_buttons[#external_buttons + 1] = VerticalSpan:new({ width = gap })
        end
        external_buttons[#external_buttons + 1] = dock_frame
        dock_column = VerticalGroup:new(external_buttons)
    end

    if self.frontlight_slider_factory then
        frontlight_column = self.frontlight_slider_factory(dock_size.h, self)
    end
    if self.warmth_slider_factory then
        warmth_column = self.warmth_slider_factory(dock_size.h, self)
    end

    local accessory_columns = {}
    if frontlight_column then
        accessory_columns[#accessory_columns + 1] = frontlight_column
    end
    if warmth_column then
        accessory_columns[#accessory_columns + 1] = warmth_column
    end
    if #accessory_columns > 0 then
        local dock_column_height = dock_column:getSize().h
        local total_height = dock_column_height
        for index = 1, #accessory_columns do
            total_height = math_max(total_height, accessory_columns[index]:getSize().h)
        end
        local aligned_dock_column = VerticalGroup:new({
            VerticalSpan:new({ width = total_height - dock_column_height }),
            dock_column,
        })
        local aligned_accessories = {}
        for index = 1, #accessory_columns do
            local accessory = accessory_columns[index]
            aligned_accessories[index] = VerticalGroup:new({
                VerticalSpan:new({ width = total_height - accessory:getSize().h }),
                accessory,
            })
        end
        local columns = {}
        local function addColumn(column)
            if #columns > 0 then
                columns[#columns + 1] = HorizontalSpan:new({
                    width = self.frontlight_slider_gap or BASE_SLIDER_GAP,
                })
            end
            columns[#columns + 1] = column
        end
        if self.dock_side == "left" then
            addColumn(aligned_dock_column)
            for index = 1, #aligned_accessories do
                addColumn(aligned_accessories[index])
            end
        else
            for index = #aligned_accessories, 1, -1 do
                addColumn(aligned_accessories[index])
            end
            addColumn(aligned_dock_column)
        end
        columns.allow_mirroring = false
        self.movable[1] = HorizontalGroup:new(columns)
    else
        self.movable[1] = dock_column
    end

    if side_button and Device:hasDPad() and self.layout then
        table.insert(self.layout, 1, { side_button })
    end
    if close_button and Device:hasDPad() and self.layout then
        table.insert(self.layout, 1, { close_button })
    end
    if info_panel_toggle_button and Device:hasDPad() and self.layout then
        table.insert(self.layout, 1, { info_panel_toggle_button })
    end
    if
        frontlight_column
        and frontlight_column.toggle_button
        and Device:hasDPad()
        and self.layout
    then
        table.insert(self.layout, 1, { frontlight_column.toggle_button })
    end
    if
        warmth_column
        and warmth_column.info_button
        and Device:hasDPad()
        and self.layout
    then
        table.insert(self.layout, 1, { warmth_column.info_button })
    end
end

return {
    LightSlider = LightSlider,
    FrontlightToggleButton = FrontlightToggleButton,
    InfoPanelToggleButton = InfoPanelToggleButton,
    FloatingControlButtonDialog = FloatingControlButtonDialog,
}
