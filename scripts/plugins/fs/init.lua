-- scripts/plugins/fs/init.lua
-- 同步文件系统操作插件 (Restoring Sync Functionality via FFI)

local pesh = _G.pesh
local M = {}

local ffi = pesh.ffi
local log = _G.log
local k32 = pesh.plugin.load("winapi.kernel32")

---
-- 复制文件 (同步/阻塞)
-- @param src string: 源路径
-- @param dst string: 目标路径
-- @param fail_if_exists boolean: 如果目标存在是否失败 (默认 false)
-- @return boolean, string: 成功返回 true
function M.copy(src, dst, fail_if_exists)
    local w_src = ffi.to_wide(src)
    local w_dst = ffi.to_wide(dst)
    local b_fail = fail_if_exists and 1 or 0
    
    if k32.CopyFileW(w_src, w_dst, b_fail) ~= 0 then
        return true
    else
        return false, "CopyFileW failed: " .. tostring(k32.GetLastError())
    end
end

---
-- 移动文件 (同步/阻塞)
function M.move(src, dst)
    if k32.MoveFileW(ffi.to_wide(src), ffi.to_wide(dst)) ~= 0 then
        return true
    else
        return false, "MoveFileW failed: " .. tostring(k32.GetLastError())
    end
end

---
-- 删除文件
function M.delete(path)
    if k32.DeleteFileW(ffi.to_wide(path)) ~= 0 then
        return true
    else
        return false, "DeleteFileW failed: " .. tostring(k32.GetLastError())
    end
end

---
-- 创建目录
function M.mkdir(path)
    if k32.CreateDirectoryW(ffi.to_wide(path), nil) ~= 0 then
        return true
    else
        local err = k32.GetLastError()
        if err == 183 then return true end -- ERROR_ALREADY_EXISTS
        return false, "CreateDirectoryW failed: " .. tostring(err)
    end
end

---
-- 删除目录
function M.rmdir(path)
    if k32.RemoveDirectoryW(ffi.to_wide(path)) ~= 0 then
        return true
    else
        return false, "RemoveDirectoryW failed: " .. tostring(k32.GetLastError())
    end
end

---
-- 检查路径是否存在
function M.exists(path)
    local attr = k32.GetFileAttributesW(ffi.to_wide(path))
    return attr ~= 0xFFFFFFFF
end

return M