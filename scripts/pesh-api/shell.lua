-- scripts/pesh-api/shell.lua
-- 封装外壳 (Shell) 的加载与守护逻辑 (v9.0 - SafeHandle & Await Fix)

local M = {}
local process = require("pesh-api.process")
local async = require("pesh-api.async")
local log = require("pesh-api.log")
local k32 = require("pesh-api.winapi.kernel32")
local u32 = require("pesh-api.winapi.user32")
local native = _G.pesh_native
local ffi = require("pesh-api.ffi")

local SHUTDOWN_EVENT_NAME = "Global\\PEShell_Guardian_Shutdown_Event"

local function guardian_coroutine(shell_command, options)
    options = options or {}
    local strategy = options.strategy or "takeover"
    local ready_event_name = options.ready_event_name
    local respawn_event_name = options.respawn_event_name

    local shell_name = process.get_process_name_from_command(shell_command)
    if not shell_name then
        log.critical("GUARDIAN: CRITICAL - Could not determine process name.")
        return
    end

    log.info("GUARDIAN: Coroutine started for '", shell_name, "' with strategy '", strategy, "'.")
    
    local shutdown_event, err = k32.create_event(SHUTDOWN_EVENT_NAME, true, false)
    if not shutdown_event then
        log.critical("GUARDIAN: CRITICAL - Failed to create shutdown event: ", err)
        return
    end

    if strategy == "takeover" then
        log.info("GUARDIAN (takeover): Performing pre-launch cleanup for '", shell_name, "'...")
        process.kill_all_by_name(shell_name)
        async.sleep_async(500)
    end

    local is_first_launch = true
    local should_run = true
    while should_run do
        local shell_proc = nil

        if strategy == "adopt" and is_first_launch then
            shell_proc = process.open_by_name(shell_name)
        end
        if not shell_proc then
             shell_proc = process.exec_async({ command = shell_command })
        end

        if shell_proc then
            if is_first_launch and ready_event_name then
                local ready_event, open_err = k32.open_event(ready_event_name)
                if ready_event then k32.set_event(ready_event) end
            elseif not is_first_launch and respawn_event_name then
                local respawn_event, open_err = k32.open_event(respawn_event_name)
                if respawn_event then k32.set_event(respawn_event) end
            end
        end
        
        if shell_proc and shell_proc.handle then
            log.info("GUARDIAN: Monitoring shell process PID: ", shell_proc.pid)
            
            -- 使用 SafeHandle 结构
            local handle_obj_shell = ffi.new("SafeHandle_t", { h = shell_proc.handle.h })
            local handle_obj_shutdown = ffi.new("SafeHandle_t", { h = shutdown_event.h })

            -- FFI 无法直接传递包含指针的结构体到 C，我们需要传递指针的指针
            local handles_to_wait = { handle_obj_shell, handle_obj_shutdown }
            local signaled_index, wait_err = await(native.wait_for_multiple_objects, handles_to_wait, false, -1)
            
            if signaled_index == 1 then
                log.warn("GUARDIAN: Shell process (PID: ", shell_proc.pid, ") terminated.")
                if strategy ~= "once" then log.info("Will restart.") end
            elseif signaled_index == 2 then
                log.info("GUARDIAN: Shutdown event received. Exiting guardian loop.")
                should_run = false
            else
                log.error("GUARDIAN: Wait failed (", tostring(wait_err), "). Exiting loop.")
                should_run = false
            end
            
            shell_proc:close_handle()
            
        elseif should_run then
            log.error("GUARDIAN: Failed to start or adopt shell process! Retrying...")
            async.sleep_async(2000)
        end
        
        is_first_launch = false
    end

    log.info("GUARDIAN: Cleaning up before exit...")
    process.kill_all_by_name(shell_name)
    log.info("GUARDIAN: Guardian cleanup complete.")
    u32.post_quit_message(0)
end

function M.lock_shell(shell_command, options)
    if not shell_command then
        log.error("Error in lock_shell: shell_command is required.")
        return false
    end
    log.info("SHELL: Dispatching background guardian for '", shell_command, "'...")
    async.run(guardian_coroutine, shell_command, options)
    return true
end

function M.exit_guardian()
    log.info("Attempting to signal guardian to shut down.")
    local shutdown_event, err = k32.open_event(SHUTDOWN_EVENT_NAME)
    if not shutdown_event then
        log.error("Could not open shutdown event. Is guardian running? Error: ", err)
        return false
    end
    log.debug("Successfully opened the shutdown event.")
    
    local success, set_err = k32.set_event(shutdown_event)
    
    if success then log.info("Shutdown signal sent.") else log.error("Failed to send shutdown signal: ", set_err) end
    return success
end

M.__commands = {
    shel = function(args)
        if not args.cmd or #args.cmd == 0 then
            log.error("shel: Missing shell command line."); return 1;
        end
        -- 适配新的简单 args 结构
        local cmd_line = table.concat(args.cmd, " ")
        local adopt_mode = false
        if args.cmd[1] == "--adopt" then
            table.remove(args.cmd, 1)
            cmd_line = table.concat(args.cmd, " ")
            adopt_mode = true
        end
        
        local shel_options = { strategy = adopt_mode and "adopt" or "takeover" }
        M.lock_shell(cmd_line, shel_options)
        return 0 -- main 模式下返回 0 以进入消息循环
    end
}

return M