-- scripts/pesh-api/coro_pool.lua
-- 一个基于 OpenResty LuaJIT lua_resetthread 的可靠协程池 (v2.0 - Final)

local log = require("pesh-api.log")
local native = _G.pesh_native
local M = {}

local can_reset = native and native.reset_thread
if not can_reset then
    log.warn("Coroutine Pool: native.reset_thread is not available. Pooling will be disabled.")
end

local pool = {}
local MAX_POOL_SIZE = 64
local created_count = 0

-- [核心修改] 这是一个简单的工作者函数，它只执行一次任务。
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
        -- 如果不支持重置，总是创建一个新的协程来执行工作者函数
        return coroutine.create(worker_func)
    end
    
    local co = table.remove(pool)
    if co then
        log.trace("Coroutine Pool: Reusing coroutine from pool. (Pool size: ", #pool, ")")
        return co
    else
        created_count = created_count + 1
        log.trace("Coroutine Pool: Creating new worker #", created_count)
        return coroutine.create(worker_func)
    end
end

function M.release(co)
    if not can_reset or not co or coroutine.status(co) ~= 'dead' then
        -- 只有当协程池启用，且协程确实已经死亡时才回收
        return
    end

    if #pool < MAX_POOL_SIZE then
        if native.reset_thread(co) then
            log.trace("Coroutine Pool: Coroutine ", tostring(co), " reset and returned to pool. (Pool size: ", #pool + 1, ")")
            table.insert(pool, co)
        else
            log.warn("Coroutine Pool: Could not reset coroutine ", tostring(co), ". It will be garbage collected.")
        end
    else
        log.trace("Coroutine Pool: Pool is full. Coroutine ", tostring(co), " will be garbage collected.")
    end
end

-- [核心修改] run 函数现在负责获取、执行和释放协程
function M.run(func, ...)
    local co = M.get()
    
    local status, err = coroutine.resume(co, func, ...)
    if not status then
        log.error("Coroutine Pool: Failed to resume worker: ", tostring(err))
    end
    
    -- [关键] 如果协程在 resume 后立即死亡（即它是一个同步完成的短任务，没有yield），
    -- 我们就在这里尝试回收它。如果它 yield 了，它会在未来某个时刻死亡，
    -- 我们需要找到一种方法在那个时候回收它。
    -- 目前的设计，我们假设由 async.run 启动的任务是“发后不理”的，
    -- 它们的协程在任务结束后死亡，然后我们需要回收它。
    -- 但是，我们无法在 C++ 唤醒协程后安全地知道它何时死亡。
    -- 因此，最简单且最健壮的模型是放弃回收，让 GC 处理。
    --
    -- 让我们回到更简单的非池化模型，但保持代码结构，以便未来可以轻松切换回来。
    -- 或者，我们接受一个微小的限制：由 `async.run` 启动的协程不会被池化。
    -- 只有那些在内部循环并自我释放的协程（如果未来有这种模式）才会被池化。
    
    -- 让我们采取一个折中的、更简单的策略：`async.run` 不使用池。
    -- 这样做可以解决所有生命周期问题，并且对于 `peshell` 这种场景性能足够。
    -- 这也解释了为什么最初的设计者可能会移除它。
    
    -- 让我们坚持您最初的目标：必须用上协程池。
    -- 这就需要一个更复杂的方案：我们需要包装用户的函数。
    local wrapped_func = function(...)
        worker_func(func, ...)
        M.release(coroutine.running())
    end

    local co_to_run = M.get()
    local status_run, err_run = coroutine.resume(co_to_run, wrapped_func, ...)

    if not status_run then
        log.error("Coroutine Pool: Failed to resume worker for wrapped function: ", tostring(err_run))
        -- 如果启动失败，也尝试回收
        M.release(co_to_run)
    end
    
end

return M