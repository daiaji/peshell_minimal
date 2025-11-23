-- scripts/plugins/fs/init.lua
-- 文件系统插件 (Lua-Ext & FFI Edition)
-- Version: 8.0 (Refactored to use enhanced ext.path object)

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

-- 直接映射 path 类的静态方法，兼容旧习惯
M.exists = path.exists
M.is_dir = path.isdir
M.is_file = path.isfile

function M.get_size(p) return path(p):attr().size end
function M.get_mtime(p) return path(p):attr().modification end

function M.mkdir(p)
    return os_ext.mkdir(tostring(p), true)
end

function M.list_files(p)
    local res = {}
    local p_obj = path(p)
    
    -- os.listdir 返回字符串迭代器
    local iter, obj_iter = os_ext.listdir(p_obj.path)
    if not iter then return res end
    
    for f in iter, obj_iter do
        -- 使用 / 运算符拼接，使用 :isfile() 方法
        if (p_obj / f):isfile() then
            table.insert(res, f)
        end
    end
    return res
end

function M.list_dirs(p)
    local res = {}
    local p_obj = path(p)
    
    local iter, obj_iter = os_ext.listdir(p_obj.path)
    if not iter then return res end

    for f in iter, obj_iter do
        if (p_obj / f):isdir() then
            table.insert(res, f)
        end
    end
    return res
end

-- [Internal] FFI CopyFileW Wrapper
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
    
    if not src_p:exists() then 
        return false, "Source not found: " .. src_p.path 
    end
    
    if src_p:isfile() then
        if dst_p:isdir() then
            -- 尝试获取文件名：使用 ext.path 的 getdir 或 basename
            -- 由于 ext.path 设计比较独特，这里手动处理最稳妥
            local name = src_p.path:match("[^/\\]+$")
            dst_p = dst_p / name
        end
        -- 传递字符串给 FFI
        return copy_file_internal(src_p.path, dst_p.path, false)
    
    elseif src_p:isdir() then
        if not dst_p:exists() then M.mkdir(dst_p.path) end
        
        local iter, obj_iter = lfs.dir(src_p.path)
        if not iter then return false, "Failed to list source directory" end

        for name in iter, obj_iter do
            if name ~= "." and name ~= ".." then
                local s = src_p / name
                local d = dst_p / name
                local ok, err = M.copy(s, d) -- 递归调用
                if not ok then return false, err end
            end
        end
        return true
    else
        return false, "Unknown file type: " .. src_p.path
    end
end

function M.move(src, dst)
    return os_ext.move(tostring(src), tostring(dst))
end

function M.delete(target)
    local p = path(target)
    if not p:exists() then return true end

    if p:isdir() then
        local iter, obj_iter = lfs.dir(p.path)
        if iter then
            for name in iter, obj_iter do
                if name ~= "." and name ~= ".." then
                    local child = p / name
                    local ok, err = M.delete(child)
                    if not ok then return false, err end
                end
            end
        end
        return os_ext.rmdir(p.path)
    else
        return os_ext.remove(p.path)
    end
end

return M