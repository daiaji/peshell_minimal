-- scripts/plugins/shell/init.lua
-- 系统外壳守护插件 (v2.2 - Modernized Control Flow)

local pesh = _G.pesh
local M = {}

-- 1. 依赖
local log = _G.log
local ffi = pesh.ffi
local native = _G.pesh_native
local process = pesh.plugin.load("process")
local async = pesh.plugin.load("async")
local k32 = pesh.plugin.load("winapi.kernel32")
local u32 = pesh.plugin.load("winapi.user32")

local SHUTDOWN_EVENT_NAME = "Global\\PEShell_Guardian_Shutdown_Event"

-- 2. 业务逻辑
local function guardian_coroutine(shell_command, options)
    options = options or {}
    local call_id = options.unique_call_id or "UNKNOWN_ID"
    local strategy = options.strategy or "takeover"
    local ready_event_name = options.ready_event_name
    local respawn_event_name = options.respawn_event_name
    local shell_name = process.get_process_name_from_command(shell_command)

    if not shell_name then
        log.critical("GUARDIAN [", call_id, "]: CRITICAL - Could not determine process name.")
        return
    end

    log.info("GUARDIAN [", call_id, "]: Coroutine started for '", shell_name, "' with strategy '", strategy, "'.")
    
    local shutdown_event_h = k32.CreateEventW(nil, 1, 0, ffi.to_wide(SHUTDOWN_EVENT_NAME))
    if shutdown_event_h == nil then
        log.critical("GUARDIAN [", call_id, "]: CRITICAL - Failed to create shutdown event: Win32 Error ", k32.GetLastError())
        return
    end
    -- RAII-style handle
    local shutdown_event = ffi.EventHandle(shutdown_event_h)

    if strategy == "takeover" then
        log.info("GUARDIAN (takeover) [", call_id, "]: Performing pre-launch cleanup for '", shell_name, "'...")
        process.kill_all_by_name(shell_name)
        async.sleep_async(500)
    end

    local is_first_launch = true
    -- [利用 Lua 5.2 特性] 使用无限循环，并通过 break 关键字退出，取代布尔标志位
    while true do
        local shell_proc
        if strategy == "adopt" and is_first_launch then
            shell_proc = process.open_by_name(shell_name)
        end
        if not shell_proc then
             shell_proc = process.exec_async({ command = shell_command })
        end

        if shell_proc then
            if is_first_launch and ready_event_name then
                local ready_event_h = k32.OpenEventW(0x0002, 0, ffi.to_wide(ready_event_name))
                if ready_event_h and ready_event_h ~= nil then 
                    k32.SetEvent(ready_event_h)
                    ffi.C.CloseHandle(ready_event_h)
                end
            elseif not is_first_launch and respawn_event_name then
                local respawn_event_h = k32.OpenEventW(0x0002, 0, ffi.to_wide(respawn_event_name))
                if respawn_event_h and respawn_event_h ~= nil then
                    k32.SetEvent(respawn_event_h)
                    ffi.C.CloseHandle(respawn_event_h)
                end
            end
        end
        
        if shell_proc and shell_proc.handle and shell_proc.handle.h then
            log.info("GUARDIAN [", call_id, "]: Monitoring shell process PID: ", shell_proc.pid)
            
            local handles_to_wait = { shell_proc.handle, shutdown_event }
            
            local signaled_index = await(native.wait_for_multiple_objects, handles_to_wait, false, -1)
            
            if signaled_index == 1 then
                log.warn("GUARDIAN [", call_id, "]: Shell process (PID: ", shell_proc.pid, ") terminated.")
                if strategy ~= "once" then 
                    log.info("GUARDIAN [", call_id, "]: Will restart.") 
                else
                    log.info("GUARDIAN [", call_id, "]: Strategy is 'once', exiting.")
                    break -- 直接退出循环
                end
            elseif signaled_index == 2 then
                log.info("GUARDIAN [", call_id, "]: Shutdown event received. Exiting guardian loop.")
                break -- 直接退出循环
            else
                log.error("GUARDIAN [", call_id, "]: Wait returned an unexpected index: ", tostring(signaled_index), ". Exiting loop.")
                break -- 直接退出循环
            end
            
        else
            log.error("GUARDIAN [", call_id, "]: Failed to start or adopt shell process! Retrying...")
            async.sleep_async(2000)
        end
        
        is_first_launch = false
    end

    log.info("GUARDIAN [", call_id, "]: Cleaning up before exit...")
    process.kill_all_by_name(shell_name)
    log.info("GUARDIAN [", call_id, "]: Guardian cleanup complete.")
    u32.PostQuitMessage(0)
end

function M.lock_shell(shell_command, options)
    if not shell_command then
        log.error("Error in lock_shell: shell_command is required.")
        return false
    end
    
    local call_id = options and options.unique_call_id or "UNSPECIFIED"
    log.info("SHELL PLUGIN: Dispatching background guardian via async.run. Call ID: [", call_id, "]")

    async.run(guardian_coroutine, shell_command, options)
    return true
end

function M.exit_guardian()
    log.info("Attempting to signal guardian to shut down.")
    local shutdown_event_h = k32.OpenEventW(0x0002, 0, ffi.to_wide(SHUTDOWN_EVENT_NAME))
    if not shutdown_event_h or shutdown_event_h == nil then
        log.error("Could not open shutdown event. Is guardian running? Win32 Error: ", k32.GetLastError())
        return false
    end
    log.debug("Successfully opened the shutdown event.")
    
    local success = (k32.SetEvent(shutdown_event_h) ~= 0)
    local err
    if not success then
        err = k32.GetLastError()
    end
    
    ffi.C.CloseHandle(shutdown_event_h)
    
    if success then 
        log.info("Shutdown signal sent.")
    else 
        log.error("Failed to send shutdown signal: Win32 Error ", err)
    end
    return success
end

-- 3. 导出命令
M.__commands = {
    shel = function(args)
        if not args.cmd or #args.cmd == 0 then
            log.error("shel: Missing shell command line."); return 1;
        end
        local adopt_mode = (args.cmd[1] == "--adopt")
        if adopt_mode then table.remove(args.cmd, 1) end
        
        local cmd_line = table.concat(args.cmd, " ")
        if cmd_line == "" then
             log.error("shel: Missing shell command line after parsing options."); return 1;
        end
        
        local shel_options = { strategy = adopt_mode and "adopt" or "takeover" }
        M.lock_shell(cmd_line, shel_options)
        return 0
    end
}

return M