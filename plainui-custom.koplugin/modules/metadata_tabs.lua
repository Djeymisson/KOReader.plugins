-- SPDX-FileCopyrightText: 2026 Anh Do
-- SPDX-License-Identifier: MIT

local userpatch = require("userpatch")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local LeftContainer = require("ui/widget/container/leftcontainer")
local MetadataFacetDropdown = require("modules.metadata_facet_dropdown")
local NetworkMgr = require("ui/network/manager")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local StatusIndicators = require("modules.status_indicators")
local TabOptionDialog = require("modules.tab_option_dialog")
local TabOptionPresenter = require("modules.tab_option_presenter")
local TabViewOptions = require("modules.tab_view_options")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local VirtualPath = require("modules.virtual_path")
local _ = require("gettext")
local Screen = Device.screen
local Size = require("ui/size")

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")
local AUTHOR_SYMBOL = VirtualPath.AUTHOR_SYMBOL
local SERIES_SYMBOL = VirtualPath.SERIES_SYMBOL
local TAG_SYMBOL = VirtualPath.KEYWORD_SYMBOL

-- Move the metadata navigation tabs (Files/Series/Authors/Tags) from the
-- title bar to the bottom footer, centered below the page navigation controls.
local PLAINUI_TABS_AT_BOTTOM = true
local PLAINUI_BOTTOM_FONT_SIZE = 22
local PLAINUI_SIDE_MARGIN = Screen:scaleBySize(14)
local PLAINUI_FOLDER_TITLE_FONT_SIZE = PLAINUI_BOTTOM_FONT_SIZE
local PLAINUI_FOLDER_TITLE_PADDING_V = Screen:scaleBySize(3)

local function getMetadataLeafInfo(path)
    local base_dir, active_dimension, filter_state = VirtualPath.parse(path)
    if active_dimension then
        return
    end

    local leaf = VirtualPath.getLeafEntry(filter_state)
    if not leaf then
        return
    end

    local title = VirtualPath.displayValue(leaf.value)

    return {
        title = title,
        parent_path = VirtualPath.buildPreviousFilterPath(base_dir, filter_state),
    }
end

local function getVirtualBaseDir(file_manager)
    local path = file_manager.file_chooser and file_manager.file_chooser.path
    return VirtualPath.getVirtualBaseDir(path)
end

local function openBooks(file_manager)
    local base_dir = getVirtualBaseDir(file_manager)
    if base_dir and file_manager.file_chooser then
        file_manager.file_chooser:changeToPath(base_dir)
    else
        file_manager:onHome()
    end
end

local function browseByMetadata(file_manager, kind)
    if file_manager.onBrowseByMetadata then
        file_manager:onBrowseByMetadata(kind)
    end
end

local function getSelectedTabKey(file_manager)
    local path = file_manager and file_manager.file_chooser and file_manager.file_chooser.path
    local fragments = VirtualPath.getFragments(path)
    if not fragments then
        return "books"
    end

    for _, fragment in ipairs(fragments) do
        if fragment == AUTHOR_SYMBOL then
            return "authors"
        elseif fragment == SERIES_SYMBOL then
            return "series"
        elseif fragment == TAG_SYMBOL then
            return "tags"
        end
    end

    return "books"
end

local BOOKS_FILTER_STATUS = {
    unread = "new",
    reading = "reading",
    finished = "complete",
}

local BOOKS_SORT_COLLATE = {
    recent = "access",
    title = "title",
    progress = "percent_natural",
}
local TAB_SELECTED_SUFFIX = " \u{25be}"
local TAB_UNSELECTED_SUFFIX = "  "
local CHECKBOX_CHECKED = "\u{2611}"
local CHECKBOX_UNCHECKED = "\u{2610}"
local OPTION_RADIO_WIDTH = 2 * Size.padding.large + Screen:scaleBySize(22)
local OPTION_COUNT_WIDTH = 2 * Size.padding.large + Screen:scaleBySize(48)
local CHECKBOX_WIDTH = 2 * Size.padding.large + Screen:scaleBySize(22)
local tab_options_label_width

local function measureTextWidth(text, font_face, font_size, bold)
    local widget = TextWidget:new{
        text = text,
        face = Font:getFace(font_face, font_size),
        bold = bold or false,
    }
    local width = widget:getSize().w
    widget:free()
    return width
end

local function getTabOptionsLabelWidth()
    if not tab_options_label_width then
        tab_options_label_width = math.max(
            measureTextWidth(TabOptionPresenter.getSummaryLabel("filter"), "cfont", 20, false),
            measureTextWidth(TabOptionPresenter.getSummaryLabel("sort"), "cfont", 20, false)
        ) + 2 * Size.padding.large + Screen:scaleBySize(4)
    end
    return tab_options_label_width
end

local function getMetadataFilterCounts(file_manager, tab_key)
    if not TabViewOptions.isMetadataTab(tab_key) then
        return
    end

    local file_chooser = file_manager and file_manager.file_chooser
    local path = file_chooser and file_chooser.path
    if VirtualPath.getTabKey(path) ~= tab_key then
        return
    end

    local base_dir, _active_dimension, filter_state = VirtualPath.parse(path)
    if not base_dir then
        return
    end

    local MetadataSource = require("modules.metadata_source")
    local BookInfoManager = require("bookinfomanager")
    return MetadataSource.getStatusFilterCounts(
        BookInfoManager,
        base_dir,
        filter_state,
        TabViewOptions.getMetadataOptions(tab_key)
    )
end

local function isVirtualPath(path)
    return VirtualPath.findRoot(path) ~= nil
end

local function isFileManagerBooksChooser(file_chooser)
    if not file_chooser
            or file_chooser.name ~= "filemanager"
            or isVirtualPath(file_chooser.path) then
        return false
    end

    local file_manager = FileManager.instance
    return not file_manager
        or file_chooser.ui == file_manager
        or file_manager.file_chooser == file_chooser
end

local function showFileWithBooksOptions(file_chooser, filename, fullpath)
    for _, pattern in ipairs(file_chooser.exclude_files) do
        if filename:match(pattern) then
            return false
        end
    end
    if not file_chooser.show_unsupported
            and file_chooser.file_filter ~= nil
            and not file_chooser.file_filter(filename) then
        return false
    end

    local filter = TabViewOptions.get("books").filter
    if filter == "all" then
        return true
    end

    local status = BOOKS_FILTER_STATUS[filter]
    if not status or not fullpath then
        return true
    end

    local BookList = require("ui/widget/booklist")
    return BookList.getBookStatus(fullpath) == status
end

local function getBackTitleBarInfo(file_manager)
    local path = file_manager and file_manager.file_chooser and file_manager.file_chooser.path
    local leaf_info = getMetadataLeafInfo(path)
    if not leaf_info then
        return
    end

    return {
        title = leaf_info.title,
        parent_path = leaf_info.parent_path,
        current_path = path,
    }
end

local function normalizePlainUIPath(path)
    if not path then
        return
    end
    while #path > 1 and path:sub(-1) == "/" do
        path = path:sub(1, -2)
    end
    return path
end

local function getConfiguredHomeDir()
    local home_dir
    if G_reader_settings and G_reader_settings.readSetting then
        home_dir = G_reader_settings:readSetting("home_dir")
    end
    if home_dir and home_dir ~= "" then
        return home_dir
    end
    return Device.home_dir
end

local function getCurrentFolderTitle(file_manager)
    local file_chooser = file_manager and file_manager.file_chooser
    local path = file_chooser and file_chooser.path
    if not path or isVirtualPath(path) then
        return ""
    end

    local normalized_path = normalizePlainUIPath(path)
    local normalized_home = normalizePlainUIPath(getConfiguredHomeDir())
    if normalized_home and normalized_path == normalized_home then
        return _("Home")
    end

    local title = normalized_path and normalized_path:match("([^/]+)$")
    if title and title ~= "" then
        return title
    end
    return _("Home")
end

local ModeLeftContainer = LeftContainer:extend{
    visible_func = nil,
}

function ModeLeftContainer:isVisible()
    return self.visible_func == nil or self.visible_func()
end

function ModeLeftContainer:paintTo(bb, x, y)
    if self:isVisible() then
        return LeftContainer.paintTo(self, bb, x, y)
    end
