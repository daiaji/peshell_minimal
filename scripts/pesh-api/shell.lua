-- pesh-api/shell.lua
-- 封装外壳 (Shell) 的加载与守护逻辑

local M = {}
local process = require("pesh-api.process")
local async = require("pesh-api.async")
local log = require("pesh-api.log")

--[[
@description 加载并锁定一个程序作为系统外壳。
             如果外壳进程被关闭，此函数会自动重新启动它。
             这是一个阻塞函数，会进入一个无限循环。
@param shell_path string: 外壳程序的可执行文件完整路径。
]]
function M.lock_shell(shell_path)
    if not shell_path then
        log.error("Error in lock_shell: shell_path is required.")
        return
    end

    -- 从完整路径中提取文件名
    local _, _, shell_name = shell_path:find("([^\\\\]+)$")
    shell_name = shell_name or shell_path

    log.info("SHELL: Locking shell process '", shell_name, "'...")

    -- 进入守护循环
    while true do
        -- 查找外壳进程是否存在
        local shell_process = process.find(shell_name)

        if not shell_process then
            log.warn("SHELL: Shell process not found, attempting to restart...")
            local new_proc = process.exec_async({ command = shell_path })
            if new_proc then
                log.info("SHELL: Shell process restarted with PID: ", new_proc.pid)
            else
                log.error("SHELL: Failed to restart shell process!")
            end
        else
            log.trace("SHELL: Guardian check passed, shell process (PID: ", shell_process.pid, ") is running.")
        end

        -- 每 3 秒检查一次
        async.sleep_async(3000)
    end
end

return M