-- pesh-api/shell.lua
-- 封装外壳 (Shell) 的加载与守护逻辑
-- 版本 4.1 - 优化日志和健壮性

local M = {}
local process = require("pesh-api.process")
local async = require("pesh-api.async")
local log = require("pesh-api.log")

-- 这是一个在后台运行的守护协程
local function guardian_coroutine(shell_path, shell_name)
    log.info("SHELL GUARDIAN: Coroutine started for '", shell_name, "'.")
    while true do
        -- 启动外壳进程
        local shell_proc = process.exec_async({ command = shell_path })

        if shell_proc then
            log.info("SHELL GUARDIAN: Shell process started with PID: ", shell_proc.pid, ". Waiting for it to terminate...")
            
            -- 使用事件驱动方式，异步等待进程结束
            local gracefully_exited = shell_proc:wait_for_exit_async(-1)
            
            if gracefully_exited then
                 log.warn("SHELL GUARDIAN: Shell process (PID: ", shell_proc.pid, ") has terminated. Restarting...")
            else
                 log.error("SHELL GUARDIAN: Wait failed for PID ", shell_proc.pid, ". Assuming terminated and attempting restart...")
            end
        else
            log.error("SHELL GUARDIAN: Failed to start shell process! Retrying after a delay...")
            -- 如果启动失败，等待更长时间再重试
            async.sleep_async(5000)
        end
        -- 重启前的短暂延时，给系统一点喘息时间
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

    local _, _, shell_name = shell_path:find("([^\\\\]+)$")
    shell_name = shell_name or shell_path

    log.info("SHELL: Dispatching background guardian for '", shell_name, "'...")

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