end

function ModeLeftContainer:handleEvent(event)
    if self:isVisible() then
        return LeftContainer.handleEvent(self, event)
    end
    return false
end

local MetadataTabsTitleBar = OverlapGroup:extend{
    show_parent = nil,
    right_icon = nil,
    right_icon_tap_callback = function() end,
    right_icon_hold_callback = function() end,
}

function MetadataTabsTitleBar:init()
    self.show_parent = self.show_parent or self
    self.width = Screen:getWidth()
    self.icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE)
    self.button_padding = Screen:scaleBySize(5)
    self.tab_padding_h = Screen:scaleBySize(7)
    self.tab_padding_v = Screen:scaleBySize(5)
    self.tab_font_face = "smallinfofont"
    self.tab_font_size = 18
    self.status_padding_h = Screen:scaleBySize(7)
    self.status_gap = self.tab_padding_h
    self.titlebar_height = self.icon_size + self.button_padding * 2
    self.header_primary_height = self.titlebar_height

    self.file_manager = self.file_manager or FileManager.instance
    local file_manager = self.file_manager
    local function getTextWidth(text, bold)
        local face = Font:getFace(self.tab_font_face, self.tab_font_size)
        local widget = TextWidget:new{
            text = text,
            face = face,
            bold = bold or false,
        }
        local width = widget:getSize().w
        widget:free()
        return width
    end
    local function getTabWidth(text)
        local selected_text = text .. TAB_SELECTED_SUFFIX
        local unselected_text = text .. TAB_UNSELECTED_SUFFIX
        local width = math.max(
            getTextWidth(unselected_text, false),
            getTextWidth(unselected_text, true),
            getTextWidth(selected_text, true)
        ) + 2 * self.tab_padding_h
        return width
    end
    local function makeTab(key, text, callback, hold_callback)
        local tab_width = getTabWidth(text)
        local button = Button:new{
            text = text,
            text_font_face = self.tab_font_face,
            text_font_size = self.tab_font_size,
            text_font_bold = false,
            width = tab_width,
            bordersize = 0,
            padding_h = self.tab_padding_h,
            padding_v = self.tab_padding_v,
            callback = function()
                if self.selected_tab_key == key then
                    self:showTabOptions(key)
                else
                    callback()
                end
            end,
            hold_callback = hold_callback,
            show_parent = self.show_parent,
        }
        local tab = VerticalGroup:new{
            align = "center",
            button,
        }
        tab.key = key
        tab.text = text
        tab.button = button
        return tab
    end

    self.books_tab = makeTab("books", _("Files"), function()
        openBooks(file_manager)
    end, function()
        file_manager:onShowFolderMenu()
    end)
    self.series_tab = makeTab("series", _("Series"), function()
        browseByMetadata(file_manager, "series")
    end)
    self.authors_tab = makeTab("authors", _("Authors"), function()
        browseByMetadata(file_manager, "author")
    end)
    self.tags_tab = makeTab("tags", _("Tags"), function()
        browseByMetadata(file_manager, "tags")
    end)
    self.books_button = self.books_tab.button
    self.series_button = self.series_tab.button
    self.authors_button = self.authors_tab.button
    self.tags_button = self.tags_tab.button
    self.tabs_by_key = {
        books = self.books_tab,
        series = self.series_tab,
        authors = self.authors_tab,
        tags = self.tags_tab,
    }
    self.tab_label_height = self.books_button.label_container.dimen.h
    self.back_chevron_hit_width = self.tab_label_height + self.tab_padding_h
    self.tabs_group = HorizontalGroup:new{
        align = "bottom",
        allow_mirroring = false,
        self.books_tab,
        self.series_tab,
        self.authors_tab,
        self.tags_tab,
    }
    local tabs_size = self.tabs_group:getSize()
    if not PLAINUI_TABS_AT_BOTTOM then
        self.titlebar_height = math.max(self.titlebar_height, tabs_size.h)
        self.header_primary_height = self.titlebar_height
    end

    if PLAINUI_TABS_AT_BOTTOM then
        local folder_sample = TextWidget:new{
            text = "W",
            face = Font:getFace(self.tab_font_face, PLAINUI_FOLDER_TITLE_FONT_SIZE),
            bold = true,
        }
        self.folder_title_label_height = folder_sample:getSize().h
        folder_sample:free()
        self.folder_title_button = Button:new{
            text = "",
            align = "center",
            text_font_face = self.tab_font_face,
            text_font_size = PLAINUI_FOLDER_TITLE_FONT_SIZE,
            text_font_bold = true,
            avoid_text_truncation = false,
            width = math.max(1, self.width - 2 * PLAINUI_SIDE_MARGIN),
            height = self.folder_title_label_height,
            bordersize = 0,
            padding_h = self.tab_padding_h,
            padding_v = PLAINUI_FOLDER_TITLE_PADDING_V,
            show_parent = self.show_parent,
        }
        self.folder_title_row = HorizontalGroup:new{
            align = "bottom",
            allow_mirroring = false,
            HorizontalSpan:new{ width = PLAINUI_SIDE_MARGIN },
            self.folder_title_button,
            HorizontalSpan:new{ width = PLAINUI_SIDE_MARGIN },
        }
        local folder_title_size = self.folder_title_row:getSize()
        self.folder_title_height = folder_title_size.h
        self.titlebar_height = self.header_primary_height + self.folder_title_height
    end
    local titlebar_body_height = self.titlebar_height
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = titlebar_body_height,
    }

    self.tabs_stack = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = math.max(0, titlebar_body_height - tabs_size.h) },
        self.tabs_group,
    }
    self.tabs_container = ModeLeftContainer:new{
        allow_mirroring = false,
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = self.width,
            h = titlebar_body_height,
        },
        visible_func = function()
            return not PLAINUI_TABS_AT_BOTTOM and self.back_title_info == nil
        end,
        self.tabs_stack,
    }
    table.insert(self, self.tabs_container)
    self:updateSelectedTab(false)

    if PLAINUI_TABS_AT_BOTTOM and self.folder_title_row then
        self.folder_title_top_spacer = VerticalSpan:new{ width = self.header_primary_height }
        self.folder_title_stack = VerticalGroup:new{
            align = "left",
            self.folder_title_top_spacer,
            self.folder_title_row,
        }
        self.folder_title_container = LeftContainer:new{
            allow_mirroring = false,
            dimen = Geom:new{
                x = 0,
                y = 0,
                w = self.width,
                h = titlebar_body_height,
            },
            self.folder_title_stack,
        }
        table.insert(self, self.folder_title_container)
        self:updateFolderTitle(false)
    end

    local status_widths = StatusIndicators.getWidths(self.tab_font_face, self.tab_font_size, self.status_padding_h)
    self.night_mode_width = status_widths.night_mode
    self.frontlight_width = status_widths.frontlight
    self.wifi_width = status_widths.wifi
    self.battery_width = status_widths.battery
    self.status_width = self.night_mode_width + self.frontlight_width + self.wifi_width + self.battery_width + 3 * self.status_gap
    self.night_mode_button = Button:new{
        text = StatusIndicators.NIGHT_MODE_SYMBOL,
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.night_mode_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            UIManager:broadcastEvent(Event:new("ToggleNightMode"))
        end,
        show_parent = self.show_parent,
    }
    self.frontlight_button = Button:new{
        text = StatusIndicators.getFrontlightText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.frontlight_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            if Device:hasFrontlight() then
                UIManager:broadcastEvent(Event:new("ShowFlDialog"))
            end
        end,
        hold_callback = function()
            if Device:hasFrontlight() then
                UIManager:broadcastEvent(Event:new("ToggleFrontlight"))
                self:refreshStatusIndicators()
            end
        end,
        show_parent = self.show_parent,
    }
    self.wifi_button = Button:new{
        text = StatusIndicators.getWifiText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.wifi_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            StatusIndicators.toggleWifi(function()
                self:updateStatusIndicators()
            end)
        end,
        hold_callback = function()
            StatusIndicators.showWifiNetworks(function()
                self:updateStatusIndicators()
            end)
        end,
        show_parent = self.show_parent,
    }
    self.battery_button = Button:new{
        text = StatusIndicators.getBatteryText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.battery_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        hold_callback = function()
            StatusIndicators.showBatteryInfo()
            self:updateStatusIndicators()
        end,
        show_parent = self.show_parent,
    }
    local status_row_items = {
        align = "bottom",
        allow_mirroring = false,
    }
    table.insert(status_row_items, self.night_mode_button)
    table.insert(status_row_items, HorizontalSpan:new{ width = self.status_gap })
    table.insert(status_row_items, self.frontlight_button)
    table.insert(status_row_items, HorizontalSpan:new{ width = self.status_gap })
    table.insert(status_row_items, self.wifi_button)
    table.insert(status_row_items, HorizontalSpan:new{ width = self.status_gap })
    table.insert(status_row_items, self.battery_button)
    self.status_row = HorizontalGroup:new(status_row_items)
    self.status_group = VerticalGroup:new{
        align = "right",
        self.status_row,
    }
    self.status_stack = VerticalGroup:new{
        align = "right",
        VerticalSpan:new{ width = math.max(0, titlebar_body_height - self.status_group:getSize().h) },
        self.status_group,
    }
    self.status_container = RightContainer:new{
        allow_mirroring = false,
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = self.width,
            h = titlebar_body_height,
        },
        self.status_stack,
    }
    if not PLAINUI_TABS_AT_BOTTOM then
        table.insert(self, self.status_container)
    end

    self.back_title_width = self.width - self.status_width - self.tab_padding_h
    self.back_button = Button:new{
        text = "",
        align = "left",
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = true,
        avoid_text_truncation = false,
        width = self.back_title_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = 0,
        padding_v = self.tab_padding_v,
        callback = function()
            MetadataFacetDropdown.show(file_manager, function()
                return self:getDropdownAnchor()
            end)
        end,
        show_parent = self.show_parent,
    }
    self.back_chevron_button = Button:new{
        icon = "chevron.left",
        align = "left",
        icon_width = self.tab_label_height,
        icon_height = self.tab_label_height,
        width = self.back_chevron_hit_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = 0,
        padding_v = self.tab_padding_v,
        callback = function()
            self:onBackTitleTap()
        end,
        show_parent = self.show_parent,
    }
    self.back_button.width = self.back_title_width - self.back_chevron_button:getSize().w
    self.back_button:init()
    self.back_row = HorizontalGroup:new{
        align = "bottom",
        allow_mirroring = false,
        self.back_chevron_button,
        self.back_button,
    }
    self.back_title_group = VerticalGroup:new{
        align = "left",
        self.back_row,
    }
    self.back_stack = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = math.max(0, titlebar_body_height - self.back_title_group:getSize().h) },
        self.back_title_group,
    }
    self.back_container = ModeLeftContainer:new{
        allow_mirroring = false,
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = self.width,
            h = titlebar_body_height,
        },
        visible_func = function()
            return not PLAINUI_TABS_AT_BOTTOM and self.back_title_info ~= nil
        end,
        self.back_stack,
    }
    table.insert(self, self.back_container)
    self:updateBackTitle(false)

    self.dimen.h = self.titlebar_height

    -- Compatibility for callers that anchor popups on title_bar.left_button.image.dimen.
    self.left_button = {
        image = {
            dimen = self.books_button[1].dimen or self.books_button.dimen,
        },
    }

    OverlapGroup.init(self)
