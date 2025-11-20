-- scripts/plugins/shell/init.lua
-- 系统外壳守护插件 (v7.1 - Async Sleep Fix)

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
        log.critical("GUARDIAN [", call_id, "]: Failed to create shutdown event.")
        return
    end
    -- RAII-style event handle
    local shutdown_event = ffi.EventHandle(shutdown_event_h)

    if strategy == "takeover" then
        log.info("GUARDIAN (takeover): Cleaning up '", shell_name, "'...")
        process.kill_all_by_name(shell_name)
        
        -- [修复] 使用真正的异步睡眠
        await(async.sleep, 500)
    end

    local is_first_launch = true
    
    while true do
        local shell_proc = nil
        
        -- 尝试启动或接管
        if strategy == "adopt" and is_first_launch then
            shell_proc = process.find(shell_name)
            if shell_proc then
                 log.info("GUARDIAN: Adopted existing process PID: ", shell_proc.pid)
            end
        end
        
        if not shell_proc then
             shell_proc = process.exec_async({ command = shell_command })
        end

        -- 发送就绪/重启信号
        if shell_proc then
            if is_first_launch and ready_event_name then
                local h = k32.OpenEventW(0x0002, 0, ffi.to_wide(ready_event_name))
                if h and h ~= nil then k32.SetEvent(h); ffi.C.CloseHandle(h) end
            elseif not is_first_launch and respawn_event_name then
                local h = k32.OpenEventW(0x0002, 0, ffi.to_wide(respawn_event_name))
                if h and h ~= nil then k32.SetEvent(h); ffi.C.CloseHandle(h) end
            end
        end
        
        -- 监控循环
        if shell_proc and shell_proc:is_valid() then
            log.info("GUARDIAN [", call_id, "]: Monitoring PID: ", shell_proc.pid)
            
            local waitable_proc_handle = process.get_waitable_handle(shell_proc)
            
            if waitable_proc_handle then
                local handles_to_wait = { waitable_proc_handle, shutdown_event }
                
                -- 阻塞协程，直到任意一个 Handle 被触发
                local signaled_index = await(native.wait_for_multiple_objects, handles_to_wait, false, -1)
                
                if signaled_index == 1 then
                    log.warn("GUARDIAN: Shell process (PID: ", shell_proc.pid, ") terminated.")
                    if strategy == "once" then 
                        log.info("GUARDIAN: Strategy is 'once', exiting.")
                        break 
                    end
                    log.info("GUARDIAN: Will restart shell...")
                elseif signaled_index == 2 then
                    log.info("GUARDIAN: Shutdown event received.")
                    break
                else
                    log.error("GUARDIAN: Wait returned unexpected index: ", tostring(signaled_index))
                    break
                end
            else
                log.error("GUARDIAN: Failed to get waitable handle. Process may have exited immediately.")
                -- [修复] 使用真正的异步睡眠
                await(async.sleep, 1000)
            end
            
        else
            log.error("GUARDIAN: Failed to start/adopt shell process! Retrying in 2s...")
            -- [修复] 使用真正的异步睡眠，防止阻塞其他任务
            await(async.sleep, 2000)
        end
        
        is_first_launch = false
    end

    log.info("GUARDIAN: Cleaning up before exit...")
    process.kill_all_by_name(shell_name)
    u32.PostQuitMessage(0)
end

function M.lock_shell(shell_command, options)
    if not shell_command then return false end
    local call_id = options and options.unique_call_id or "UNSPECIFIED"
    log.info("SHELL PLUGIN: Dispatching guardian for [", call_id, "]")
    async.run(guardian_coroutine, shell_command, options)
    return true
end

function M.exit_guardian()
    local h = k32.OpenEventW(0x0002, 0, ffi.to_wide(SHUTDOWN_EVENT_NAME))
    if not h or h == nil then return false end
    local success = (k32.SetEvent(h) ~= 0)
    ffi.C.CloseHandle(h)
    return success
end

M.__commands = {
    shel = function(args)
        if not args.cmd or #args.cmd == 0 then return 1 end
        local adopt_mode = (args.cmd[1] == "--adopt")
        if adopt_mode then table.remove(args.cmd, 1) end
        local cmd_line = table.concat(args.cmd, " ")
        if cmd_line == "" then return 1 end
        M.lock_shell(cmd_line, { strategy = adopt_mode and "adopt" or "takeover" })
        return 0
    end,
    shutdown = function()
        if M.exit_guardian() then return 0 else return 1 end
    end
}

return M