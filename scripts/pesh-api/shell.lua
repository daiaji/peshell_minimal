-- scripts/pesh-api/shell.lua
-- 封装外壳 (Shell) 的加载与守护逻辑 (重构版)

local M = {}
local process = require("pesh-api.process")
local async = require("pesh-api.async")
local log = require("pesh-api.log")

-- 这是一个在后台运行的守护协程
local function guardian_coroutine(shell_path, shell_name)
    log.info("SHELL GUARDIAN: Coroutine started for '", shell_name, "'.")
    while true do
        -- 启动外壳进程，现在我们能获取到它的句柄
        local shell_proc = process.exec_async({ command = shell_path })

        if shell_proc then
            log.info("SHELL GUARDIAN: Shell process started with PID: ", shell_proc.pid,
                ". Waiting for it to terminate via its handle...")

            -- [核心改进]
            -- 这是一个基于句柄的、精确的、事件驱动的等待。
            -- 它会一直阻塞（同时处理UI消息），直到进程确实退出。
            shell_proc:wait_for_exit_async(-1) -- -1 表示无限等待

            log.warn("SHELL GUARDIAN: Shell process (PID: ", shell_proc.pid, ") has terminated. Restarting...")
            
            -- 进程结束后，句柄已失效。虽然GC会自动处理，但显式关闭是好习惯。
            shell_proc:close_handle()
        else
            log.error("SHELL GUARDIAN: Failed to start shell process! Retrying after 5 seconds...")
            async.sleep_async(5000)
        end
        -- 重启前的短暂延时，防止因某种错误导致的高CPU占用循环
        async.sleep_async(1000)
    end
end

--[[
@description 配置并启动一个后台协程来守护系统外壳。
]]
function M.lock_shell(shell_path)
    if not shell_path then
        log.error("Error in lock_shell: shell_path is required.")
        return
    end

    -- 从路径中提取文件名
    local _, _, shell_name = shell_path:find("([^\\\\]+)$")
    shell_name = shell_name or shell_path

    log.info("SHELL: Dispatching background guardian for '", shell_name, "'...")

    -- 创建并启动守护协程
    local co = coroutine.create(guardian_coroutine)
    local status, err = coroutine.resume(co, shell_path, shell_name)
    if not status then
        log.critical("SHELL: Failed to start guardian coroutine! ", tostring(err))
    end
end

-- 声明要导出的子命令
M.__commands = {
    shel = function(...)
        local args = { ... }
        if #args == 0 then
            log.error("shel: Missing shell executable path.")
            return
        end
        M.lock_shell(args[1])
    end
}

return M