local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local math_max = math.max

local SETTINGS_DIR = DataStorage:getSettingsDir()
local HISTORY_FILE = SETTINGS_DIR .. "/lookup_history.lua"
local VOCABULARY_FILE = SETTINGS_DIR .. "/vocabulary_builder.sqlite3"
local PREVIEWS_FILE = SETTINGS_DIR .. "/quickdock_lookup_previews.lua"
-- KOReader appends every lookup to its history as one LookupHistoryEntry{...}
-- record (LuaData), so the latest lookups are at the end of the file. Only
-- its last bytes are read, more of it only when they hold too few words.
local ENTRY_MARKER = "LookupHistoryEntry"
local HISTORY_TAIL_SIZES = { 8192, 65536, math.huge }
-- Previews kept: a few more than the panel lists, for words looked up again.
local MAX_PREVIEWS = 50
local PREVIEW_LENGTH = 160
-- Only the start of a definition is cleaned up for its preview.
local DEFINITION_SCAN_LENGTH = 2048

-- One record's table, evaluated in an empty environment; nil when it is not
-- a complete table, such as the record cut at the start of a tail.
local function readRecord(chunk)
    local loader = loadstring("return " .. chunk)
    if not loader then
        return nil
    end
    setfenv(loader, {})
    local ok, record = pcall(loader)
    if ok and type(record) == "table" then
        return record
    end
    return nil
end

