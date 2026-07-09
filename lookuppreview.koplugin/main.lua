local ctx = require("modules.context")

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
