-- scripts/plugins/async/init.lua
-- 异步执行插件，提供 await 和 async.run

local pesh = _G.pesh
local M = {}

-- 依赖
local log = _G.log
local native = _G.pesh_native
local coro_pool = pesh.plugin.load("coro_pool")

-- 全局的 await 函数
function _G.await(future_provider_func, ...)
    -- [利用 Lua 5.2 特性] coroutine.running() 返回两个值
    local co, is_main = coroutine.running()
    if not co or is_main then
        error("await() must be called from within a coroutine, not the main thread.", 2)
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

-- 启动一个异步任务，使用协程池来执行
M.run = coro_pool.run
log.info("Async plugin initialized with coroutine pooling.")

-- 带消息循环的阻塞式休眠（保留用于简单场景）
function M.sleep_async(ms)
    native.sleep(ms)
    return true
end

return M