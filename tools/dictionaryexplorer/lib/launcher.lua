--[[
The plugin run.sh installs into the throwaway KOReader profile. It waits for
the book to be ready, then hands the harness to the suite named by DE_SUITE.
It is not part of the Dictionary Explorer plugin, and is never shipped.
]]

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Launcher = WidgetContainer:extend({ name = "zzharness", is_doc_only = true })

function Launcher:onReaderReady()
	if self.started then
		return
	end
	self.started = true

	local harness = dofile(os.getenv("DE_TOOLS") .. "/lib/harness.lua")
	harness.init(self.ui)
	local ok, suite = pcall(dofile, os.getenv("DE_SUITE"))
	if not ok or type(suite) ~= "function" then
		harness.check("the suite loads", false, suite)
		harness.finish()
		return
	end
	-- Let KOReader finish drawing the book, then clear its first-run notices.
	harness.step(1, function()
		harness.closeStartupMessages()
	end)
	local started, err = pcall(suite, harness, self.ui)
	if not started then
		harness.check("the suite starts", false, err)
		harness.finish()
	end
end

return Launcher
