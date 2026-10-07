local Device = require("device")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen
local math_floor = math.floor
local math_max = math.max

-- The information panel and the status block as on-screen overlays. Their
-- content comes from info_data.lua (what to show), info_covers.lua (book
-- covers) and info_render.lua (the widgets); this module places them on
-- screen and is the only one main.lua talks to.
local PanelOverlay = WidgetContainer:extend({
    -- Toasts are ignored while UIManager looks for the input target. The
    -- panels may be replaced while the dock remains open; keeping them in
    -- KOReader's non-blocking overlay layer prevents a refreshed panel from
    -- becoming the input target above the dock, and keeps the status block
    -- visually above the dock without intercepting its taps or the controls
    -- of a network-selection dialog. Unlike Notification, these widgets do
    -- not close themselves on input.
    modal = false,
    toast = true,
    -- Extra room reserved above the usual screen margin, e.g. to clear a
    -- sibling plugin's own floating overlay sitting on this same side. Left
    -- untouched (0) unless a caller has a reason to reserve more.
    extra_bottom_margin = 0,
})

function PanelOverlay:getScreenMargin()
    return math_max(0, tonumber(self.screen_margin) or Size.padding.large)
end

-- Left edge of a panel on the given side of the screen.
function PanelOverlay:getSideLeft(panel_width, margin)
    if self.panel_side == "right" then
        return Screen:getWidth() - margin - panel_width
    end
    return margin
end

function PanelOverlay:getExtraBottomMargin()
    return math_max(0, tonumber(self.extra_bottom_margin) or 0)
end

function PanelOverlay:onShow()
    UIManager:setDirty(self, "ui", self.dimen)
    return true
end

function PanelOverlay:onCloseWidget()
    if self._quickdock_suppress_close_refresh then
        return
    end
    UIManager:setDirty(nil, "ui", self.dimen)
end

local InfoPanelOverlay = PanelOverlay:extend({})

function InfoPanelOverlay:init()
    local panel_size = self.panel:getSize()
    local margin = self:getScreenMargin()
    if self.placement == "top" then
        self.dimen = Geom:new({ x = margin, y = margin, w = panel_size.w, h = panel_size.h })
        self[1] = self.panel
        return
    end
    -- Only the bottom offset grows here -- the horizontal margin stays the
    -- screen-edge one, so reserving room for a sibling overlay never pushes
    -- this panel sideways.
    local bottom_margin = margin + self:getExtraBottomMargin()
    self.dimen = Geom:new({
        x = math_floor(self:getSideLeft(panel_size.w, margin)),
        y = math_floor(math_max(margin, Screen:getHeight() - bottom_margin - panel_size.h)),
        w = panel_size.w,
        h = panel_size.h,
    })
    self[1] = self.panel
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

-- Stacked against anchor_widget, the information panel: above it beside the
-- column dock, below it with the arc dock's top panel.
local StatusPanelOverlay = PanelOverlay:extend({})

function StatusPanelOverlay:init()
    local panel_size = self.panel:getSize()
    local margin = self:getScreenMargin()
    local panel_gap = self.panel_gap or Size.padding.default
    local anchor_dimen = self.anchor_widget and self.anchor_widget.dimen
    if self.placement == "top" then
        -- Below the top information panel, or at the top edge without one.
        local top = margin
        if anchor_dimen then
            top = anchor_dimen.y + anchor_dimen.h + panel_gap
        end
        self.dimen = Geom:new({ x = margin, y = top, w = panel_size.w, h = panel_size.h })
        self[1] = self.panel
        return
    end

    -- With an anchor_widget (the panel below), this already stacks above
    -- whatever bottom offset that widget resolved to (extra margin included),
    -- so extra_bottom_margin only needs to apply to the fallback case below.
    local bottom = Screen:getHeight() - margin - self:getExtraBottomMargin()
    if anchor_dimen then
        bottom = anchor_dimen.y - panel_gap
    end
    self.dimen = Geom:new({
        x = math_floor(self:getSideLeft(panel_size.w, margin)),
        y = math_floor(math_max(margin, bottom - panel_size.h)),
        w = panel_size.w,
        h = panel_size.h,
    })
    self[1] = self.panel
end

return function(loadModule)
    local Util = loadModule("info_util")
    local Covers = loadModule("info_covers")(Util)
    local InfoData = loadModule("info_data")(Util, Covers)
    local Render = loadModule("info_render")(Util, Covers)

    local InfoPanel = {
        clearCoverCache = Covers.clearCoverCache,
        clearRecentCoverCache = Covers.clearRecentCoverCache,
        collect = InfoData.collect,
    }

    -- Caches a mode no longer needs once it is disabled.
    local RELEASE = {
        reading = Covers.clearCoverCache,
        recent = Covers.clearRecentCoverCache,
    }

    function InfoPanel.release(kind, plugin)
        if RELEASE[kind] then
            RELEASE[kind](plugin)
        end
    end

    -- Overlays are placed by a view (QuickDock:getPanelView()):
    --   metrics, screen_margin: the dock's dimensions and screen margin
    --   placement: "top" along the top of the screen, otherwise beside the
    --     column dock, on panel_side, extra_bottom_margin above the bottom
    --   text_alignment: the panel text alignment setting

    -- The information panel showing data. plugin hosts the panel's taps and
    -- icons: getIcon(), openRecentDocument(), setRecentDocumentsPage().
    function InfoPanel.createOverlay(plugin, data, view)
        local screen_margin = Util.screenMargin(view.screen_margin)
        local top = view.placement == "top"
        local panel_side = view.panel_side == "left" and "left" or "right"
        local maximum_width = top and Screen:getWidth() - 2 * screen_margin
            or Util.maximumPanelWidth(screen_margin)
        local panel = Render.build(plugin, data, {
            metrics = view.metrics,
            maximum_outer_width = maximum_width,
            horizontal = top,
            -- The top panel aligns its nearest screen edge to the left.
            text_alignment = Render.resolveAlignment(view.text_alignment, top and "left" or panel_side),
        })
        local overlay = InfoPanelOverlay:new({
            panel = panel,
            placement = view.placement,
            panel_side = panel_side,
            screen_margin = screen_margin,
            dithered = data.cover ~= nil or data.kind == "recent",
            extra_bottom_margin = not top and view.extra_bottom_margin or nil,
        })
        panel.show_parent = overlay
        return overlay
    end

    -- The status block showing text, stacked against view.anchor_widget (the
    -- information panel): below the top panel, above the side one. Along the
    -- top it is as wide as the top panel.
    function InfoPanel.createStatusOverlay(text, view)
        local metrics = view.metrics
        local top = view.placement == "top"
        local panel
        if top then
            local screen_margin = Util.screenMargin(view.screen_margin)
            local width = Screen:getWidth() - 2 * screen_margin
            local content_width = width - 2 * (Util.panelPadding(metrics) + Size.border.button)
            panel = Render.buildStatus(metrics, text, content_width, width)
        else
            local content_width = Util.panelContentWidth(metrics, Util.maximumPanelWidth(view.screen_margin))
            panel = Render.buildStatus(metrics, text, content_width)
        end
        local overlay = StatusPanelOverlay:new({
            panel = panel,
            placement = view.placement,
            panel_side = view.panel_side == "left" and "left" or "right",
            screen_margin = view.screen_margin,
            panel_gap = Size.padding.default,
            anchor_widget = view.anchor_widget,
            extra_bottom_margin = not top and view.extra_bottom_margin or nil,
        })
        panel.show_parent = overlay
        return overlay
    end

    return InfoPanel

end
