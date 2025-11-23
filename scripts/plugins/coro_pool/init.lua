-- scripts/plugins/coro_pool/init.lua
-- 协程池

local log = _G.log
local native = _G.pesh_native
local M = {}

local can_reset = native and native.reset_thread
if not can_reset then
    log.warn("Coroutine Pool: native.reset_thread is not available. Pooling will be disabled.")
end

local pool = {}
local MAX_POOL_SIZE = 64
local created_count = 0

local function worker_func(func, ...)
    local status, err = xpcall(func, function(err_msg)
        return debug.traceback(coroutine.running(), tostring(err_msg), 2)
    end, ...)
    
    if not status then
        log.error("Coroutine Pool: Error in running task:\n", tostring(err))
    end
end

function M.get()
    if not can_reset then
        return coroutine.create(worker_func)
    end
    
    local co = table.remove(pool)
    if co then
        log.trace("Coroutine Pool: Reusing coroutine. (Size: ", #pool, ")")
        return co
    else
        created_count = created_count + 1
        log.trace("Coroutine Pool: Creating new worker #", created_count)
        return coroutine.create(worker_func)
    end
end

function M.release(co)
    if not can_reset or not co or coroutine.status(co) ~= 'dead' then
        return
    end

    if #pool < MAX_POOL_SIZE then
        if native.reset_thread(co) then
            table.insert(pool, co)
        end
    end
end

function M.run(func, ...)
    local args = table.pack(...)
    local call_id = "ID_NOT_FOUND"
    
    if args.n >= 2 and type(args[2]) == "table" and args[2].unique_call_id then
        call_id = args[2].unique_call_id
    end
    log.debug("CORO_POOL: run() for Call ID: [", call_id, "]")

    local wrapped_func = function(...)
        worker_func(func, ...)
        M.release(coroutine.running())
    end

    local co_to_run = M.get()
    local status_run, err_run = coroutine.resume(co_to_run, wrapped_func, table.unpack(args, 1, args.n))

    if not status_run then
        log.error("CORO_POOL: Failed to resume worker: ", tostring(err_run))
        M.release(co_to_run)
    end
end

return M