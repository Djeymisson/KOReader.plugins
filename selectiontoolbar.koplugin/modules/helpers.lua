-- Small helpers shared by several modules: reading multiple-choice settings, telling a
-- live selection from a saved highlight, and refreshing screen areas.

local UIManager = require("ui/uimanager")

local function findChoice(choices, id)
    for _, choice in ipairs(choices) do
        if choice.id == id then
            return choice
        end
    end
end

-- The saved choice of a multiple-choice setting, or the default one if it is unset or
-- no longer exists.
local function readChoice(setting, choices, default_id)
    return findChoice(choices, G_reader_settings:readSetting(setting)) or findChoice(choices, default_id)
end

local function isLiveSelection(selected_text)
    return selected_text and type(selected_text.pos0) == "string" and type(selected_text.pos1) == "string"
end

local function refreshRects(widget, rects)
    for _, rect in ipairs(rects) do
        UIManager:setDirty(widget, "ui", rect)
    end
end

return {
    findChoice = findChoice,
    readChoice = readChoice,
    isLiveSelection = isLiveSelection,
    refreshRects = refreshRects,
}
