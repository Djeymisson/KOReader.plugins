local ctx = require("modules.context")

local source = debug.getinfo(1, "S").source or ""
local plugin_dir = source:match("^@(.*/)") or source:match("^(.*/)") or ""
ctx.plugin_meta = dofile(plugin_dir .. "_meta.lua")

local module_names = {
	"modules.utils",
	"modules.widgets",
	"modules.core",
	"modules.dictionary",
	"modules.payload",
	"modules.translation",
	"modules.wikipedia",
	"modules.carousel",
}

for _, module_name in ipairs(module_names) do
	require(module_name)(ctx)
end

return ctx.LookupPreview
