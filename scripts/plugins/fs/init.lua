-- scripts/plugins/fs/init.lua
-- 文件系统插件 (Enhanced Path Edition)
-- Version: 9.0

local M = {}
local log = _G.log

local ffi = require("ffi")
local path = require("ext.path")
local os_ext = require("ext.os")
local io_ext = require("ext.io")
local lfs = require("lfs_ffi")

require("ffi.req")("Windows.sdk.kernel32")
local k32 = ffi.load("kernel32")

M.read_file = io_ext.readfile
M.write_file = io_ext.writefile

-- 直接代理
M.exists = path.exists
M.is_dir = path.isdir
M.is_file = path.isfile 

function M.get_size(p) return path(p):stat().size end
function M.get_mtime(p) return path(p):stat().modification end

function M.mkdir(p)
    -- path 对象现在有 :mkdir(recursive)
    return path(p):mkdir(true)
end

function M.list_files(p)
    local res = {}
    local p_obj = path(p)
    
    local iter, obj_iter = os_ext.listdir(p_obj:str())
    if not iter then return res end
    
    for f in iter, obj_iter do
        if (p_obj / f):isfile() then
            table.insert(res, f)
        end
    end
    return res
end

function M.list_dirs(p)
    local res = {}
    local p_obj = path(p)
    
    local iter, obj_iter = os_ext.listdir(p_obj:str())
    if not iter then return res end

    for f in iter, obj_iter do
        if (p_obj / f):isdir() then
            table.insert(res, f)
        end
    end
    return res
end

-- [Internal] FFI CopyFileW Wrapper (Still needed for Unicode robustness)
local function copy_file_internal(src, dst, fail_if_exists)
    local CP_UTF8 = 65001
    local function to_w(s)
        local len = ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, -1, nil, 0)
        local buf = ffi.new("wchar_t[?]", len)
        ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, -1, buf, len)
        return buf
    end

    local w_src = to_w(src)
    local w_dst = to_w(dst)
    local b_fail = fail_if_exists and 1 or 0
    
    if k32.CopyFileW(w_src, w_dst, b_fail) ~= 0 then
        return true
    else
        return false, "CopyFileW failed: " .. tostring(k32.GetLastError())
    end
end

function M.copy(src, dst)
    local src_p = path(src)
    local dst_p = path(dst)
    
    if not src_p:exists() then return false, "Source not found: " .. src_p:str() end
    
    if src_p:isfile() then
        if dst_p:isdir() then
            dst_p = dst_p / src_p:name()
        end
        return copy_file_internal(src_p:str(), dst_p:str(), false)
    
    elseif src_p:isdir() then
        if not dst_p:exists() then dst_p:mkdir(true) end
        
        local iter, obj_iter = lfs.dir(src_p:str())
        if not iter then return false, "Failed to list source directory" end

        for name in iter, obj_iter do
            if name ~= "." and name ~= ".." then
                local s = src_p / name
                local d = dst_p / name
                local ok, err = M.copy(s, d)
                if not ok then return false, err end
            end
        end
        return true
    else
        return false, "Unknown file type: " .. src_p:str()
    end
end

function M.move(src, dst)
    return os_ext.move(tostring(src), tostring(dst))
end

function M.delete(target)
    local p = path(target)
    if not p:exists() then return true end

    if p:isdir() then
        local iter, obj_iter = lfs.dir(p:str())
        if iter then
            for name in iter, obj_iter do
                if name ~= "." and name ~= ".." then
                    local ok, err = M.delete(p / name)
                    if not ok then return false, err end
                end
            end
        end
        return p:remove() -- path:remove() handles rmdir/remove logic
    else
        return p:remove()
    end
end

return M