end

function MetadataTabsTitleBar:updateBackTitle(refresh)
    local file_manager = self.file_manager or FileManager.instance
    local back_title_info = getBackTitleBarInfo(file_manager)
    local title = back_title_info and back_title_info.title or nil
    if self.back_title == title then
        return
    end

    self.back_title_info = back_title_info
    self.back_title = title
    self.back_button:setText(title and title .. " \u{25be}" or "", self.back_button.width)

    if refresh ~= false then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function MetadataTabsTitleBar:onBackTitleTap()
    local file_manager = self.file_manager or FileManager.instance
    local file_chooser = file_manager and file_manager.file_chooser
    local back_title_info = getBackTitleBarInfo(file_manager)
    if file_chooser and back_title_info then
        file_chooser:changeToPath(back_title_info.parent_path, back_title_info.current_path)
    end
end

function MetadataTabsTitleBar:getDropdownAnchor()
    local button = self.back_button
    return button and button[1] and button[1].dimen or button and button.dimen, true
end

function MetadataTabsTitleBar:getTabDropdownAnchor(tab_key)
    local tab = self.tabs_by_key and self.tabs_by_key[tab_key]
    local button = tab and tab.button
    return button and button[1] and button[1].dimen or button and button.dimen, true
end

function MetadataTabsTitleBar:refreshForTabOptionChange()
    local file_manager = self.file_manager or FileManager.instance
    local file_chooser = file_manager and file_manager.file_chooser
    if file_chooser then
        file_chooser:refreshPath()
    else
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function MetadataTabsTitleBar:showTabOptions(tab_key, anchor)
    anchor = anchor or function()
        return self:getTabDropdownAnchor(tab_key)
    end
    local options = TabViewOptions.get(tab_key)
    local sort_value = tab_key == "books" and options.sort or options.folder_sort
    local dialog
    local function showValues(field)
        if dialog then
            UIManager:close(dialog)
        end
        self:showTabOptionValues(tab_key, field, anchor)
    end
    local function makeSummaryRow(label, value, field)
        return {
            {
                text = label,
                align = "left",
                font_bold = false,
                no_vertical_sep = true,
                width = getTabOptionsLabelWidth(),
                callback = function()
                    showValues(field)
                end,
            },
            {
                text = value,
                align = "left",
                font_bold = true,
                callback = function()
                    showValues(field)
                end,
            },
        }
    end
    local buttons = {
        makeSummaryRow(
            TabOptionPresenter.getSummaryLabel("filter"),
            TabOptionPresenter.getFilterLabel(options.filter),
            "filter"
        ),
        makeSummaryRow(
            TabOptionPresenter.getSummaryLabel("sort"),
            TabOptionPresenter.getSortLabel(sort_value, tab_key),
            "sort"
        ),
    }
    if tab_key == "books" and options.filter ~= "legacy" then
        local function toggleExcludeFolders()
            if dialog then
                UIManager:close(dialog)
            end
            TabViewOptions.set("books", "exclude_folders", not TabViewOptions.get("books").exclude_folders)
            self:refreshForTabOptionChange()
            self:showTabOptions(tab_key, anchor)
        end
        table.insert(buttons, {})
        table.insert(buttons, {
            {
                text = TabViewOptions.get("books").exclude_folders and CHECKBOX_CHECKED or CHECKBOX_UNCHECKED,
                align = "center",
                font_bold = false,
                no_vertical_sep = true,
                width = CHECKBOX_WIDTH,
                callback = toggleExcludeFolders,
            },
            {
                text = _("Exclude folders"),
                align = "left",
                font_bold = false,
                callback = toggleExcludeFolders,
            },
        })
    end
    dialog = ButtonDialog:new{
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = anchor,
    }
    UIManager:show(dialog)
end

function MetadataTabsTitleBar:showTabOptionValues(tab_key, field, anchor)
    local option_field = TabOptionPresenter.getOptionField(tab_key, field)
    local options = TabViewOptions.get(tab_key)
    local current_value = options[option_field]
    local filter_counts
    if field == "filter" then
        filter_counts = getMetadataFilterCounts(self.file_manager or FileManager.instance, tab_key)
    end
    TabOptionDialog.showValues{
        anchor = anchor,
        values = TabOptionPresenter.getFieldValues(tab_key, field),
        current_value = current_value,
        radio_width = OPTION_RADIO_WIDTH,
        count_width = OPTION_COUNT_WIDTH,
        getLabel = function(value)
            return TabOptionPresenter.getValueLabel(tab_key, field, value)
        end,
        getCount = filter_counts and function(value)
            return filter_counts[value]
        end or nil,
        onBack = function()
            self:showTabOptions(tab_key, anchor)
        end,
        onSelect = function(value)
            TabViewOptions.set(tab_key, option_field, value)
            self:refreshForTabOptionChange()
        end,
        onSelected = function()
            self:showTabOptionValues(tab_key, field, anchor)
        end,
    }
