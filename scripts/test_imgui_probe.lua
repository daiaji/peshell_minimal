-- Offline smoke test for the ImGui loader. It must not require cimgui to exist.

package.path = "./scripts/?.lua;./scripts/?/init.lua;./scripts/lib/?.lua;./scripts/lib/?/init.lua;" .. package.path

local imgui = require("ui.imgui")
local status = imgui.status()

assert(type(status) == "table")
assert(type(status.available) == "boolean")
if status.available then
    assert(type(status.version) == "string")
else
    assert(type(status.error) == "string")
end

_G.log = {
    info = function() end,
    warn = function() end,
}
local plugin = require("plugins.imgui")
assert(type(plugin.__commands["imgui-probe"]) == "function")
assert(type(plugin.__commands["imgui-native-smoke"]) == "function")

local old_native = _G.pesh_native
_G.pesh_native = nil
local result, err = plugin.native_smoke({ frames = 1 })
assert(result == nil)
assert(type(err) == "string")
_G.pesh_native = old_native

package.loaded["plugins.imgui"] = nil
local old_host = package.loaded["ui.native_host"]
local old_runtime = package.loaded["ui.runtime"]
local old_message = package.loaded["ui.widgets.message_box"]
local old_picker = package.loaded["ui.widgets.file_picker"]

local calls = { frames = 0 }
package.loaded["ui.native_host"] = {
    create_win32_d3d11 = function(opts)
        assert(opts.title == "Smoke")
        return {
            hwnd = "hwnd",
            device = "device",
            device_context = "context",
            swap_chain = "swap",
            d3d = "d3d",
            destroy = function() calls.native_destroy = true end,
        }
    end,
}
package.loaded["ui.runtime"] = {
    create = function(opts)
        assert(opts.backend == "win32_d3d11")
        assert(opts.hwnd == "hwnd")
        return { opts = opts }
    end,
    frame = function(_, draw)
        calls.frames = calls.frames + 1
        draw({ token = "ig" })
        return calls.frames < 2
    end,
    shutdown = function(rt)
        calls.shutdown = true
        rt.opts.destroy()
        return true
    end,
}
package.loaded["ui.widgets.message_box"] = {
    create = function(opts)
        assert(opts.buttons == "ok_cancel")
        return { selected = "OK" }
    end,
    draw = function(model, ig)
        calls.message_draw = ig.token
        model.selected = "OK"
    end,
}
package.loaded["ui.widgets.file_picker"] = {
    create = function(opts)
        assert(opts.cwd == "/tmp")
        return { selected = "/tmp/a.txt" }
    end,
    draw = function(model, ig)
        calls.picker_draw = ig.token
        model.selected = "/tmp/a.txt"
    end,
}

plugin = require("plugins.imgui")
result, err = plugin.native_smoke({ title = "Smoke", cwd = "/tmp", frames = 2, fs = {} })
assert(result, err)
assert(result.frames == 2)
assert(result.message == "OK")
assert(result.file == "/tmp/a.txt")
assert(calls.message_draw == "ig")
assert(calls.picker_draw == "ig")
assert(calls.shutdown == true)
assert(calls.native_destroy == true)

package.loaded["plugins.imgui"] = nil
package.loaded["ui.native_host"] = old_host
package.loaded["ui.runtime"] = old_runtime
package.loaded["ui.widgets.message_box"] = old_message
package.loaded["ui.widgets.file_picker"] = old_picker

return true
