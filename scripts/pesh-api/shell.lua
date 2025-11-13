-- pesh-api/shell.lua
-- 封装外壳 (Shell) 的加载与守护逻辑
-- 版本 2.0 - 采用事件驱动的等待逻辑

local M = {}
local process = require("pesh-api.process")
local async = require("pesh-api.async")
local log = require("pesh-api.log")

--[[
@description 加载并锁定一个程序作为系统外壳，使用高效的事件驱动等待。
             如果外壳进程被关闭，此函数会自动重新启动它。
             这是一个阻塞函数，会进入一个无限循环。
@param shell_path string: 外壳程序的可执行文件完整路径。
]]
function M.lock_shell(shell_path)
    if not shell_path then
        log.error("Error in lock_shell: shell_path is required.")
        return
    end

    local _, _, shell_name = shell_path:find("([^\\\\]+)$")
    shell_name = shell_name or shell_path

    log.info("SHELL: Starting event-driven guardian for '", shell_name, "'...")

    -- 进入守护循环
    while true do
        log.info("SHELL: Starting/Restarting shell and beginning to wait for its termination...")

        -- 启动外壳进程
        local shell_proc = process.exec_async({ command = shell_path })

        if shell_proc then
            log.info("SHELL: Shell process started with PID: ", shell_proc.pid, ". Now entering wait state.")

            -- ########## 核心逻辑修改 ##########
            -- 使用事件驱动的方式等待进程结束。
            -- 这里的 wait_for_exit_async 内部调用了 MsgWaitForMultipleObjects，
            -- 它会在等待期间处理窗口消息，使程序保持响应，且CPU占用极低。
            -- 最后一个参数 -1 表示无限等待。
            shell_proc:wait_for_exit_async(-1)
            -- #################################

            log.warn("SHELL: Shell process (PID: ", shell_proc.pid, ") has terminated. Restarting after a short delay...")

        else
            log.error("SHELL: Failed to start shell process! Retrying in 5 seconds...")
            -- 如果启动失败，退化为简单的延时，防止CPU空转
            async.sleep_async(5000)
        end

        -- 在重启前稍作延时，避免因启动失败导致的快速、无意义的循环
        async.sleep_async(1000)

    end
end

return M