end

function MetadataTabsTitleBar:updateStatusIndicators(refresh)
    if not self.battery_button then
        return
    end

    local battery_text = StatusIndicators.getBatteryText()
    local wifi_text = StatusIndicators.getWifiText()
    local frontlight_text = StatusIndicators.getFrontlightText()
    if self.battery_text == battery_text
            and self.wifi_text == wifi_text
            and self.frontlight_text == frontlight_text then
        return
    end

    self.battery_text = battery_text
    self.wifi_text = wifi_text
    self.frontlight_text = frontlight_text
    self.battery_button:setText(battery_text, self.battery_width)
    self.wifi_button:setText(wifi_text, self.wifi_width)
    self.frontlight_button:setText(frontlight_text, self.frontlight_width)
    if refresh ~= false then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function MetadataTabsTitleBar:refreshStatusIndicators()
    self:updateStatusIndicators(false)
    UIManager:setDirty(self.show_parent, "ui", self.dimen)
end

function MetadataTabsTitleBar:setTabSelected(tab, selected)
    local text = tab.text .. (selected and TAB_SELECTED_SUFFIX or TAB_UNSELECTED_SUFFIX)
    if tab.button.text_font_bold ~= selected then
        tab.button.text_font_bold = selected
        tab.button.text = text
        tab.button.label_widget:free()
        tab.button:init()
        return
    end
    tab.button:setText(text, tab.button.width)
end

function MetadataTabsTitleBar:updateSelectedTab(refresh)
    local file_manager = self.file_manager or FileManager.instance
    local selected_tab_key = getSelectedTabKey(file_manager)
    if selected_tab_key == self.selected_tab_key then
        return
    end

    self.selected_tab_key = selected_tab_key
    for _, tab in ipairs({ self.books_tab, self.series_tab, self.authors_tab, self.tags_tab }) do
        self:setTabSelected(tab, tab.key == selected_tab_key)
    end

    if refresh ~= false then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function MetadataTabsTitleBar:updateFolderTitle(refresh)
    if not self.folder_title_button then
        return
    end

    local title = getCurrentFolderTitle(self.file_manager or FileManager.instance)
    if self.folder_title == title then
        return
    end

    self.folder_title = title
    self.folder_title_button:setText(title or "", self.folder_title_button.width)
    if refresh ~= false and self.dimen then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function MetadataTabsTitleBar:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    self:updateBackTitle(false)
    self:updateSelectedTab(false)
    self:updateStatusIndicators(false)
    self:updateFolderTitle(false)
    OverlapGroup.paintTo(self, bb, x, y)
    if self.books_button and self.books_button[1] and self.books_button[1].dimen then
        self.left_button.image.dimen = self.books_button[1].dimen
    end
end

function MetadataTabsTitleBar:getHeight()
    return self.titlebar_height
end

function MetadataTabsTitleBar:installPageControls(page_controls, header_status)
    if not page_controls or self._plainui_header_page_controls then
        return
    end

    local controls_size = page_controls:getSize()
    local status_size = header_status and header_status:getSize() or nil
    local folder_extra_height = self.folder_title_height or 0
    local primary_height = self.header_primary_height or math.max(0, self.titlebar_height - folder_extra_height)
    local max_primary_height = primary_height
    if controls_size and controls_size.h then
        max_primary_height = math.max(max_primary_height, controls_size.h)
    end
    if status_size and status_size.h then
        max_primary_height = math.max(max_primary_height, status_size.h)
    end
    if max_primary_height > primary_height then
        self.header_primary_height = max_primary_height
        self.titlebar_height = max_primary_height + folder_extra_height
        if self.folder_title_top_spacer then
            self.folder_title_top_spacer.width = max_primary_height
        end
        if self.folder_title_container and self.folder_title_container.dimen then
            self.folder_title_container.dimen.h = self.titlebar_height
        end
        if self.dimen then
            self.dimen.h = self.titlebar_height
        end
    end

    local header_dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width or Screen:getWidth(),
        h = self.header_primary_height or self.titlebar_height,
    }

    -- Left side: 24h clock, battery and Wi-Fi indicator.
    if header_status then
        self._plainui_header_status = header_status
        self._plainui_header_status_container = LeftContainer:new{
            allow_mirroring = false,
            dimen = header_dimen,
            header_status,
        }
        table.insert(self, self._plainui_header_status_container)
    end

    -- Right side: page navigation buttons plus the page indicator, with a small
    -- side margin so the last button is not glued to the screen edge.
    local padded_page_controls = HorizontalGroup:new{
        align = "center",
        allow_mirroring = false,
        page_controls,
        HorizontalSpan:new{ width = PLAINUI_SIDE_MARGIN },
    }
    self._plainui_header_page_controls = RightContainer:new{
        allow_mirroring = false,
        dimen = header_dimen,
        padded_page_controls,
    }
    table.insert(self, self._plainui_header_page_controls)
end

function MetadataTabsTitleBar:setTitle()
end

function MetadataTabsTitleBar:setSubTitle()
    self:updateBackTitle()
    self:updateSelectedTab()
    self:updateStatusIndicators()
    self:updateFolderTitle()
end

function MetadataTabsTitleBar:setLeftIcon()
end

function MetadataTabsTitleBar:setRightIcon()
    self:updateStatusIndicators()
    local file_manager = self.file_manager or FileManager.instance
    local bottom_status = file_manager
        and file_manager.file_chooser
        and file_manager.file_chooser._plainui_bottom_status_bar
    if bottom_status then
        bottom_status:updateStatusIndicators()
    end
    local header_status = file_manager
        and file_manager.file_chooser
        and file_manager.file_chooser._plainui_header_status_bar
    if header_status then
        header_status:updateStatusIndicators()
    end
end

function MetadataTabsTitleBar:onNetworkConnected()
    NetworkMgr:queryNetworkState()
    self:updateStatusIndicators()
end

function MetadataTabsTitleBar:onNetworkDisconnected()
    NetworkMgr:queryNetworkState()
    self:updateStatusIndicators()
end

function MetadataTabsTitleBar:onNetworkDisconnecting()
    NetworkMgr.is_wifi_on = false
    self:updateStatusIndicators()
end

function MetadataTabsTitleBar:onFrontlightStateChanged()
    self:refreshStatusIndicators()
    UIManager:scheduleIn(0.2, self.refreshStatusIndicators, self)
    UIManager:scheduleIn(1, self.refreshStatusIndicators, self)
end

local FileChooser_show_file = FileChooser.show_file
FileChooser.show_file = function(self, filename, fullpath)
    if not isFileManagerBooksChooser(self) then
        return FileChooser_show_file(self, filename, fullpath)
    end

    local books_options = TabViewOptions.get("books")
    if books_options.filter == "legacy" then
        return FileChooser_show_file(self, filename, fullpath)
    end
    return showFileWithBooksOptions(self, filename, fullpath)
end

local FileChooser_show_dir = FileChooser.show_dir
FileChooser.show_dir = function(self, dirname)
    local books_options = TabViewOptions.get("books")
    if isFileManagerBooksChooser(self)
            and books_options.filter ~= "legacy"
            and books_options.exclude_folders then
        return false
    end
    return FileChooser_show_dir(self, dirname)
end

local FileChooser_getCollate = FileChooser.getCollate
FileChooser.getCollate = function(self)
    if isFileManagerBooksChooser(self) then
        local books_options = TabViewOptions.get("books")
        if books_options.sort == "legacy" then
            return FileChooser_getCollate(self)
        end

        local collate_id = BOOKS_SORT_COLLATE[books_options.sort]
        local collate = collate_id and self.collates[collate_id]
        if collate then
            return collate, collate_id
        end
    end
    return FileChooser_getCollate(self)
end

local FileChooser_getSortingFunction = FileChooser.getSortingFunction
FileChooser.getSortingFunction = function(self, collate, reverse_collate)
    if isFileManagerBooksChooser(self) then
        local books_options = TabViewOptions.get("books")
        if books_options.sort ~= "legacy" then
            reverse_collate = false
        end
    end
    return FileChooser_getSortingFunction(self, collate, reverse_collate)
