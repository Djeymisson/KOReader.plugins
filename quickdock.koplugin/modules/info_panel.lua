local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local datetime = require("datetime")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
local NetworkMgr = require("ui/network/manager")
local ProgressWidget = require("ui/widget/progresswidget")
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("quickdock_l10n")
local N_ = _.ngettext
local T = require("ffi/util").template

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local STATS_FONT_SCALE = 0.85

local InfoPanelOverlay = WidgetContainer:extend({
    modal = false,
    -- The panel may be replaced while the dock remains open. Keeping it in
    -- KOReader's non-blocking overlay layer prevents a refreshed panel from
    -- becoming the input target above the dock. Unlike Notification, this
    -- widget does not close itself on input.
    toast = true,
    -- Extra room reserved above the usual screen margin, e.g. to clear a
    -- sibling plugin's own floating overlay sitting on this same side. Left
    -- untouched (0) unless a caller has a reason to reserve more.
    extra_bottom_margin = 0,
})

local StatusPanelOverlay = WidgetContainer:extend({
    -- Toasts are ignored while UIManager looks for the input target. This
    -- keeps the status block visually above the dock without intercepting its
    -- taps or the controls of a network-selection dialog.
    modal = false,
    toast = true,
    -- Same meaning as InfoPanelOverlay's own field above; only used when
    -- there's no anchor_widget to stack above instead.
    extra_bottom_margin = 0,
})

function InfoPanelOverlay:init()
    local panel_size = self.panel:getSize()
    local margin = math_max(0, tonumber(self.screen_margin) or Size.padding.large)
    if self.placement == "top" then
        self.dimen = Geom:new({ x = margin, y = margin, w = panel_size.w, h = panel_size.h })
        self[1] = self.panel
        return
    end
    local left = margin
    if self.panel_side == "right" then
        left = Screen:getWidth() - margin - panel_size.w
    end
    -- Only the bottom offset grows here -- the horizontal margin stays the
    -- screen-edge one, so reserving room for a sibling overlay never pushes
    -- this panel sideways.
    local bottom_margin = margin + math_max(0, tonumber(self.extra_bottom_margin) or 0)
    self.dimen = Geom:new({
        x = math_floor(left),
        y = math_floor(math_max(margin, Screen:getHeight() - bottom_margin - panel_size.h)),
        w = panel_size.w,
        h = panel_size.h,
    })
    self[1] = self.panel
end

function InfoPanelOverlay:onShow()
    UIManager:setDirty(self, "ui", self.dimen)
    return true
end

function InfoPanelOverlay:onCloseWidget()
    if self._quickdock_suppress_close_refresh then
        return
    end
    UIManager:setDirty(nil, "ui", self.dimen)
end

function StatusPanelOverlay:init()
    local panel_size = self.panel:getSize()
    local margin = math_max(0, tonumber(self.screen_margin) or Size.padding.large)
    if self.placement == "top" then
        -- Below the top information panel, or at the top edge without one.
        local top = margin
        local upper_dimen = self.anchor_widget and self.anchor_widget.dimen
        if upper_dimen then
            top = upper_dimen.y + upper_dimen.h + (self.panel_gap or Size.padding.default)
        end
        self.dimen = Geom:new({ x = margin, y = top, w = panel_size.w, h = panel_size.h })
        self[1] = self.panel
        return
    end
    local left = margin
    if self.panel_side == "right" then
        left = Screen:getWidth() - margin - panel_size.w
    end

    -- With an anchor_widget (the panel below), this already stacks above
    -- whatever bottom offset that widget resolved to (extra margin included),
    -- so extra_bottom_margin only needs to apply to the fallback case below.
    local bottom = Screen:getHeight() - margin - math_max(0, tonumber(self.extra_bottom_margin) or 0)
    local lower_dimen = self.anchor_widget and self.anchor_widget.dimen
    if lower_dimen then
        bottom = lower_dimen.y - (self.panel_gap or Size.padding.default)
    end
    self.dimen = Geom:new({
        x = math_floor(left),
        y = math_floor(math_max(margin, bottom - panel_size.h)),
        w = panel_size.w,
        h = panel_size.h,
    })
    self[1] = self.panel
end

function StatusPanelOverlay:onShow()
    UIManager:setDirty(self, "ui", self.dimen)
    return true
end

function StatusPanelOverlay:onCloseWidget()
    if self._quickdock_suppress_close_refresh then
        return
    end
    UIManager:setDirty(nil, "ui", self.dimen)
end

local function safeCall(callback, fallback)
    local ok, result = pcall(callback)
    if ok and result ~= nil then
        return result
    end
    return fallback
end

