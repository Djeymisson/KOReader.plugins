local InfoMessage = require("ui/widget/infomessage")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local _ = require("quickdock_l10n")

return function(QuickDock, constants)
    local ACTION_CONTEXT_READER = constants.ACTION_CONTEXT_READER
    local ACTION_CONTEXT_BROWSER = constants.ACTION_CONTEXT_BROWSER

function QuickDock:isReaderContext()
    return self.ui and self.ui.document ~= nil
end

function QuickDock:getLoadedBookshelfWidget()
    -- Use already-loaded Bookshelf modules to keep this integration optional
    -- and avoid loading the plugin merely because Quick Dock is opened.
    local BookshelfWidget = package.loaded["lib/bookshelf_widget"]
        or package.loaded["bookshelf_widget"]
    local live_widget = type(BookshelfWidget) == "table" and BookshelfWidget.live or nil
    if
        not live_widget
        or type(UIManager.isWidgetShown) ~= "function"
    then
        return nil
    end

    local shown_ok, shown = pcall(UIManager.isWidgetShown, UIManager, live_widget)
    if not shown_ok or not shown then
        return nil
    end

    return live_widget
end

function QuickDock:getActiveBookshelfWidget()
    local live_widget = self:getLoadedBookshelfWidget()
    if not live_widget then
        return nil
    end

    -- Bookshelf deliberately remains in UIManager's stack after a parked
    -- reader is resumed. In that state isWidgetShown() is still true, but the
    -- ReaderUI that owns this plugin is above Bookshelf and is the active
    -- context. Compare both positions so context-sensitive search targets the
    -- screen actually in the foreground.
    local stack = UIManager._window_stack
    if type(stack) == "table" then
        local bookshelf_index
        local host_index
        for index, window in ipairs(stack) do
            local widget = type(window) == "table" and window.widget or nil
            if widget == live_widget then
                bookshelf_index = index
            elseif widget == self.ui then
                host_index = index
            end
        end

        if not bookshelf_index then
            return nil
        elseif host_index then
            return bookshelf_index > host_index and live_widget or nil
        end
    end

    -- Compatibility fallback for UIManager implementations whose stack is
    -- unavailable or does not expose the host widget. In reader context,
    -- Bookshelf is active only while that reader is parked.
    if self:isReaderContext() then
        local Park = package.loaded["lib/bookshelf_reader_park"]
            or package.loaded["bookshelf_reader_park"]
        if type(Park) ~= "table" or type(Park.isParked) ~= "function" then
            return nil
        end
        local parked_ok, parked = pcall(Park.isParked)
        if not parked_ok or not parked then
            return nil
        end
    end

    return live_widget
end

function QuickDock:getParkedBookshelfContext()
    -- Bookshelf keeps ReaderUI alive while showing its full-screen widget, so
    -- self.ui.document alone cannot distinguish the shelf from the reader.
    local live_widget = self:getActiveBookshelfWidget()
    local Park = package.loaded["lib/bookshelf_reader_park"]
        or package.loaded["bookshelf_reader_park"]
    if
        not live_widget
        or type(Park) ~= "table"
        or type(Park.isParked) ~= "function"
        or type(Park.unpark) ~= "function"
    then
        return nil
    end

    local parked_ok, parked = pcall(Park.isParked)
    if parked_ok and parked then
        return {
            park = Park,
            widget = live_widget,
        }
    end
end

function QuickDock:getCurrentActionContext()
    if self:getParkedBookshelfContext() then
        return ACTION_CONTEXT_BROWSER
    end
    return self:isReaderContext() and ACTION_CONTEXT_READER or ACTION_CONTEXT_BROWSER
end

function QuickDock:onQuickDockContextHome()
    local bookshelf = self:getParkedBookshelfContext()
    if bookshelf then
        local ok, resumed = pcall(bookshelf.park.unpark, bookshelf.widget)
        if not ok or resumed == false then
            UIManager:show(InfoMessage:new({
                text = _("Could not return to the reader."),
            }))
        end
        return true
    end

    if self:isReaderContext() then
        UIManager:broadcastEvent(Event:new("Home"))
    else
        UIManager:broadcastEvent(Event:new("OpenLastDoc"))
    end
    return true
end

function QuickDock:onQuickDockContextSearch()
    local bookshelf = self:getActiveBookshelfWidget()
    if bookshelf and type(bookshelf._openSearchDialog) == "function" then
        local ok = pcall(bookshelf._openSearchDialog, bookshelf)
        if ok then
            return true
        end
    end

    local event = self:isReaderContext() and "ShowFulltextSearchInput" or "ShowFileSearch"
    UIManager:broadcastEvent(Event:new(event))
    return true
end

function QuickDock:openBookshelfRecent()
    local active_bookshelf = self:getActiveBookshelfWidget()
    local bookshelf = active_bookshelf

    -- When a book was opened from Bookshelf, its widget remains alive below
    -- ReaderUI. History should return to that same widget and select Recent,
    -- instead of falling through to KOReader's native history screen.
    local show_bookshelf = false
    if not bookshelf and self:isReaderContext() then
        bookshelf = self:getLoadedBookshelfWidget()
        if not bookshelf then
            return false
        end
        show_bookshelf = true
    end

    if not bookshelf then
        return false
    end

    local scoped_select_chip = bookshelf._setActiveChip
    local full_select_chip = bookshelf._selectChip
    if
        type(scoped_select_chip) ~= "function"
        and type(full_select_chip) ~= "function"
    then
        return false
    end

    local recent_id = "recent"
    local TabModel = package.loaded["lib/bookshelf_tab_model"]
        or package.loaded["bookshelf_tab_model"]
    if type(TabModel) == "table" and type(TabModel.load) == "function" then
        local loaded_ok, tabs = pcall(TabModel.load)
        if loaded_ok and type(tabs) == "table" then
            recent_id = nil
            for _, tab in ipairs(tabs) do
                if type(tab) == "table" and tab.source and tab.source.kind == "recent" then
                    recent_id = tab.id
                    break
                end
            end
            if not recent_id then
                return false
            end
        end
    end

    local function selectRecentChip()
        -- Prefer Bookshelf's scoped refresh, then retry with the older full
        -- selector if this version cannot use the scoped method in its current
        -- widget state.
        if type(scoped_select_chip) == "function" then
            local ok = pcall(scoped_select_chip, bookshelf, recent_id)
            if ok then
                return true
            end
        end
        if type(full_select_chip) == "function" and full_select_chip ~= scoped_select_chip then
            return pcall(full_select_chip, bookshelf, recent_id)
        end
        return false
    end

    if show_bookshelf then
        -- Follow the same Home event path as the fixed context button. The
        -- Bookshelf reader plugin consumes this event before ReaderUI and
        -- raises its widget through the parking fast path. Broadcasting is
        -- more reliable than looking for the plugin instance on self.ui,
        -- whose registration key varies across KOReader/Bookshelf versions.
        UIManager:broadcastEvent(Event:new("Home"))

        -- Bookshelf's parking path schedules its own warm refresh on the next
        -- UI tick. Queue the tab switch after it, so selection happens with
        -- the shelf in front and both refreshes can be coalesced.
        UIManager:nextTick(selectRecentChip)
        return true
    end

    return selectRecentChip()
end

end
