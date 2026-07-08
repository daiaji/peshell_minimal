package.path = "./scripts/?.lua;./scripts/?/init.lua;./scripts/lib/?.lua;./scripts/lib/?/init.lua;" .. package.path

local runtime = require("ui.runtime")
local rt = runtime.create({ backend = "null", title = "test" })

local called = false
assert(runtime.frame(rt, function(_, err)
    called = true
    if not rt.imgui_available then assert(type(err) == "string") end
end))
assert(called)
assert(rt.backend_ctx.frames == 1)
assert(runtime.shutdown(rt))

local old_preload = package.preload["ui.backends.fail"]
package.preload["ui.backends.fail"] = function()
    return {
        create = function() return nil, "backend failed" end,
    }
end
local failed, err = runtime.create({ backend = "fail" })
assert(failed == nil)
assert(err == "backend failed")
package.preload["ui.backends.fail"] = old_preload

return true
