local Device = require("device")

-- A saved boolean: one that defaults to true is on unless explicitly false.
local function readBoolean(key, default)
    local value = G_reader_settings:readSetting(key)
    if default then
        return value ~= false
    end
    return value == true
end

local function saveBoolean(key, enabled)
    G_reader_settings:saveSetting(key, enabled and true or false)
end

-- A saved value that must be one of allowed's keys.
local function readChoice(key, allowed, default)
    local value = G_reader_settings:readSetting(key)
    if allowed[value] then
        return value
    end
    return default
end

local function saveChoice(key, value, allowed, default)
    G_reader_settings:saveSetting(key, allowed[value] and value or default)
end

-- A saved number that must be one of a list's values.
local function readListed(key, list, default)
    local value = tonumber(G_reader_settings:readSetting(key))
    for _index, allowed in ipairs(list) do
        if value == allowed then
            return value
        end
    end
    return default
end

local function toSet(...)
    local set = {}
    for index = 1, select("#", ...) do
        set[select(index, ...)] = true
    end
    return set
end

-- The saved preferences, as plain functions over KOReader's settings: no
-- plugin instance is involved, so every instance (reader, file browser) sees
-- the same values. Getters validate what they read and fall back to the
-- default; setters only store. Effects of a change on an open dock (freeing
-- caches, ...) belong to the caller.
return function(C)
    local SIDES = toSet("left", "right")
    local SIDE_MODES = toSet(C.SIDE_MODE_FIXED, C.SIDE_MODE_GESTURE)
    local DOCK_SHAPES = toSet(C.DOCK_SHAPE_COLUMN, C.DOCK_SHAPE_ARC)
    local ARC_EMPTY_SPACES = toSet(C.ARC_EMPTY_SPACE_END, C.ARC_EMPTY_SPACE_START)
    local TEXT_ALIGNMENTS = toSet(
        C.INFO_PANEL_TEXT_LEFT,
        C.INFO_PANEL_TEXT_CENTER,
        C.INFO_PANEL_TEXT_SCREEN_EDGE
    )
    -- Contexts an action can be pinned to; automatic is the lack of one.
    local ACTION_CONTEXTS = toSet(C.ACTION_CONTEXT_ALL, C.ACTION_CONTEXT_READER, C.ACTION_CONTEXT_BROWSER)

    local Prefs = {}

    -- On/off preferences: getter, setter, key, default.
    local BOOLEAN_SETTINGS = {
        { "showSideButton", "setShowSideButton", C.SETTING_SHOW_SIDE_BUTTON, true },
        { "showCloseButton", "setShowCloseButton", C.SETTING_SHOW_CLOSE_BUTTON, false },
        { "showContextButton", "setShowContextButton", C.SETTING_SHOW_CONTEXT_BUTTON, true },
        { "showArcBand", "setShowArcBand", C.SETTING_ARC_BAND, true },
        { "fillArc", "setFillArc", C.SETTING_ARC_FILL, false },
        { "closeDockTogether", "setCloseDockTogether", C.SETTING_CLOSE_TOGETHER, false },
        { "automaticVisibilityEnabled", "setAutomaticVisibility", C.SETTING_AUTO_VISIBILITY, false },
        { "showInfoPanelCover", "setShowInfoPanelCover", C.SETTING_SHOW_INFO_PANEL_COVER, true },
    }
    for _index, setting in ipairs(BOOLEAN_SETTINGS) do
        local getter, setter, key, default = setting[1], setting[2], setting[3], setting[4]
        Prefs[getter] = function()
            return readBoolean(key, default)
        end
        Prefs[setter] = function(enabled)
            saveBoolean(key, enabled)
        end
    end

    -- Lighting controls are only offered on devices that have them.
    function Prefs.showFrontlightSlider()
        return Device:hasFrontlight() and readBoolean(C.SETTING_SHOW_FRONTLIGHT_SLIDER, true)
    end

    function Prefs.setShowFrontlightSlider(enabled)
        saveBoolean(C.SETTING_SHOW_FRONTLIGHT_SLIDER, enabled)
    end

    function Prefs.showWarmthSlider()
        return Device:hasNaturalLight() and readBoolean(C.SETTING_SHOW_WARMTH_SLIDER, true)
    end

    function Prefs.setShowWarmthSlider(enabled)
        saveBoolean(C.SETTING_SHOW_WARMTH_SLIDER, enabled)
    end

    -- Actions and their visibility. The tables are returned as saved; the
    -- caller owns their cleanup and copies.

    function Prefs.readActions()
        return G_reader_settings:readSetting(C.SETTING_ACTIONS)
    end

    function Prefs.saveActions(actions)
        G_reader_settings:saveSetting(C.SETTING_ACTIONS, actions)
    end

    -- Per-action contexts, keeping only valid ones.
    function Prefs.readActionContexts()
        local saved_contexts = G_reader_settings:readSetting(C.SETTING_ACTION_CONTEXTS)
        local action_contexts = {}
        if type(saved_contexts) == "table" then
            for action_id, context in pairs(saved_contexts) do
                if ACTION_CONTEXTS[context] then
                    action_contexts[action_id] = context
                end
            end
        end
        return action_contexts
    end

    function Prefs.saveActionContexts(action_contexts)
        G_reader_settings:saveSetting(C.SETTING_ACTION_CONTEXTS, action_contexts)
    end

    function Prefs.isActionContext(context)
        return ACTION_CONTEXTS[context] == true
    end

    -- Placement and shape

    function Prefs.getSide()
        return readChoice(C.SETTING_SIDE, SIDES, "right")
    end

    function Prefs.setSide(side)
        saveChoice(C.SETTING_SIDE, side, SIDES, "right")
    end

    function Prefs.getSideMode()
        return readChoice(C.SETTING_SIDE_MODE, SIDE_MODES, C.SIDE_MODE_GESTURE)
    end

    function Prefs.setSideMode(mode)
        saveChoice(C.SETTING_SIDE_MODE, mode, SIDE_MODES, C.SIDE_MODE_FIXED)
    end

    function Prefs.getDockSize()
        return readChoice(C.SETTING_DOCK_SIZE, C.DOCK_SIZE_FACTORS, C.DOCK_SIZE_SMALL)
    end

    function Prefs.setDockSize(size)
        saveChoice(C.SETTING_DOCK_SIZE, size, C.DOCK_SIZE_FACTORS, C.DOCK_SIZE_SMALL)
    end

    function Prefs.getMaxActionDockHeight()
        return readChoice(
            C.SETTING_MAX_ACTION_DOCK_HEIGHT,
            C.MAX_ACTION_DOCK_HEIGHT_FACTORS,
            C.MAX_ACTION_DOCK_HEIGHT_100
        )
    end

    function Prefs.setMaxActionDockHeight(height)
        saveChoice(
            C.SETTING_MAX_ACTION_DOCK_HEIGHT,
            height,
            C.MAX_ACTION_DOCK_HEIGHT_FACTORS,
            C.MAX_ACTION_DOCK_HEIGHT_100
        )
    end

    function Prefs.getMaxActionDockHeightFactor()
        return C.MAX_ACTION_DOCK_HEIGHT_FACTORS[Prefs.getMaxActionDockHeight()]
    end

    function Prefs.getDockShape()
        return readChoice(C.SETTING_DOCK_SHAPE, DOCK_SHAPES, C.DOCK_SHAPE_COLUMN)
    end

    function Prefs.setDockShape(shape)
        saveChoice(C.SETTING_DOCK_SHAPE, shape, DOCK_SHAPES, C.DOCK_SHAPE_COLUMN)
    end

    function Prefs.isArcLayout()
        return Prefs.getDockShape() == C.DOCK_SHAPE_ARC
    end

    function Prefs.getArcEmptySpace()
        return readChoice(C.SETTING_ARC_EMPTY_SPACE, ARC_EMPTY_SPACES, C.ARC_EMPTY_SPACE_END)
    end

    function Prefs.setArcEmptySpace(position)
        saveChoice(C.SETTING_ARC_EMPTY_SPACE, position, ARC_EMPTY_SPACES, C.ARC_EMPTY_SPACE_END)
    end

    function Prefs.getArcAngle()
        return readListed(C.SETTING_ARC_ANGLE, C.ARC_ANGLES, C.DEFAULT_ARC_ANGLE)
    end

    function Prefs.setArcAngle(angle)
        G_reader_settings:saveSetting(C.SETTING_ARC_ANGLE, tonumber(angle) or C.DEFAULT_ARC_ANGLE)
    end

    -- Information panel

    function Prefs.getRecentDocumentsCount()
        return readListed(
            C.SETTING_RECENT_DOCUMENTS_COUNT,
            C.RECENT_DOCUMENTS_COUNTS,
            C.DEFAULT_RECENT_DOCUMENTS_COUNT
        )
    end

    function Prefs.setRecentDocumentsCount(count)
        G_reader_settings:saveSetting(
            C.SETTING_RECENT_DOCUMENTS_COUNT,
            tonumber(count) or C.DEFAULT_RECENT_DOCUMENTS_COUNT
        )
    end

    function Prefs.isInfoPanelKindEnabled(kind)
        local mode = C.INFO_PANEL_MODES_BY_KIND[kind]
        if not mode then
            return false
        end
        return readBoolean(mode.setting, mode.default)
    end

    function Prefs.setInfoPanelKindEnabled(kind, enabled)
        local mode = C.INFO_PANEL_MODES_BY_KIND[kind]
        if mode then
            saveBoolean(mode.setting, enabled)
        end
    end

    -- Enabled panels in the order the switch button cycles through them.
    function Prefs.getEnabledInfoPanelKinds()
        local kinds = {}
        for _index, mode in ipairs(C.INFO_PANEL_MODES) do
            if Prefs.isInfoPanelKindEnabled(mode.kind) then
                kinds[#kinds + 1] = mode.kind
            end
        end
        return kinds
    end

    function Prefs.showInfoPanel()
        return #Prefs.getEnabledInfoPanelKinds() > 0
    end

    -- The switch button only shows with more than one panel to cycle through.
    function Prefs.showInfoPanelToggleButton()
        return #Prefs.getEnabledInfoPanelKinds() > 1
    end

    function Prefs.getInfoPanelTextAlignment()
        return readChoice(
            C.SETTING_INFO_PANEL_TEXT_ALIGNMENT,
            TEXT_ALIGNMENTS,
            C.INFO_PANEL_TEXT_SCREEN_EDGE
        )
    end

    function Prefs.setInfoPanelTextAlignment(alignment)
        saveChoice(
            C.SETTING_INFO_PANEL_TEXT_ALIGNMENT,
            alignment,
            TEXT_ALIGNMENTS,
            C.INFO_PANEL_TEXT_SCREEN_EDGE
        )
    end

    return Prefs
end
