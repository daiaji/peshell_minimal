-- scripts/pesh-api/shell.lua
-- 封装外壳 (Shell) 的加载与守护逻辑 (v3 - 包含退出函数)

local M = {}
local process = require("pesh-api.process")
local async = require("pesh-api.async")
local log = require("pesh-api.log")
local native = pesh_native

-- 定义一个全局唯一的事件名称
local SHUTDOWN_EVENT_NAME = "Global\\PEShell_Guardian_Shutdown_Event"

--
-- 后台守护协程
--
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
        
        log.info("GUARDIAN: Attempting to adopt existing shell process '", shell_name, "'...")
        local shell_proc = process.open_by_name(shell_name)

        if not shell_proc then
            log.info("GUARDIAN: No existing shell process found. Launching a new one...")
            shell_proc = process.exec_async({ command = shell_path })
        else
            log.info("GUARDIAN: Successfully adopted existing shell process with PID: ", shell_proc.pid)
        end

        if shell_proc and shell_proc.handle then
            log.info("GUARDIAN: Now monitoring shell process with PID: ", shell_proc.pid, ".")

            local handles_to_wait = { shell_proc.handle, shutdown_event }
            local signaled_index, err = native.wait_for_multiple_objects(handles_to_wait, -1)

            if signaled_index == 1 then
                log.warn("GUARDIAN: Shell process (PID: ", shell_proc.pid, ") terminated. Will restart.")
            elseif signaled_index == 2 then
                log.info("GUARDIAN: Shutdown event received. Exiting guardian loop.")
                should_run = false
            else
                log.error("GUARDIAN: Wait failed or interrupted (", tostring(err), "). Exiting loop.")
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
    
    -- [关键] 关闭我们自己创建的事件句柄
    native.close_handle(shutdown_event)
    log.info("GUARDIAN: Guardian cleanup complete.")

    log.info("GUARDIAN: Posting WM_QUIT to terminate the main process.")
    native.post_quit_message(0)
end

---
-- @description 启动并守护一个系统外壳程序。
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

---
-- @description 向正在运行的守护进程发送一个优雅的关闭信号。
function M.exit_guardian()
    log.info("Attempting to signal the guardian process to shut down.")

    local shutdown_event = native.open_event(SHUTDOWN_EVENT_NAME)

    if not shutdown_event then
        log.error("Could not open the shutdown event. Is the guardian process running?")
        return false
    end
    log.debug("Successfully opened the shutdown event.")

    local success = native.set_event(shutdown_event)
    native.close_handle(shutdown_event) -- [关键] 打开后要记得关闭

    if success then
        log.info("Shutdown signal sent successfully.")
        return true
    else
        log.error("Failed to send the shutdown signal.")
        return false
    end
end

-- 声明要导出的子命令
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