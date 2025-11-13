-- pesh-api/pe.lua
-- 负责 PE 环境初始化相关的逻辑

local M = {}
-- 引入 LuaFileSystem 和 log 模块
local lfs = require("lfs")
local log = require("pesh-api.log")

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
        log.debug("Creating directory: ", full_path)

        -- 使用 lfs 创建目录，lfs.mkdir 会自动创建所有父级目录
        local success, err = lfs.mkdir(full_path)
        if not success then
            -- 检查错误是否是 "File exists"，如果是，则忽略
            if not (err and err:find("exists")) then
                log.warn("Could not create directory '", full_path, "': ", tostring(err))
            end
        end
    end

    -- 提示：一个完整的实现还需要通过 FFI 调用 Windows API (如 RegInstall)
    -- 来注册核心的 Shell COM 组件，这里予以省略。
    log.info("PE: User environment folders initialized.")
end

return M