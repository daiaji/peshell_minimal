-- scripts/pesh-api/async.lua (v4.0 - Coroutine Pool Re-integrated)
-- 本模块提供核心的 await 函数，并将异步任务的执行委托给协程池。

local M = {}
local native = pesh_native
local log = require("pesh-api.log")

-- [关键] 引入协程池模块
local coro_pool = require("pesh-api.coro_pool")

-- 全局的 await 函数 (此部分保持不变)
function _G.await(future_provider_func, ...)
    local co = coroutine.running()
    if not co then
        error("await() must be called from within a coroutine.", 2)
    end

    -- 执行 future_provider_func，它会启动一个后台任务
    -- 它需要将当前协程 co 传递给后台
    future_provider_func(co, ...)
    
    -- 让出执行权，等待 C++ 调度器唤醒
    -- 当唤醒时，yield 会返回 C++ 传来的多个值
    local resumed_success, resumed_data_or_error = coroutine.yield()
    
    if not resumed_success then
        -- 如果后台任务失败，我们在这里抛出错误，这样调用方可以用 pcall 捕获
        error(resumed_data_or_error, 2)
    end
    
    return resumed_data_or_error
end

-- [关键] 启动一个异步任务，现在使用协程池来执行
-- 直接将 M.run 指向 coro_pool.run，实现功能委托
M.run = coro_pool.run
log.info("Async module initialized with coroutine pooling.")


-- 带消息循环的阻塞式休眠（保留用于简单场景）
function M.sleep_async(ms)
    native.sleep(ms)
    return true
end

return M