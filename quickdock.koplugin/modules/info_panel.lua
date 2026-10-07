local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local datetime = require("datetime")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
local NetworkMgr = require("ui/network/manager")
local ProgressWidget = require("ui/widget/progresswidget")
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local gettext = require("gettext")
local _ = require("quickdock_l10n")
local N_ = _.ngettext
local T = require("ffi/util").template

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local STATS_FONT_SCALE = 0.85
-- Height-to-width ratio of a recent-document cover tile, close to most book
-- covers, so a typical cover fills its tile.
local RECENT_COVER_RATIO = 1.45
-- Share of the screen height the recent-documents grid may take: the side
-- panel shares its edge only with a status block, while the top panel must
-- leave room for the arc dock below it.
local RECENT_SIDE_HEIGHT_SHARE = 0.55
local RECENT_TOP_HEIGHT_SHARE = 0.3

-- A part of the panel that reacts to taps. The panel itself is a non-modal
-- overlay, so the dock forwards taps outside its own area here; the region
-- is only known once the panel has been painted.
local TapTarget = WidgetContainer:extend({})

function TapTarget:getSize()
    return self[1]:getSize()
end

function TapTarget:paintTo(bb, x, y)
    local size = self[1]:getSize()
    self.dimen = Geom:new({ x = x, y = y, w = size.w, h = size.h })
    self[1]:paintTo(bb, x, y)
end

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

-- Called by the dock for taps outside its own area. Returns true when the
-- tap belongs to an interactive panel, so the dock stays open; panels
-- without tap targets keep the usual tap-outside-to-close behavior.
function InfoPanelOverlay:handleTap(pos)
    local targets = self.panel.tap_targets
    if not targets or not pos or not self.dimen or not self.dimen:contains(pos) then
        return false
    end
    for _index, target in ipairs(targets) do
        if target.dimen and target.dimen:contains(pos) then
            if target.callback then
                target.callback()
            end
            return true
        end
    end
    return true
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

local function getBookInfoManager()
    -- Provided by KOReader's Cover browser plugin, whose folder is on the
    -- module path when it is enabled. Its database already holds the
    -- covers and metadata of every book it has shown, so nothing has to be
    -- opened here.
    local ok, manager = pcall(require, "bookinfomanager")
    if ok and type(manager) == "table" and type(manager.getBookInfo) == "function" then
        return manager
    end
    return nil
end

-- The current document's cover from the Cover browser plugin's database,
-- when it holds a thumbnail at least as large as the panel would show the
-- original: reading it is a query and a decompression, while extracting the
-- cover decodes the full-size image (EPUB) or renders the first page (PDF,
-- DjVu). Anything uncertain returns nil, and the cover is extracted as
-- before: no thumbnail, one too small, a document changed since it was
-- indexed, a custom cover (its replacement may not have reached the Cover
-- browser yet), or a cover the user hid there. Nothing is ever indexed here.
local function getIndexedCover(file, content_width, maximum_height)
    local manager = type(file) == "string" and getBookInfoManager() or nil
    if not manager then
        return nil
    end
    local has_custom_cover = safeCall(function()
        return require("docsettings"):findCustomCoverFile(file) ~= nil
    end, true)
    if has_custom_cover then
        return nil
    end
    -- Without the cover first: deciding needs no decompression.
    local bookinfo = safeCall(function()
        return manager:getBookInfo(file, false)
    end, nil)
    if
        type(bookinfo) ~= "table"
        or bookinfo._no_provider
        or not bookinfo.has_cover
        or bookinfo.ignore_cover
        or tonumber(bookinfo.filemtime) ~= lfs.attributes(file, "modification")
    then
        return nil
    end
    local original_width, original_height = tostring(bookinfo.cover_sizetag or ""):match("^(%d+)x(%d+)$")
    original_width, original_height = tonumber(original_width), tonumber(original_height)
    local thumbnail_width, thumbnail_height = tonumber(bookinfo.cover_w), tonumber(bookinfo.cover_h)
    if not (original_width and original_height and thumbnail_width and thumbnail_height)
        or original_width <= 0 or original_height <= 0
    then
        return nil
    end
    -- The size getCover() gives the original, which it never enlarges.
    local scale = math_min(1, content_width / original_width, maximum_height / original_height)
    local needed_width = math_max(1, math_floor(original_width * scale + 0.5))
    local needed_height = math_max(1, math_floor(original_height * scale + 0.5))
    if thumbnail_width < needed_width or thumbnail_height < needed_height then
        return nil
    end
    bookinfo = safeCall(function()
        return manager:getBookInfo(file, true)
    end, nil)
    return type(bookinfo) == "table" and bookinfo.cover_bb or nil
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
    local started = time.now()
    local source = "Cover browser"
    local cover_bb = getIndexedCover(document.file, content_width, maximum_height)
    if not cover_bb then
        source = "document"
        cover_bb = safeCall(function()
            if ui.bookinfo and type(ui.bookinfo.getCoverImage) == "function" then
                return ui.bookinfo:getCoverImage(document)
            end
            if type(document.getCoverPageImage) == "function" then
                return document:getCoverPageImage()
            end
        end, nil)
    end
    logger.dbg("QuickDock: cover from", source, "in",
        time.to_ms(time.since(started)), "ms:", cover_bb ~= nil)

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

