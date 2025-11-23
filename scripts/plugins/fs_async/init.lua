-- scripts/plugins/fs_async/init.lua
-- 异步文件系统操作插件

local log = _G.log
local native = _G.pesh_native
local M = {}

function M.copy_file_async(co, source_path, dest_path)
    log.debug("Dispatching worker to copy '", source_path, "' to '", dest_path, "'")
    native.dispatch_worker("file_copy_worker", source_path, dest_path, co)
end

function M.read_file_async(co, filepath)
    log.debug("Dispatching worker to read '", filepath, "'")
    native.dispatch_worker("file_read_worker", filepath, co)
end

return M