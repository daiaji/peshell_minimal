-- scripts/plugins/fs/init.lua
-- 文件系统插件 (Lua-Ext Proxy Edition)
-- Version: 13.0

local M = {}
local log = _G.log
local path = require("ext.path")

-- 1. Predicates & Attributes
-- Delegate directly to ext.path
M.exists = path.exists
M.is_dir = path.isdir
M.is_file = path.isfile

function M.get_size(p) 
    local attr = path(p):stat()
    return attr and attr.size 
end

function M.get_mtime(p)
    local attr = path(p):stat()
    return attr and attr.modification
end

-- 2. Operations
-- Fully delegated to ext.path (which uses FFI/lfs_ffi internally)

function M.mkdir(p)
    -- recursive = true
    local ok, err = path(p):mkdir(true)
    if not ok then return nil, err end
    return true
end

function M.delete(p)
    -- ext.path:remove handles both files and directories
    local ok, err = path(p):remove()
    if not ok then return nil, err end
    return true
end

function M.copy(src, dst)
    -- ext.path:copy uses CopyFileW on Windows
    local ok, err = path(src):copy(dst)
    if not ok then
        log.error("fs.copy failed: ", err)
        return nil, err
    end
    return true
end

function M.move(src, dst)
    -- ext.path:move uses MoveFileExW on Windows
    local ok, err = path(src):move(dst)
    if not ok then
        log.error("fs.move failed: ", err)
        return nil, err
    end
    return true
end

-- 3. Iteration
function M.list_files(p)
    local res = {}
    local p_obj = path(p)
    if not p_obj:isdir() then return nil, "Not a directory" end
    
    -- path:dir() returns Path objects
    for f in p_obj:dir() do
        if f:isfile() then table.insert(res, f:str()) end
    end
    return res
end

function M.list_dirs(p)
    local res = {}
    local p_obj = path(p)
    if not p_obj:isdir() then return nil, "Not a directory" end
    
    for f in p_obj:dir() do
        if f:isdir() then table.insert(res, f:str()) end
    end
    return res
end

-- 4. IO Helpers (Read/Write)
local io_ext = require("ext.io")
M.read_file = io_ext.readfile
M.write_file = io_ext.writefile

-- Helper
function M.unique_path(base_dir, prefix)
    base_dir = base_dir or os.getenv("TEMP") or "."
    prefix = prefix or "pesh_tmp"
    local uid = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    return path(base_dir) / (prefix .. "_" .. uid)
end

return M