local function clearRecentCoverCache(plugin)
    local cache = plugin and plugin.recent_cover_cache
    if cache then
        for _file, entry in pairs(cache) do
            freeBlitBuffer(entry.bb)
        end
        plugin.recent_cover_cache = nil
    end
end

local function fileTitle(file)
    local name = tostring(file or ""):match("([^/]+)$") or tostring(file or "")
    return (name:gsub("%.[^.]+$", ""))
end

-- The cover and title of one recent document, scaled to the tile. Entries
-- are kept while the document stays in the list and the tile size is the
-- same; a document Cover browser has not indexed yet is not cached, so its
-- cover shows up once it has been.
local function getRecentCover(plugin, file, width, height)
    plugin.recent_cover_cache = plugin.recent_cover_cache or {}
    local key = tostring(width) .. "x" .. tostring(height)
    local entry = plugin.recent_cover_cache[file]
    if entry and entry.key == key then
        return entry
    end
    if entry then
        freeBlitBuffer(entry.bb)
        plugin.recent_cover_cache[file] = nil
    end

    local manager = getBookInfoManager()
    local bookinfo = manager and safeCall(function()
        return manager:getBookInfo(file, true)
    end, nil)
    if type(bookinfo) ~= "table" or bookinfo._no_provider then
        return { title = fileTitle(file) }
    end

    entry = {
        key = key,
        title = bookinfo.title and bookinfo.title ~= "" and bookinfo.title or fileTitle(file),
    }
    local cover_bb = bookinfo.cover_bb
    if cover_bb and not bookinfo.ignore_cover then
        local cover_width = tonumber(safeCall(function() return cover_bb:getWidth() end, nil))
        local cover_height = tonumber(safeCall(function() return cover_bb:getHeight() end, nil))
        if cover_width and cover_height and cover_width > 0 and cover_height > 0 then
            local scale = math_min(width / cover_width, height / cover_height)
            local target_width = math_max(1, math_floor(cover_width * scale + 0.5))
            local target_height = math_max(1, math_floor(cover_height * scale + 0.5))
            local ok, scaled_bb = pcall(
                RenderImage.scaleBlitBuffer,
                RenderImage,
                cover_bb,
                target_width,
                target_height,
                false
            )
            if ok and scaled_bb then
                entry.bb = scaled_bb
                entry.width = target_width
                entry.height = target_height
            end
        end
    end
    freeBlitBuffer(cover_bb)
    plugin.recent_cover_cache[file] = entry
    return entry
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

-- Runs read-only queries on KOReader's Statistics database, closing it
-- afterwards. Returns query's results, or nothing when it failed.
local function withStatisticsDatabase(query)
    local conn
    local results = { pcall(function()
        conn = require("lua-ljsqlite3/init").open(
            require("datastorage"):getSettingsDir() .. "/statistics.sqlite3",
            "ro"
        )
        return query(conn)
    end) }
    if conn then
        pcall(conn.close, conn)
    end
    if not results[1] then
        return nil
    end
    return unpack(results, 2, table.maxn(results))
end

