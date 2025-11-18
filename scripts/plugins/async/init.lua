-- scripts/plugins/async/init.lua
-- 异步执行插件，提供 await, async.run 和真正非阻塞的 sleep
-- v5.4 - Final Release (With GC Anchoring)

local pesh = _G.pesh
local M = {}

-- 依赖
local log = _G.log
local native = _G.pesh_native
local coro_pool = pesh.plugin.load("coro_pool")

-- [[ 关键修复: 协程锚定表 ]]
-- 用于防止挂起的协程在 C++ 任务完成前被 Lua GC 回收
local active_anchors = {}

-- 全局的 await 函数
function _G.await(future_provider_func, ...)
    local co, is_main = coroutine.running()
    if not co or is_main then
        error("await() must be called from within a coroutine, not the main thread.", 2)
    end

    -- 1. 在派发任务前，将协程锚定，防止 GC
    active_anchors[co] = true

    -- 2. 执行派发逻辑 (C++ 将持有 co 指针)
    future_provider_func(co, ...)
    
    -- 3. 挂起等待
    local resumed_success, resumed_data_or_error = coroutine.yield()
    
    -- 4. 恢复后，解除锚定，允许 GC (如果任务结束)
    active_anchors[co] = nil
    
    if not resumed_success then
        error(resumed_data_or_error, 2)
    end
    
    return resumed_data_or_error
end

-- 启动一个异步任务
M.run = coro_pool.run
log.info("Async plugin initialized with coroutine pooling and GC safety.")

---
-- [真正异步] 休眠指定的毫秒数
local function sleep_async_impl(co, ms)
    native.dispatch_worker("timer_worker", ms, co)
end

---
-- [公开接口] 异步休眠
function M.sleep(co, ms)
    return sleep_async_impl(co, ms)
end

---
-- [同步阻塞] 带消息循环的休眠 (仅限主线程使用)
function M.sleep_blocking(ms)
    native.sleep(ms)
    return true
end

return M