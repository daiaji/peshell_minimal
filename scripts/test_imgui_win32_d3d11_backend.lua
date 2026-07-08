package.path = "./scripts/?.lua;./scripts/?/init.lua;./scripts/lib/?.lua;./scripts/lib/?/init.lua;" .. package.path

local backend = require("ui.backends.win32_d3d11")
local status = backend.status()
assert(type(status) == "table")
assert(type(status.available) == "boolean")
if not status.available then assert(type(status.error) == "string") end

local ctx, err = backend.create({})
assert(ctx == nil)
assert(type(err) == "string")

local old_native = _G.pesh_native
local calls = {}
_G.pesh_native = { ui = {
    begin_d3d11_frame = function(d3d)
        calls.begin_d3d11_frame = d3d.token
        return true
    end,
    end_d3d11_frame = function(d3d)
        calls.end_d3d11_frame = d3d.token
        return true
    end,
} }

local old_loader = package.loaded["ui.imgui"]
package.loaded["ui.imgui"] = {
    load = function()
        return {
            ImGui_ImplDX11_RenderDrawData = function(data)
                calls.render = data
            end,
            igGetDrawData = function() return "draw_data" end,
        }
    end,
}
package.loaded["ui.backends.win32_d3d11"] = nil
backend = require("ui.backends.win32_d3d11")
assert(backend.render({ d3d = { token = "d3d" } }) == true)
assert(calls.begin_d3d11_frame == "d3d")
assert(calls.render == "draw_data")
assert(calls.end_d3d11_frame == "d3d")

package.loaded["ui.backends.win32_d3d11"] = nil
package.loaded["ui.imgui"] = old_loader
_G.pesh_native = old_native

return true