end

function MetadataTabsTitleBar:generateHorizontalLayout()
    local row = {
        self.back_button,
        self.books_button,
        self.series_button,
        self.authors_button,
        self.tags_button,
    }
    table.insert(row, self.night_mode_button)
    table.insert(row, self.frontlight_button)
    table.insert(row, self.wifi_button)
    table.insert(row, self.battery_button)
    return {
        row,
    }
end

function MetadataTabsTitleBar:generateVerticalLayout()
    local layout = {
        { self.back_button },
        { self.books_button },
        { self.series_button },
        { self.authors_button },
        { self.tags_button },
    }
    table.insert(layout, { self.night_mode_button })
    table.insert(layout, { self.frontlight_button })
    table.insert(layout, { self.wifi_button })
    table.insert(layout, { self.battery_button })
    return layout
end



local FileChooser_recalculateDimen = FileChooser._recalculateDimen
if FileChooser_recalculateDimen then
    FileChooser._recalculateDimen = function(self, no_recalculate_dimen)
        FileChooser_recalculateDimen(self, no_recalculate_dimen)

        local extra_footer_height = self._plainui_bottom_metadata_tabs_extra_height
        if not PLAINUI_TABS_AT_BOTTOM
                or no_recalculate_dimen
                or not extra_footer_height
                or not self.available_height
                or not self.item_dimen then
            return
        end

        self.available_height = math.max(1, self.available_height - extra_footer_height)
        if self.perpage and self.perpage > 0 then
            self.item_dimen.h = math.max(1, math.floor(self.available_height / self.perpage))
        end
        if self.items_max_lines then
            self:setupItemHeights()
            self.page_num = self:getPageNumber(#self.item_table)
            if self.page > self.page_num then
                self.page = self.page_num
            end
        end
    end
end

local PlainUIMetadataTabsBar = VerticalGroup:extend{
    file_manager = nil,
    show_parent = nil,
}

function PlainUIMetadataTabsBar:init()
    self.show_parent = self.show_parent or self
    self.file_manager = self.file_manager or FileManager.instance
    local file_manager = self.file_manager

    self.tab_padding_h = Screen:scaleBySize(7)
    self.tab_padding_v = Screen:scaleBySize(5)
    self.tab_font_face = "smallinfofont"
    self.tab_font_size = PLAINUI_BOTTOM_FONT_SIZE

    local function getTextWidth(text, bold)
        local face = Font:getFace(self.tab_font_face, self.tab_font_size)
        local widget = TextWidget:new{
            text = text,
            face = face,
            bold = bold or false,
        }
        local width = widget:getSize().w
        widget:free()
        return width
    end

    local function getTabWidth(text)
        local selected_text = text .. TAB_SELECTED_SUFFIX
        local unselected_text = text .. TAB_UNSELECTED_SUFFIX
        return math.max(
            getTextWidth(unselected_text, false),
            getTextWidth(unselected_text, true),
            getTextWidth(selected_text, true)
        ) + 2 * self.tab_padding_h
    end

    local function makeTab(key, text, callback, hold_callback)
        local tab_width = getTabWidth(text)
        local button = Button:new{
            text = text,
            text_font_face = self.tab_font_face,
            text_font_size = self.tab_font_size,
            text_font_bold = false,
            width = tab_width,
            bordersize = 0,
            padding_h = self.tab_padding_h,
            padding_v = self.tab_padding_v,
            callback = function()
                if self.selected_tab_key == key then
                    self:showTabOptions(key)
                else
                    callback()
                end
            end,
            hold_callback = hold_callback,
            show_parent = self.show_parent,
        }
        local tab = VerticalGroup:new{
            align = "center",
            button,
        }
        tab.key = key
        tab.text = text
        tab.button = button
        return tab
    end

    self.books_tab = makeTab("books", _("Files"), function()
        openBooks(file_manager)
    end, function()
        file_manager:onShowFolderMenu()
    end)
    self.series_tab = makeTab("series", _("Series"), function()
        browseByMetadata(file_manager, "series")
    end)
    self.authors_tab = makeTab("authors", _("Authors"), function()
        browseByMetadata(file_manager, "author")
    end)
    self.tags_tab = makeTab("tags", _("Tags"), function()
        browseByMetadata(file_manager, "tags")
    end)

    self.books_button = self.books_tab.button
    self.series_button = self.series_tab.button
    self.authors_button = self.authors_tab.button
    self.tags_button = self.tags_tab.button
    self.tabs_by_key = {
        books = self.books_tab,
        series = self.series_tab,
        authors = self.authors_tab,
        tags = self.tags_tab,
    }
    self.tabs_group = HorizontalGroup:new{
        align = "center",
        allow_mirroring = false,
        self.books_tab,
        self.series_tab,
        self.authors_tab,
        self.tags_tab,
    }

    local tabs_size = self.tabs_group:getSize()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = tabs_size.h,
    }

    table.insert(self, self.tabs_group)
    self:updateSelectedTab(false)
end

PlainUIMetadataTabsBar.showTabOptions = MetadataTabsTitleBar.showTabOptions
PlainUIMetadataTabsBar.showTabOptionValues = MetadataTabsTitleBar.showTabOptionValues
PlainUIMetadataTabsBar.getTabDropdownAnchor = MetadataTabsTitleBar.getTabDropdownAnchor
PlainUIMetadataTabsBar.setTabSelected = MetadataTabsTitleBar.setTabSelected
PlainUIMetadataTabsBar.updateSelectedTab = MetadataTabsTitleBar.updateSelectedTab

function PlainUIMetadataTabsBar:refreshForTabOptionChange()
    local file_manager = self.file_manager or FileManager.instance
    local file_chooser = file_manager and file_manager.file_chooser
    if file_chooser then
        file_chooser:refreshPath()
    elseif self.dimen then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function PlainUIMetadataTabsBar:isVisible()
    return getBackTitleBarInfo(self.file_manager or FileManager.instance) == nil
end

function PlainUIMetadataTabsBar:paintTo(bb, x, y)
    if not self.dimen then
        local size = self:getSize()
        self.dimen = Geom:new{
            x = x or 0,
            y = y or 0,
            w = size and size.w or Screen:getWidth(),
            h = size and size.h or 0,
        }
    else
        self.dimen.x = x or 0
        self.dimen.y = y or 0
    end
    self:updateSelectedTab(false)
    if self:isVisible() then
        VerticalGroup.paintTo(self, bb, x, y)
    end
end

function PlainUIMetadataTabsBar:handleEvent(event)
    self:updateSelectedTab(false)
    if self:isVisible() then
        return VerticalGroup.handleEvent(self, event)
    end
    return false
end

local PlainUIBackTitleBar = VerticalGroup:extend{
    file_manager = nil,
    show_parent = nil,
}

function PlainUIBackTitleBar:init()
    self.show_parent = self.show_parent or self
    self.file_manager = self.file_manager or FileManager.instance
    local file_manager = self.file_manager

    self.width = Screen:getWidth()
    self.tab_padding_h = Screen:scaleBySize(7)
    self.tab_padding_v = Screen:scaleBySize(5)
    self.tab_font_face = "smallinfofont"
    self.tab_font_size = PLAINUI_BOTTOM_FONT_SIZE

    local face = Font:getFace(self.tab_font_face, self.tab_font_size)
    local sample = TextWidget:new{
        text = "W",
        face = face,
        bold = true,
    }
    self.tab_label_height = sample:getSize().h
    sample:free()

    -- This widget now renders only the current metadata listing title.
    -- The back arrow itself is handled by PlainUIBackButtonBar on the left side.
    self.back_title_width = math.floor(self.width * 0.56)

    self.back_button = Button:new{
        text = "",
        align = "center",
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = true,
        avoid_text_truncation = false,
        width = self.back_title_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.tab_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            MetadataFacetDropdown.show(file_manager, function()
                return self:getDropdownAnchor()
            end)
        end,
        show_parent = self.show_parent,
    }

    self.back_row = HorizontalGroup:new{
        align = "bottom",
        allow_mirroring = false,
        self.back_button,
    }

    local row_size = self.back_row:getSize()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.back_title_width,
        h = row_size.h,
    }

    table.insert(self, self.back_row)
    self:updateBackTitle(false)
