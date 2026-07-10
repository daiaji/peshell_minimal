local imgui = require("ui.imgui")

local M = {}

local function load_backend(name)
    name = name or "null"
    return require("ui.backends." .. name)
end

function M.create(opts)
    opts = opts or {}
    local backend = load_backend(opts.backend)
    local status = imgui.status()
    local imgui_ctx = nil
    if status.available then
        imgui_ctx = assert(imgui.create_context())
    end
    local backend_ctx, backend_err = backend.create(opts)
    if not backend_ctx then
        if imgui_ctx then imgui.destroy_context(imgui_ctx) end
        return nil, backend_err or "backend create failed"
    end
    return {
        backend = backend,
        backend_ctx = backend_ctx,
        imgui_ctx = imgui_ctx,
        imgui_available = status.available,
        imgui_error = status.error,
    }
end

function M.frame(rt, draw)
    if not rt.backend.poll(rt.backend_ctx) then return false end
    rt.backend.new_frame(rt.backend_ctx)
    if rt.imgui_available then
        local cimgui = assert(imgui.load())
        cimgui.igNewFrame()
        if draw then draw(cimgui) end
        cimgui.igRender()
    elseif draw then
        draw(nil, rt.imgui_error)
    end
    local ok, err = rt.backend.render(rt.backend_ctx)
    if not ok then error(err or "backend render failed") end
    return true
end

function M.shutdown(rt)
    if not rt then return true end
    if rt.imgui_ctx then imgui.destroy_context(rt.imgui_ctx) end
    return rt.backend.shutdown(rt.backend_ctx)
end

return M
