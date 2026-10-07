local Device = require("device")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

-- Book covers for the information panel: the open document's, cached on the
-- plugin as info_panel_cover_cache, and the recent documents' thumbnails,
-- cached per file as recent_cover_cache.
return function(Util)
    local safeCall = Util.safeCall
    local freeBlitBuffer = Util.freeBlitBuffer

    local Covers = {}

    function Covers.clearCoverCache(plugin)
        local cache = plugin and plugin.info_panel_cover_cache
        if cache then
            freeBlitBuffer(cache.bb)
            plugin.info_panel_cover_cache = nil
        end
    end

    function Covers.clearRecentCoverCache(plugin)
        local cache = plugin and plugin.recent_cover_cache
        if cache then
            for _file, entry in pairs(cache) do
                freeBlitBuffer(entry.bb)
            end
            plugin.recent_cover_cache = nil
        end
    end

    -- Drops the thumbnails of documents no longer listed (a set of files).
    function Covers.pruneRecentCovers(plugin, listed)
        local cache = plugin and plugin.recent_cover_cache
        if not cache then
            return
        end
        for file, entry in pairs(cache) do
            if not listed[file] then
                freeBlitBuffer(entry.bb)
                cache[file] = nil
            end
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

    -- The box the open document's cover is fitted in: beside the text columns
    -- of the top panel (horizontal), or above the text of a side panel.
    local function getCoverBox(metrics, screen_margin, horizontal)
        if horizontal then
            local maximum_height = Util.scaled(metrics, 96)
            local content_width = math_min(
                math_floor(maximum_height * 0.8),
                math_floor(Screen:getWidth() * 0.18)
            )
            return content_width, maximum_height
        end
        local content_width = Util.panelContentWidth(metrics, Util.maximumPanelWidth(screen_margin))
        local maximum_height = math_max(
            Screen:scaleBySize(100),
            math_min(math_floor(Screen:getHeight() * 0.26), math_floor(content_width * 1.45))
        )
        return content_width, maximum_height
    end

    -- The open document's cover, scaled to the panel: { bb, width, height }, or
    -- nil without one. Kept while the document and the box stay the same; a
    -- missing cover is remembered too, so it is not looked for again.
    function Covers.getCover(plugin, ui, metrics, screen_margin, horizontal)
        local document = ui and ui.document
        if not document then
            Covers.clearCoverCache(plugin)
            return nil
        end

        local content_width, maximum_height = getCoverBox(metrics, screen_margin, horizontal)
        local filepath = tostring(document.file or document.filepath or document)
        local cache_key = filepath .. "|" .. tostring(content_width) .. "x" .. tostring(maximum_height)
        local cache = plugin.info_panel_cover_cache
        if cache and cache.key == cache_key then
            return cache.bb and cache or nil
        end

        Covers.clearCoverCache(plugin)
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

        local width, height
        if cover_bb then
            cover_bb, width, height = Util.fitImage(cover_bb, content_width, maximum_height, false)
        end
        if not cover_bb then
            plugin.info_panel_cover_cache = { key = cache_key }
            return nil
        end
        cache = {
            key = cache_key,
            bb = cover_bb,
            width = width,
            height = height,
        }
        plugin.info_panel_cover_cache = cache
        return cache
    end

    -- Whether Cover browser's answer about a cover is final: there is none
    -- to show because the user hid it, or because it was looked for and not
    -- found. Until then (not looked for yet, extraction still in progress)
    -- the cover may still come.
    local function isCoverFinallyMissing(bookinfo)
        return bookinfo.ignore_cover
            or (bookinfo.cover_fetched
                and not bookinfo.has_cover
                and (tonumber(bookinfo.in_progress) or 0) == 0)
    end

    -- The cover and title of one recent document, scaled to the tile. Only
    -- final results are kept, while the document stays in the list and the
    -- tile size is the same: a cover, or the lack of one Cover browser will
    -- not change. A document it has not indexed yet, a cover it has not
    -- extracted yet and one that could not be read are looked up again next
    -- time, so the cover shows up once available.
    function Covers.getRecentCover(plugin, file, width, height)
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
            return { title = Util.fileTitle(file) }
        end

        entry = {
            key = key,
            title = bookinfo.title and bookinfo.title ~= "" and bookinfo.title or Util.fileTitle(file),
        }
        local cover_bb = bookinfo.cover_bb
        if cover_bb then
            if bookinfo.ignore_cover then
                freeBlitBuffer(cover_bb)
            else
                entry.bb, entry.width, entry.height = Util.fitImage(cover_bb, width, height, true)
            end
        end
        if entry.bb or isCoverFinallyMissing(bookinfo) then
            plugin.recent_cover_cache[file] = entry
        end
        return entry
    end

    return Covers

end