end

PlainUIBackTitleBar.updateBackTitle = MetadataTabsTitleBar.updateBackTitle
PlainUIBackTitleBar.onBackTitleTap = MetadataTabsTitleBar.onBackTitleTap
PlainUIBackTitleBar.getDropdownAnchor = MetadataTabsTitleBar.getDropdownAnchor

function PlainUIBackTitleBar:isVisible()
    return self.back_title_info ~= nil
end

function PlainUIBackTitleBar:paintTo(bb, x, y)
    if not self.dimen then
        local size = self:getSize()
        self.dimen = Geom:new{
            x = x or 0,
            y = y or 0,
            w = size and size.w or self.back_title_width or 0,
            h = size and size.h or 0,
        }
    else
        self.dimen.x = x or 0
        self.dimen.y = y or 0
    end

    self:updateBackTitle(false)
    if self:isVisible() then
        VerticalGroup.paintTo(self, bb, x, y)
    end
end

function PlainUIBackTitleBar:handleEvent(event)
    self:updateBackTitle(false)
    if self:isVisible() then
        return VerticalGroup.handleEvent(self, event)
    end
    return false
end

local PlainUIBackButtonBar = VerticalGroup:extend{
    file_manager = nil,
    show_parent = nil,
}

function PlainUIBackButtonBar:init()
    self.show_parent = self.show_parent or self
    self.file_manager = self.file_manager or FileManager.instance

    self.tab_padding_h = Screen:scaleBySize(7)
    self.tab_padding_v = Screen:scaleBySize(5)
    self.tab_font_face = "smallinfofont"
    self.tab_font_size = PLAINUI_BOTTOM_FONT_SIZE

    local face = Font:getFace(self.tab_font_face, self.tab_font_size)
    local sample = TextWidget:new{
        text = "W",
        face = face,
        bold = true,
    }
    self.tab_label_height = sample:getSize().h
    sample:free()

    self.back_chevron_hit_width = self.tab_label_height + self.tab_padding_h
    self.back_chevron_button = Button:new{
        icon = "chevron.left",
        align = "left",
        icon_width = self.tab_label_height,
        icon_height = self.tab_label_height,
        width = self.back_chevron_hit_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = 0,
        padding_v = self.tab_padding_v,
        callback = function()
            self:onBackTitleTap()
        end,
        show_parent = self.show_parent,
    }

    self.back_row = HorizontalGroup:new{
        align = "bottom",
        allow_mirroring = false,
        self.back_chevron_button,
    }

    local row_size = self.back_row:getSize()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = row_size.w,
        h = row_size.h,
    }

    table.insert(self, self.back_row)
    self:updateBackTitle(false)
end

function PlainUIBackButtonBar:updateBackTitle(refresh)
    local file_manager = self.file_manager or FileManager.instance
    local back_title_info = getBackTitleBarInfo(file_manager)
    local title = back_title_info and back_title_info.title or nil
    if self.back_title == title then
        return
    end

    self.back_title_info = back_title_info
    self.back_title = title

    if refresh ~= false and self.dimen then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

PlainUIBackButtonBar.onBackTitleTap = MetadataTabsTitleBar.onBackTitleTap

function PlainUIBackButtonBar:isVisible()
    return self.back_title_info ~= nil
end

function PlainUIBackButtonBar:paintTo(bb, x, y)
    if not self.dimen then
        local size = self:getSize()
        self.dimen = Geom:new{
            x = x or 0,
            y = y or 0,
            w = size and size.w or self.back_chevron_hit_width or 0,
            h = size and size.h or 0,
        }
    else
        self.dimen.x = x or 0
        self.dimen.y = y or 0
    end

    self:updateBackTitle(false)
    if self:isVisible() then
        VerticalGroup.paintTo(self, bb, x, y)
    end
end

function PlainUIBackButtonBar:handleEvent(event)
    self:updateBackTitle(false)
    if self:isVisible() then
        return VerticalGroup.handleEvent(self, event)
    end
    return false
end


local PlainUIBottomStatusBar = VerticalGroup:extend{
    file_manager = nil,
    show_parent = nil,
}

function PlainUIBottomStatusBar:init()
    self.show_parent = self.show_parent or self
    self.file_manager = self.file_manager or FileManager.instance
    local file_manager = self.file_manager

    self.width = Screen:getWidth()
    self.tab_padding_h = Screen:scaleBySize(7)
    self.tab_padding_v = Screen:scaleBySize(5)
    self.tab_font_face = "smallinfofont"
    self.tab_font_size = PLAINUI_BOTTOM_FONT_SIZE
    self.status_padding_h = Screen:scaleBySize(7)
    self.status_gap = self.tab_padding_h

    local face = Font:getFace(self.tab_font_face, self.tab_font_size)
    local sample = TextWidget:new{
        text = "W",
        face = face,
        bold = false,
    }
    self.tab_label_height = sample:getSize().h
    sample:free()

    local status_widths = StatusIndicators.getWidths(self.tab_font_face, self.tab_font_size, self.status_padding_h)
    self.night_mode_width = status_widths.night_mode
    self.frontlight_width = status_widths.frontlight
    self.wifi_width = status_widths.wifi
    self.battery_width = status_widths.battery
    self.time_width = measureTextWidth("23:59", self.tab_font_face, self.tab_font_size, false)
        + 2 * self.status_padding_h
    self.right_icon_width = self.tab_label_height + 2 * self.status_padding_h

    self.time_button = Button:new{
        text = os.date("%H:%M"),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.time_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        show_parent = self.show_parent,
    }
    self.night_mode_button = Button:new{
        text = StatusIndicators.NIGHT_MODE_SYMBOL,
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.night_mode_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            UIManager:broadcastEvent(Event:new("ToggleNightMode"))
        end,
        show_parent = self.show_parent,
    }
    self.frontlight_button = Button:new{
        text = StatusIndicators.getFrontlightText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.frontlight_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            if Device:hasFrontlight() then
                UIManager:broadcastEvent(Event:new("ShowFlDialog"))
            end
        end,
        hold_callback = function()
            if Device:hasFrontlight() then
                UIManager:broadcastEvent(Event:new("ToggleFrontlight"))
                self:refreshStatusIndicators()
            end
        end,
        show_parent = self.show_parent,
    }
    self.wifi_button = Button:new{
        text = StatusIndicators.getWifiText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.wifi_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            StatusIndicators.toggleWifi(function()
                self:updateStatusIndicators()
            end)
        end,
        hold_callback = function()
            StatusIndicators.showWifiNetworks(function()
                self:updateStatusIndicators()
            end)
        end,
        show_parent = self.show_parent,
    }
    self.battery_button = Button:new{
        text = StatusIndicators.getBatteryText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.battery_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        hold_callback = function()
            StatusIndicators.showBatteryInfo()
            self:updateStatusIndicators()
        end,
        show_parent = self.show_parent,
    }
    self.right_icon_button = Button:new{
        icon = self:getRightIcon(),
        icon_width = self.tab_label_height,
        icon_height = self.tab_label_height,
        width = self.right_icon_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            if file_manager and file_manager.onShowPlusMenu then
                file_manager:onShowPlusMenu()
            end
        end,
        hold_callback = false,
        show_parent = self.show_parent,
    }

    local status_row_items = {
        align = "bottom",
        allow_mirroring = false,
    }
    -- Footer keeps only the night mode indicator; battery and clock were moved to the header.
    table.insert(status_row_items, self.night_mode_button)
    table.insert(status_row_items, HorizontalSpan:new{ width = PLAINUI_SIDE_MARGIN })
    self.status_row = HorizontalGroup:new(status_row_items)

    local row_size = self.status_row:getSize()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = row_size.w,
        h = row_size.h,
    }

    table.insert(self, self.status_row)
    self:updateStatusIndicators(false)
    self:scheduleClockRefresh()
end

function PlainUIBottomStatusBar:getRightIcon()
    local file_manager = self.file_manager or FileManager.instance
    return file_manager and file_manager.selected_files and "check" or "plus"
end

