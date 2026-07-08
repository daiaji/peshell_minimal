-- Lua-side contract for native UI host integration.
-- The C++ host is expected to expose pesh_native.ui when real rendering is enabled.

local M = {}

function M.available()
    return type(_G.pesh_native) == "table" and type(_G.pesh_native.ui) == "table"
end

function M.status()
    if not M.available() then
        return { available = false, error = "pesh_native.ui unavailable" }
    end
    local ui = _G.pesh_native.ui
    if type(ui.create_window) ~= "function" then return { available = false, error = "pesh_native.ui.create_window missing" } end
    if type(ui.create_d3d11) ~= "function" then return { available = false, error = "pesh_native.ui.create_d3d11 missing" } end
    if type(ui.destroy_window) ~= "function" then return { available = false, error = "pesh_native.ui.destroy_window missing" } end
    if type(ui.destroy_d3d11) ~= "function" then return { available = false, error = "pesh_native.ui.destroy_d3d11 missing" } end
    if type(ui.begin_d3d11_frame) ~= "function" then return { available = false, error = "pesh_native.ui.begin_d3d11_frame missing" } end
    if type(ui.end_d3d11_frame) ~= "function" then return { available = false, error = "pesh_native.ui.end_d3d11_frame missing" } end
    return { available = true }
end

function M.create_win32_d3d11(opts)
    opts = opts or {}
    local status = M.status()
    if not status.available then return nil, status.error end
    local ui = _G.pesh_native.ui

    local window, win_err = ui.create_window(opts.title or "PEShell", opts.width or 960, opts.height or 640)
    if not window then return nil, win_err or "create_window failed" end

    local d3d, d3d_err = ui.create_d3d11(window)
    if not d3d then
        ui.destroy_window(window)
        return nil, d3d_err or "create_d3d11 failed"
    end

    return {
        window = window,
        hwnd = window.hwnd,
        device = d3d.device,
        device_context = d3d.device_context,
        swap_chain = d3d.swap_chain,
        d3d = d3d,
        destroy = function()
            ui.destroy_d3d11(d3d)
            ui.destroy_window(window)
        end,
    }
end

return M
