-- scripts/plugins/shutdown/init.lua
-- 独立的 shutdown 插件，用于向 guardian 进程发送退出信号

local pesh = _G.pesh
local log = _G.log
local M = {}

-- 这个插件的功能依赖于 shell 插件提供的底层 API
local shell = pesh.plugin.load("shell")

-- 将 shutdown 逻辑封装为一个命令
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