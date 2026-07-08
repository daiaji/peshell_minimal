-- Null ImGui backend for offline tests and headless environments.

local M = {}

function M.create(opts)
    opts = opts or {}
    return {
        name = "null",
        title = opts.title or "PEShell",
        running = true,
        frames = 0,
    }
end

function M.poll(ctx)
    return ctx and ctx.running ~= false
end

function M.new_frame(ctx)
    if ctx then ctx.frames = (ctx.frames or 0) + 1 end
    return true
end

function M.render()
    return true
end

function M.shutdown(ctx)
    if ctx then ctx.running = false end
    return true
end

return M
