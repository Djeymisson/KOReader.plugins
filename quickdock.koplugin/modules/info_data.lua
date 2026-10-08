local datetime = require("datetime")
local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local lfs = require("libs/libkoreader-lfs")
local gettext = require("gettext")
local _ = require("quickdock_l10n")
local T = require("ffi/util").template

local math_floor = math.floor
local math_max = math.max

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

-- What each information panel mode shows, collected when the dock opens or
-- the panel is switched. Collectors return plain tables; info_render.lua
-- turns them into widgets.
return function(Util, Covers)
    local safeCall = Util.safeCall
    local clamp = Util.clamp
    local compactDuration = Util.compactDuration

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

    -- The clock and battery shown at the bottom of every panel but the recent
    -- documents.
    local function baseData(kind)
        return {
            kind = kind,
            clock = datetime.secondsToHour(
                os.time(),
                G_reader_settings:isTrue("twelve_hour_clock")
            ),
            battery = getBatteryText(),
        }
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

    -- Title, author and progress of the open document.
    local function getDocumentHeader(ui, page, total)
        local props = ui.doc_props or {}
        return {
            title = tostring(props.display_title or props.title or _("Document")),
            author = primaryAuthor(props.authors or props.author),
            percentage = math_floor(clamp(page / total * 100, 0, 100)),
        }
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
        if not isStatisticsEnabled(statistics) then
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

    -- The cover shown with the reading and statistics panels, when enabled.
    local function getCover(plugin, ui, options)
        if options.include_cover then
            return Covers.getCover(plugin, ui, options.metrics, options.screen_margin, options.horizontal)
        end
        Covers.clearCoverCache(plugin)
        return nil
    end

    local function collectReading(plugin, options)
        local ui = plugin and plugin.ui or nil
        local data = baseData("reading")

        if not ui or not ui.document then
            Covers.clearCoverCache(plugin)
            data.statistics = getStatisticsData(ui, 0, nil)
            return data
        end

        local page = getCurrentPage(ui)
        local total = getPageCount(ui)
        local left = math_max(0, total - page)
        data.document = getDocumentHeader(ui, page, total)
        data.document.page = page
        data.document.total = total
        data.document.left = left
        data.chapter = getChapterData(ui, page, total)
        data.statistics = getStatisticsData(ui, left, data.chapter and data.chapter.left or nil)
        data.cover = getCover(plugin, ui, options)

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

    local function collectStats(plugin, options)
        local ui = plugin and plugin.ui or nil
        local data = baseData("stats")
        if not ui or not ui.document then
            Covers.clearCoverCache(plugin)
            return data
        end

        local page = getCurrentPage(ui)
        local total = getPageCount(ui)
        data.document = getDocumentHeader(ui, page, total)
        data.book_stats = getBookStatistics(ui, page, total)
        data.cover = getCover(plugin, ui, options)
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

    local function collectNetwork(plugin)
        local state_hint = plugin and plugin.network_state_hint or nil
        local wifi_on = safeCall(function()
            return NetworkMgr:isWifiOn()
        end, false) == true
        local connected = wifi_on and safeCall(function()
            return NetworkMgr:isConnected()
        end, false) == true
        -- NetworkMgr broadcasts NetworkConnecting before setting
        -- pending_connection, and NetworkConnected before clearing it, so a
        -- completed connection wins over the pending flag, and the event that
        -- triggered the refresh wins over both.
        local status
        if state_hint == "connecting" then
            status = _("Connecting to Wi-Fi…")
        elseif connected then
            status = _("Connected")
        elseif wifi_on and NetworkMgr.pending_connection == true then
            status = _("Connecting to Wi-Fi…")
        elseif wifi_on then
            status = _("Wi-Fi on, not connected")
        else
            status = _("Wi-Fi off")
        end

        local current_network = wifi_on and safeCall(function()
            return NetworkMgr:getCurrentNetwork()
        end, nil) or nil
        local details = wifi_on and getInterfaceDetails() or nil

        local data = baseData("network")
        data.network = {
            status = status,
            ssid = current_network and current_network.ssid or nil,
            details = details,
        }
        return data
    end

    -- The most recently opened documents from KOReader's history, newest first.
    -- Only the list is read here; covers are loaded for the visible page when
    -- the panel is built. The document open in the reader is left out, as
    -- opening it again would do nothing.
    local function collectRecent(plugin, options)
        local ui = plugin and plugin.ui or nil
        local current_file = ui and ui.document and ui.document.file or nil
        local history = safeCall(function()
            return require("readhistory").hist
        end, {})
        local limit = math_max(1, math_floor(tonumber(options.recent_count) or 1))

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
        Covers.pruneRecentCovers(plugin, listed)

        return {
            kind = "recent",
            documents = documents,
            page = 1,
        }
    end

    -- One collector per mode kind (C.INFO_PANEL_MODES). options holds metrics,
    -- screen_margin, include_cover, horizontal and recent_count.
    local COLLECTORS = {
        reading = collectReading,
        stats = collectStats,
        recent = collectRecent,
        network = collectNetwork,
    }

    local InfoData = {}

    function InfoData.collect(kind, plugin, options)
        return (COLLECTORS[kind] or collectReading)(plugin, options or {})
    end

    return InfoData

end
