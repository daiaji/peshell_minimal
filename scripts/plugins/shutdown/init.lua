-- scripts/plugins/shutdown/init.lua
-- 独立的 shutdown 插件

local pesh = _G.pesh
local log = _G.log
local M = {}

local shell = pesh.plugin.load("shell")

M.__commands = {
    shutdown = function()
        log.info("Executing shutdown command via plugin...")
        if shell.exit_guardian() then
            log.info("Shutdown signal sent successfully.")
            return 0
        else
            log.error("Failed to send shutdown signal.")
            return 1
        end
    end
}

return M