local function clamp(value, minimum, maximum)
    return math_max(minimum, math_min(maximum, tonumber(value) or minimum))
end

local function maximumPanelWidth(screen_margin)
    screen_margin = math_max(0, tonumber(screen_margin) or Size.padding.large)
    return math_max(
        Screen:scaleBySize(110),
        math_floor(Screen:getWidth() / 2) - 2 * screen_margin
    )
end

local function panelContentWidth(metrics, maximum_outer_width)
    local factor = tonumber(metrics and metrics.scale_factor) or 1
    local padding = math_max(Size.padding.small, math_floor(Screen:scaleBySize(8) * factor + 0.5))
    local screen_short_side = math_min(Screen:getWidth(), Screen:getHeight())
    local width = math_max(
        math_floor((metrics and metrics.button_width or Screen:scaleBySize(54)) * 2.5),
        math_min(math_floor(screen_short_side * 0.34), math_floor(Screen:getWidth() * 0.38))
    )
    local outer_horizontal_space = 2 * (padding + Size.border.button)
    local maximum_content_width = math_max(
        Screen:scaleBySize(90),
        math_floor(tonumber(maximum_outer_width) or Screen:getWidth()) - outer_horizontal_space
    )
    return math_min(width, maximum_content_width)
end

local function freeBlitBuffer(bb)
    if bb and bb.free then
        pcall(bb.free, bb)
    end
end

local function clearCoverCache(plugin)
    local cache = plugin and plugin.info_panel_cover_cache
    if cache then
        freeBlitBuffer(cache.bb)
        plugin.info_panel_cover_cache = nil
    end
end

local function getCover(plugin, ui, metrics, screen_margin, horizontal)
    local document = ui and ui.document
    if not document then
        clearCoverCache(plugin)
        return nil
    end

    local content_width
    local maximum_height
    if horizontal then
        -- A thumbnail beside the text columns of the top panel.
        local factor = tonumber(metrics and metrics.scale_factor) or 1
        maximum_height = math_floor(Screen:scaleBySize(96) * factor + 0.5)
        content_width = math_min(
            math_floor(maximum_height * 0.8),
            math_floor(Screen:getWidth() * 0.18)
        )
    else
        content_width = panelContentWidth(metrics, maximumPanelWidth(screen_margin))
        maximum_height = math_max(
            Screen:scaleBySize(100),
            math_min(math_floor(Screen:getHeight() * 0.26), math_floor(content_width * 1.45))
        )
    end
    local filepath = tostring(document.file or document.filepath or document)
    local cache_key = filepath .. "|" .. tostring(content_width) .. "x" .. tostring(maximum_height)
    local cache = plugin.info_panel_cover_cache
    if cache and cache.key == cache_key then
        return cache.bb and cache or nil
    end

    clearCoverCache(plugin)
    local cover_bb = safeCall(function()
        if ui.bookinfo and type(ui.bookinfo.getCoverImage) == "function" then
            return ui.bookinfo:getCoverImage(document)
        end
        if type(document.getCoverPageImage) == "function" then
            return document:getCoverPageImage()
        end
    end, nil)

    if not cover_bb then
        -- Cache a negative result too, so reopening the dock does not retry an
        -- unavailable cover for the same document and panel dimensions.
        plugin.info_panel_cover_cache = { key = cache_key }
        return nil
    end

    local width = tonumber(safeCall(function() return cover_bb:getWidth() end, nil))
    local height = tonumber(safeCall(function() return cover_bb:getHeight() end, nil))
    if not width or not height or width <= 0 or height <= 0 then
        freeBlitBuffer(cover_bb)
        plugin.info_panel_cover_cache = { key = cache_key }
        return nil
    end

    local scale = math_min(1, content_width / width, maximum_height / height)
    local target_width = math_max(1, math_floor(width * scale + 0.5))
    local target_height = math_max(1, math_floor(height * scale + 0.5))
    if scale < 1 then
        local ok, scaled_bb = pcall(
            RenderImage.scaleBlitBuffer,
            RenderImage,
            cover_bb,
            target_width,
            target_height,
            false
        )
        freeBlitBuffer(cover_bb)
        cover_bb = ok and scaled_bb or nil
    end

    cache = {
        key = cache_key,
        bb = cover_bb,
        width = target_width,
        height = target_height,
    }
    plugin.info_panel_cover_cache = cache
    return cover_bb and cache or nil
end

