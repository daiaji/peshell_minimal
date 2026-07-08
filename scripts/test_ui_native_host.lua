package.path = "./scripts/?.lua;./scripts/?/init.lua;./scripts/lib/?.lua;./scripts/lib/?/init.lua;" .. package.path

local host = require("ui.native_host")
local old = _G.pesh_native
_G.pesh_native = nil
assert(host.available() == false)
assert(host.status().available == false)

_G.pesh_native = { ui = {} }
assert(host.status().available == false)

local destroyed = {}
_G.pesh_native = { ui = {
    create_window = function(title, width, height)
        assert(title == "Test")
        assert(width == 320)
        assert(height == 240)
        return { hwnd = "hwnd" }
    end,
    destroy_window = function(window)
        destroyed.window = window.hwnd
        return true
    end,
    create_d3d11 = function(window)
        assert(window.hwnd == "hwnd")
        return { device = "device", device_context = "context", swap_chain = "swap" }
    end,
    destroy_d3d11 = function(d3d)
        destroyed.d3d = d3d.device
        return true
    end,
    begin_d3d11_frame = function() return true end,
    end_d3d11_frame = function() return true end,
} }
assert(host.status().available == true)
local native, err = host.create_win32_d3d11({ title = "Test", width = 320, height = 240 })
assert(native, err)
assert(native.hwnd == "hwnd")
assert(native.device == "device")
assert(native.device_context == "context")
assert(native.swap_chain == "swap")
assert(type(native.d3d) == "table")
native.destroy()
assert(destroyed.d3d == "device")
assert(destroyed.window == "hwnd")

_G.pesh_native = old
return true
