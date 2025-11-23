-- scripts/plugins/fs/init.lua
-- 文件系统插件 (Lua-Ext & FFI Edition)
-- 完全支持 Windows Unicode，移除 Penlight 依赖。

local M = {}
local log = _G.log

-- 1. 依赖
local ffi = require("ffi")
local path = require("ext.path") -- 核心路径对象
local os_ext = require("ext.os") -- 扩展 os 模块
local io_ext = require("ext.io") -- 扩展 io 模块

-- 加载 lfs_ffi
local lfs = require("lfs_ffi")

-- 加载 Kernel32 用于 CopyFileW
require("ffi.req")("Windows.sdk.kernel32")
local k32 = ffi.load("kernel32")

-- ============================================================
-- 基础 I/O (映射到 ext)
-- ============================================================

M.read_file = io_ext.readfile
M.write_file = io_ext.writefile

-- ============================================================
-- 路径与属性
-- ============================================================

M.exists = path.exists
M.is_dir = path.isdir
M.is_file = path.isfile

function M.get_size(p) return path(p):attr().size end
function M.get_mtime(p) return path(p):attr().modification end

-- ============================================================
-- 目录操作
-- ============================================================

function M.mkdir(p)
    return os_ext.mkdir(p, true) -- true 表示递归创建
end

function M.list_files(p)
    local res = {}
    -- os.listdir 使用 lfs_ffi，支持 Unicode
    for f in os_ext.listdir(p) do
        if path(p):join(f):isfile() then
            table.insert(res, f)
        end
    end
    return res
end

function M.list_dirs(p)
    local res = {}
    for f in os_ext.listdir(p) do
        if path(p):join(f):isdir() then
            table.insert(res, f)
        end
    end
    return res
end

-- ============================================================
-- 高级操作：复制/移动/删除
-- ============================================================

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
    
    if not src_p:exists() then return false, "Source not found" end
    
    if src_p:isfile() then
        if dst_p:isdir() then
            dst_p = dst_p:join(src_p:name())
        end
        return copy_file_internal(src_p:str(), dst_p:str(), false)
    
    elseif src_p:isdir() then
        if not dst_p:exists() then M.mkdir(dst_p:str()) end
        
        for name in lfs.dir(src_p:str()) do
            if name ~= "." and name ~= ".." then
                local s = src_p:join(name):str()
                local d = dst_p:join(name):str()
                local ok, err = M.copy(s, d)
                if not ok then return false, err end
            end
        end
        return true
    else
        return false, "Unknown file type"
    end
end

function M.move(src, dst)
    return os_ext.move(src, dst)
end

function M.delete(target)
    local p = path(target)
    if p:isdir() then
        for name in lfs.dir(p:str()) do
            if name ~= "." and name ~= ".." then
                local child = p:join(name):str()
                local ok, err = M.delete(child)
                if not ok then return false, err end
            end
        end
        return os_ext.rmdir(p:str())
    else
        return os_ext.remove(p:str())
    end
end

return M