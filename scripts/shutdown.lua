-- scripts/shutdown.lua
-- 用于通知守护进程优雅退出的脚本

local log = require("pesh-api.log")
local shell = require("pesh-api.shell")

log.info("Executing shutdown script to signal the guardian...")

if shell.exit_guardian() then
    log.info("Shutdown signal sent. The guardian process should exit soon.")
    return 0 -- 返回 0 表示成功
else
    log.error("Failed to send shutdown signal. The guardian may not be running or an error occurred.")
    return 1 -- 返回 1 表示失败
end