-- pesh-api/pe.lua
-- 负责 PE 环境初始化相关的逻辑

local M = {}
-- 引入 LuaFileSystem 和 log 模块
local lfs = require("lfs")
local log = require("pesh-api.log")

--[[
@description 递归创建目录，类似于 `mkdir -p`。
@param path string: 要创建的目录的完整路径。
@return boolean, string: 成功返回 true，失败返回 false 和错误信息。
]]
local function mkdirs(path)
    -- lfs.attributes() 可以检查路径是否存在及其类型
    local attr = lfs.attributes(path)

    -- 如果路径已存在且是目录，则无需操作
    if attr and attr.mode == "directory" then
        return true
    end

    -- 如果路径存在但不是目录（例如是个文件），则返回错误
    if attr then
        return false, "Path exists but is not a directory: " .. path
    end

    -- 找到父目录
    local parent_path = path:match("(.+)[\\/][^\\/]+")

    -- 如果有父目录，并且父目录不是根目录（如 C:\），则递归创建父目录
    if parent_path and parent_path ~= "" and not parent_path:match("^[A-Za-z]:\\$") then
        local success, err = mkdirs(parent_path)
        if not success then
            return false, err
        end
    end

    -- 创建当前目录
    return lfs.mkdir(path)
end

--[[
@description 初始化 PE 的用户环境，创建必要的文件夹。
             这对应于 PECMD 的 `INIT` 命令的核心功能。
]]
function M.initialize()
    log.info("PE: Initializing user environment folders...")

    local user_profile = os.getenv("USERPROFILE")
    if not user_profile then
        log.error("USERPROFILE environment variable is not set. Cannot initialize folders.")
        return
    end

    -- 需要创建的标准用户目录列表
    local directories = {
        "Desktop",
        "Favorites",
        "Documents", -- 'My Documents' in older systems
        "Start Menu",
        "Start Menu/Programs",
        "Start Menu/Programs/Startup",
        "SendTo",
        "AppData/Roaming/Microsoft/Internet Explorer/Quick Launch"
    }

    for _, dir in ipairs(directories) do
        -- 构造完整路径，并将 / 替换为 \
        local full_path = (user_profile .. "/" .. dir):gsub("/", "\\")
        log.debug("Ensuring directory exists: ", full_path)

        -- 使用我们新的递归创建函数
        local success, err = mkdirs(full_path)
        if not success then
            log.warn("Could not create directory '", full_path, "': ", tostring(err))
        end
    end

    -- 提示：一个完整的实现还需要通过 FFI 调用 Windows API (如 RegInstall)
    -- 来注册核心的 Shell COM 组件，这里予以省略。
    log.info("PE: User environment folders initialized.")
end

-- 声明要导出的子命令
M.__commands = {
    init = function()
        M.initialize()
    end
}

-- 新增：导出内部函数以供测试
M._internal = {
    mkdirs = mkdirs
}

return M