local function compactDuration(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then
        return nil
    end
    local duration_format = G_reader_settings:readSetting("duration_format", "classic")
    return datetime.secondsToClockDuration(duration_format, seconds, true, false, true)
end

local function pagesLabel(count)
    count = math_max(0, math_floor(tonumber(count) or 0))
    return T(N_("1 page", "%1 pages", count), count)
end

local function primaryAuthor(authors)
    if type(authors) == "table" then
        authors = table.concat(authors, ", ")
    end
    authors = tostring(authors or "")
    local first = authors:match("^%s*([^\n]+)") or ""
    return first:gsub("%s+$", "")
end

local function getBatteryText()
    if not Device:hasBattery() then
        return nil
    end
    local powerd = Device:getPowerDevice()
    if not powerd then
        return nil
    end
    local level = safeCall(function()
        return powerd:getCapacity()
    end, nil)
    if level == nil then
        return nil
    end
    level = math_floor(tonumber(level) or 0)
    local charged = safeCall(function()
        return powerd:isCharged()
    end, false)
    local charging = safeCall(function()
        return powerd:isCharging()
    end, false)
    local symbol = safeCall(function()
        return powerd:getBatterySymbol(charged, charging, level)
    end, "")
    return tostring(symbol or "") .. " " .. tostring(level) .. "%"
end

local function getCurrentPage(ui)
    return math_max(1, math_floor(tonumber(safeCall(function()
        return ui.view.state.page
    end, safeCall(function()
        return ui.document:getCurrentPage()
    end, 1))) or 1))
end

local function getPageCount(ui)
    return math_max(1, math_floor(tonumber(safeCall(function()
        return ui.document:getPageCount()
    end, ui.doc_settings and ui.doc_settings.data and ui.doc_settings.data.doc_pages or 1)) or 1))
end

local function getChapterData(ui, page, book_total)
    local toc = ui.toc
    if not toc then
        return nil
    end

    local title = tostring(safeCall(function()
        return toc:getTocTitleByPage(page)
    end, "") or "")
    local chapter_page
    local chapter_total
    local chapter_left
    local uses_page_labels = safeCall(function()
        return ui.pagemap and ui.pagemap:wantsPageLabels()
    end, false)

    if uses_page_labels then
        -- Keep chapter progress tied to actual page turns even when the book
        -- displays stable page labels, as in the Mini Receipt patch.
        local chapter_start = safeCall(function()
            if toc:isChapterStart(page) then
                return page
            end
            return toc:getPreviousChapter(page)
        end, nil) or 1
        local next_chapter = safeCall(function()
            return toc:getNextChapter(page)
        end, nil) or (book_total + 1)
        chapter_page = page - chapter_start + 1
        chapter_total = math_max(1, next_chapter - chapter_start)
        chapter_left = math_max(0, next_chapter - page - 1)
    else
        local pages_done = safeCall(function()
            return toc:getChapterPagesDone(page)
        end, nil)
        chapter_page = math_max(1, (tonumber(pages_done) or (page - 1)) + 1)
        chapter_total = math_max(1, tonumber(safeCall(function()
            return toc:getChapterPageCount(page)
        end, book_total)) or book_total)
        chapter_left = tonumber(safeCall(function()
            return toc:getChapterPagesLeft(page)
        end, nil))
        if chapter_left == nil then
            chapter_left = chapter_total - chapter_page
        end
        chapter_left = math_max(0, chapter_left)
    end

    return {
        title = title,
        page = chapter_page,
        total = chapter_total,
        left = chapter_left,
        percentage = math_floor(clamp(chapter_page / chapter_total * 100, 0, 100)),
    }
end

local function isStatisticsEnabled(statistics)
    return statistics ~= nil
        and statistics.settings ~= nil
        and statistics.settings.is_enabled == true
end

local function getAveragePageTime(statistics)
    local average = tonumber(statistics.avg_time)
    if not average or average ~= average or average <= 0 then
        return nil
    end
    return average
end

local function getStatisticsData(ui, book_left, chapter_left)
    local statistics = ui and ui.statistics
    if
        not statistics
        or not statistics.settings
        or not statistics.settings.is_enabled
    then
        return nil
    end

    local today_seconds
    local today_pages
    -- Obtain both return values in one protected call. This is the panel's
    -- only statistics query, and it runs only when the dock is opened.
    local ok, seconds, pages = pcall(statistics.getTodayBookStats, statistics)
    if ok then
        today_seconds = tonumber(seconds) or 0
        today_pages = tonumber(pages) or 0
    else
        today_seconds = nil
        today_pages = nil
    end

    local average = getAveragePageTime(statistics)

    return {
        today_pages = today_pages,
        today_duration = compactDuration(today_seconds),
        book_time_left = average and compactDuration((book_left + 1) * average) or nil,
        chapter_time_left = average and chapter_left
            and compactDuration((chapter_left + 1) * average) or nil,
    }
end

local function collect(plugin, metrics, screen_margin, include_cover, horizontal)
    local ui = plugin and plugin.ui or nil
    local data = {
        kind = "reading",
        clock = datetime.secondsToHour(
            os.time(),
            G_reader_settings:isTrue("twelve_hour_clock")
        ),
        battery = getBatteryText(),
    }

    if not ui or not ui.document then
        clearCoverCache(plugin)
        data.statistics = getStatisticsData(ui, 0, nil)
        return data
    end

    local page = getCurrentPage(ui)
    local total = getPageCount(ui)
    local left = math_max(0, total - page)
    local props = ui.doc_props or {}
    data.document = {
        title = tostring(props.display_title or props.title or _("Document")),
        author = primaryAuthor(props.authors or props.author),
        page = page,
        total = total,
        left = left,
        percentage = math_floor(clamp(page / total * 100, 0, 100)),
    }
    data.chapter = getChapterData(ui, page, total)
    data.statistics = getStatisticsData(ui, left, data.chapter and data.chapter.left or nil)
    if include_cover then
        data.cover = getCover(plugin, ui, metrics, screen_margin, horizontal)
    else
        clearCoverCache(plugin)
    end

    if ui.pagemap and safeCall(function()
        return ui.pagemap:wantsPageLabels()
    end, false) then
        data.document.page_label = safeCall(function()
            return ui.pagemap:getCurrentPageLabel(true)
        end, page)
        data.document.total_label = safeCall(function()
            return ui.pagemap:getLastPageLabel(true)
        end, total)
    end
    return data
end

-- KOReader keeps the book's capped reading time and average page time in
-- memory, but not when the book was started or on how many days it was read;
-- only its Statistics database has that. One aggregate, read-only query over
-- the current book, made only while the statistics panel is being collected.
local function queryReadingSpan(statistics)
    local id_book = tonumber(statistics.id_curr_book)
    if not id_book then
        return nil
    end
    local conn
    local ok, first_open, days = pcall(function()
        conn = require("lua-ljsqlite3/init").open(
            require("datastorage"):getSettingsDir() .. "/statistics.sqlite3",
            "ro"
        )
        return conn:rowexec(string.format([[
            SELECT min(start_time),
                   count(DISTINCT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime'))
            FROM   page_stat_data
            WHERE  id_book = %d;
        ]], id_book))
    end)
    if conn then
        pcall(conn.close, conn)
    end
    first_open = ok and tonumber(first_open) or nil
    days = ok and tonumber(days) or nil
    if not first_open or first_open <= 0 or not days or days < 1 then
        return nil
    end
    return first_open, days
end

local function getBookStatistics(ui, page, total)
    local statistics = ui and ui.statistics
    local stats = { enabled = isStatisticsEnabled(statistics) }
    if not stats.enabled then
        return stats
    end

    -- Time and pages still waiting for KOReader's next database flush.
    local pending_time = tonumber(statistics.mem_read_time) or 0
    local read_time = (tonumber(statistics.book_read_time) or 0) + pending_time
    local read_pages = (tonumber(statistics.book_read_pages) or 0)
        + (tonumber(statistics.mem_read_pages) or 0)
    if read_time > 0 then
        stats.read_time = read_time
    end

    -- With no recorded pages KOReader seeds avg_time with a placeholder
    -- (half of the maximum page time), which is not this reader's speed.
    local average = read_pages > 0 and getAveragePageTime(statistics) or nil
    if average then
        stats.pages_per_minute = 60 / average
        stats.time_left = (total - page + 1) * average
    end

    local first_open, days = queryReadingSpan(statistics)
    if not first_open and pending_time > 0 then
        first_open = tonumber(statistics.start_current_period)
        days = 1
    end
    local now = os.time()
    if first_open and first_open > 0 and first_open <= now then
        stats.first_open = first_open
        stats.days_ago = math_floor((now - first_open) / 86400)
        if read_time > 0 then
            stats.daily_average = read_time / days
        end
    end

    if stats.time_left and stats.daily_average then
        stats.finish_date = now + math.ceil(stats.time_left / stats.daily_average) * 86400
    end
    return stats
end

local function collectStats(plugin, metrics, screen_margin, include_cover, horizontal)
    local ui = plugin and plugin.ui or nil
    local data = {
        kind = "stats",
        clock = datetime.secondsToHour(
            os.time(),
            G_reader_settings:isTrue("twelve_hour_clock")
        ),
        battery = getBatteryText(),
    }
    if not ui or not ui.document then
        clearCoverCache(plugin)
        return data
    end

    local page = getCurrentPage(ui)
    local total = getPageCount(ui)
    local props = ui.doc_props or {}
    data.document = {
        title = tostring(props.display_title or props.title or _("Document")),
        author = primaryAuthor(props.authors or props.author),
        percentage = math_floor(clamp(page / total * 100, 0, 100)),
    }
    data.book_stats = getBookStatistics(ui, page, total)
    if include_cover then
        data.cover = getCover(plugin, ui, metrics, screen_margin, horizontal)
    else
        clearCoverCache(plugin)
    end
    return data
end

local function collectNetwork()
    local wifi_on = safeCall(function()
        return NetworkMgr:isWifiOn()
    end, false) == true
    local connected = wifi_on and safeCall(function()
        return NetworkMgr:isConnected()
    end, false) == true
    local connecting = wifi_on and NetworkMgr.pending_connection == true
    local status
    if connecting then
        status = _("Connecting to Wi-Fi…")
    elseif connected then
        status = _("Connected")
    elseif wifi_on then
        status = _("Wi-Fi on, not connected")
    else
        status = _("Wi-Fi off")
    end

    local current_network = wifi_on and safeCall(function()
        return NetworkMgr:getCurrentNetwork()
    end, nil) or nil
    local details
    if wifi_on and type(Device.retrieveNetworkInfo) == "function" then
        details = safeCall(function()
            return Device:retrieveNetworkInfo()
        end, nil)
        if details ~= nil then
            details = tostring(details):gsub("%s+$", "")
            if details == "" then
                details = nil
            end
        end
    end

    return {
        kind = "network",
        clock = datetime.secondsToHour(
            os.time(),
            G_reader_settings:isTrue("twelve_hour_clock")
        ),
        battery = getBatteryText(),
        network = {
            status = status,
            ssid = current_network and current_network.ssid or nil,
            details = details,
        },
    }
end

local function makeText(text, face, width, bold, color, alignment)
    return TextBoxWidget:new({
        text = text,
        face = face,
        bold = bold,
        fgcolor = color or Blitbuffer.COLOR_BLACK,
        width = width,
        alignment = alignment or "left",
        line_height = 0.15,
    })
end

local function addGap(items, height)
    items[#items + 1] = VerticalSpan:new({ width = height })
end

local function addSeparator(items, width, gap)
    addGap(items, gap)
    items[#items + 1] = LineWidget:new({
        background = Blitbuffer.COLOR_GRAY,
        dimen = Geom:new({ w = width, h = math_max(1, Screen:scaleBySize(1)) }),
    })
    addGap(items, gap)
end

-- Lays the panel groups out side by side for the top panel: the cover keeps
-- its width and the text columns share the rest equally, separated by thin
-- vertical rules as tall as the tallest column.
local function buildColumns(groups, content_width, padding, gap, cover)
    local by_column = {}
    local order = {}
    for _index, group in ipairs(groups) do
        if not by_column[group.column] then
            by_column[group.column] = {}
            order[#order + 1] = group.column
        end
        table.insert(by_column[group.column], group)
    end
    table.sort(order)

    local rule_width = math_max(1, Screen:scaleBySize(1))
    local divider_width = 2 * padding + rule_width
    local text_columns = #order
    local available = content_width - (#order - 1) * divider_width
    if by_column[0] then
        text_columns = text_columns - 1
        available = available - cover.width
    end
    local text_width = math_max(
        Screen:scaleBySize(60),
        math_floor(available / math_max(1, text_columns))
    )

    local columns = {}
    local tallest = 0
    for _index, column in ipairs(order) do
        local width = column == 0 and cover.width or text_width
        local items = { align = "left" }
        for index, group in ipairs(by_column[column]) do
            if index > 1 then
                addSeparator(items, width, gap)
            end
            group.render(width, items)
        end
        local widget = VerticalGroup:new(items)
        columns[#columns + 1] = widget
        tallest = math_max(tallest, widget:getSize().h)
    end

    local row = { align = "top" }
    for index, widget in ipairs(columns) do
        if index > 1 then
            row[#row + 1] = HorizontalSpan:new({ width = padding })
            row[#row + 1] = LineWidget:new({
                background = Blitbuffer.COLOR_GRAY,
                dimen = Geom:new({ w = rule_width, h = tallest }),
            })
            row[#row + 1] = HorizontalSpan:new({ width = padding })
        end
        row[#row + 1] = widget
    end
    return HorizontalGroup:new(row)
end

-- The panel content is a list of groups, each one a few related lines. The
-- side panel stacks every group in one column with a separator between them;
-- the top panel (arc dock) places the groups side by side in up to three
-- columns, each group saying in which column it goes. Column 0 holds the
-- cover, which keeps its own width.
local function build(plugin, metrics, parent, maximum_outer_width, data, panel_side, horizontal)
    local factor = tonumber(metrics and metrics.scale_factor) or 1
    local padding = math_max(Size.padding.small, math_floor(Screen:scaleBySize(8) * factor + 0.5))
    local gap = math_max(1, math_floor(Screen:scaleBySize(3) * factor + 0.5))
    local content_width
    if horizontal then
        content_width = math_max(
            Screen:scaleBySize(90),
            math_floor(maximum_outer_width) - 2 * (padding + Size.border.button)
        )
    else
        content_width = panelContentWidth(metrics, maximum_outer_width)
    end
    -- The statistics panel packs more lines than the others, so all of its
    -- fonts (including the shared header and footer) are scaled down together.
    local font_factor = data and data.kind == "stats" and factor * STATS_FONT_SCALE or factor
    local title_face = Font:getFace("infofont", math_floor(16 * font_factor + 0.5))
    local body_face = Font:getFace("smallinfofont", math_floor(13 * font_factor + 0.5))
    local alignment_setting = plugin.getInfoPanelTextAlignment
        and plugin:getInfoPanelTextAlignment()
        or "left"
    local text_alignment = alignment_setting
    if alignment_setting == "screen_edge" then
        text_alignment = panel_side == "right" and "right" or "left"
    elseif alignment_setting ~= "center" then
        text_alignment = "left"
    end
    local function makePanelText(width, text, face, bold, color)
        return makeText(text, face, width, bold, color, text_alignment)
    end
    data = data or collect(plugin)
    local groups = {}
    local function addGroup(column, render)
        groups[#groups + 1] = { column = column, render = render }
    end

    -- Cover, title, and author: the top of both the reading and statistics panels.
    local function addDocumentHeader()
        if data.cover and data.cover.bb then
            addGroup(0, function(width, items)
                items[#items + 1] = CenterContainer:new({
                    dimen = Geom:new({ w = width, h = data.cover.height }),
                    ImageWidget:new({
                        image = data.cover.bb,
                        image_disposable = false,
                        width = data.cover.width,
                        height = data.cover.height,
                    }),
                })
            end)
        end
        addGroup(1, function(width, items)
            items[#items + 1] = makePanelText(width, data.document.title, title_face, true)
            if data.document.author ~= "" then
                addGap(items, gap)
                items[#items + 1] = makePanelText(
                    width,
                    data.document.author,
                    body_face,
                    false,
                    Blitbuffer.COLOR_DARK_GRAY
                )
            end
        end)
    end

    local footer_column = 2
    if data.kind == "network" then
        addGroup(1, function(width, items)
            items[#items + 1] = makePanelText(width, _("Network information"), title_face, true)
            addGap(items, gap)
            items[#items + 1] = makePanelText(width, data.network.status, body_face, true)
            if data.network.ssid and not data.network.details then
                addGap(items, gap)
                items[#items + 1] = makePanelText(
                    width,
                    T(_("SSID: %1"), data.network.ssid),
                    body_face
                )
            end
        end)
        if data.network.details then
            addGroup(2, function(width, items)
                items[#items + 1] = makePanelText(width, data.network.details, body_face)
            end)
            footer_column = 3
        end
    elseif data.kind == "stats" then
        if data.document then
            addDocumentHeader()
            local stats = data.book_stats
            local half_gap = 2 * gap
            local hero_face = Font:getFace("infofont", math_floor(28 * font_factor + 0.5))
            local value_face = Font:getFace("infofont", math_floor(17 * font_factor + 0.5))
            local caption_face = Font:getFace("smallinfofont", math_floor(11 * font_factor + 0.5))
            local gray = Blitbuffer.COLOR_DARK_GRAY

            -- A large value over a small gray caption. Missing values are
            -- flagged with a gray, non-bold "N/A" rather than left out.
            local function statCell(value, caption, width, face)
                return VerticalGroup:new({
                    makeText(value or _("N/A"), face or value_face, width, value ~= nil,
                        value ~= nil and Blitbuffer.COLOR_BLACK or gray, text_alignment),
                    makeText(caption, caption_face, width, false, gray, text_alignment),
                })
            end
            local function statRow(width, left_value, left_caption, right_value, right_caption)
                local half_width = math_floor((width - half_gap) / 2)
                return HorizontalGroup:new({
                    statCell(left_value, left_caption, half_width),
                    HorizontalSpan:new({ width = half_gap }),
                    statCell(right_value, right_caption, half_width),
                })
            end
            local function duration(seconds)
                return seconds and compactDuration(seconds) or nil
            end

            addGroup(1, function(width, items)
                local progress_height = math_max(4, math_floor(Screen:scaleBySize(8) * factor + 0.5))
                items[#items + 1] = statCell(
                    data.document.percentage .. "%", _("Progress"), width, hero_face
                )
                addGap(items, gap)
                items[#items + 1] = ProgressWidget:new({
                    width = width,
                    height = progress_height,
                    percentage = data.document.percentage / 100,
                    margin_h = Screen:scaleBySize(1),
                    margin_v = Screen:scaleBySize(1),
                    radius = math_floor(progress_height / 2),
                    bordersize = Size.border.thin,
                    bgcolor = Blitbuffer.COLOR_WHITE,
                    fillcolor = Blitbuffer.COLOR_BLACK,
                })
            end)

            addGroup(2, function(width, items)
                items[#items + 1] = statRow(
                    width,
                    duration(stats.read_time), _("Time read"),
                    duration(stats.time_left), _("Time left")
                )
                addGap(items, 2 * gap)
                items[#items + 1] = statRow(
                    width,
                    duration(stats.daily_average), _("Daily average"),
                    stats.pages_per_minute and string.format("%.1f", stats.pages_per_minute) or nil,
                    _("Pages/min")
                )
            end)

            addGroup(3, function(width, items)
                -- Not N_: ngettext does not read this plugin's own catalog.
                local started_value, started_caption
                if stats.first_open then
                    if stats.days_ago == 0 then
                        started_value = _("Today")
                    elseif stats.days_ago == 1 then
                        started_value = _("1 day ago")
                    else
                        started_value = T(_("%1 days ago"), stats.days_ago)
                    end
                    started_caption = T(_("Started on %1"), datetime.secondsToDate(stats.first_open, true))
                end
                items[#items + 1] = statCell(started_value, started_caption or _("Started"), width)
                addGap(items, 2 * gap)
                items[#items + 1] = statCell(
                    stats.finish_date and datetime.secondsToDate(stats.finish_date, true) or nil,
                    _("Estimated end"),
                    width
                )
                if not stats.enabled then
                    addGap(items, gap)
                    items[#items + 1] = makePanelText(
                        width,
                        _("Enable KOReader's Statistics plugin to collect reading data."),
                        body_face,
                        false,
                        Blitbuffer.COLOR_DARK_GRAY
                    )
                end
            end)
            footer_column = 3
        else
            addGroup(1, function(width, items)
                items[#items + 1] = makePanelText(width, _("Book statistics"), title_face, true)
                addGap(items, gap)
                items[#items + 1] = makePanelText(
                    width,
                    _("No document is currently open."),
                    body_face,
                    false,
                    Blitbuffer.COLOR_DARK_GRAY
                )
            end)
        end
    elseif data.document then
        addDocumentHeader()

        addGroup(2, function(width, items)
            local page = data.document.page_label or data.document.page
            local total = data.document.total_label or data.document.total
            local book_lines = {
                T(_("Book: %1 / %2  ·  %3%"), page, total, data.document.percentage),
            }
            if data.statistics and data.statistics.book_time_left then
                book_lines[2] = T(_("Remaining: %1"), data.statistics.book_time_left)
            end
            items[#items + 1] = makePanelText(width, table.concat(book_lines, "\n"), body_face)
        end)

        if data.chapter then
            addGroup(2, function(width, items)
                local chapter_title = data.chapter.title ~= ""
                    and data.chapter.title or _("Chapter")
                items[#items + 1] = makePanelText(width, chapter_title, body_face, true)
                addGap(items, gap)
                local chapter_lines = {
                    T(_("Page: %1 / %2  ·  %3%"), data.chapter.page,
                        data.chapter.total, data.chapter.percentage),
                }
                if data.statistics and data.statistics.chapter_time_left then
                    chapter_lines[2] = T(_("Remaining: %1"), data.statistics.chapter_time_left)
                end
                items[#items + 1] = makePanelText(width, table.concat(chapter_lines, "\n"), body_face)
            end)
        end
        footer_column = 3
    else
        addGroup(1, function(width, items)
            items[#items + 1] = makePanelText(width, _("Reading today"), title_face, true)
            addGap(items, gap)
            items[#items + 1] = makePanelText(
                width,
                _("No document is currently open."),
                body_face,
                false,
                Blitbuffer.COLOR_DARK_GRAY
            )
        end)
    end

    if data.statistics and data.statistics.today_pages ~= nil then
        addGroup(footer_column, function(width, items)
            local pages = pagesLabel(data.statistics.today_pages)
            local today = T(_("Today: %1"), pages)
            if data.statistics.today_duration then
                today = T(_("Today: %1  ·  %2"), pages, data.statistics.today_duration)
            end
            items[#items + 1] = makePanelText(width, today, body_face)
        end)
    end

    addGroup(footer_column, function(width, items)
        local status = { data.clock }
        if data.battery then
            status[#status + 1] = data.battery
        end
        items[#items + 1] = makePanelText(
            width,
            table.concat(status, "  ·  "),
            body_face,
            true
        )
    end)

    local content
    if horizontal then
        content = buildColumns(groups, content_width, padding, gap, data.cover)
    else
        local items = {}
        for index, group in ipairs(groups) do
            if index > 1 then
                addSeparator(items, content_width, gap)
            end
            group.render(content_width, items)
        end
        content = VerticalGroup:new(items)
    end

    return FrameContainer:new({
        show_parent = parent,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.button,
        color = Blitbuffer.COLOR_BLACK,
        radius = Size.radius.button,
        margin = 0,
        padding = padding,
        width = horizontal and math_floor(maximum_outer_width) or nil,
        allow_mirroring = false,
        content,
    })
end

local function createOverlay(plugin, metrics, panel_side, screen_margin, data, extra_bottom_margin)
    screen_margin = math_max(0, tonumber(screen_margin) or Size.padding.large)
    local maximum_width = maximumPanelWidth(screen_margin)
    local panel = build(plugin, metrics, nil, maximum_width, data, panel_side)
    local overlay = InfoPanelOverlay:new({
        panel = panel,
        panel_side = panel_side == "left" and "left" or "right",
        screen_margin = screen_margin,
        dithered = data and data.cover ~= nil,
        extra_bottom_margin = extra_bottom_margin,
    })
    panel.show_parent = overlay
    return overlay
end

local function createTopOverlay(plugin, metrics, screen_margin, data)
    screen_margin = math_max(0, tonumber(screen_margin) or Size.padding.large)
    local width = Screen:getWidth() - 2 * screen_margin
    local panel = build(plugin, metrics, nil, width, data, "left", true)
    local overlay = InfoPanelOverlay:new({
        panel = panel,
        placement = "top",
        screen_margin = screen_margin,
        dithered = data and data.cover ~= nil,
    })
    panel.show_parent = overlay
    return overlay
end

local function createStatusOverlay(metrics, panel_side, screen_margin, text, lower_widget, extra_bottom_margin)
    local factor = tonumber(metrics and metrics.scale_factor) or 1
    local padding = math_max(Size.padding.small, math_floor(Screen:scaleBySize(8) * factor + 0.5))
    local content_width = panelContentWidth(metrics, maximumPanelWidth(screen_margin))
    local body_face = Font:getFace("smallinfofont", math_floor(13 * factor + 0.5))
    local panel = FrameContainer:new({
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.button,
        color = Blitbuffer.COLOR_BLACK,
        radius = Size.radius.button,
        margin = 0,
        padding = padding,
        allow_mirroring = false,
        makeText(tostring(text or ""), body_face, content_width, true),
    })
    local overlay = StatusPanelOverlay:new({
        panel = panel,
        panel_side = panel_side == "left" and "left" or "right",
        screen_margin = screen_margin,
        panel_gap = Size.padding.default,
        anchor_widget = lower_widget,
        extra_bottom_margin = extra_bottom_margin,
    })
    panel.show_parent = overlay
    return overlay
end

-- The arc dock's status line: as wide as the top panel, right below it.
local function createTopStatusOverlay(metrics, screen_margin, text, upper_widget)
    screen_margin = math_max(0, tonumber(screen_margin) or Size.padding.large)
    local factor = tonumber(metrics and metrics.scale_factor) or 1
    local padding = math_max(Size.padding.small, math_floor(Screen:scaleBySize(8) * factor + 0.5))
    local width = Screen:getWidth() - 2 * screen_margin
    local body_face = Font:getFace("smallinfofont", math_floor(13 * factor + 0.5))
    local panel = FrameContainer:new({
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.button,
        color = Blitbuffer.COLOR_BLACK,
        radius = Size.radius.button,
        margin = 0,
        padding = padding,
        width = width,
        allow_mirroring = false,
        makeText(
            tostring(text or ""),
            body_face,
            width - 2 * (padding + Size.border.button),
            true
        ),
    })
    local overlay = StatusPanelOverlay:new({
        panel = panel,
        placement = "top",
        screen_margin = screen_margin,
        panel_gap = Size.padding.default,
        anchor_widget = upper_widget,
    })
    panel.show_parent = overlay
    return overlay
end

return {
    build = build,
    clearCoverCache = clearCoverCache,
    collect = collect,
    collectStats = collectStats,
    collectNetwork = collectNetwork,
    createOverlay = createOverlay,
    createStatusOverlay = createStatusOverlay,
    createTopOverlay = createTopOverlay,
    createTopStatusOverlay = createTopStatusOverlay,
}
