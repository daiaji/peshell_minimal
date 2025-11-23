-- scripts/plugins/fs/init.lua
-- 文件系统插件 (Lua-Ext & FFI Edition)
-- Version: 9.1 (Fix missing CopyFileW symbol)

local M = {}
local log = _G.log

local ffi = require("ffi")
local path = require("ext.path")
local os_ext = require("ext.os")
local io_ext = require("ext.io")
local lfs = require("lfs_ffi")

require("ffi.req")("Windows.sdk.kernel32")
local k32 = ffi.load("kernel32")

-- [FIX] Explicitly define CopyFileW
ffi.cdef[[
    int CopyFileW(const wchar_t* lpExistingFileName, const wchar_t* lpNewFileName, int bFailIfExists);
]]

M.read_file = io_ext.readfile
M.write_file = io_ext.writefile

M.exists = path.exists
M.is_dir = path.isdir

-- Check file mode robustly
function M.is_file(p)
    local mode = lfs.attributes(tostring(p), "mode")
    return mode == "file"
end

function M.get_size(p) return path(p):attr().size end
function M.get_mtime(p) return path(p):attr().modification end

function M.mkdir(p)
    return os_ext.mkdir(tostring(p), true)
end

function M.list_files(p)
    local res = {}
    local parent_str = tostring(p)
    local iter, obj = os_ext.listdir(parent_str)
    if not iter then return res end
    
    for f in iter, obj do
        local full_path = path(parent_str) / f
        if M.is_file(tostring(full_path)) then
            table.insert(res, f)
        end
    end
    return res
end

function M.list_dirs(p)
    local res = {}
    local parent_str = tostring(p)
    local iter, obj = os_ext.listdir(parent_str)
    if not iter then return res end

    for f in iter, obj do
        local full_path = path(parent_str) / f
        if full_path:isdir() then
            table.insert(res, f)
        end
    end
    return res
end

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
    local src_str = tostring(src)
    local dst_str = tostring(dst)
    local src_p = path(src_str)
    local dst_p = path(dst_str)
    
    if not src_p:exists() then return false, "Source not found: " .. src_str end
    
    if M.is_file(src_str) then
        if dst_p:isdir() then
            local name = path(src_str):name() or path.basename(src_str)
            dst_p = dst_p / name
        end
        return copy_file_internal(src_str, tostring(dst_p), false)
    
    elseif src_p:isdir() then
        if not dst_p:exists() then M.mkdir(dst_str) end
        
        local iter, obj = lfs.dir(src_str)
        if not iter then return false, "Failed to list source directory" end

        for name in iter, obj do
            if name ~= "." and name ~= ".." then
                local s = src_p / name
                local d = dst_p / name
                local ok, err = M.copy(tostring(s), tostring(d))
                if not ok then return false, err end
            end
        end
        return true
    else
        return false, "Unknown file type: " .. src_str
    end
end

function M.move(src, dst)
    return os_ext.move(tostring(src), tostring(dst))
end

function M.delete(target)
    local p_str = tostring(target)
    local p = path(p_str)
    if not p:exists() then return true end

    if p:isdir() then
        local iter, obj = lfs.dir(p_str)
        if iter then
            for name in iter, obj do
                if name ~= "." and name ~= ".." then
                    local child = p / name
                    local ok, err = M.delete(tostring(child))
                    if not ok then return false, err end
                end
            end
        end
        return os_ext.rmdir(p_str)
    else
        return os_ext.remove(p_str)
    end
end

return M