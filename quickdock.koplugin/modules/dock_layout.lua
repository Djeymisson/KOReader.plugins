local Size = require("ui/size")

local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local function scaleMetric(value, factor, minimum)
    return math_max(minimum or 1, math_floor(value * factor + 0.5))
end

-- Dock geometry as pure functions of their inputs: the dimensions for a
-- scale factor, how many rows the column fits, and how actions are split
-- into pages. Nothing here reads preferences or the plugin's state.
return function(C)
    local Layout = {}
    local metrics_cache = {}

    -- Every dock dimension for a scale factor (C.DOCK_SIZE_FACTORS). The
    -- result is shared and must not be modified.
    function Layout.metrics(factor)
        if metrics_cache[factor] then
            return metrics_cache[factor]
        end
        local button_height = scaleMetric(C.BASE_BUTTON_HEIGHT, factor)
        local button_side_padding = scaleMetric(C.BASE_BUTTON_SIDE_PADDING, factor)
        local side_button_height = scaleMetric(C.BASE_SIDE_BUTTON_HEIGHT, factor)
        local side_button_padding = scaleMetric(C.BASE_SIDE_BUTTON_PADDING, factor)
        local metrics = {
            button_icon_size = scaleMetric(C.BASE_BUTTON_ICON_SIZE, factor),
            button_height = button_height,
            button_side_padding = button_side_padding,
            button_width = button_height + 2 * button_side_padding,
            fallback_font_size = scaleMetric(18, factor),
            page_font_size = scaleMetric(24, factor),
            side_font_size = scaleMetric(22, factor),
            side_button_icon_size = scaleMetric(C.BASE_SIDE_BUTTON_ICON_SIZE, factor),
            side_button_height = side_button_height,
            side_button_padding = side_button_padding,
            side_button_outer_height = side_button_height
                + 2 * side_button_padding
                + 2 * Size.border.button,
            side_button_gap = scaleMetric(C.BASE_SIDE_BUTTON_GAP, factor),
            frontlight_slider_gap = scaleMetric(C.BASE_FRONTLIGHT_SLIDER_GAP, factor),
            frontlight_slider_padding = scaleMetric(C.BASE_FRONTLIGHT_SLIDER_PADDING, factor),
            frontlight_track_width = scaleMetric(C.BASE_FRONTLIGHT_TRACK_WIDTH, factor, 2),
            frontlight_knob_radius = scaleMetric(C.BASE_FRONTLIGHT_KNOB_RADIUS, factor, 5),
            -- Larger buttons need a longer ring, but only half as much longer, so
            -- the ring stays within reach of the thumb.
            arc_radius = scaleMetric(C.BASE_ARC_RADIUS, 1 + (factor - 1) / 2),
            arc_utility_diameter = math_floor((button_height + 2 * button_side_padding) * 0.8 + 0.5),
            arc_track_width = scaleMetric(C.BASE_ARC_TRACK_WIDTH, factor, 3),
            arc_knob_radius = scaleMetric(C.BASE_ARC_KNOB_RADIUS, factor, 6),
            scale_factor = factor,
        }
        metrics_cache[factor] = metrics
        return metrics
    end

    -- How many button rows the column dock fits, its page arrows and the
    -- reader/browser button included.
    --   screen_height: the screen's height
    --   height_factor: the share of it the dock may take
    --   stacked_buttons: buttons stacked above the column (side switch, ...)
    --   minimum_rows: the fewest rows to allow, whatever the screen
    function Layout.maxColumnRows(metrics, options)
        -- ButtonTable adds vertical padding and separators around the requested
        -- button height. Account for all of it before ButtonDialog decides that
        -- it needs a ScrollableContainer (and, consequently, a scrollbar).
        local button_row_height = metrics.button_height
            + 2 * Size.padding.buttontable
            + 2 * Size.span.vertical_default
        local row_separator_height = Size.line.medium
        local screen_height = options.screen_height
        local dialog_height = screen_height
            - 2 * Size.padding.buttontable
            - 2 * Size.margin.default
        local stacked_buttons = options.stacked_buttons or 0
        local screen_available_height = screen_height
            - 2 * C.DOCK_MARGIN
            - 2 * Size.border.window
            - stacked_buttons * metrics.side_button_outer_height
            - stacked_buttons * metrics.side_button_gap
        local configured_height = math_floor(screen_height * options.height_factor)
            - 2 * Size.border.window
        local available_height = math_min(
            dialog_height,
            screen_available_height,
            configured_height
        )
        return math_max(options.minimum_rows, math_floor(
            (available_height + row_separator_height)
            / (button_row_height + row_separator_height)
        ))
    end

    -- Splits action_count actions into pages of at most max_rows items:
    -- fixed_rows items (the reader/browser button) only on the first page,
    -- and the page arrows wherever there is a page before or after.
    -- Returns a list of { first, last } action ranges.
    function Layout.paginate(action_count, max_rows, fixed_rows)
        local first_page_capacity = max_rows - fixed_rows
        if action_count <= first_page_capacity then
            return { { first = 1, last = action_count } }
        end

        local pages = {}
        local first = 1
        while first <= action_count do
            local remaining = action_count - first + 1
            local action_capacity
            if #pages == 0 then
                -- The reader/browser button belongs only to the first page, which
                -- also needs the next-page arrow when pagination is active.
                action_capacity = max_rows - fixed_rows - 1
            elseif remaining <= max_rows - 1 then
                -- The last page only needs the previous-page arrow.
                action_capacity = remaining
            else
                -- Intermediate pages need one navigation arrow at each end.
                action_capacity = max_rows - 2
            end
            local last = math_min(action_count, first + action_capacity - 1)
            pages[#pages + 1] = { first = first, last = last }
            first = last + 1
        end
        return pages
    end

    return Layout
end
