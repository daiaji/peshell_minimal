-- scripts/test_run.lua
-- 用于测试 'run' 子命令功能的脚本

-- 引入日志模块
local log = require("pesh-api.log")

log.info("-----------------------------------------")
log.info("Hello from test_run.lua!")
log.info("This script was executed by 'peshell run'.")

-- 检查并打印从命令行传递过来的参数
-- 这些参数由 prelude.lua 中的 run_command 放入全局 arg 表
if arg and #arg > 0 then
    log.info("Arguments received by this script:")
    for i, v in ipairs(arg) do
        log.info("  arg[", i, "]: ", v)
    end
else
    log.info("No additional arguments were passed to this script.")
end

-- 模拟一些操作
log.info("Performing a quick task...")
require("pesh-api.async").sleep_async(2000) -- 暂停2秒

log.info("Task finished. This script will now exit.")
log.info("-----------------------------------------")
