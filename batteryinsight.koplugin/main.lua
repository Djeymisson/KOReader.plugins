local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local datetime = require("datetime")
local time = require("ui/time")
local _ = require("gettext")

local Screen = Device.screen
local PowerD = Device:getPowerDevice()

local VERSION = "v0.3.4"
local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/battery_insight.lua"
local DEFAULT_SAMPLE_INTERVAL_MIN = 15
local MAX_SAMPLES = 1200
local GRAPH_HOURS = 24

local COLOR_BLACK = Blitbuffer.COLOR_BLACK
local COLOR_DARK = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_GRAY_4 or COLOR_BLACK
local COLOR_GRAY = Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_LIGHT_GRAY or COLOR_DARK
local COLOR_LIGHT = Blitbuffer.COLOR_LIGHT_GRAY or COLOR_GRAY
local COLOR_WHITE = Blitbuffer.COLOR_WHITE

local function clamp(value, min_value, max_value)
    if value < min_value then return min_value end
    if value > max_value then return max_value end
    return value
end

local function round(value, digits)
    local mul = 10 ^ (digits or 0)
    return math.floor((value or 0) * mul + 0.5) / mul
end

local function wallClock()
    return os.time()
end

local function bootClock()
    return time.to_s(time.boottime_or_realtime_coarse())
end

local function formatPercent(value, digits)
    if type(value) ~= "number" then return _("N/A") end
    return string.format("%." .. tostring(digits or 1) .. "f%%", value)
end

local function formatRate(value)
    if type(value) ~= "number" then return _("N/A") end
    return string.format("%.2f%%/h", value)
end

local function formatTime(ts)
    if type(ts) ~= "number" then return _("N/A") end
    return os.date("%H:%M", ts)
end

local function formatDateTime(ts)
    if type(ts) ~= "number" then return _("N/A") end
    return datetime.secondsToDateTime(ts, nil, true)
end

local function formatDuration(seconds)
    if type(seconds) ~= "number" or seconds < 0 then return _("N/A") end
    return datetime.secondsToClockDuration(
        G_reader_settings:readSetting("duration_format", "classic"),
        seconds,
        true,
        true
    )
end