function PlainUIBottomStatusBar:scheduleClockRefresh()
    if self._clock_scheduled then
        return
    end
    local seconds = 60 - tonumber(os.date("%S"))
    if seconds < 1 or seconds > 60 then
        seconds = 60
    end
    self._clock_scheduled = true
    UIManager:scheduleIn(seconds, self.refreshStatusIndicators, self)
end

function PlainUIBottomStatusBar:updateStatusIndicators(refresh)
    if not self.battery_button then
        return
    end

    local time_text = os.date("%H:%M")
    local battery_text = StatusIndicators.getBatteryText()
    local wifi_text = StatusIndicators.getWifiText()
    local frontlight_text = StatusIndicators.getFrontlightText()
    local right_icon = self:getRightIcon()

    local changed = false
    if self.time_text ~= time_text then
        self.time_text = time_text
        self.time_button:setText(time_text, self.time_width)
        changed = true
    end
    if self.battery_text ~= battery_text then
        self.battery_text = battery_text
        self.battery_button:setText(battery_text, self.battery_width)
        changed = true
    end
    if self.wifi_text ~= wifi_text then
        self.wifi_text = wifi_text
        self.wifi_button:setText(wifi_text, self.wifi_width)
        changed = true
    end
    if self.frontlight_text ~= frontlight_text then
        self.frontlight_text = frontlight_text
        self.frontlight_button:setText(frontlight_text, self.frontlight_width)
        changed = true
    end
    if self.right_icon ~= right_icon then
        self.right_icon = right_icon
        self.right_icon_button:setIcon(right_icon, self.right_icon_width)
        changed = true
    end

    if changed and refresh ~= false and self.dimen then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function PlainUIBottomStatusBar:refreshStatusIndicators()
    self._clock_scheduled = false
    self:updateStatusIndicators(false)
    if self.dimen then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
    self:scheduleClockRefresh()
end

function PlainUIBottomStatusBar:paintTo(bb, x, y)
    if not self.dimen then
        local size = self:getSize()
        self.dimen = Geom:new{
            x = x or 0,
            y = y or 0,
            w = size and size.w or 0,
            h = size and size.h or 0,
        }
    else
        self.dimen.x = x or 0
        self.dimen.y = y or 0
    end
    self:updateStatusIndicators(false)
    self:scheduleClockRefresh()
    VerticalGroup.paintTo(self, bb, x, y)
end

function PlainUIBottomStatusBar:handleEvent(event)
    self:updateStatusIndicators(false)
    return VerticalGroup.handleEvent(self, event)
end

function PlainUIBottomStatusBar:onNetworkConnected()
    NetworkMgr:queryNetworkState()
    self:updateStatusIndicators()
end

function PlainUIBottomStatusBar:onNetworkDisconnected()
    NetworkMgr:queryNetworkState()
    self:updateStatusIndicators()
end

function PlainUIBottomStatusBar:onNetworkDisconnecting()
    NetworkMgr.is_wifi_on = false
    self:updateStatusIndicators()
end

function PlainUIBottomStatusBar:onFrontlightStateChanged()
    self:refreshStatusIndicators()
    UIManager:scheduleIn(0.2, self.refreshStatusIndicators, self)
    UIManager:scheduleIn(1, self.refreshStatusIndicators, self)
end


local PlainUIHeaderStatusBar = VerticalGroup:extend{
    file_manager = nil,
    show_parent = nil,
}

function PlainUIHeaderStatusBar:init()
    self.show_parent = self.show_parent or self
    self.file_manager = self.file_manager or FileManager.instance

    self.tab_padding_h = Screen:scaleBySize(7)
    self.tab_padding_v = Screen:scaleBySize(5)
    self.tab_font_face = "smallinfofont"
    self.tab_font_size = PLAINUI_BOTTOM_FONT_SIZE
    self.status_padding_h = Screen:scaleBySize(7)
    self.status_gap = self.tab_padding_h

    local face = Font:getFace(self.tab_font_face, self.tab_font_size)
    local sample = TextWidget:new{
        text = "W",
        face = face,
        bold = false,
    }
    self.tab_label_height = sample:getSize().h
    sample:free()

    local status_widths = StatusIndicators.getWidths(self.tab_font_face, self.tab_font_size, self.status_padding_h)
    self.battery_width = status_widths.battery
    self.wifi_width = status_widths.wifi
    self.time_width = measureTextWidth("23:59", self.tab_font_face, self.tab_font_size, false)
        + 2 * self.status_padding_h

    self.time_button = Button:new{
        text = os.date("%H:%M"),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.time_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        show_parent = self.show_parent,
    }
    self.battery_button = Button:new{
        text = StatusIndicators.getBatteryText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.battery_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        hold_callback = function()
            StatusIndicators.showBatteryInfo()
            self:updateStatusIndicators()
        end,
        show_parent = self.show_parent,
    }
    self.wifi_button = Button:new{
        text = StatusIndicators.getWifiText(),
        text_font_face = self.tab_font_face,
        text_font_size = self.tab_font_size,
        text_font_bold = false,
        width = self.wifi_width,
        height = self.tab_label_height,
        bordersize = 0,
        padding_h = self.status_padding_h,
        padding_v = self.tab_padding_v,
        callback = function()
            StatusIndicators.toggleWifi(function()
                self:updateStatusIndicators()
            end)
        end,
        hold_callback = function()
            StatusIndicators.showWifiNetworks(function()
                self:updateStatusIndicators()
            end)
        end,
        show_parent = self.show_parent,
    }

    self.status_row = HorizontalGroup:new{
        align = "bottom",
        allow_mirroring = false,
        HorizontalSpan:new{ width = PLAINUI_SIDE_MARGIN },
        self.time_button,
        HorizontalSpan:new{ width = self.status_gap },
        self.battery_button,
        HorizontalSpan:new{ width = self.status_gap },
        self.wifi_button,
    }

    local row_size = self.status_row:getSize()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = row_size.w,
        h = row_size.h,
    }

    table.insert(self, self.status_row)
    self:updateStatusIndicators(false)
    self:scheduleClockRefresh()
end

function PlainUIHeaderStatusBar:scheduleClockRefresh()
    if self._clock_scheduled then
        return
    end
    local seconds = 60 - tonumber(os.date("%S"))
    if seconds < 1 or seconds > 60 then
        seconds = 60
    end
    self._clock_scheduled = true
    UIManager:scheduleIn(seconds, self.refreshStatusIndicators, self)
end

function PlainUIHeaderStatusBar:updateStatusIndicators(refresh)
    if not self.battery_button then
        return
    end

    local time_text = os.date("%H:%M")
    local battery_text = StatusIndicators.getBatteryText()
    local wifi_text = StatusIndicators.getWifiText()
    local changed = false

    if self.time_text ~= time_text then
        self.time_text = time_text
        self.time_button:setText(time_text, self.time_width)
        changed = true
    end
    if self.battery_text ~= battery_text then
        self.battery_text = battery_text
        self.battery_button:setText(battery_text, self.battery_width)
        changed = true
    end
    if self.wifi_text ~= wifi_text then
        self.wifi_text = wifi_text
        self.wifi_button:setText(wifi_text, self.wifi_width)
        changed = true
    end

    if changed and refresh ~= false and self.dimen then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
end

function PlainUIHeaderStatusBar:refreshStatusIndicators()
    self._clock_scheduled = false
    self:updateStatusIndicators(false)
    if self.dimen then
        UIManager:setDirty(self.show_parent, "ui", self.dimen)
    end
    self:scheduleClockRefresh()
end

function PlainUIHeaderStatusBar:paintTo(bb, x, y)
    if not self.dimen then
        local size = self:getSize()
        self.dimen = Geom:new{
            x = x or 0,
            y = y or 0,
            w = size and size.w or 0,
            h = size and size.h or 0,
        }
    else
        self.dimen.x = x or 0
        self.dimen.y = y or 0
    end
    self:updateStatusIndicators(false)
    self:scheduleClockRefresh()
    VerticalGroup.paintTo(self, bb, x, y)
end

function PlainUIHeaderStatusBar:handleEvent(event)
    self:updateStatusIndicators(false)
    return VerticalGroup.handleEvent(self, event)
end

function PlainUIHeaderStatusBar:onNetworkConnected()
    self:updateStatusIndicators()
