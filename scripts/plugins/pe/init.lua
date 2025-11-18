-- scripts/plugins/pe/init.lua
-- PE 环境初始化插件

local pesh = _G.pesh
local M = {}

-- 依赖
local log = _G.log
local ffi = pesh.ffi
local C = ffi.C
local path = require("pl.path")
local dir = require("pl.dir")

-- [REFACTOR] FFI 定义和库现在通过插件加载，而不是内联定义
local kernel32 = pesh.plugin.load("winapi.kernel32")
local advpack = pesh.plugin.load("winapi.advpack")
local ole32 = pesh.plugin.load("winapi.ole32")

-- 使用 FFI 安全地获取环境变量
local function getenv_w(name)
    local name_w = ffi.to_wide(name)
    local size = kernel32.GetEnvironmentVariableW(name_w, nil, 0)
    if size == 0 then return nil end
    local buf = ffi.new("wchar_t[?]", size)
    if kernel32.GetEnvironmentVariableW(name_w, buf, size) > 0 then
        return ffi.from_wide(buf)
    end
    return nil
end

function M.initialize()
    log.info("PE: Starting core environment initialization...")

    -- 1. 创建用户目录
    log.info("PE: --> Step 1: Creating user environment folders...")
    local user_profile = getenv_w("USERPROFILE")
    if not user_profile then
        log.error("USERPROFILE environment variable is not set. Cannot initialize folders.")
        return false
    end
    local directories = {
        "Desktop", "Favorites", "Documents", "Start Menu",
        "Start Menu/Programs", "Start Menu/Programs/Startup",
        "SendTo", "AppData/Roaming/Microsoft/Internet Explorer/Quick Launch"
    }
    for _, subdir_rel in ipairs(directories) do
        local full_path = path.join(user_profile, subdir_rel)
        local success, err = dir.makepath(full_path)
        if not success then
            log.warn("Could not create directory '", full_path, "': ", tostring(err))
        end
    end
    log.info("PE: User folders creation complete.")

    -- 2. 注册核心 Shell 组件
    log.info("PE: --> Step 2: Registering core shell components...")
    local h_shell32 = kernel32.LoadLibraryW(ffi.to_wide("shell32.dll"))
    if h_shell32 and h_shell32 ~= nil then
        local err_code = advpack.RegInstallW(h_shell32, ffi.to_wide("Install"), nil)
        kernel32.FreeLibrary(h_shell32)
        if err_code == 0 then
            log.info("PE: shell32.dll components registered successfully via RegInstallW.")
        else
            log.warn("PE: RegInstallW on shell32.dll failed with code: ", err_code)
        end
    else
        log.warn("PE: Could not load shell32.dll for component registration.")
    end

    -- 3. 初始化 COM 库
    log.info("PE: --> Step 3: Initializing COM library...")
    local hresult = ole32.CoInitialize(nil)
    if hresult < 0 then
        log.warn("PE: CoInitialize failed with HRESULT: ", string.format("0x%X", hresult))
    else
        log.info("PE: COM library initialized successfully.")
    end

    log.info("PE: Core environment initialization complete.")
    return true
end

-- 导出为 peshell 命令
M.__commands = {
    init = function()
        if M.initialize() then return 0 else return 1 end
    end
}

return M