local function readFirstLine(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local line = f:read("*line")
    f:close()
    return line
end

local function readCpuStat()
    local line = readFirstLine("/proc/stat")
    if not line then return nil end

    local values = {}
    for token in line:gmatch("%S+") do
        values[#values + 1] = token
    end
    if values[1] ~= "cpu" then return nil end

    local total, idle = 0, 0
    for i = 2, #values do
        local n = tonumber(values[i]) or 0
        total = total + n
        if i == 5 or i == 6 then
            idle = idle + n
        end
    end

    return { total = total, idle = idle }
end

local function readProcStat(pid)
    local line = readFirstLine("/proc/" .. pid .. "/stat")
    if not line then return nil end

    local name = line:match("%((.*)%)") or tostring(pid)
    local after = line:match("%)%s+(.+)$")
    if not after then return nil end

    local fields = {}
    for token in after:gmatch("%S+") do
        fields[#fields + 1] = token
    end

    return {
        pid = tostring(pid),
        name = name,
        ticks = (tonumber(fields[12]) or 0) + (tonumber(fields[13]) or 0),
    }
end

local function readProcessSnapshot()
    local snapshot = {}
    local p = io.popen("ls -1 /proc 2>/dev/null")
    if not p then return snapshot end

    for line in p:lines() do
        if line:match("^%d+$") then
            local stat = readProcStat(line)
            if stat then
                snapshot[stat.pid] = stat
            end
        end
    end
    p:close()

    return snapshot
end

local function processDeltas(previous, current, cpu_delta)
    local result = {}
    if not previous or not current or not cpu_delta or cpu_delta <= 0 then
        return result
    end

    for pid, curr in pairs(current) do
        local prev = previous[pid]
        if prev then
            local delta = curr.ticks - prev.ticks
            if delta > 0 then
                result[#result + 1] = {
                    pid = pid,
                    name = curr.name,
                    cpu = (delta / cpu_delta) * 100,
                }
            end
        end
    end

    table.sort(result, function(a, b) return a.cpu > b.cpu end)

    local top = {}
    for i = 1, math.min(10, #result) do
        top[#top + 1] = result[i]
    end
    return top
end

local function getCapacity()
    local ok, value = pcall(function() return PowerD:getCapacityHW() end)
    if ok and type(value) == "number" then return clamp(math.floor(value + 0.5), 0, 100) end

    ok, value = pcall(function() return PowerD:getCapacity() end)
    if ok and type(value) == "number" then return clamp(math.floor(value + 0.5), 0, 100) end

    return nil
end

local function isCharging()
    local ok, value = pcall(function() return PowerD:isCharging() end)
    return ok and value == true
end

local function isCharged()
    local ok, value = pcall(function() return PowerD:isCharged() end)
    return ok and value == true
end

local function getWifiState()
    local candidates = {
        function() return Device:isWifiOn() end,
        function() return Device.wifi_enable end,
        function() return Device.network_manager and Device.network_manager:isWifiOn() end,
    }

    for _, fn in ipairs(candidates) do
        local ok, value = pcall(fn)
        if ok and value ~= nil then return value and true or false end
    end
    return nil
end

local function getFrontlightLevel()
    local candidates = {
        function() return Device.frontlightIntensity end,
        function() return Device.screen and Device.screen:getFrontlightLevel() end,
        function() return PowerD:getFrontlightLevel() end,
    }

    for _, fn in ipairs(candidates) do
        local ok, value = pcall(fn)
        if ok and type(value) == "number" then return value end
    end
    return nil
end

local function sampleDrainRate(first, last)
    if not first or not last then return nil end
    if type(first.capacity) ~= "number" or type(last.capacity) ~= "number" then return nil end
    if type(first.wall_ts) ~= "number" or type(last.wall_ts) ~= "number" then return nil end
    if last.wall_ts <= first.wall_ts then return nil end
    if last.charging or last.capacity >= first.capacity then return nil end

    local hours = (last.wall_ts - first.wall_ts) / 3600
    if hours <= 0 then return nil end
    return (first.capacity - last.capacity) / hours
end

local function windowSamples(samples, seconds)
    local cutoff = wallClock() - seconds
    local out = {}
    for _, sample in ipairs(samples) do
        if type(sample.wall_ts) == "number" and sample.wall_ts >= cutoff then
            out[#out + 1] = sample
        end
    end
    return out
end

local function firstLastInWindow(samples, seconds)
    local filtered = windowSamples(samples, seconds)
    return filtered[1], filtered[#filtered], filtered
end

local function averageDrain(samples, seconds)
    local first, last = firstLastInWindow(samples, seconds)
    return sampleDrainRate(first, last)
end

local function estimateRemaining(samples)
    local last = samples[#samples]
    if not last or type(last.capacity) ~= "number" or last.charging then return nil end

    local rate = averageDrain(samples, 6 * 3600)
        or averageDrain(samples, 24 * 3600)
        or averageDrain(samples, 72 * 3600)
    if not rate or rate <= 0 then return nil end

    return (last.capacity / rate) * 3600
end

local function hourlyDrainBuckets(samples, hours)
    local now_ts = wallClock()
    local buckets = {}
    for i = 1, hours do
        local bucket_end = now_ts - ((hours - i) * 3600)
        local bucket_start = bucket_end - 3600
        local first, last

        for _, sample in ipairs(samples) do
            if type(sample.wall_ts) == "number" and sample.wall_ts >= bucket_start and sample.wall_ts <= bucket_end then
                if not first then first = sample end
                last = sample
            end
        end

        buckets[i] = sampleDrainRate(first, last) or 0
    end
    return buckets
end

local function downsample(samples, max_points)
    if #samples <= max_points then return samples end

    local out = {}
    local step = (#samples - 1) / (max_points - 1)
    for i = 1, max_points do
        local idx = math.floor(1 + ((i - 1) * step) + 0.5)
        out[#out + 1] = samples[clamp(idx, 1, #samples)]
    end
    return out
end

local function batteryStatus(samples)
    local last = samples[#samples]
    if not last then return _("Collecting") end
    if last.charging then return _("Charging") end

    local rate = averageDrain(samples, 6 * 3600) or averageDrain(samples, 24 * 3600)
    if not rate then return _("Learning") end
    if rate >= 3 then return _("High drain") end
    if rate >= 1.5 then return _("Moderate drain") end
    return _("Stable")
end

local BatteryInsightState = {
    settings = LuaSettings:open(SETTINGS_FILE),
    samples = {},
    enabled = true,
    sample_interval_min = DEFAULT_SAMPLE_INTERVAL_MIN,
    scheduled = false,
    cpu_snapshot = nil,
    process_snapshot = nil,
    dashboard = nil,
}

function BatteryInsightState:init()
    self.samples = self.settings:readSetting("samples") or {}
    self.enabled = self.settings:readSetting("enabled")
    if self.enabled == nil then self.enabled = true end
    self.sample_interval_min = self.settings:readSetting("sample_interval_min") or DEFAULT_SAMPLE_INTERVAL_MIN
    self.cpu_snapshot = self.settings:readSetting("cpu_snapshot")
    self.process_snapshot = self.settings:readSetting("process_snapshot")
    self:trimSamples()
end

function BatteryInsightState:trimSamples()
    while #self.samples > MAX_SAMPLES do
        table.remove(self.samples, 1)
    end
end

function BatteryInsightState:flush()
    self.settings:reset({
        samples = self.samples,
        enabled = self.enabled,
        sample_interval_min = self.sample_interval_min,
        cpu_snapshot = self.cpu_snapshot,
        process_snapshot = self.process_snapshot,
    })
    self.settings:flush()
end

function BatteryInsightState:capture(reason)
    local capacity = getCapacity()
    if not capacity then return nil end

    local cpu = readCpuStat()
    local proc = readProcessSnapshot()
    local cpu_delta = self.cpu_snapshot and cpu and (cpu.total - self.cpu_snapshot.total) or nil
    local top_processes = processDeltas(self.process_snapshot, proc, cpu_delta)
    local cpu_usage = nil

    if self.cpu_snapshot and cpu and cpu_delta and cpu_delta > 0 then
        local idle_delta = cpu.idle - self.cpu_snapshot.idle
        cpu_usage = clamp((1 - idle_delta / cpu_delta) * 100, 0, 100)
    end

    local sample = {
        ts = bootClock(),
        wall_ts = wallClock(),
        capacity = capacity,
        charging = isCharging(),
        charged = isCharged(),
        wifi = getWifiState(),
        frontlight = getFrontlightLevel(),
        cpu_usage = cpu_usage,
        top_processes = top_processes,
        reason = reason or "timer",
    }

    self.samples[#self.samples + 1] = sample
    self.cpu_snapshot = cpu
    self.process_snapshot = proc
    self:trimSamples()
    self:flush()
    return sample
end

function BatteryInsightState:scheduleNext()
    if self.scheduled or not self.enabled then return end

    self.scheduled = true
    UIManager:scheduleIn(math.max(1, self.sample_interval_min) * 60, function()
        self.scheduled = false
        if self.enabled then
            self:capture("timer")
            self:scheduleNext()
            if self.dashboard then
                self.dashboard[1]:refreshData()
                UIManager:setDirty(self.dashboard, "ui")
            end
        end
    end)
end

function BatteryInsightState:resetHistory()
    self.samples = {}
    self.cpu_snapshot = nil
    self.process_snapshot = nil
    self:capture("reset")
    self:flush()
end

function BatteryInsightState:setInterval(minutes)
    self.sample_interval_min = minutes
    self:flush()
    self:scheduleNext()
end

local DashboardWidget = Widget:extend{
    state = nil,
    face_small = nil,
    face = nil,
    face_medium = nil,
    face_large = nil,
    dimen = nil,
    data = nil,
}

function DashboardWidget:init()
    self.face_axis = Font:getFace("cfont", 16)
    self.face_tiny = Font:getFace("cfont", 17)
    self.face_small = Font:getFace("cfont", 18)
    self.face = Font:getFace("cfont", 22)
    self.face_medium = Font:getFace("cfont", 28)
    self.face_large = Font:getFace("cfont", 38)
    self:refreshData()
end

function DashboardWidget:getSize()
    return Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() }
end

function DashboardWidget:refreshData()
    local samples = self.state.samples or {}
    local last = samples[#samples]

    self.data = {
        samples = samples,
        graph_samples = downsample(windowSamples(samples, GRAPH_HOURS * 3600), 120),
        last = last,
        status = batteryStatus(samples),
    }
end

function DashboardWidget:drawText(bb, text, x, y, face, opts)
    opts = opts or {}
    local widget = TextWidget:new{
        text = tostring(text or ""),
        face = face or self.face,
        bold = opts.bold,
        fgcolor = opts.fgcolor or COLOR_BLACK,
    }
    local size = widget:getSize()
    local tx = x
    if opts.align == "center" and opts.w then
        tx = x + math.floor((opts.w - size.w) / 2)
    elseif opts.align == "right" and opts.w then
        tx = x + opts.w - size.w
    end
    widget:paintTo(bb, tx, y)
    return size
end

function DashboardWidget:drawLine(bb, x1, y1, x2, y2, color, thickness)
    color = color or COLOR_BLACK
    thickness = thickness or 2

    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy

    while true do
        bb:paintRect(x1, y1, thickness, thickness, color)
        if x1 == x2 and y1 == y2 then break end
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x1 = x1 + sx
        end
        if e2 < dx then
            err = err + dx
            y1 = y1 + sy
        end
    end
end

function DashboardWidget:drawBatteryBar(bb, x, y, w, h, capacity)
    local value = type(capacity) == "number" and clamp(capacity, 0, 100) or 0
    local fill_w = math.floor((w - 4) * (value / 100))

    bb:paintBorder(x, y, w, h, 2, COLOR_BLACK, 0)
    bb:paintRect(x + w, y + math.floor(h * 0.25), 8, math.floor(h * 0.5), COLOR_BLACK)
    if fill_w > 0 then
        bb:paintRect(x + 2, y + 2, fill_w, h - 4, COLOR_BLACK)
    end
end

function DashboardWidget:drawMainGraph(bb, x, y, w, h)
    local samples = self.data.graph_samples or {}
    local title_h = Screen:scaleBySize(52)
    local bottom_pad = Screen:scaleBySize(62)
    local left_pad = Screen:scaleBySize(62)
    local right_pad = Screen:scaleBySize(22)
    local top_pad = Screen:scaleBySize(22)
    local plot_x = x + left_pad
    local plot_y = y + title_h + top_pad
    local plot_w = w - left_pad - right_pad
    local plot_h = h - title_h - top_pad - bottom_pad

    if plot_h < Screen:scaleBySize(120) then
        plot_h = Screen:scaleBySize(120)
    end

    bb:paintBorder(x, y, w, h, 2, COLOR_BLACK, 0)
    self:drawText(bb, _("Battery curve · last 24h"), x + 14, y + 14, self.face, { bold = true })

    for _, level in ipairs({100, 75, 50, 25, 0}) do
        local gy = plot_y + math.floor((100 - level) / 100 * plot_h)
        bb:paintRect(plot_x, gy, plot_w, 1, level == 0 and COLOR_BLACK or COLOR_LIGHT)
        self:drawText(bb, tostring(level), x + 8, gy - 8, self.face_axis or self.face_tiny or self.face_small, {
            fgcolor = COLOR_DARK,
            align = "right",
            w = left_pad - 18,
        })
    end

    bb:paintRect(plot_x, plot_y, 2, plot_h, COLOR_BLACK)
    bb:paintRect(plot_x, plot_y + plot_h, plot_w, 2, COLOR_BLACK)

    if #samples < 2 then
        self:drawText(bb, _("Collect more samples to draw the battery curve."), plot_x + 8, plot_y + math.floor(plot_h / 2) - 12, self.face_small, { fgcolor = COLOR_DARK })
        return
    end

    local previous_x, previous_y
    for i, sample in ipairs(samples) do
        local capacity = clamp(sample.capacity or 0, 0, 100)
        local px = plot_x + math.floor(((i - 1) / (#samples - 1)) * plot_w)
        local py = plot_y + math.floor((100 - capacity) / 100 * plot_h)

        if previous_x then
            self:drawLine(bb, previous_x, previous_y, px, py, COLOR_BLACK, 3)
        end
        bb:paintRect(px - 2, py - 2, 5, 5, COLOR_BLACK)
        previous_x, previous_y = px, py
    end

    local first = samples[1]
    local last = samples[#samples]
    local label_y = y + h - Screen:scaleBySize(38)
    self:drawText(bb, first and formatTime(first.wall_ts) or "", plot_x, label_y, self.face_axis or self.face_tiny or self.face_small, { fgcolor = COLOR_DARK })
    self:drawText(bb, last and formatTime(last.wall_ts) or "", plot_x + plot_w - Screen:scaleBySize(90), label_y, self.face_axis or self.face_tiny or self.face_small, {
        fgcolor = COLOR_DARK,
        align = "right",
        w = Screen:scaleBySize(90),
    })
end

function DashboardWidget:drawProcessList(bb, x, y, w, h)
    local last = self.data.last
    local top = last and last.top_processes or nil

    bb:paintBorder(x, y, w, h, 2, COLOR_BLACK, 0)
    self:drawText(bb, _("Potential battery drainers"), x + 14, y + 14, self.face, { bold = true })
    self:drawText(bb, _("Recent CPU activity since the previous sample"), x + 14, y + 54, self.face_small, { fgcolor = COLOR_DARK })

    local header_y = y + Screen:scaleBySize(92)
    local line_h = Screen:scaleBySize(29)
    local name_x = x + Screen:scaleBySize(58)
    local pid_x = x + math.floor(w * 0.62)
    local cpu_x = x + w - Screen:scaleBySize(112)

    bb:paintRect(x + 14, header_y + Screen:scaleBySize(28), w - 28, 1, COLOR_LIGHT)
    self:drawText(bb, "#", x + 18, header_y, self.face_tiny or self.face_small, { fgcolor = COLOR_DARK })
    self:drawText(bb, _("Process"), name_x, header_y, self.face_tiny or self.face_small, { fgcolor = COLOR_DARK })
    self:drawText(bb, "PID", pid_x, header_y, self.face_tiny or self.face_small, { fgcolor = COLOR_DARK })
    self:drawText(bb, _("CPU"), cpu_x, header_y, self.face_tiny or self.face_small, { fgcolor = COLOR_DARK, align = "right", w = Screen:scaleBySize(90) })

    local yy = header_y + Screen:scaleBySize(40)
    local max_rows = math.max(0, math.floor((y + h - yy - Screen:scaleBySize(16)) / line_h))

    if not top or #top == 0 then
        self:drawText(bb, _("The process list appears after two samples."), x + 18, yy + 10, self.face_small, { fgcolor = COLOR_DARK })
        self:drawText(bb, _("Tap the center to collect another sample."), x + 18, yy + 42, self.face_tiny or self.face_small, { fgcolor = COLOR_DARK })
        return
    end

    local shown = math.min(#top, max_rows)
    for i = 1, shown do
        local proc = top[i]
        local name = proc.name or "?"
        local max_name = w > 620 and 30 or 22
        if #name > max_name then
            name = name:sub(1, max_name - 1) .. "…"
        end

        self:drawText(bb, tostring(i), x + 18, yy, self.face_tiny or self.face_small)
        self:drawText(bb, name, name_x, yy, self.face_tiny or self.face_small)
        self:drawText(bb, tostring(proc.pid or "?"), pid_x, yy, self.face_tiny or self.face_small, { fgcolor = COLOR_DARK })
        self:drawText(bb, formatPercent(proc.cpu, 1), cpu_x, yy, self.face_tiny or self.face_small, { align = "right", w = Screen:scaleBySize(90) })
        yy = yy + line_h
    end

    if shown < #top and yy <= y + h - 28 then
        self:drawText(bb, string.format(_("+%d more"), #top - shown), x + 18, yy, self.face_tiny or self.face_small, { fgcolor = COLOR_DARK })
    end
end


function DashboardWidget:paintTo(bb, x, y)
    local size = self:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }

    bb:paintRect(x, y, size.w, size.h, COLOR_WHITE)

    local margin = Screen:scaleBySize(26)
    local gap = Screen:scaleBySize(16)
    local footer_h = Screen:scaleBySize(72)
    local content_w = size.w - (margin * 2)
    local last = self.data.last
    local capacity = last and last.capacity or 0
    local state = last and (last.charging and _("charging") or _("discharging")) or _("no data")

    local cursor_y = y + margin

    self:drawText(bb, "Battery Insight", margin, cursor_y, self.face_medium, { bold = true })
    self:drawText(bb, VERSION, x + size.w - margin - Screen:scaleBySize(86), cursor_y + 4, self.face_tiny or self.face_small, {
        align = "right",
        w = Screen:scaleBySize(86),
        fgcolor = COLOR_DARK,
    })

    self:drawText(bb, self.data.status .. " · " .. state, margin, cursor_y + Screen:scaleBySize(40), self.face_small, { fgcolor = COLOR_DARK })

    local percent_y = cursor_y + Screen:scaleBySize(68)
    self:drawText(bb, tostring(capacity) .. "%", margin, percent_y, self.face_large, { bold = true })

    local battery_bar_offset = Screen:scaleBySize(330)
    local battery_bar_x = margin + battery_bar_offset
    local battery_bar_w = content_w - battery_bar_offset - Screen:scaleBySize(12)
    if battery_bar_w < Screen:scaleBySize(170) then
        battery_bar_offset = Screen:scaleBySize(280)
        battery_bar_x = margin + battery_bar_offset
        battery_bar_w = content_w - battery_bar_offset - Screen:scaleBySize(12)
    end
    self:drawBatteryBar(bb, battery_bar_x, percent_y + Screen:scaleBySize(12), battery_bar_w, Screen:scaleBySize(28), capacity)

    cursor_y = percent_y + Screen:scaleBySize(76)

    local footer_y = y + size.h - footer_h - Screen:scaleBySize(8)
    local available_h = footer_y - cursor_y
    local graph_h = math.floor((available_h - gap) * 0.64)
    local process_h = available_h - graph_h - gap

    local min_graph_h = Screen:scaleBySize(260)
    local min_process_h = Screen:scaleBySize(190)
    if available_h - gap < min_graph_h + min_process_h then
        process_h = math.max(Screen:scaleBySize(155), math.floor((available_h - gap) * 0.34))
        graph_h = available_h - gap - process_h
    else
        if graph_h < min_graph_h then
            graph_h = min_graph_h
            process_h = available_h - graph_h - gap
        end
        if process_h < min_process_h then
            process_h = min_process_h
            graph_h = available_h - process_h - gap
        end
    end

    if graph_h > Screen:scaleBySize(560) then
        graph_h = Screen:scaleBySize(560)
        process_h = available_h - graph_h - gap
    end

    self:drawMainGraph(bb, margin, cursor_y, content_w, graph_h)

    local process_y = cursor_y + graph_h + gap
    self:drawProcessList(bb, margin, process_y, content_w, process_h)

    bb:paintRect(margin, footer_y, content_w, 1, COLOR_LIGHT)
    self:drawText(bb, last and (_("Last sample: ") .. formatDateTime(last.wall_ts)) or _("No samples"), margin, footer_y + 10, self.face_tiny or self.face_small, { fgcolor = COLOR_DARK })
    self:drawText(bb, _("Tap left: close · center: refresh · right: reset history"), margin, footer_y + 38, self.face_tiny or self.face_small, { fgcolor = COLOR_DARK })
end

local function showResetConfirm(state)
    UIManager:show(ConfirmBox:new{
        text = _("Clear all Battery Insight history?"),
        ok_text = _("Clear"),
        ok_callback = function()
            state:resetHistory()
            if state.dashboard then
                state.dashboard[1]:refreshData()
                UIManager:setDirty(state.dashboard, "ui")
            end
        end,
    })
end

function BatteryInsightState:showDashboard()
    self:capture("view")

    if self.dashboard then
        UIManager:close(self.dashboard)
        self.dashboard = nil
    end

    local dashboard_widget = DashboardWidget:new{ state = self }
    local container
    container = InputContainer:new{
        dashboard_widget,
        modal = true,
        stop_events_propagation = true,
        key_events = {
            Close = { { { "Back", "Esc" } } },
            Refresh = { { { "ScreenKB", "Press" } } },
        },
    }

    function container:onClose()
        UIManager:close(self)
        BatteryInsightState.dashboard = nil
        return true
    end

    function container:onRefresh()
        BatteryInsightState:capture("manual")
        dashboard_widget:refreshData()
        UIManager:setDirty(self, "ui")
        return true
    end

    container:registerTouchZones({
        {
            id = "battery_insight_close",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 0.33, ratio_h = 1 },
            handler = function()
                UIManager:close(container)
                BatteryInsightState.dashboard = nil
                return true
            end,
        },
        {
            id = "battery_insight_refresh",
            ges = "tap",
            screen_zone = { ratio_x = 0.33, ratio_y = 0, ratio_w = 0.34, ratio_h = 1 },
            handler = function()
                BatteryInsightState:capture("manual")
                dashboard_widget:refreshData()
                UIManager:setDirty(container, "ui")
                return true
            end,
        },
        {
            id = "battery_insight_reset",
            ges = "tap",
            screen_zone = { ratio_x = 0.67, ratio_y = 0, ratio_w = 0.33, ratio_h = 1 },
            handler = function()
                showResetConfirm(BatteryInsightState)
                return true
            end,
        },
    })

    self.dashboard = container
    UIManager:show(container, "ui")
end

BatteryInsightState:init()

local BatteryInsight = WidgetContainer:extend{
    name = "batteryinsight",
    title = "Battery Insight",
    is_doc_only = false,
}

function BatteryInsight:onDispatcherRegisterActions()
    Dispatcher:registerAction("battery_insight", {
        category = "none",
        event = "ShowBatteryInsight",
        title = self.title,
        general = true,
        device = true,
    })
end

function BatteryInsight:init()
    if not self.ui or not self.ui.menu then return end

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    BatteryInsightState:capture("start")
    BatteryInsightState:scheduleNext()
end

function BatteryInsight:addToMainMenu(menu_items)
    menu_items.battery_insight = {
        text = self.title,
        sorting_hint = "more_tools",
        keep_menu_open = true,
        callback = function()
            BatteryInsightState:showDashboard()
        end,
    }
end

function BatteryInsight:onShowBatteryInsight()
    BatteryInsightState:showDashboard()
end

function BatteryInsight:onFlushSettings()
    BatteryInsightState:flush()
end

function BatteryInsight:onSuspend()
    BatteryInsightState:capture("suspend")
end

function BatteryInsight:onResume()
    BatteryInsightState:capture("resume")
    BatteryInsightState:scheduleNext()
end

function BatteryInsight:onCharging()
    BatteryInsightState:capture("charging")
end

function BatteryInsight:onNotCharging()
    BatteryInsightState:capture("not_charging")
end

return BatteryInsight
