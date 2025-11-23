-- scripts/plugins/shell/init.lua
-- 系统外壳守护插件 (Lua-Ext Edition)
-- Version: 9.0 (Robust Single-Instance Cleanup)

local pesh = _G.pesh
local M = {}
local log = _G.log

local ffi = require("ffi")
local native = _G.pesh_native
local process = pesh.plugin.load("process")
local async = pesh.plugin.load("async")

require("ffi.req")("Windows.sdk.kernel32")
require("ffi.req")("Windows.sdk.user32")

local k32 = ffi.load("kernel32")
local u32 = ffi.load("user32")

local SHUTDOWN_EVENT_NAME = "Global\\PEShell_Guardian_Shutdown_Event"

local function get_event_handle(name, open_only)
    local CP_UTF8 = 65001
    local function to_w(s)
        if not s then return nil end
        local len = k32.MultiByteToWideChar(CP_UTF8, 0, s, -1, nil, 0)
        local buf = ffi.new("wchar_t[?]", len)
        k32.MultiByteToWideChar(CP_UTF8, 0, s, -1, buf, len)
        return buf
    end

    if open_only then
        return k32.OpenEventW(0x0002, 0, to_w(name))
    else
        return k32.CreateEventW(nil, 1, 0, to_w(name))
    end
end

-- [新增] 确保目标进程彻底消失
-- 对于 Explorer 这种单实例应用，必须确保旧进程彻底死亡，
-- 否则新进程启动时会检测到旧实例并自动退出，导致守护进程误判并无限重启。
local function ensure_clean_state(process_name, timeout_ms)
    timeout_ms = timeout_ms or 10000 -- 默认最多尝试 10 秒
    local start_time = k32.GetTickCount()
    
    log.debug("GUARDIAN: Ensuring clean slate for '", process_name, "'...")

    while true do
        local pids = process.find_all(process_name)
        
        -- 1. 如果没有找到任何进程，说明环境已干净
        if not pids or #pids == 0 then
            return true
        end

        -- 2. 检查是否超时
        if (k32.GetTickCount() - start_time) > timeout_ms then
            log.error("GUARDIAN: Timeout waiting for '", process_name, "' to die. PIDs remaining: ", #pids)
            return false
        end

        -- 3. 再次尝试强制杀死所有残留进程
        log.warn("GUARDIAN: Cleaning up ", #pids, " instance(s) of ", process_name)
        -- 使用 false 参数表示 Force Kill (TerminateProcess)
        process.kill_all_by_name(process_name, false)

        -- 4. 异步等待一小会儿，让内核有时间释放资源
        await(async.sleep, 200)
    end
end

local function guardian_coroutine(shell_command, options)
    options = options or {}
    local strategy = options.strategy or "takeover"
    local shell_name = process.get_process_name_from_command(shell_command)

    if not shell_name then
        log.critical("GUARDIAN: Could not determine process name from command: ", shell_command)
        return
    end

    local shutdown_event = get_event_handle(SHUTDOWN_EVENT_NAME, false)
    local shutdown_wrapper = ffi.new("struct { void* h; }", { h = shutdown_event })

    -- [修改] 启动前的强力清理
    if strategy == "takeover" then
        log.info("GUARDIAN: Performing PRE-LAUNCH scrub for '", shell_name, "'...")
        local is_clean = ensure_clean_state(shell_name, 10000)
        
        if not is_clean then
            log.critical("GUARDIAN: ABORTING! Unable to kill existing instances of '", shell_name, "'. Launching now would cause a spawn loop.")
            k32.CloseHandle(shutdown_event)
            -- 既然无法接管，最好不要继续，以免炸掉系统
            return 
        end
        log.info("GUARDIAN: Environment is clean. Proceeding to launch.")
    end

    local is_first_launch = true
    local current_shell_proc = nil
    
    while true do
        -- 策略逻辑：如果是 adopt 且是第一次，尝试查找现有进程
        if strategy == "adopt" and is_first_launch and not current_shell_proc then
            current_shell_proc = process.find(shell_name)
            if current_shell_proc then 
                log.info("GUARDIAN: Adopted existing PID: ", current_shell_proc.pid) 
            end
        end
        
        -- 如果没有进程对象（没找到 或 策略是 takeover 或 上次死掉了），则创建
        if not current_shell_proc then
             -- [关键] 在每次重生前，再次确保没有残留的僵尸进程
             -- 防止例如 explorer 崩溃后留下的半死不活的进程干扰新实例
             if not is_first_launch then
                 ensure_clean_state(shell_name, 3000)
             end

             current_shell_proc = process.exec_async({ command = shell_command })
        end

        -- 信号触发逻辑 (Ready / Respawn)
        if current_shell_proc then
            local evt_name = is_first_launch and options.ready_event_name or options.respawn_event_name
            if evt_name then
                local h = get_event_handle(evt_name, true)
                if h ~= nil then 
                    k32.SetEvent(h)
                    k32.CloseHandle(h) 
                end
            end
        end
        
        -- 监控逻辑
        if current_shell_proc and current_shell_proc:is_valid() then
            log.info("GUARDIAN: Monitoring PID: ", current_shell_proc.pid)
            
            local proc_h = ffi.new("struct { void* h; }", { h = current_shell_proc:handle() })
            local handles = { proc_h, shutdown_wrapper }
            
            -- 阻塞等待：要么进程死，要么收到 Shutdown 信号
            local signaled_index = await(native.wait_for_multiple_objects, handles)
            
            if signaled_index == 1 then
                log.warn("GUARDIAN: Shell process (PID: ", current_shell_proc.pid, ") terminated unexpectedly.")
                current_shell_proc:close()
                current_shell_proc = nil
                
                if strategy == "once" then 
                    log.info("GUARDIAN: Strategy is 'once'. Exiting guardian.")
                    break 
                end
                
                log.info("GUARDIAN: Preparing to respawn...")
                await(async.sleep, 1000) -- 避免疯狂重启
                
            elseif signaled_index == 2 then
                log.info("GUARDIAN: Shutdown signal received.")
                break
            else
                log.error("GUARDIAN: Wait error (Index: ", tostring(signaled_index), "). Sleeping and retrying...")
                await(async.sleep, 2000)
            end
        else
            log.error("GUARDIAN: Failed to start shell process! Retrying in 3s...")
            await(async.sleep, 3000)
        end
        
        is_first_launch = false
    end

    log.info("GUARDIAN: Shutting down. Cleaning up...")
    
    if current_shell_proc and current_shell_proc:is_valid() then
        log.info("Terminating guarded shell PID: ", current_shell_proc.pid)
        current_shell_proc:terminate(0)
        current_shell_proc:close()
    else
        -- 如果是接管模式，退出时也确保清理干净
        if strategy == "takeover" then
            process.kill_all_by_name(shell_name, false)
        end
    end

    k32.CloseHandle(shutdown_event)
    u32.PostQuitMessage(0)
end

function M.lock_shell(shell_command, options)
    -- 启动协程运行守护逻辑
    async.run(guardian_coroutine, shell_command, options)
    return true
end

function M.exit_guardian()
    local h = get_event_handle(SHUTDOWN_EVENT_NAME, true)
    if h ~= nil then
        k32.SetEvent(h)
        k32.CloseHandle(h)
        return true
    end
    return false
end

M.__commands = {
    shel = function(args)
        if not args.cmd[1] then return 1 end
        -- 支持简单的参数传递
        local cmd = table.concat(args.cmd, " ")
        M.lock_shell(cmd)
        return 0
    end,
    shutdown = function() return M.exit_guardian() and 0 or 1 end
}

return M