-- Pages and seconds read today across all books, as KOReader's
-- ReaderStatistics:getTodayBookStats() counts them: through its page_stat
-- view, which rescales each record to the book's current page count. For
-- that query SQLite picks the (id_book, page, start_time) index, which spares
-- it sorting for the GROUP BY, and scans the whole reading history on every
-- call. The same rescaling is applied here with the start_time index forced,
-- so only today's records are read and that scan is avoided. Should the
-- schema differ (no such index, renamed columns), KOReader's own query is
-- used instead.
local TODAY_STATS_SQL = [[
    SELECT count(*),
           sum(sum_duration)
    FROM   (
                SELECT sum(duration) AS sum_duration
                FROM   (
                            SELECT id_book,
                                   first_page + idx - 1 AS page,
                                   duration / (last_page - first_page + 1) AS duration
                            FROM   (
                                        SELECT id_book,
                                               duration,
                                               ((page - 1) * pages) / total_pages + 1 AS first_page,
                                               max(((page - 1) * pages) / total_pages + 1,
                                                   (page * pages) / total_pages) AS last_page,
                                               idx
                                        FROM   (
                                                    SELECT *
                                                    FROM   page_stat_data
                                                    INDEXED BY page_stat_data_start_time
                                                    WHERE  start_time >= %d
                                               ) AS today
                                        JOIN   book ON book.id = today.id_book
                                        JOIN   (SELECT number AS idx FROM numbers) AS N
                                               ON idx <= (last_page - first_page + 1)
                                   )
                       )
                GROUP  BY id_book, page
           );
]]

