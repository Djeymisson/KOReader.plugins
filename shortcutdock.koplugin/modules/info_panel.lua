local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local datetime = require("datetime")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local InfoPanelOverlay = WidgetContainer:extend({
    modal = false,
})

local StatusPanelOverlay = WidgetContainer:extend({
    -- Toasts are ignored while UIManager looks for the input target. This
    -- keeps the status block visually above the dock without intercepting its
    -- taps or the controls of a network-selection dialog.
    modal = false,
    toast = true,
})

function InfoPanelOverlay:init()
    local panel_size = self.panel:getSize()
    local margin = math_max(0, tonumber(self.screen_margin) or Size.padding.large)
    local left = margin
    if self.panel_side == "right" then
        left = Screen:getWidth() - margin - panel_size.w
    end
    self.dimen = Geom:new({
        x = math_floor(left),
        y = math_floor(math_max(margin, Screen:getHeight() - margin - panel_size.h)),
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
    if self._shortcutdock_suppress_close_refresh then
        return
    end
    UIManager:setDirty(nil, "ui", self.dimen)
end

function StatusPanelOverlay:init()
    local panel_size = self.panel:getSize()
    local margin = math_max(0, tonumber(self.screen_margin) or Size.padding.large)
    local left = margin
    if self.panel_side == "right" then
        left = Screen:getWidth() - margin - panel_size.w
    end

    local bottom = Screen:getHeight() - margin
    local lower_dimen = self.lower_widget and self.lower_widget.dimen
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
    if self._shortcutdock_suppress_close_refresh then
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

local function getCover(plugin, ui, metrics, screen_margin)
    local document = ui and ui.document
    if not document then
        clearCoverCache(plugin)
        return nil
    end

    local content_width = panelContentWidth(metrics, maximumPanelWidth(screen_margin))
    local maximum_height = math_max(
        Screen:scaleBySize(100),
        math_min(math_floor(Screen:getHeight() * 0.26), math_floor(content_width * 1.45))
    )
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

    local average = tonumber(statistics.avg_time)
    if not average or average ~= average or average <= 0 then
        average = nil
    end

    return {
        today_pages = today_pages,
        today_duration = compactDuration(today_seconds),
        book_time_left = average and compactDuration((book_left + 1) * average) or nil,
        chapter_time_left = average and chapter_left
            and compactDuration((chapter_left + 1) * average) or nil,
    }
end

local function collect(plugin, metrics, screen_margin, include_cover)
    local ui = plugin and plugin.ui or nil
    local data = {
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
        data.cover = getCover(plugin, ui, metrics, screen_margin)
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

local function makeText(text, face, width, bold, color)
    return TextBoxWidget:new({
        text = text,
        face = face,
        bold = bold,
        fgcolor = color or Blitbuffer.COLOR_BLACK,
        width = width,
        alignment = "left",
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

local function build(plugin, metrics, parent, maximum_outer_width, data)
    local factor = tonumber(metrics and metrics.scale_factor) or 1
    local padding = math_max(Size.padding.small, math_floor(Screen:scaleBySize(8) * factor + 0.5))
    local gap = math_max(1, math_floor(Screen:scaleBySize(3) * factor + 0.5))
    local content_width = panelContentWidth(metrics, maximum_outer_width)
    local title_face = Font:getFace("infofont", math_floor(16 * factor + 0.5))
    local body_face = Font:getFace("smallinfofont", math_floor(13 * factor + 0.5))
    data = data or collect(plugin)
    local items = {}

    if data.document then
        if data.cover and data.cover.bb then
            items[#items + 1] = CenterContainer:new({
                dimen = Geom:new({ w = content_width, h = data.cover.height }),
                ImageWidget:new({
                    image = data.cover.bb,
                    image_disposable = false,
                    width = data.cover.width,
                    height = data.cover.height,
                }),
            })
            addSeparator(items, content_width, gap)
        end
        items[#items + 1] = makeText(data.document.title, title_face, content_width, true)
        if data.document.author ~= "" then
            addGap(items, gap)
            items[#items + 1] = makeText(
                data.document.author,
                body_face,
                content_width,
                false,
                Blitbuffer.COLOR_DARK_GRAY
            )
        end
        addSeparator(items, content_width, gap)

        local page = data.document.page_label or data.document.page
        local total = data.document.total_label or data.document.total
        local book_lines = {
            _("Book") .. ": " .. tostring(page) .. " / " .. tostring(total)
                .. "  ·  " .. tostring(data.document.percentage) .. "%",
        }
        if data.statistics and data.statistics.book_time_left then
            book_lines[2] = _("Remaining") .. ": " .. data.statistics.book_time_left
        end
        items[#items + 1] = makeText(table.concat(book_lines, "\n"), body_face, content_width)

        if data.chapter then
            addSeparator(items, content_width, gap)
            local chapter_title = data.chapter.title ~= ""
                and data.chapter.title or _("Chapter")
            items[#items + 1] = makeText(chapter_title, body_face, content_width, true)
            addGap(items, gap)
            local chapter_lines = {
                _("Page") .. ": " .. tostring(data.chapter.page)
                    .. " / " .. tostring(data.chapter.total)
                    .. "  ·  " .. tostring(data.chapter.percentage) .. "%",
            }
            if data.statistics and data.statistics.chapter_time_left then
                chapter_lines[2] = _("Remaining")
                    .. ": " .. data.statistics.chapter_time_left
            end
            items[#items + 1] = makeText(table.concat(chapter_lines, "\n"), body_face, content_width)
        end
    else
        items[#items + 1] = makeText(_("Reading today"), title_face, content_width, true)
        addGap(items, gap)
        items[#items + 1] = makeText(
            _("No document is currently open."),
            body_face,
            content_width,
            false,
            Blitbuffer.COLOR_DARK_GRAY
        )
    end

    if data.statistics and data.statistics.today_pages ~= nil then
        addSeparator(items, content_width, gap)
        local today = _("Today") .. ": " .. pagesLabel(data.statistics.today_pages)
        if data.statistics.today_duration then
            today = today .. "  ·  " .. data.statistics.today_duration
        end
        items[#items + 1] = makeText(today, body_face, content_width)
    end

    addSeparator(items, content_width, gap)
    local status = { data.clock }
    if data.battery then
        status[#status + 1] = data.battery
    end
    items[#items + 1] = makeText(table.concat(status, "  ·  "), body_face, content_width, true)

    return FrameContainer:new({
        show_parent = parent,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.button,
        color = Blitbuffer.COLOR_BLACK,
        radius = Size.radius.button,
        margin = 0,
        padding = padding,
        allow_mirroring = false,
        VerticalGroup:new(items),
    })
end

local function createOverlay(plugin, metrics, panel_side, screen_margin, data)
    screen_margin = math_max(0, tonumber(screen_margin) or Size.padding.large)
    local maximum_width = maximumPanelWidth(screen_margin)
    local panel = build(plugin, metrics, nil, maximum_width, data)
    local overlay = InfoPanelOverlay:new({
        panel = panel,
        panel_side = panel_side == "left" and "left" or "right",
        screen_margin = screen_margin,
        dithered = data and data.cover ~= nil,
    })
    panel.show_parent = overlay
    return overlay
end

local function createStatusOverlay(metrics, panel_side, screen_margin, text, lower_widget)
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
        lower_widget = lower_widget,
    })
    panel.show_parent = overlay
    return overlay
end

return {
    build = build,
    clearCoverCache = clearCoverCache,
    collect = collect,
    createOverlay = createOverlay,
    createStatusOverlay = createStatusOverlay,
}
