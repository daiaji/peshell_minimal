-- scripts/pesh-api/shell.lua
-- 封装外壳 (Shell) 的加载与守护逻辑 (v7.0 - Takeover Strategy)

local M = {}
local process = require("pesh-api.process")
local async = require("pesh-api.async")
local log = require("pesh-api.log")
local native = _G.pesh_native

local SHUTDOWN_EVENT_NAME = "Global\\PEShell_Guardian_Shutdown_Event"

local function guardian_coroutine(shell_command, options)
    options = options or {}
    -- [关键] 默认策略改为 "takeover"
    local strategy = options.strategy or "takeover"
    local ready_event_name = options.ready_event_name
    local respawn_event_name = options.respawn_event_name

    local shell_name = process.get_process_name_from_command(shell_command)
    if not shell_name then
        log.critical("GUARDIAN: CRITICAL - Could not determine process name. Guardian cannot run.")
        return
    end

    log.info("GUARDIAN: Coroutine started for '", shell_name, "' with strategy '", strategy, "'.")

    local shutdown_event = native.create_event(SHUTDOWN_EVENT_NAME)
    if not shutdown_event then
        log.critical("GUARDIAN: CRITICAL - Failed to create shutdown event.")
        return
    end

    -- [关键] "接管" 策略的实现：在循环开始前进行一次性清理
    if strategy == "takeover" then
        log.info("GUARDIAN (takeover): Performing pre-launch cleanup for '", shell_name, "'...")
        process.kill_all_by_name(shell_name)
        -- 短暂等待，确保进程已完全终止
        async.sleep_async(500)
    end

    local is_first_launch = true
    local should_run = true
    while should_run do
        local shell_proc = nil

        -- 根据策略决定是“收养”还是“总是新建”
        if strategy == "adopt" then
            log.info("GUARDIAN (adopt): Attempting to adopt/create '", shell_name, "'...")
            shell_proc = process.open_by_name(shell_name)
            if not shell_proc then
                shell_proc = process.exec_async({ command = shell_command })
            end
        else -- 默认的 "takeover" 或 "respawn" 策略总是创建新进程
            log.info("GUARDIAN (respawn/takeover): Launching a new instance of '", shell_name, "'...")
            shell_proc = process.exec_async({ command = shell_command })
        end

        if shell_proc then
            if is_first_launch and ready_event_name then
                local ready_event = native.open_event(ready_event_name)
                if ready_event then
                    log.info("GUARDIAN: Signaling READY event '", ready_event_name, "' now that process handle is confirmed.")
                    native.set_event(ready_event)
                    native.close_handle(ready_event)
                end
            elseif not is_first_launch and respawn_event_name then
                local respawn_event = native.open_event(respawn_event_name)
                if respawn_event then
                    log.info("GUARDIAN: Signaling RESPAWN event '", respawn_event_name, "'.")
                    native.set_event(respawn_event)
                    native.close_handle(respawn_event)
                end
            end
        end
        
        if shell_proc and shell_proc.handle then
            log.info("GUARDIAN: Now monitoring shell process with PID: ", shell_proc.pid, ".")
            local handles_to_wait = { shell_proc.handle, shutdown_event }
            local signaled_index, err = native.wait_for_multiple_objects(handles_to_wait, -1)

            if signaled_index == 1 then
                log.warn("GUARDIAN: Shell process (PID: ", shell_proc.pid, ") terminated.")
                if strategy ~= "once" then log.info("Will restart.") end
            elseif signaled_index == 2 then
                log.info("GUARDIAN: Shutdown event received. Exiting guardian loop.")
                should_run = false
            else
                log.error("GUARDIAN: Wait failed (", tostring(err), "). Exiting loop.")
                should_run = false
            end
            
            shell_proc:close_handle()
        elseif should_run then
            log.error("GUARDIAN: Failed to start or adopt shell process! Retrying...")
            async.sleep_async(2000)
        end
        
        is_first_launch = false
    end

    -- 清理逻辑
    log.info("GUARDIAN: Cleaning up before exit...")
    -- [关键] 退出时也清理所有同名进程，确保干净退出
    process.kill_all_by_name(shell_name)
    native.close_handle(shutdown_event)
    log.info("GUARDIAN: Guardian cleanup complete.")
    native.post_quit_message(0)
end

function M.lock_shell(shell_command, options)
    if not shell_command then
        log.error("Error in lock_shell: shell_command is required.")
        return false
    end
    log.info("SHELL: Dispatching background guardian for '", shell_command, "'...")
    local co = coroutine.create(guardian_coroutine)
    local status, err = coroutine.resume(co, shell_command, options)
    if not status then
        log.critical("SHELL: Failed to start guardian coroutine! ", tostring(err))
        return false
    end
    return true
end

function M.exit_guardian()
    log.info("Attempting to signal the guardian process to shut down.")
    local shutdown_event = native.open_event(SHUTDOWN_EVENT_NAME)
    if not shutdown_event then
        log.error("Could not open the shutdown event. Is the guardian process running?")
        return false
    end
    log.debug("Successfully opened the shutdown event.")
    if native.set_event(shutdown_event) then
        log.info("Shutdown signal sent successfully.")
        native.close_handle(shutdown_event)
        return true
    else
        log.error("Failed to send the shutdown signal.")
        native.close_handle(shutdown_event)
        return false
    end
end

M.__commands = {
    shel = function(...)
        local args = { ... }
        if #args == 0 then
            log.error("shel: Missing shell command line.")
            return 1
        end
        -- 允许通过 --adopt 命令行参数覆盖默认的 takeover 策略
        local options = {}
        if args[1] == "--adopt" then
            table.remove(args, 1)
            options.strategy = "adopt"
        end
        M.lock_shell(table.concat(args, " "), options)
        return 0
    end,
    shutdown = function()
        if M.exit_guardian() then
            log.info("Command 'shutdown' executed successfully.")
            return 0
        else
            log.error("Command 'shutdown' failed.")
            return 1
        end
    end
}

return M