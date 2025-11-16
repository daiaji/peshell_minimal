-- scripts/pesh-api/shell.lua
-- 封装外壳 (Shell) 的加载与守护逻辑 (v4 - 增强日志)

local M = {}
local process = require("pesh-api.process")
local async = require("pesh-api.async")
local log = require("pesh-api.log")
local native = pesh_native

local SHUTDOWN_EVENT_NAME = "Global\\PEShell_Guardian_Shutdown_Event"

local function guardian_coroutine(shell_path, shell_name)
    log.info("GUARDIAN: Coroutine started for '", shell_name, "'.")

    local shutdown_event = native.create_event(SHUTDOWN_EVENT_NAME)
    if not shutdown_event then
        log.critical("GUARDIAN: CRITICAL - Failed to create shutdown event. Guardian cannot run.")
        return
    end
    log.info("GUARDIAN: Shutdown event '", SHUTDOWN_EVENT_NAME, "' created.")

    local should_run = true
    while should_run do
        
        -- 核心逻辑：尝试领养，如果失败则创建
        log.trace("GUARDIAN: Loop iteration starts. Attempting to find/adopt '", shell_name, "'...")
        local shell_proc = process.open_by_name(shell_name)

        if not shell_proc then
            -- 领养失败，说明进程不存在，需要我们自己创建
            log.info("GUARDIAN: Process not found. Launching a new instance of '", shell_path, "'...")
            shell_proc = process.exec_async({ command = shell_path })
            if shell_proc then
                log.info("GUARDIAN: Successfully launched new process with PID: ", shell_proc.pid)
            end
        else
            -- 领养成功！
            log.info("GUARDIAN: Successfully adopted existing process with PID: ", shell_proc.pid)
        end

        if shell_proc and shell_proc.handle then
            log.info("GUARDIAN: Monitoring shell process (PID: ", shell_proc.pid, ") and shutdown event.")

            local handles_to_wait = { shell_proc.handle, shutdown_event }
            local signaled_index, err = native.wait_for_multiple_objects(handles_to_wait, -1)

            if signaled_index == 1 then
                log.warn("GUARDIAN: Shell process (PID: ", shell_proc.pid, ") terminated unexpectedly. Will restart on next loop.")
            elseif signaled_index == 2 then
                log.info("GUARDIAN: Shutdown event received. Exiting guardian loop.")
                should_run = false
            else
                log.error("GUARDIAN: Wait failed or was interrupted (", tostring(err), "). Exiting loop.")
                should_run = false
            end
            
            shell_proc:close_handle()
        else
            log.error("GUARDIAN: Failed to start or adopt shell process! Retrying after 5 seconds...")
            async.sleep_async(5000)
        end
    end

    log.info("GUARDIAN: Cleaning up before exit...")
    local running_shell = process.open_by_name(shell_name)
    if running_shell then
        log.info("GUARDIAN: Terminating remaining shell process (PID: ", running_shell.pid, ")...")
        running_shell:kill()
        running_shell:close_handle()
    end
    
    native.close_handle(shutdown_event)
    log.info("GUARDIAN: Guardian cleanup complete.")

    log.info("GUARDIAN: Posting WM_QUIT to terminate the main process.")
    native.post_quit_message(0)
end

function M.lock_shell(shell_path)
    if not shell_path or shell_path == "" then
        log.error("Error in lock_shell: shell_path is required.")
        return false
    end
    
    -- 检查文件是否存在
    if not native.search_path(shell_path) then
        log.error("Error in lock_shell: Executable not found: '", shell_path, "'")
        return false
    end

    local _, _, shell_name = shell_path:find("([^\\\\]+)$")
    shell_name = shell_name or shell_path

    log.info("SHELL: Dispatching background guardian for '", shell_name, "'...")

    local co = coroutine.create(guardian_coroutine)
    local status, err = coroutine.resume(co, shell_path, shell_name)
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

    local success = native.set_event(shutdown_event)
    native.close_handle(shutdown_event)

    if success then
        log.info("Shutdown signal sent successfully.")
        return true
    else
        log.error("Failed to send the shutdown signal.")
        return false
    end
end

M.__commands = {
    shel = function(...)
        local args = { ... }
        if #args == 0 then log.error("shel: Missing shell executable path."); return 1; end
        M.lock_shell(args[1])
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