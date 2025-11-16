-- scripts/pesh-api/fs_async.lua
-- 提供真正的异步文件系统操作 (v2.0 - 完整版)

local log = require("pesh-api.log")
local native = pesh_native
local M = {}

---
-- 以异步方式复制一个文件。
-- @param co coroutine: 必须由 await 传入的当前协程。
-- @param source_path string: 源文件路径。
-- @param dest_path string: 目标文件路径。
function M.copy_file_async(co, source_path, dest_path)
    log.debug("Dispatching worker to copy '", source_path, "' to '", dest_path, "'")
    -- 将耗时操作交给 C++ 线程池，并传入当前协程以便任务完成后唤醒
    native.dispatch_worker("file_copy_worker", source_path, dest_path, co)
end

---
-- 以异步方式读取一个文件的全部内容。
-- @param co coroutine: 必须由 await 传入的当前协程。
-- @param filepath string: 要读取的文件的完整路径。
function M.read_file_async(co, filepath)
    log.debug("Dispatching worker to read '", filepath, "'")
    -- 将耗时操作交给 C++ 线程池
    native.dispatch_worker("file_read_worker", filepath, co)
end


return M