end

function PlainUIHeaderStatusBar:onNetworkDisconnected()
    self:updateStatusIndicators()
end

function PlainUIHeaderStatusBar:onNetworkDisconnecting()
    self:updateStatusIndicators()
end

function PlainUIHeaderStatusBar:onFrontlightStateChanged()
    self:refreshStatusIndicators()
end

local function installBottomMetadataTabs(file_manager)
    if not PLAINUI_TABS_AT_BOTTOM then
        return
    end

    local file_chooser = file_manager and file_manager.file_chooser
    if not file_chooser
            or file_chooser._plainui_bottom_metadata_tabs_installed
            or not file_chooser.page_info
            or not file_chooser.page_info.clear then
        return
    end

    -- Move the original page navigation buttons and the page indicator to the
    -- right side of the header. Clock, battery and night mode stay on the left side.
    file_chooser.page_info:clear()

    local spacer_width = Screen:scaleBySize(24)
    local page_controls = HorizontalGroup:new{
        align = "center",
        allow_mirroring = false,
        file_chooser.page_info_first_chev,
        HorizontalSpan:new{ width = spacer_width },
        file_chooser.page_info_left_chev,
        HorizontalSpan:new{ width = spacer_width },
        file_chooser.page_info_text,
        HorizontalSpan:new{ width = spacer_width },
        file_chooser.page_info_right_chev,
        HorizontalSpan:new{ width = spacer_width },
        file_chooser.page_info_last_chev,
    }
    local header_status = PlainUIHeaderStatusBar:new{
        file_manager = file_manager,
        show_parent = file_manager.show_parent or file_manager,
    }

    local title_bar = file_manager.title_bar
    if title_bar and title_bar.installPageControls then
        title_bar:installPageControls(page_controls, header_status)
    end

    local metadata_tabs = PlainUIMetadataTabsBar:new{
        file_manager = file_manager,
        show_parent = file_manager.show_parent or file_manager,
    }
    local back_button = PlainUIBackButtonBar:new{
        file_manager = file_manager,
        show_parent = file_manager.show_parent or file_manager,
    }
    local back_title = PlainUIBackTitleBar:new{
        file_manager = file_manager,
        show_parent = file_manager.show_parent or file_manager,
    }
    local metadata_tabs_size = metadata_tabs:getSize()
    local back_button_size = back_button:getSize()
    local back_title_size = back_title:getSize()
    local bottom_row_height = math.max(
        metadata_tabs_size.h,
        back_button_size.h,
        back_title_size.h
    )

    local bottom_row = OverlapGroup:new{
        dimen = Geom:new{
            x = 0,
            y = 0,
            w = Screen:getWidth(),
            h = bottom_row_height,
        },
        LeftContainer:new{
            allow_mirroring = false,
            dimen = Geom:new{
                x = 0,
                y = 0,
                w = Screen:getWidth(),
                h = bottom_row_height,
            },
            HorizontalGroup:new{
                align = "center",
                allow_mirroring = false,
                HorizontalSpan:new{ width = PLAINUI_SIDE_MARGIN },
                back_button,
            },
        },
        CenterContainer:new{
            allow_mirroring = false,
            dimen = Geom:new{
                x = 0,
                y = 0,
                w = Screen:getWidth(),
                h = bottom_row_height,
            },
            metadata_tabs,
        },
        CenterContainer:new{
            allow_mirroring = false,
            dimen = Geom:new{
                x = 0,
                y = 0,
                w = Screen:getWidth(),
                h = bottom_row_height,
            },
            back_title,
        },
    }

    local footer_content = VerticalGroup:new{
        align = "center",
        bottom_row,
    }

    table.insert(file_chooser.page_info, footer_content)
    file_chooser._plainui_bottom_metadata_tabs_installed = true
    file_chooser._plainui_bottom_metadata_tabs = metadata_tabs
    file_chooser._plainui_bottom_back_button = back_button
    file_chooser._plainui_bottom_back_title = back_title
    file_chooser._plainui_header_status_bar = header_status
    file_chooser._plainui_bottom_metadata_tabs_extra_height = bottom_row_height
    file_chooser.page_info:resetLayout()
    file_chooser:updateItems(1)
end

local function findTitleBarUpvalue(func, seen)
    if type(func) ~= "function" then
        return
    end
    seen = seen or {}
    if seen[func] then
        return
    end
    seen[func] = true

    local nested = {}
    local idx = 1
    while true do
        local name, value = debug.getupvalue(func, idx)
        if not name then
            break
        end
        if name == "TitleBar" then
            return func, idx, value
        elseif type(value) == "function" then
            table.insert(nested, value)
        end
        idx = idx + 1
    end

    for _, nested_func in ipairs(nested) do
        local target_func, target_idx, original = findTitleBarUpvalue(nested_func, seen)
        if target_func then
            return target_func, target_idx, original
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", function()
    local BookInfoManager = require("bookinfomanager")
    local FFIUtil = require("ffi/util")
    local FileChooser__updateItemsBuildUI = FileChooser._updateItemsBuildUI
    if not FileChooser__updateItemsBuildUI then
        return
    end

    local LOADING_TOAST_DELAY_S = 0.25

    local function maybeShowLoadingToast(state)
        if state.info then
            return
        end
        if FFIUtil.getTimestamp() - state.started_at < LOADING_TOAST_DELAY_S then
            return
        end
        state.info = InfoMessage:new{
            text = _("Loading covers…"),
            dismissable = false,
            flush_events_on_show = true,
        }
        UIManager:show(state.info)
        UIManager:forceRePaint()
    end

    local function closeLoadingToast(state)
        if state.info then
            UIManager:close(state.info)
            state.info = nil
        end
    end

    local function needsCoverExtraction(filepath, cover_specs)
        local bookinfo = BookInfoManager:getBookInfo(filepath, false)
        if not bookinfo then
            return true
        end
        if bookinfo.ignore_cover then
            return false
        end
        if not bookinfo.cover_fetched then
            return true
        end
        return bookinfo.has_cover and BookInfoManager.isCachedCoverInvalid(bookinfo, cover_specs)
    end

    local function extractVisibleLeafCovers(file_chooser)
        if not getMetadataLeafInfo(file_chooser.path) then
            return
        end
        if not file_chooser._do_cover_images or not file_chooser.item_width or not file_chooser.item_height then
            return
        end

        local cover_specs = {
            max_cover_w = file_chooser.item_width - 2 * Size.border.thin,
            max_cover_h = file_chooser.item_height - 2 * Size.border.thin,
        }
        local loading_state = {
            started_at = FFIUtil.getTimestamp(),
            info = nil,
        }
        local idx_offset = (file_chooser.page - 1) * file_chooser.perpage
        for idx = 1, file_chooser.perpage do
            local item = file_chooser.item_table[idx_offset + idx]
            if not item then
                break
            end
            if item.is_file and item.path and needsCoverExtraction(item.path, cover_specs) then
                maybeShowLoadingToast(loading_state)
                BookInfoManager:extractBookInfo(item.path, cover_specs)
            end
        end
        closeLoadingToast(loading_state)
    end

    FileChooser._updateItemsBuildUI = function(self, ...)
        local leaf_info = getMetadataLeafInfo(self.path)
        if leaf_info then
            extractVisibleLeafCovers(self)
        end
        return FileChooser__updateItemsBuildUI(self, ...)
    end
end)

local FileManager_setupLayout = FileManager.setupLayout
FileManager.setupLayout = function(self, ...)
    local target_func, titlebar_idx, original_titlebar = findTitleBarUpvalue(FileManager_setupLayout)
    if target_func and titlebar_idx then
        MetadataTabsTitleBar.file_manager = self
        debug.setupvalue(target_func, titlebar_idx, MetadataTabsTitleBar)
        local ok, ret = pcall(FileManager_setupLayout, self, ...)
        debug.setupvalue(target_func, titlebar_idx, original_titlebar)
        MetadataTabsTitleBar.file_manager = nil
        if not ok then
            error(ret)
        end
        installBottomMetadataTabs(self)
        return ret
    end
    local ret = FileManager_setupLayout(self, ...)
    installBottomMetadataTabs(self)
    return ret
end
