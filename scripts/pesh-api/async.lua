-- pesh-api/async.lua
-- 最小化实现的异步辅助模块

local M = {}
local native = pesh_native
local log = require("pesh-api.log")

--[[
@description 在不阻塞主线程消息循环的情况下暂停执行。
@param ms number: 暂停的毫秒数。
]]
function M.sleep_async(ms)
    ms = ms or 0
    log.trace("Async sleep for ", ms, " ms.")
    -- 在这个最小化方案中，我们直接调用 C++ 提供的、能够处理消息循环的 sleep 函数。
    native.sleep(ms)
end

--[[
@description (占位符) 等待一个 future 对象完成。
@param future table: 一个代表异步操作的 future 对象。
@return any: 异步操作的结果。
--]]
function M.await(future)
    -- 在一个完整的协程调度器实现中，这里会 yield 当前协程，
    -- 直到 future 对象所代表的操作完成。
    -- 在最小化方案中，我们暂时不需要复杂的实现。
    log.trace("Awaiting a future object (placeholder).")
end

return M
