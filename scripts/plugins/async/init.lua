-- scripts/plugins/async/init.lua
-- 异步执行插件，提供 await, async.run 和真正非阻塞的 sleep

local pesh = _G.pesh
local M = {}

-- 依赖
local log = _G.log
local native = _G.pesh_native
local coro_pool = pesh.plugin.load("coro_pool")

-- 协程锚定表，防止 GC
local active_anchors = {}

-- 全局的 await 函数
function _G.await(future_provider_func, ...)
    local co, is_main = coroutine.running()
    if not co or is_main then
        error("await() must be called from within a coroutine, not the main thread.", 2)
    end

    active_anchors[co] = true

    future_provider_func(co, ...)
    
    local resumed_success, resumed_data_or_error = coroutine.yield()
    
    active_anchors[co] = nil
    
    if not resumed_success then
        error(resumed_data_or_error, 2)
    end
    
    return resumed_data_or_error
end

M.run = coro_pool.run
log.info("Async plugin initialized.")

local function sleep_async_impl(co, ms)
    native.dispatch_worker("timer_worker", ms, co)
end

function M.sleep(co, ms)
    return sleep_async_impl(co, ms)
end

-- 同步阻塞休眠 (仅限主线程)
function M.sleep_blocking(ms)
    native.sleep(ms)
    return true
end

return M