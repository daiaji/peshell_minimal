-- scripts/plugins/pe/init.lua
-- PE 环境初始化插件 (Lua-Ext Edition)

local pesh = _G.pesh
local M = {}

local log = _G.log
local ffi = require("ffi")
local path = require("ext.path")
local os_ext = require("ext.os")

require("ffi.req")("Windows.sdk.kernel32")
require("ffi.req")("Windows.sdk.advapi32")

ffi.cdef[[
    long RegInstallW(void* hMod, const wchar_t* pszSection, const void* pstTable);
    long CoInitialize(void* pvReserved);
]]
local k32 = ffi.load("kernel32")
local advpack = ffi.load("advpack")
local ole32 = ffi.load("ole32")

function M.initialize()
    log.info("PE: Starting core environment initialization...")

    local user_profile = os.getenv("USERPROFILE")
    if not user_profile then
        log.error("USERPROFILE not set.")
        return false
    end
    
    local directories = {
        "Desktop", "Favorites", "Documents", "Start Menu",
        "Start Menu/Programs", "Start Menu/Programs/Startup",
        "SendTo", "AppData/Roaming/Microsoft/Internet Explorer/Quick Launch"
    }
    
    for _, subdir in ipairs(directories) do
        -- [FIX] 使用 / 运算符
        local p = path(user_profile) / subdir
        if not os_ext.mkdir(p:str(), true) then
            if not p:isdir() then
                log.warn("Could not create directory: ", p:str())
            end
        end
    end
    log.info("PE: User folders created.")

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
        log.info("PE: shell32 components registered.")
    end

    ole32.CoInitialize(nil)
    log.info("PE: COM initialized.")

    return true
end

M.__commands = {
    init = function() return M.initialize() and 0 or 1 end
}

return M