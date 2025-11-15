-- scripts/pesh-api/shell.lua
-- 封装外壳 (Shell) 的加载与守护逻辑 (v3 - 包含退出函数)

local M = {}
local process = require("pesh-api.process")
local async = require("pesh-api.async")
local log = require("pesh-api.log")
local native = pesh_native

-- 定义一个全局唯一的事件名称，用于优雅地关闭守护进程
-- "Global\\" 前缀确保在所有用户会话中都可见，这在 PE 环境下是最佳实践
local SHUTDOWN_EVENT_NAME = "Global\\PEShell_Guardian_Shutdown_Event"

--
-- 后台守护协程 (此部分保持不变)
--
local function guardian_coroutine(shell_path, shell_name)
    log.info("GUARDIAN: Coroutine started for '", shell_name, "'.")

    -- 1. 创建全局关闭事件
    local shutdown_event = native.create_event(SHUTDOWN_EVENT_NAME)
    if not shutdown_event then
        log.critical("GUARDIAN: CRITICAL - Failed to create shutdown event. Guardian cannot run.")
        return
    end
    log.info("GUARDIAN: Shutdown event '", SHUTDOWN_EVENT_NAME, "' created.")

    local should_run = true
    while should_run do
        -- ================== 最终的守护逻辑 (更简洁) ==================
        
        -- 1. 直接尝试“领养”一个已存在的进程。
        -- 这个API会一步完成查找和获取句柄。
        log.info("GUARDIAN: Attempting to adopt existing shell process '", shell_name, "'...")
        local shell_proc = process.open_by_name(shell_name)

        -- 2. 如果“领养”失败 (进程不存在)，则“创建”一个新的。
        if not shell_proc then
            log.info("GUARDIAN: No existing shell process found. Launching a new one...")
            shell_proc = process.exec_async({ command = shell_path })
        else
            log.info("GUARDIAN: Successfully adopted existing shell process with PID: ", shell_proc.pid)
        end
        -- =============================================================

        if shell_proc and shell_proc.handle then
            log.info("GUARDIAN: Now monitoring shell process with PID: ", shell_proc.pid, ".")

            local handles_to_wait = { shell_proc.handle, shutdown_event }
            local signaled_index, err = native.wait_for_multiple_objects(handles_to_wait, -1)

            if signaled_index == 1 then
                log.warn("GUARDIAN: Shell process (PID: ", shell_proc.pid, ") terminated. Will restart on next loop iteration.")
            elseif signaled_index == 2 then
                log.info("GUARDIAN: Shutdown event received. Exiting guardian loop.")
                should_run = false
            else
                log.error("GUARDIAN: Wait failed or interrupted (", tostring(err), "). Exiting loop.")
                should_run = false
            end
            
            -- 无论进程是领养的还是新建的，都需要在使用后关闭句柄
            shell_proc:close_handle()
        else
            log.error("GUARDIAN: Failed to start or adopt shell process! Retrying after 5 seconds...")
            async.sleep_async(5000)
        end
    end

    -- 4. 循环结束后，执行清理工作
    log.info("GUARDIAN: Cleaning up before exit...")

    local running_shell = process.find(shell_name)
    if running_shell then
        log.info("GUARDIAN: Terminating remaining shell process (PID: ", running_shell.pid, ")...")
        running_shell:kill()
    end
    
    log.info("GUARDIAN: Guardian cleanup complete.")

    -- 5. [关键] 通知主 C++ 消息循环退出
    log.info("GUARDIAN: Posting WM_QUIT to terminate the main process.")
    native.post_quit_message(0)
end

---
-- @description 启动并守护一个系统外壳程序。
-- @param shell_path string: 外壳程序的可执行文件路径。
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
-- @return boolean: 如果成功发送信号则返回 true，否则返回 false。
function M.exit_guardian()
    log.info("Attempting to signal the guardian process to shut down.")

    -- 1. 尝试打开守护进程创建的命名事件
    local shutdown_event = native.open_event(SHUTDOWN_EVENT_NAME)

    if not shutdown_event then
        log.error("Could not open the shutdown event. Is the guardian process running?")
        return false
    end

    log.debug("Successfully opened the shutdown event.")

    -- 2. 触发事件
    if native.set_event(shutdown_event) then
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
        if #args == 0 then
            log.error("shel: Missing shell executable path.")
            return 1 -- 返回错误码
        end
        M.lock_shell(args[1])
        return 0 -- 成功
    end,

    shutdown = function()
        if M.exit_guardian() then
            log.info("Command 'shutdown' executed successfully.")
            return 0 -- 成功退出码
        else
            log.error("Command 'shutdown' failed.")
            return 1 -- 失败退出码
        end
    end
}

return M