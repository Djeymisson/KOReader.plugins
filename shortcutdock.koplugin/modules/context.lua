local InfoMessage = require("ui/widget/infomessage")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

return function(ShortcutDock, constants)
    local ACTION_CONTEXT_READER = constants.ACTION_CONTEXT_READER
    local ACTION_CONTEXT_BROWSER = constants.ACTION_CONTEXT_BROWSER

function ShortcutDock:isReaderContext()
    return self.ui and self.ui.document ~= nil
end

function ShortcutDock:getActiveBookshelfWidget()
    -- Use already-loaded Bookshelf modules to keep this integration optional
    -- and avoid loading the plugin merely because Shortcut Dock is opened.
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

    -- Bookshelf deliberately remains in UIManager's stack after a parked
    -- reader is resumed. In that state isWidgetShown() is still true, but the
    -- ReaderUI that owns this plugin is above Bookshelf and is the active
    -- context. Compare both positions so search and history target the screen
    -- actually in the foreground.
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

function ShortcutDock:getParkedBookshelfContext()
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

function ShortcutDock:getCurrentActionContext()
    if self:getParkedBookshelfContext() then
        return ACTION_CONTEXT_BROWSER
    end
    return self:isReaderContext() and ACTION_CONTEXT_READER or ACTION_CONTEXT_BROWSER
end

function ShortcutDock:onShortcutDockContextHome()
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

function ShortcutDock:onShortcutDockContextSearch()
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

function ShortcutDock:openBookshelfRecent()
    local bookshelf = self:getActiveBookshelfWidget()
    if not bookshelf then
        return false
    end

    local select_chip = bookshelf._selectChip or bookshelf._setActiveChip
    if type(select_chip) ~= "function" then
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

    local ok = pcall(select_chip, bookshelf, recent_id)
    return ok
end

end
