-- scripts/plugins/fs/init.lua
-- 文件系统插件 (Penlight Enhanced Version)
-- 哲学：对于逻辑遍历和通用操作，全力使用 Penlight；对于核心 I/O (复制/移动/删除)，使用 FFI 以确保 Windows Unicode 兼容性和性能。

local pesh = _G.pesh
local M = {}

-- 1. 核心依赖
local ffi = pesh.ffi
local log = _G.log
local k32 = pesh.plugin.load("winapi.kernel32")

-- 2. Penlight 深度集成
local path = require("pl.path")   -- 路径操作
local dir = require("pl.dir")     -- 目录操作
local utils = require("pl.utils") -- 通用工具 (读写文件)

-- ============================================================
-- 第一部分：直接映射 Penlight 的强大功能 (无需重复造轮子)
-- ============================================================

---
-- 读取整个文件内容
-- @see pl.utils.readfile
M.read_file = utils.readfile

---
-- 将字符串写入文件
-- @see pl.utils.writefile
M.write_file = utils.writefile

---
-- 创建目录 (支持递归，相当于 mkdir -p)
-- @see pl.dir.makepath
M.mkdir = dir.makepath

---
-- 获取文件大小 (字节)
-- @see pl.path.getsize
M.get_size = path.getsize

---
-- 获取文件修改时间
-- @see pl.path.getmtime
M.get_mtime = path.getmtime

---
-- 获取目录下的所有文件
-- @return table (pl.List)
-- @see pl.dir.getfiles
M.list_files = dir.getfiles

---
-- 获取目录下的所有子目录
-- @return table (pl.List)
-- @see pl.dir.getdirectories
M.list_dirs = dir.getdirectories

---
-- 检查路径是否存在
-- @see pl.path.exists
M.exists = path.exists

---
-- 检查是否为文件
-- @see pl.path.isfile
M.is_file = path.isfile

---
-- 检查是否为目录
-- @see pl.path.isdir
M.is_dir = path.isdir

-- ============================================================
-- 第二部分：FFI 增强实现 (弥补 Penlight 在 Windows 上的短板)
-- ============================================================

-- [内部] 单文件复制封装 (Unicode Safe)
local function copy_file_internal(src, dst, fail_if_exists)
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
-- 智能复制 (支持文件和目录递归)
-- Penlight 没有递归复制目录的功能 (copytree)，且 pl.dir.copyfile 性能不如 CopyFileW。
function M.copy(src, dst)
    if not path.exists(src) then
        return false, "Source path does not exist: " .. src
    end

    if path.isfile(src) then
        -- [文件 -> 目录] 自动拼接文件名
        if path.isdir(dst) then
            dst = path.join(dst, path.basename(src))
        end
        -- [文件 -> 文件]
        return copy_file_internal(src, dst, false)

    elseif path.isdir(src) then
        -- [目录 -> 目录] 递归复制
        log.debug("fs.copy: Recursive copy from '", src, "' to '", dst, "'")
        
        -- 利用 Penlight 的 makepath 确保根存在
        if not path.exists(dst) then
            local ok, err = dir.makepath(dst)
            if not ok then return false, "Failed to create dest dir: " .. tostring(err) end
        end

        -- 利用 Penlight 的 walk 遍历目录树 (极其简洁且正确)
        for root, _, files in dir.walk(src) do
            local rel_path = path.relpath(root, src)
            if rel_path == "." then rel_path = "" end
            
            local current_dst_dir = path.join(dst, rel_path)
            if not path.exists(current_dst_dir) then
                dir.makepath(current_dst_dir)
            end

            for _, fname in ipairs(files) do
                local f_src = path.join(root, fname)
                local f_dst = path.join(current_dst_dir, fname)
                
                -- 使用 FFI 进行实际的复制操作
                local ok, err = copy_file_internal(f_src, f_dst, false)
                if not ok then
                    log.warn("fs.copy: Failed to copy '", f_src, "'. Error: ", err)
                    return false, err
                end
            end
        end
        return true
    else
        return false, "Unknown file type: " .. src
    end
end

---
-- 移动文件或目录
-- MoveFileW 比 pl.file.move 更原子化，且支持 UTF-16。
function M.move(src, dst)
    if k32.MoveFileW(ffi.to_wide(src), ffi.to_wide(dst)) ~= 0 then
        return true
    else
        return false, "MoveFileW failed: " .. tostring(k32.GetLastError())
    end
end

---
-- 删除文件或目录 (智能判断)
function M.delete(target)
    if path.isdir(target) then
        -- 目录删除：Penlight 的 rmtree 实现得很好，直接复用
        local ok, err = dir.rmtree(target)
        if ok then return true else return false, tostring(err) end
    else
        -- 单文件删除：FFI DeleteFileW 更稳健 (不经过 Lua io/os 层)
        if k32.DeleteFileW(ffi.to_wide(target)) ~= 0 then
            return true
        else
            return false, "DeleteFileW failed: " .. tostring(k32.GetLastError())
        end
    end
end

return M