local ctx = require("modules.context")

require("modules.utils")(ctx)
require("modules.widgets")(ctx)
require("modules.core")(ctx)
require("modules.dictionary")(ctx)
require("modules.payload")(ctx)
require("modules.translation")(ctx)
require("modules.wikipedia")(ctx)
require("modules.carousel")(ctx)

return ctx.LookupPreview