local function copyArray(source)
    local entries = {}
    for _index, entry in ipairs(type(source) == "table" and source or {}) do
        entries[#entries + 1] = entry
    end
    return entries
end

-- The lookups in text, oldest first, applying its records the way LuaData
-- does. The second result tells whether they reach back to the start of the
-- history: the start of the file, or a record replacing everything before it
-- (KOReader rewrites the file when the history is cleared).
local function parseHistory(text, from_start)
    local entries = {}
    local complete = from_start
    local position = text:find(ENTRY_MARKER, 1, true)
    while position do
        local next_position = text:find(ENTRY_MARKER, position + #ENTRY_MARKER, true)
        local record = readRecord(text:sub(position + #ENTRY_MARKER, next_position and next_position - 1 or -1))
        if record then
            if record.index == nil then
                entries = copyArray(record.lookup_history)
                complete = true
            elseif record.index == "lookup_history" then
                local values = {}
                for _key, value in pairs(type(record.data) == "table" and record.data or {}) do
                    values[#values + 1] = value
                end
                if #values == 1 then
                    entries[#entries + 1] = values[1]
                else
                    entries = copyArray(record.data)
                    complete = true
                end
            end
        end
        position = next_position
    end
    return entries, complete
end

local function readTail(size)
    local file = io.open(HISTORY_FILE, "rb")
    if not file then
        return nil
    end
    local length = file:seek("end") or 0
    local offset = math_max(0, length - size)
    file:seek("set", offset)
    local text = file:read("*a")
    file:close()
    return text, offset == 0
end

-- The newest lookup of each word, newest first, at most limit of them.
local function latestWords(entries, limit)
    local words = {}
    local listed = {}
    for index = #entries, 1, -1 do
        if #words >= limit then
            break
        end
        local entry = entries[index]
        local word = type(entry) == "table" and type(entry.word) == "string" and entry.word or ""
        local key = word:lower()
        if word ~= "" and not listed[key] then
            listed[key] = true
            words[#words + 1] = {
                word = word,
                time = tonumber(entry.time),
                book_title = entry.book_title,
            }
        end
    end
    return words
end

-- A definition as one line of plain text, without the headword many
-- dictionaries repeat at its start.
local function previewText(word, definition, is_html)
    local text = definition:sub(1, DEFINITION_SCAN_LENGTH)
    if is_html then
        -- Tags become spaces, so the lines of a definition stay apart.
        text = util.htmlEntitiesToUtf8(text:gsub("<[^>]*>", " "):gsub("<[^>]*$", ""))
    end
    text = text:gsub("\u{00A0}", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local lower_word = word:lower()
    if text:sub(1, #word):lower() == lower_word and text:sub(#word + 1, #word + 1):match("^[%s%p]") then
        text = text:sub(#word + 1):gsub("^[%s%p]+", "")
    end
    if #text > PREVIEW_LENGTH then
        -- Cut before a character, never inside its UTF-8 bytes.
        local cut = PREVIEW_LENGTH
        local byte = text:byte(cut + 1)
        while cut > 0 and byte >= 128 and byte < 192 do
            cut = cut - 1
            byte = text:byte(cut + 1)
        end
        text = text:sub(1, cut)
    end
    return text
end

-- The recent dictionary lookups (KOReader's lookup history), whether their
-- words are in the Vocabulary Builder, and the definition previews saved as
-- the words were looked up. Loaded once by main.lua, so the caches here are
-- shared by the reader's and the file browser's plugin instances.
return function()
    local Lookups = {}

    -- The words last read from the history, with the file size and time they
    -- were read at: the history is only read again once a lookup changed it.
    local history_cache

    function Lookups.recent(limit)
        local attributes = lfs.attributes(HISTORY_FILE)
        if type(attributes) ~= "table" or attributes.mode ~= "file" then
            history_cache = nil
            return {}
        end
        if
            history_cache
            and history_cache.size == attributes.size
            and history_cache.modification == attributes.modification
            and history_cache.limit >= limit
        then
            return { unpack(history_cache.words, 1, math.min(limit, #history_cache.words)) }
        end

        local words = {}
        for _index, size in ipairs(HISTORY_TAIL_SIZES) do
            local text, from_start = readTail(size)
            if not text then
                return {}
            end
            local entries, complete = parseHistory(text, from_start)
            words = latestWords(entries, limit)
            if complete or #words >= limit then
                break
            end
        end
        history_cache = {
            size = attributes.size,
            modification = attributes.modification,
            limit = limit,
            words = words,
        }
        return { unpack(words) }
    end

    -- Which of words are in KOReader's Vocabulary Builder, with one read-only
    -- query over its database. nil when it cannot be read.
    function Lookups.vocabularyWords(words)
        if #words == 0 or lfs.attributes(VOCABULARY_FILE, "mode") ~= "file" then
            return nil
        end
        local quoted = {}
        for index, word in ipairs(words) do
            quoted[index] = "'" .. (word:gsub("'", "''")) .. "'"
        end
        local found = {}
        local conn
        local ok, err = pcall(function()
            conn = require("lua-ljsqlite3/init").open(VOCABULARY_FILE, "ro")
            local result = conn:exec(
                "SELECT word FROM vocabulary WHERE word IN (" .. table.concat(quoted, ",") .. ");"
            )
            for _index, word in ipairs(result and result[1] or {}) do
                found[tostring(word)] = true
            end
        end)
        if conn then
            pcall(conn.close, conn)
        end
        if not ok then
            logger.dbg("QuickDock: could not read the vocabulary builder:", err)
            return nil
        end
        return found
    end

    -- Definition previews by word, loaded on first use and written back only
    -- when KOReader flushes its settings.
    local preview_store
    local previews_changed = false

    local function getPreviews()
        if not preview_store then
            local ok, store = pcall(LuaSettings.open, LuaSettings, PREVIEWS_FILE)
            if not ok or type(store) ~= "table" or type(store.data) ~= "table" then
                logger.warn("QuickDock: could not read the lookup previews:", store)
                store = LuaSettings:open(PREVIEWS_FILE)
                store.data = {}
            end
            preview_store = store
        end
        return preview_store.data
    end

    function Lookups.getPreview(word)
        local entry = getPreviews()[word]
        if type(entry) == "table" and type(entry.text) == "string" then
            return entry.text
        end
        return nil
    end

    -- Keeps the start of the first definition found for word, dropping the
    -- oldest previews past MAX_PREVIEWS.
    function Lookups.recordPreview(word, results)
        if type(word) ~= "string" or word == "" or type(results) ~= "table" then
            return
        end
        for _index, result in ipairs(results) do
            if type(result) == "table" and not result.no_result and type(result.definition) == "string" then
                local text = previewText(word, result.definition, result.is_html)
                if text ~= "" then
                    local previews = getPreviews()
                    previews[word] = { text = text, time = os.time() }
                    previews_changed = true
                    local count = 0
                    local oldest_word, oldest_time
                    for saved_word, entry in pairs(previews) do
                        count = count + 1
                        local saved_time = type(entry) == "table" and tonumber(entry.time) or 0
                        if not oldest_time or saved_time < oldest_time then
                            oldest_word, oldest_time = saved_word, saved_time
                        end
                    end
                    if count > MAX_PREVIEWS then
                        previews[oldest_word] = nil
                    end
                    return
                end
            end
        end
    end

    function Lookups.flushPreviews()
        if previews_changed and preview_store then
            previews_changed = false
            pcall(preview_store.flush, preview_store)
        end
    end

    return Lookups
end
