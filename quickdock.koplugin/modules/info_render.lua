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
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
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
-- Height-to-width ratio of a recent-document cover tile, close to most book
-- covers, so a typical cover fills its tile.
local RECENT_COVER_RATIO = 1.45
-- Share of the screen height the recent-documents grid may take: the side
-- panel shares its edge only with a status block, while the top panel must
-- leave room for the arc dock below it.
local RECENT_SIDE_HEIGHT_SHARE = 0.55
local RECENT_TOP_HEIGHT_SHARE = 0.3
-- A heading's font may shrink to this share of its size to fit its words.
local MINIMUM_HEADING_SCALE = 0.5

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

local function pagesLabel(count)
    count = math_max(0, math_floor(tonumber(count) or 0))
    -- KOReader's own catalog has this plural.
    return T(N_("1 page", "%1 pages", count), count)
end

return function(Util, Covers)
    local clamp = Util.clamp

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
        local gap = math_max(Size.padding.small, Util.scaled(metrics, 6))
        local documents = data.documents or {}
        local items = { align = "left" }

        local tile_width, tile_height
        if horizontal then
            tile_height = Util.scaled(metrics, 110)
            tile_width = math_floor(tile_height / RECENT_COVER_RATIO + 0.5)
        else
            local minimum_width = Util.scaled(metrics, 64)
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
        local arrow_size = Util.scaled(metrics, 32)
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
                    -- A custom icon is a file path, which the dock's IconWidget
                    -- patch (modules/icons.lua) accepts as an icon name.
                    widget = IconWidget:new({
                        icon = icon,
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
            title:free()
            if pager_beside then
                local title_width = math_max(1, content_width - pager:getSize().w - gap)
                header = HorizontalGroup:new({
                    align = "center",
                    beside_title,
                    HorizontalSpan:new({ width = title_width - beside_title:getSize().w + gap }),
                    pager,
                })
            else
                -- The title and the arrows, each on its own line, both centered.
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
            local cover = Covers.getRecentCover(
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
                        text = cover.title or Util.fileTitle(document.file),
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

    -- Cover, title, and author: the top of both the reading and statistics panels.
    local function addDocumentHeader(panel, data)
        if data.cover and data.cover.bb then
            panel.addGroup(0, function(width, items)
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
        panel.addGroup(1, function(width, items)
            items[#items + 1] = panel.text(width, data.document.title, panel.title_face, true)
            if data.document.author ~= "" then
                addGap(items, panel.gap)
                items[#items + 1] = panel.text(
                    width,
                    data.document.author,
                    panel.body_face,
                    false,
                    Blitbuffer.COLOR_DARK_GRAY
                )
            end
        end)
    end

    -- A heading over a gray note, for panels without anything else to show.
    local function addNotice(panel, heading, notice)
        panel.addGroup(1, function(width, items)
            items[#items + 1] = makeHeading(heading, panel.title_face, width, panel.alignment)
            addGap(items, panel.gap)
            items[#items + 1] = panel.text(width, notice, panel.body_face, false, Blitbuffer.COLOR_DARK_GRAY)
        end)
    end

    -- One renderer per mode kind, except the recent documents, which have their
    -- own layout. Each adds its groups to the panel and returns the column of
    -- the shared footer (today's reading, clock and battery) in the top panel.
    local RENDERERS = {}

    function RENDERERS.reading(panel, data)
        if not data.document then
            addNotice(panel, _("Reading today"), _("No document is currently open."))
            return 2
        end
        addDocumentHeader(panel, data)

        panel.addGroup(2, function(width, items)
            local page = data.document.page_label or data.document.page
            local total = data.document.total_label or data.document.total
            local book_lines = {
                T(_("Book: %1 / %2  ·  %3%"), page, total, data.document.percentage),
            }
            if data.statistics and data.statistics.book_time_left then
                book_lines[2] = T(_("Remaining: %1"), data.statistics.book_time_left)
            end
            items[#items + 1] = panel.text(width, table.concat(book_lines, "\n"), panel.body_face)
        end)

        if data.chapter then
            panel.addGroup(2, function(width, items)
                local chapter_title = data.chapter.title ~= ""
                    and data.chapter.title or _("Chapter")
                items[#items + 1] = panel.text(width, chapter_title, panel.body_face, true)
                addGap(items, panel.gap)
                local chapter_lines = {
                    T(_("Page: %1 / %2  ·  %3%"), data.chapter.page,
                        data.chapter.total, data.chapter.percentage),
                }
                if data.statistics and data.statistics.chapter_time_left then
                    chapter_lines[2] = T(_("Remaining: %1"), data.statistics.chapter_time_left)
                end
                items[#items + 1] = panel.text(width, table.concat(chapter_lines, "\n"), panel.body_face)
            end)
        end
        return 3
    end

    function RENDERERS.stats(panel, data)
        if not data.document then
            addNotice(panel, _("Book statistics"), _("No document is currently open."))
            return 2
        end
        addDocumentHeader(panel, data)
        local stats = data.book_stats
        local gap = panel.gap
        local half_gap = 2 * gap
        local font_factor = panel.font_factor
        local hero_face = Font:getFace("infofont", math_floor(28 * font_factor + 0.5))
        local value_face = Font:getFace("infofont", math_floor(17 * font_factor + 0.5))
        local caption_face = Font:getFace("smallinfofont", math_floor(11 * font_factor + 0.5))
        local gray = Blitbuffer.COLOR_DARK_GRAY

        -- A large value over a small gray caption. Missing values are
        -- flagged with a gray, non-bold "N/A" rather than left out.
        local function statCell(value, caption, width, face)
            return VerticalGroup:new({
                makeText(value or _("N/A"), face or value_face, width, value ~= nil,
                    value ~= nil and Blitbuffer.COLOR_BLACK or gray, panel.alignment),
                makeText(caption, caption_face, width, false, gray, panel.alignment),
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
            return seconds and Util.compactDuration(seconds) or nil
        end

        panel.addGroup(1, function(width, items)
            local progress_height = math_max(4, Util.scaled(panel.metrics, 8))
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

        panel.addGroup(2, function(width, items)
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

        panel.addGroup(3, function(width, items)
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
                items[#items + 1] = panel.text(
                    width,
                    _("Enable KOReader's Statistics plugin to collect reading data."),
                    panel.body_face,
                    false,
                    Blitbuffer.COLOR_DARK_GRAY
                )
            end
        end)
        return 3
    end

    function RENDERERS.network(panel, data)
        panel.addGroup(1, function(width, items)
            items[#items + 1] = makeHeading(_("Network information"), panel.title_face, width, panel.alignment)
            addGap(items, panel.gap)
            items[#items + 1] = panel.text(width, data.network.status, panel.body_face, true)
            if data.network.ssid and not data.network.details then
                addGap(items, panel.gap)
                items[#items + 1] = panel.text(
                    width,
                    T(_("SSID: %1"), data.network.ssid),
                    panel.body_face
                )
            end
        end)
        if data.network.details then
            panel.addGroup(2, function(width, items)
                items[#items + 1] = panel.text(width, data.network.details, panel.body_face)
            end)
            return 3
        end
        return 2
    end

    -- Today's reading (when the Statistics plugin records it), then the clock
    -- and battery.
    local function addFooter(panel, data, column)
        if data.statistics and data.statistics.today_pages ~= nil then
            panel.addGroup(column, function(width, items)
                local pages = pagesLabel(data.statistics.today_pages)
                local today = T(_("Today: %1"), pages)
                if data.statistics.today_duration then
                    today = T(_("Today: %1  ·  %2"), pages, data.statistics.today_duration)
                end
                items[#items + 1] = panel.text(width, today, panel.body_face)
            end)
        end

        panel.addGroup(column, function(width, items)
            local status = { data.clock }
            if data.battery then
                status[#status + 1] = data.battery
            end
            items[#items + 1] = panel.text(
                width,
                table.concat(status, "  ·  "),
                panel.body_face,
                true
            )
        end)
    end

    -- How a panel's lines are aligned: the setting, with the nearest screen
    -- edge resolved for the side the panel is on.
    local function resolveAlignment(alignment, panel_side)
        if alignment == "screen_edge" then
            return panel_side == "right" and "right" or "left"
        elseif alignment ~= "center" then
            return "left"
        end
        return alignment
    end

    -- The panel content is a list of groups, each one a few related lines. The
    -- side panel stacks every group in one column with a separator between them;
    -- the top panel (arc dock) places the groups side by side in up to three
    -- columns, each group saying in which column it goes. Column 0 holds the
    -- cover, which keeps its own width.
    --   layout.metrics: the dock's dimensions
    --   layout.maximum_outer_width: the widest the panel may be
    --   layout.horizontal: the arc dock's top panel, groups side by side
    --   layout.text_alignment: resolved alignment of the panel's lines
    local function build(plugin, data, layout)
        local metrics = layout.metrics
        local maximum_outer_width = layout.maximum_outer_width
        local horizontal = layout.horizontal
        local factor = Util.scaleFactor(metrics)
        local padding = Util.panelPadding(metrics)
        local content_width
        if horizontal then
            content_width = math_max(
                Screen:scaleBySize(90),
                math_floor(maximum_outer_width) - 2 * (padding + Size.border.button)
            )
        else
            content_width = Util.panelContentWidth(metrics, maximum_outer_width)
        end
        -- The statistics panel packs more lines than the others, so all of its
        -- fonts (including the shared header and footer) are scaled down together.
        local font_factor = data.kind == "stats" and factor * STATS_FONT_SCALE or factor
        local alignment = layout.text_alignment
        local panel = {
            metrics = metrics,
            gap = math_max(1, Util.scaled(metrics, 3)),
            font_factor = font_factor,
            title_face = Font:getFace("infofont", math_floor(16 * font_factor + 0.5)),
            body_face = Font:getFace("smallinfofont", math_floor(13 * font_factor + 0.5)),
            alignment = alignment,
            text = function(width, text, face, bold, color)
                return makeText(text, face, width, bold, color, alignment)
            end,
        }
        local function makeFrame(content)
            return FrameContainer:new({
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
                title = panel.title_face,
                body = panel.body_face,
                caption = Font:getFace("smallinfofont", math_floor(11 * font_factor + 0.5)),
            }, tap_targets))
            frame.tap_targets = tap_targets
            return frame
        end

        local groups = {}
        function panel.addGroup(column, render)
            groups[#groups + 1] = { column = column, render = render }
        end
        local footer_column = (RENDERERS[data.kind] or RENDERERS.reading)(panel, data)
        addFooter(panel, data, footer_column)

        local content
        if horizontal then
            content = buildColumns(groups, content_width, padding, panel.gap, data.cover)
        else
            local items = {}
            for index, group in ipairs(groups) do
                if index > 1 then
                    addSeparator(items, content_width, panel.gap)
                end
                group.render(content_width, items)
            end
            content = VerticalGroup:new(items)
        end

        return makeFrame(content)
    end

    -- A one-paragraph status panel, content_width wide; width sets the frame's
    -- own width when given.
    local function buildStatus(metrics, text, content_width, width)
        local body_face = Font:getFace("smallinfofont", math_floor(13 * Util.scaleFactor(metrics) + 0.5))
        return FrameContainer:new({
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.button,
            color = Blitbuffer.COLOR_BLACK,
            radius = Size.radius.button,
            margin = 0,
            padding = Util.panelPadding(metrics),
            width = width,
            allow_mirroring = false,
            makeText(tostring(text or ""), body_face, content_width, true),
        })
    end

    return {
        build = build,
        buildStatus = buildStatus,
        resolveAlignment = resolveAlignment,
    }

end
