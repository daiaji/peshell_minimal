-- scripts/pesh-api/pe.lua (v3.2 - Robust Handle Management)

local M = {}
local log = require("pesh-api.log")
local ffi = require("pesh-api.ffi")
-- Penlight 模块由 prelude 全局化
local path = require("pl.path")
local dir = require("pl.dir")

-- [修正] 显式加载包含所需API的DLL
local advpack = ffi.load("advpack") -- 修正：RegInstallW 位于 advpack.dll
local ole32 = ffi.load("ole32")

-- [新增] 使用 FFI 安全地获取环境变量，避免 ANSI/Unicode 冲突
local function getenv_w(name)
    local name_w = ffi.to_wide(name)
    -- 先调用一次获取所需缓冲区大小
    local size = ffi.C.GetEnvironmentVariableW(name_w, nil, 0)
    if size == 0 then
        return nil
    end
    local buf = ffi.new("wchar_t[?]", size)
    -- 再次调用以填充缓冲区
    if ffi.C.GetEnvironmentVariableW(name_w, buf, size) > 0 then
        return ffi.from_wide(buf)
    end
    return nil
end


--[[
@description 初始化 PE 的用户环境，创建必要的文件夹，并注册核心组件。
             这对应于 PECMD 的 `INIT` 命令的完整功能。
]]
function M.initialize()
    log.info("PE: Starting core environment initialization...")

    -- 1. 创建用户目录
    log.info("PE: --> Step 1: Creating user environment folders...")
    -- [修正] 使用 FFI 版本的 getenv 来读取由测试设置的 Unicode 环境变量
    local user_profile = getenv_w("USERPROFILE")
    if not user_profile then
        log.error("USERPROFILE environment variable is not set. Cannot initialize folders.")
        return false
    end
    local directories = {
        "Desktop",
        "Favorites",
        "Documents",
        "Start Menu",
        "Start Menu/Programs",
        "Start Menu/Programs/Startup",
        "SendTo",
        "AppData/Roaming/Microsoft/Internet Explorer/Quick Launch"
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
    --    使用 FFI.C.LoadLibraryW 精确控制，而不是 ffi.load
    log.info("PE: --> Step 2: Registering core shell components...")
    local h_shell32 = ffi.C.LoadLibraryW(ffi.to_wide("shell32.dll"))
    if h_shell32 and h_shell32 ~= nil then
        local err_code = advpack.RegInstallW(h_shell32, ffi.to_wide("Install"), nil)
        
        -- [关键修正] 无论 RegInstallW 是否成功，都必须释放已加载的库句柄
        ffi.C.FreeLibrary(h_shell32)

        if err_code == 0 then
            log.info("PE: shell32.dll components registered successfully via RegInstallW.")
        else
            -- 在 CI/CD 等非 PE 环境下，由于权限不足，此操作失败是预期的。
            -- 我们只记录警告，并继续执行。
            log.warn("PE: RegInstallW on shell32.dll failed with code: ", err_code)
        end
    else
        log.warn("PE: Could not load shell32.dll for component registration.")
    end

    -- 3. 初始化 COM 库
    log.info("PE: --> Step 3: Initializing COM library...")
    -- [修正] 从正确的库命名空间(ole32)调用 CoInitialize
    local hresult = ole32.CoInitialize(nil)
    if hresult < 0 then
        -- 小于 0 表示错误，S_FALSE (1) 表示已经初始化过了，是正常的。
        log.warn("PE: CoInitialize failed with HRESULT: ", string.format("0x%X", hresult))
    else
        log.info("PE: COM library initialized successfully.")
    end

    log.info("PE: Core environment initialization complete.")
    return true
end

-- 导出为 peshell 命令，方便从命令行直接调用
M.__commands = {
    init = function()
        if M.initialize() then
            return 0
        else
            return 1
        end
    end
}

return M