local function getTodayStats(statistics)
    local now = os.date("*t")
    local start_today = os.time() - (now.hour * 3600 + now.min * 60 + now.sec)
    local pages, seconds = withStatisticsDatabase(function(conn)
        return conn:rowexec(string.format(TODAY_STATS_SQL, start_today))
    end)
    if pages ~= nil then
        return tonumber(seconds) or 0, tonumber(pages) or 0
    end
    local ok, native_seconds, native_pages = pcall(statistics.getTodayBookStats, statistics)
    if ok then
        return tonumber(native_seconds) or 0, tonumber(native_pages) or 0
    end
    return nil
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

    -- The panel's only statistics query, made only when the dock is opened.
    local today_seconds, today_pages = getTodayStats(statistics)

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
    local first_open, days = withStatisticsDatabase(function(conn)
        return conn:rowexec(string.format([[
            SELECT min(start_time),
                   count(DISTINCT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime'))
            FROM   page_stat_data
            WHERE  id_book = %d;
        ]], id_book))
    end)
    first_open = tonumber(first_open)
    days = tonumber(days)
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

-- The interfaces with their MAC, SSID and addresses, read the way KOReader's
-- own network information reads them, without its gateway ping: that ping is
-- synchronous, blocks the UI until it times out, and keeps the radio busy.
-- Only getifaddrs(), an SSID ioctl and /proc/net/route are used here, so
-- nothing is sent over the network. The labels are KOReader's own, so they
-- keep its translations.
local function getInterfaceDetails()
    local loaded, NetInfo = pcall(require, "ffi/netinfo")
    if not loaded or type(NetInfo) ~= "table" or type(NetInfo.new) ~= "function" then
        return nil
    end
    local has_routes = type(Device.getDefaultRoute) == "function"
    local netinfo
    local ok, lines = pcall(function()
        netinfo = NetInfo:new()
        local results = {}
        for _index, iface in ipairs(netinfo:retrieve()) do
            if #results > 0 then
                results[#results + 1] = ""
            end
            results[#results + 1] = T(gettext("Interface: %1"), iface.name)
            results[#results + 1] = T(gettext("MAC: %1"), iface.mac)
            if iface.wireless then
                if iface.ssid then
                    results[#results + 1] = T(gettext("SSID: \"%1\""), iface.ssid)
                else
                    results[#results + 1] = gettext("SSID: off/any")
                end
            end
            if iface.ipv4 then
                results[#results + 1] = T(gettext("IPv4: %1"), iface.ipv4)
                local gateway = has_routes and safeCall(function()
                    return Device:getDefaultRoute(iface.name)
                end, nil)
                if gateway then
                    results[#results + 1] = T(gettext("Default gateway: %1"), gateway)
                end
            end
            if iface.ipv6 then
                results[#results + 1] = T(gettext("IPv6: %1"), iface.ipv6)
            end
        end
        return results
    end)
    if netinfo then
        pcall(netinfo.free, netinfo)
    end
    if not ok or type(lines) ~= "table" or #lines == 0 then
        return nil
    end
    return table.concat(lines, "\n")
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
    local details = wifi_on and getInterfaceDetails() or nil

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

-- The most recently opened documents from KOReader's history, newest first.
-- Only the list is read here; covers are loaded for the visible page when
-- the panel is built. The document open in the reader is left out, as
-- opening it again would do nothing.
local function collectRecent(plugin, limit)
    local ui = plugin and plugin.ui or nil
    local current_file = ui and ui.document and ui.document.file or nil
    local history = safeCall(function()
        return require("readhistory").hist
    end, {})
    limit = math_max(1, math_floor(tonumber(limit) or 1))

    local documents = {}
    local listed = {}
    for _index, item in ipairs(type(history) == "table" and history or {}) do
        if #documents >= limit then
            break
        end
        local file = type(item) == "table" and item.file or nil
        if
            file
            and not item.dim
            and file ~= current_file
            and not listed[file]
            and lfs.attributes(file, "mode") == "file"
        then
            listed[file] = true
            documents[#documents + 1] = { file = file }
        end
    end

    -- Drop the thumbnails of documents that left the list.
    local cache = plugin and plugin.recent_cover_cache
    if cache then
        for file, entry in pairs(cache) do
            if not listed[file] then
                freeBlitBuffer(entry.bb)
                cache[file] = nil
            end
        end
    end

    return {
        kind = "recent",
        documents = documents,
        page = 1,
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

-- A panel heading that may wrap between words but never inside one: the
-- font shrinks until its longest word fits the width, down to a minimum
-- size, past which the word is cut with an ellipsis. The second result
-- tells whether every word fit.
local MINIMUM_HEADING_SCALE = 0.5

local function makeHeading(text, face, width, alignment)
    local words = {}
    for word in tostring(text):gmatch("%S+") do
        words[#words + 1] = word
    end
    local base_size = tonumber(face.orig_size or face.size) or 16
    local minimum_size = math_max(8, math_floor(base_size * MINIMUM_HEADING_SCALE))
    for size = base_size, minimum_size, -1 do
        local candidate = size == base_size and face or Font:getFace(face.orig_font or "infofont", size)
        local fits = true
        for _index, word in ipairs(words) do
            local probe = TextWidget:new({ text = word, face = candidate, bold = true })
            fits = probe:getSize().w <= width
            probe:free()
            if not fits then
                break
            end
        end
        if fits then
            return makeText(text, candidate, width, true, nil, alignment), true
        end
    end
    return TextWidget:new({
        text = text,
        face = Font:getFace(face.orig_font or "infofont", minimum_size),
        bold = true,
        max_width = width,
    }), false
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

-- A tile per document, laid out in as many rows and columns as fit the
-- panel, with the title and page arrows above. Tapping a tile opens the
-- document; when the documents need more than one page, the arrows turn it
-- in place. Every page keeps the full grid height so the panel does not
-- change size while paging.
local function buildRecent(plugin, metrics, data, content_width, horizontal, faces, tap_targets)
    local factor = tonumber(metrics and metrics.scale_factor) or 1
    local gap = math_max(Size.padding.small, math_floor(Screen:scaleBySize(6) * factor + 0.5))
    local documents = data.documents or {}
    local items = { align = "left" }

    local tile_width, tile_height
    if horizontal then
        tile_height = math_floor(Screen:scaleBySize(110) * factor + 0.5)
        tile_width = math_floor(tile_height / RECENT_COVER_RATIO + 0.5)
    else
        local minimum_width = math_floor(Screen:scaleBySize(64) * factor + 0.5)
        local columns = clamp(math_floor((content_width + gap) / (minimum_width + gap)), 1, 3)
        tile_width = math_floor((content_width - (columns - 1) * gap) / columns)
        tile_height = math_floor(tile_width * RECENT_COVER_RATIO + 0.5)
    end
    local columns = math_max(1, math_floor((content_width + gap) / (tile_width + gap)))
    -- In the wide top panel, full rows spread over the whole width.
    local column_gap = gap
    if horizontal and columns > 1 and #documents >= columns then
        column_gap = math_floor((content_width - columns * tile_width) / (columns - 1))
    end
    local arrow_size = math_floor(Screen:scaleBySize(32) * factor + 0.5)
    local height_share = horizontal and RECENT_TOP_HEIGHT_SHARE or RECENT_SIDE_HEIGHT_SHARE
    local function paginate(header_height)
        local available_height = math_floor(Screen:getHeight() * height_share) - header_height - gap
        local rows = math_max(1, math_floor((available_height + gap) / (tile_height + gap)))
        local per_page = columns * rows
        -- Use only as many rows as the documents need.
        rows = math_max(1, math_min(rows, math.ceil(#documents / columns)))
        if #documents <= per_page then
            per_page = columns * rows
        end
        return rows, per_page, math_max(1, math.ceil(#documents / per_page))
    end

    -- Header: the panel title, and the page arrows when there is more than
    -- one page. The arrows sit beside the title or, when the title's words
    -- would not fit beside them, both are centered on lines of their own.
    local title_text = _("Recent documents")
    local title = makeHeading(title_text, faces.title, content_width)
    local title_height = title:getSize().h
    local rows, per_page, page_count = paginate(math_max(arrow_size, title_height))
    local pager_beside = true
    local beside_title
    if page_count > 1 then
        local widest_counter = TextWidget:new({
            text = T("%1 / %2", page_count, page_count),
            face = faces.body,
        })
        local pager_width = 2 * arrow_size + 2 * gap + widest_counter:getSize().w
        widest_counter:free()
        local beside_width = math_max(1, content_width - pager_width - gap)
        local fits
        beside_title, fits = makeHeading(title_text, faces.title, beside_width)
        if not fits then
            pager_beside = false
            beside_title:free()
            beside_title = nil
            rows, per_page, page_count = paginate(title_height + gap + arrow_size)
        end
    end
    local page = clamp(data.page or 1, 1, page_count)
    data.page = page

    local header
    if page_count > 1 then
        local function arrow(direction, target_page)
            local enabled = target_page >= 1 and target_page <= page_count
            local icon = plugin.getIcon and plugin:getIcon("chevron-" .. direction) or nil
            local widget
            if icon then
                widget = IconWidget:new({
                    icon = not icon:find("/", 1, true) and icon or nil,
                    file = icon:find("/", 1, true) and icon or nil,
                    width = arrow_size,
                    height = arrow_size,
                    dim = not enabled,
                })
            else
                widget = CenterContainer:new({
                    dimen = Geom:new({ w = arrow_size, h = arrow_size }),
                    TextWidget:new({
                        text = direction == "left" and "‹" or "›",
                        face = faces.title,
                        bold = true,
                        fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY,
                    }),
                })
            end
            local target = TapTarget:new({
                callback = enabled and function()
                    plugin:setRecentDocumentsPage(target_page)
                end or nil,
                widget,
            })
            tap_targets[#tap_targets + 1] = target
            return target
        end
        local pager = HorizontalGroup:new({
            align = "center",
            arrow("left", page - 1),
            HorizontalSpan:new({ width = gap }),
            TextWidget:new({
                text = T("%1 / %2", page, page_count),
                face = faces.body,
            }),
            HorizontalSpan:new({ width = gap }),
            arrow("right", page + 1),
        })
        if pager_beside then
            title:free()
            local title_width = math_max(1, content_width - pager:getSize().w - gap)
            header = HorizontalGroup:new({
                align = "center",
                beside_title,
                HorizontalSpan:new({ width = title_width - beside_title:getSize().w + gap }),
                pager,
            })
        else
            -- The title and the arrows, each on its own line, both centered.
            title:free()
            header = VerticalGroup:new({
                align = "center",
                makeHeading(title_text, faces.title, content_width, "center"),
                VerticalSpan:new({ width = gap }),
                pager,
            })
        end
    else
        if beside_title then
            beside_title:free()
        end
        header = title
    end
    items[#items + 1] = header
    addGap(items, gap)

    if #documents == 0 then
        items[#items + 1] = makeText(
            _("No recent documents."),
            faces.body,
            content_width,
            false,
            Blitbuffer.COLOR_DARK_GRAY
        )
        return VerticalGroup:new(items)
    end

    local first = (page - 1) * per_page + 1
    local border = Size.border.thin
    local function makeTile(document)
        local cover = getRecentCover(
            plugin,
            document.file,
            math_max(1, tile_width - 2 * border),
            math_max(1, tile_height - 2 * border)
        )
        local tile
        if cover.bb then
            tile = CenterContainer:new({
                dimen = Geom:new({ w = tile_width, h = tile_height }),
                FrameContainer:new({
                    bordersize = border,
                    color = Blitbuffer.COLOR_DARK_GRAY,
                    padding = 0,
                    margin = 0,
                    ImageWidget:new({
                        image = cover.bb,
                        image_disposable = false,
                        width = cover.width,
                        height = cover.height,
                    }),
                }),
            })
        else
            -- Without a cover, a framed tile with the title.
            local inner_padding = Size.padding.small
            local inner_width = math_max(1, tile_width - 2 * (border + inner_padding))
            local inner_height = math_max(1, tile_height - 2 * (border + inner_padding))
            local function makeTitle(height)
                return TextBoxWidget:new({
                    text = cover.title or fileTitle(document.file),
                    face = faces.caption,
                    width = inner_width,
                    height = height,
                    height_overflow_show_ellipsis = height ~= nil,
                    alignment = "center",
                    bold = true,
                })
            end
            -- Centered when it fits, cut with an ellipsis when it does not.
            local tile_title = makeTitle()
            if tile_title:getSize().h > inner_height then
                tile_title:free()
                tile_title = makeTitle(inner_height)
            end
            tile = FrameContainer:new({
                bordersize = border,
                color = Blitbuffer.COLOR_DARK_GRAY,
                background = Blitbuffer.COLOR_WHITE,
                padding = inner_padding,
                margin = 0,
                CenterContainer:new({
                    dimen = Geom:new({ w = inner_width, h = inner_height }),
                    tile_title,
                }),
            })
        end
        local file = document.file
        local target = TapTarget:new({
            callback = function()
                plugin:openRecentDocument(file)
            end,
            tile,
        })
        tap_targets[#tap_targets + 1] = target
        return target
    end

    for row = 1, rows do
        local row_items = { align = "top" }
        for column = 1, columns do
            local document = documents[first + (row - 1) * columns + column - 1]
            if column > 1 then
                row_items[#row_items + 1] = HorizontalSpan:new({ width = column_gap })
            end
            if document then
                row_items[#row_items + 1] = makeTile(document)
            else
                row_items[#row_items + 1] = HorizontalSpan:new({ width = tile_width })
            end
        end
        if row > 1 then
            addGap(items, gap)
        end
        -- An empty span keeps the height of rows left blank on the last page.
        items[#items + 1] = HorizontalGroup:new({
            VerticalSpan:new({ width = tile_height }),
            HorizontalGroup:new(row_items),
        })
    end
    return VerticalGroup:new(items)
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
    local function makeFrame(content)
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

    if data.kind == "recent" then
        local tap_targets = {}
        local frame = makeFrame(buildRecent(plugin, metrics, data, content_width, horizontal, {
            title = title_face,
            body = body_face,
            caption = Font:getFace("smallinfofont", math_floor(11 * font_factor + 0.5)),
        }, tap_targets))
        frame.tap_targets = tap_targets
        return frame
    end

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
            items[#items + 1] = makeHeading(_("Network information"), title_face, width, text_alignment)
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
                items[#items + 1] = makeHeading(_("Book statistics"), title_face, width, text_alignment)
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
            items[#items + 1] = makeHeading(_("Reading today"), title_face, width, text_alignment)
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

    return makeFrame(content)
end

local function createOverlay(plugin, metrics, panel_side, screen_margin, data, extra_bottom_margin)
    screen_margin = math_max(0, tonumber(screen_margin) or Size.padding.large)
    local maximum_width = maximumPanelWidth(screen_margin)
    local panel = build(plugin, metrics, nil, maximum_width, data, panel_side)
    local overlay = InfoPanelOverlay:new({
        panel = panel,
        panel_side = panel_side == "left" and "left" or "right",
        screen_margin = screen_margin,
        dithered = data and (data.cover ~= nil or data.kind == "recent"),
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
        dithered = data and (data.cover ~= nil or data.kind == "recent"),
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
    clearRecentCoverCache = clearRecentCoverCache,
    collect = collect,
    collectRecent = collectRecent,
    collectStats = collectStats,
    collectNetwork = collectNetwork,
    createOverlay = createOverlay,
    createStatusOverlay = createStatusOverlay,
    createTopOverlay = createTopOverlay,
    createTopStatusOverlay = createTopStatusOverlay,
}
