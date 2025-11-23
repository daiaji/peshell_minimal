-- scripts/plugins/pe/init.lua
-- PE 环境初始化插件 (Powered by lua-ext)
-- Version: 2.0

local pesh = _G.pesh
local M = {}

local log = _G.log
local ffi = require("ffi")
local path = require("ext.path")
local os_ext = require("ext.os")

local function req(name)
    return require("ffi.req")("Windows.sdk." .. name)
end

local k32 = req("kernel32")
local advpack = req("advpack")
local ole32 = req("ole32")

function M.initialize()
    log.info("PE: Initializing user directories...")

    local user_profile = os_ext.getenv("USERPROFILE")
    if not user_profile then
        log.error("USERPROFILE not set.")
        return false
    end
    
    local root = path(user_profile)
    
    local directories = {
        "Desktop", 
        "Favorites", 
        "Documents", 
        "Start Menu/Programs/Startup",
        "SendTo", 
        "AppData/Roaming/Microsoft/Internet Explorer/Quick Launch"
    }
    
    if not root:exists() then
        root:mkdir(true)
    end
    
    for _, subdir in ipairs(directories) do
        local p = root / subdir
        if not p:exists() then
            local ok, err = p:mkdir(true)
            if not ok then
                log.warn("Failed to create '", p:str(), "': ", tostring(err))
            else
                log.debug("Created: ", p:str())
            end
        end
    end
    
    log.info("PE: Directories created.")

    local function to_w(s) 
        local len = ffi.C.MultiByteToWideChar(65001, 0, s, -1, nil, 0)
        local buf = ffi.new("wchar_t[?]", len)
        ffi.C.MultiByteToWideChar(65001, 0, s, -1, buf, len)
        return buf
    end
    
    local h_shell32 = k32.LoadLibraryW(to_w("shell32.dll"))
    if h_shell32 then
        advpack.RegInstallW(h_shell32, to_w("Install"), nil)
        k32.FreeLibrary(h_shell32)
        log.info("PE: Shell components registered.")
    end

    ole32.CoInitialize(nil)
    
    return true
end

M.__commands = {
    init = function() return M.initialize() and 0 or 1 end
}

return M