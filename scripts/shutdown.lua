-- scripts/shutdown.lua
-- 用于通知守护进程优雅退出的脚本 (v2 - API 调用版本)

-- 引入日志和包含退出函数的 shell 模块
local log = require("pesh-api.log")
local shell = require("pesh-api.shell")

log.info("Executing shutdown script...")

-- 直接调用封装好的 API 函数，并根据其返回值设置本脚本的退出码
if shell.exit_guardian() then
    -- 返回 0 表示成功
    return 0
else
    -- 返回 1 表示失败
    return 1
end