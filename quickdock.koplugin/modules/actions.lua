local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")

local function copyTable(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, child in pairs(value) do
        result[copyTable(key)] = copyTable(child)
    end
    return result
end

-- The configured actions and where they show. Each plugin instance (reader,
-- file browser) keeps its own copy: self.actions, edited in place by
-- Dispatcher's menu, which sets self.updated, and self.action_contexts, the
-- per-action visibility. Another instance may save new actions meanwhile,
-- so a copy without local edits is reloaded before use, and only local edits
-- are ever saved: an untouched copy must not overwrite a newer one.
return function(QuickDock, C, lib)
    local Prefs = lib.Prefs

    function QuickDock:loadActions()
        local actions = Prefs.readActions()
        if type(actions) ~= "table" then
            return copyTable(C.DEFAULT_ACTIONS)
        end

        -- Dispatcher represents “Nothing” as an empty table. Keep that as an
        -- explicit empty configuration instead of mistaking it for first use and
        -- restoring the default actions when another KOReader UI is opened.
        if type(actions.settings) ~= "table" then
            actions.settings = {}
        end

        -- Execution modes are not offered by Quick Dock. Drop any left over from
        -- older versions so the arrange dialog does not show QuickMenu separators.
        local settings = actions.settings
        settings.show_as_quickmenu = nil
        settings.execute_one_by_one = nil
        settings.quickmenu_separators = nil
        settings.keep_open_on_apply = nil
        settings.anchor_quickmenu = nil
        settings.quickmenu_position = nil

        -- The context-aware action is a fixed dock button, not a configurable
        -- action. Discard a stray saved entry to avoid showing it twice.
        actions[C.ACTION_HOME] = nil
        local order = actions.settings.order
        if type(order) == "table" then
            for index = #order, 1, -1 do
                if order[index] == C.ACTION_HOME then
                    table.remove(order, index)
                end
            end
        end
        return actions
    end

    function QuickDock:saveActions()
        Prefs.saveActions(self.actions)
    end

    -- Saves the actions edited in this instance, if any.
    function QuickDock:savePendingActions()
        if self.updated then
            self:saveActions()
            self.updated = false
        end
    end

    function QuickDock:resetActions()
        self.actions = copyTable(C.DEFAULT_ACTIONS)
        self.updated = false
        self:saveActions()
    end

    -- Another UI instance (reader or file browser) may have changed the
    -- actions or their visibility since this instance read them. Dispatcher
    -- looks the actions up on self each time, so replacing them is safe.
    function QuickDock:reloadSharedSettings()
        self.action_contexts = Prefs.readActionContexts()
        if not self.updated then
            self.actions = self:loadActions()
        end
    end

    function QuickDock:getAutomaticActionVisibility(action_id)
        if C.BROWSER_ONLY_ACTIONS[action_id] then
            return C.ACTION_CONTEXT_BROWSER
        elseif C.READER_ONLY_ACTIONS[action_id] or tostring(action_id):match("^kopt_") then
            return C.ACTION_CONTEXT_READER
        end
        return C.ACTION_CONTEXT_ALL
    end

    function QuickDock:getActionVisibilityMode(action_id)
        local override = self.action_contexts[action_id]
        if override then
            return override
        elseif Prefs.automaticVisibilityEnabled() then
            return C.ACTION_CONTEXT_AUTOMATIC
        end
        return C.ACTION_CONTEXT_ALL
    end

    function QuickDock:getEffectiveActionVisibility(action_id)
        local mode = self:getActionVisibilityMode(action_id)
        if mode == C.ACTION_CONTEXT_AUTOMATIC then
            return self:getAutomaticActionVisibility(action_id)
        end
        return mode
    end

    function QuickDock:setActionVisibility(action_id, context)
        self.action_contexts[action_id] = Prefs.isActionContext(context) and context or nil
        Prefs.saveActionContexts(self.action_contexts)
    end

    function QuickDock:resetActionVisibility()
        self.action_contexts = {}
        Prefs.saveActionContexts(self.action_contexts)
    end

    function QuickDock:getConfiguredActions()
        local configured_actions = {}
        for _index, item in ipairs(Dispatcher.getDisplayList(self.actions)) do
            if item.key ~= C.ACTION_HOME then
                configured_actions[#configured_actions + 1] = item
            end
        end
        return configured_actions
    end

    function QuickDock:getDisplayActions()
        local display_actions = {}
        local current_context = self:getCurrentActionContext()
        for _index, item in ipairs(self:getConfiguredActions()) do
            local visibility = self:getEffectiveActionVisibility(item.key)
            if visibility == C.ACTION_CONTEXT_ALL or visibility == current_context then
                display_actions[#display_actions + 1] = item
            end
        end
        return display_actions
    end

    -- The actions the dock shows here, or nil when it would have no button.
    function QuickDock:getDockActions()
        local actions = self:getDisplayActions()
        if #actions == 0 and not Prefs.showContextButton() then
            return nil
        end
        return actions
    end

    function QuickDock:executeAction(action_id)
        local value = self.actions[action_id]
        if value == nil then
            return
        end

        -- Wi-Fi and night mode run in place. Every other action closes the dock
        -- before dispatch so dialogs and context changes always start from a
        -- clean widget stack.
        if self:executeInlineAction(action_id) then
            return
        end
        self:closeDock()
        UIManager:scheduleIn(C.DISPATCH_DELAY, function()
            -- Bookshelf may handle History itself.
            if action_id ~= "history" or not self:openBookshelfRecent() then
                Dispatcher:execute({ [action_id] = value })
            end
        end)
    end
end
