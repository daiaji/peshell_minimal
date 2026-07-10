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

local old_render_fail = package.preload["ui.backends.render_fail"]
package.preload["ui.backends.render_fail"] = function()
    return {
        create = function() return { running = true } end,
        poll = function() return true end,
        new_frame = function() return true end,
        render = function() return nil, "render failed" end,
        shutdown = function() return true end,
    }
end
local rt_fail = assert(runtime.create({ backend = "render_fail" }))
local ok, render_err = pcall(function() runtime.frame(rt_fail) end)
assert(ok == false)
assert(tostring(render_err):find("render failed", 1, true))
package.preload["ui.backends.render_fail"] = old_render_fail

return true
