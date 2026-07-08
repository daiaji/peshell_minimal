-- Win32 + D3D11 backend skeleton for cimgui.
-- The real window/device creation lives in a later native backend step.

local imgui = require("ui.imgui")

local M = {}

local function require_field(opts, name)
    if opts[name] == nil then return nil, name .. " required" end
    return opts[name]
end

function M.status()
    local cimgui, err = imgui.load()
    if not cimgui then return { available = false, error = err } end

    local required = {
        "ImGui_ImplWin32_Init",
        "ImGui_ImplWin32_NewFrame",
        "ImGui_ImplWin32_Shutdown",
        "ImGui_ImplDX11_Init",
        "ImGui_ImplDX11_NewFrame",
        "ImGui_ImplDX11_RenderDrawData",
        "ImGui_ImplDX11_Shutdown",
    }
    for _, name in ipairs(required) do
        local ok = pcall(function() return cimgui[name] end)
        if not ok then return { available = false, error = "missing cimgui backend symbol: " .. name } end
    end
    return { available = true }
end

function M.create(opts)
    opts = opts or {}
    local cimgui, err = imgui.load()
    if not cimgui then return nil, err end

    local hwnd, hwnd_err = require_field(opts, "hwnd")
    if not hwnd then return nil, hwnd_err end
    local device, device_err = require_field(opts, "device")
    if not device then return nil, device_err end
    local device_context, context_err = require_field(opts, "device_context")
    if not device_context then return nil, context_err end

    if not cimgui.ImGui_ImplWin32_Init(hwnd) then return nil, "ImGui_ImplWin32_Init failed" end
    if not cimgui.ImGui_ImplDX11_Init(device, device_context) then
        cimgui.ImGui_ImplWin32_Shutdown()
        return nil, "ImGui_ImplDX11_Init failed"
    end

    return {
        name = "win32_d3d11",
        hwnd = hwnd,
        device = device,
        device_context = device_context,
        d3d = opts.d3d,
        destroy = opts.destroy,
        running = true,
    }
end

function M.poll(ctx)
    local ui = type(_G.pesh_native) == "table" and type(_G.pesh_native.ui) == "table" and _G.pesh_native.ui or nil
    if ui and type(ui.poll_events) == "function" and not ui.poll_events() then
        if ctx then ctx.running = false end
        return false
    end
    return ctx and ctx.running ~= false
end

function M.new_frame()
    local cimgui = assert(imgui.load())
    cimgui.ImGui_ImplDX11_NewFrame()
    cimgui.ImGui_ImplWin32_NewFrame()
    return true
end

function M.render(ctx)
    local cimgui = assert(imgui.load())
    local ui = type(_G.pesh_native) == "table" and type(_G.pesh_native.ui) == "table" and _G.pesh_native.ui or nil
    if ui and type(ui.begin_d3d11_frame) == "function" and ctx and ctx.d3d then
        ui.begin_d3d11_frame(ctx.d3d)
    end
    cimgui.ImGui_ImplDX11_RenderDrawData(cimgui.igGetDrawData())
    if ui and type(ui.end_d3d11_frame) == "function" and ctx and ctx.d3d then
        ui.end_d3d11_frame(ctx.d3d)
    end
    return true
end

function M.shutdown(ctx)
    local cimgui = imgui.load()
    if cimgui then
        cimgui.ImGui_ImplDX11_Shutdown()
        cimgui.ImGui_ImplWin32_Shutdown()
    end
    if ctx then
        ctx.running = false
        if type(ctx.destroy) == "function" then ctx.destroy() end
    end
    return true
end

return M
