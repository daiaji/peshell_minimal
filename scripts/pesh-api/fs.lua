-- scripts/pesh-api/fs.lua
-- 文件、目录、路径操作 API 模块 (修正版 v2)

local M = {}
local lfs = require("lfs")
local log = require("pesh-api.log")
local native = pesh_native -- 引入 C++ 绑定

-- ########## Path Object Metatable ##########
-- 提供一个面向对象的接口来处理路径字符串
local path_mt = { __index = {} }

--- 返回路径的目录部分
function path_mt.__index:directory()
    return self.path:match("(.+)[\\/][^\\/]+") or ""
end

--- 返回路径的驱动器盘符 (e.g., "C:")
function path_mt.__index:drive()
    return self.path:match("^[A-Za-z]:") or ""
end

--- 返回路径的文件扩展名 (不含点)
function path_mt.__index:extension()
    return self.path:match("([^.]+)$") or ""
end

--- 返回路径的文件名 (带扩展名)
function path_mt.__index:filename()
    return self.path:match("([^\\/]+)$") or ""
end

--- 返回路径的文件名 (不含扩展名)
function path_mt.__index:name()
    local filename = self:filename()
    return filename:match("(.+)%..+") or filename
end

--- 返回路径的字符串表示
function path_mt.__tostring()
    return self.path
end

-- ########## Module-level Functions ##########

--- 创建一个 Path 对象
function M.path(filepath)
    if type(filepath) ~= "string" then return nil end
    local path_obj = { path = filepath }
    setmetatable(path_obj, path_mt)
    return path_obj
end

--- 复制文件或目录 (递归)
function M.copy(source, destination)
    -- 直接调用 C++ 实现的原生复制函数
    log.debug("NATIVE Copying '", source, "' to '", destination, "'")
    return native.fs_copy(source, destination)
end

--- 移动或重命名文件/目录
function M.move(source, destination)
    log.debug("Moving '", source, "' to '", destination, "'")
    -- ########## 关键修正 ##########
    -- 使用 Lua 内置的 os.rename 函数，而不是不存在的 lfs.rename
    return os.rename(source, destination)
    -- ############################
end

--- 删除文件或空目录
function M.delete(path)
    log.debug("Deleting '", path, "'")
    local attr = lfs.attributes(path)
    if not attr then return true end -- 不存在也算成功
    if attr.mode == "directory" then
        return lfs.rmdir(path)
    else
        return os.remove(path)
    end
end

--- 读取文件的二进制内容
function M.read_bytes(filepath)
    local file, err = io.open(filepath, "rb")
    if not file then
        log.error("Failed to read bytes from '", filepath, "': ", err)
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

--- 将二进制内容写入文件
function M.write_bytes(filepath, content)
    local file, err = io.open(filepath, "wb")
    if not file then
        log.error("Failed to write bytes to '", filepath, "': ", err)
        return false
    end
    file:write(content)
    file:close()
    return true
end

--- 获取文件属性
function M.get_attributes(filepath)
    return lfs.attributes(filepath)
end

--- 获取文件大小 (字节)
function M.get_size(filepath)
    local attr = lfs.attributes(filepath, "size")
    return attr
end

--- 返回一个遍历目录中文件的迭代器
function M.list_files(dir_path)
    return lfs.dir(dir_path)
end

return M
