-- scripts/plugins/async/init.lua
-- 异步执行插件，提供 await, async.run 和真正非阻塞的 sleep
-- v5.3 - Final Clean Version

local pesh = _G.pesh
local M = {}

-- 依赖
local log = _G.log
local native = _G.pesh_native
local coro_pool = pesh.plugin.load("coro_pool")

-- 全局的 await 函数
function _G.await(future_provider_func, ...)
    local co, is_main = coroutine.running()
    if not co or is_main then
        error("await() must be called from within a coroutine, not the main thread.", 2)
    end

    future_provider_func(co, ...)
    
    local resumed_success, resumed_data_or_error = coroutine.yield()
    
    if not resumed_success then
        error(resumed_data_or_error, 2)
    end
    
    return resumed_data_or_error
end

-- 启动一个异步任务，使用协程池来执行
M.run = coro_pool.run
log.info("Async plugin initialized with coroutine pooling.")

---
-- [真正异步] 休眠指定的毫秒数。
-- 此函数会挂起当前协程，让出 CPU 给其他任务，直到时间到达。
-- @param co coroutine: 当前协程（自动传入）
-- @param ms number: 毫秒数
local function sleep_async_impl(co, ms)
    native.dispatch_worker("timer_worker", ms, co)
end

---
-- [公开接口] 异步休眠。必须在协程中调用。
-- 使用方法: await(async.sleep, 1000)
function M.sleep(co, ms)
    return sleep_async_impl(co, ms)
end

---
-- [同步阻塞] 带消息循环的休眠。
-- 警告：这会阻塞 Lua 虚拟机，导致其他异步任务无法处理。
-- 仅在主线程脚本 (如 init.lua 或 test_suite.lua) 中使用。
function M.sleep_blocking(ms)
    native.sleep(ms)
    return true
end

return M