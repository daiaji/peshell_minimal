-- scripts/plugins/shell/init.lua
-- 系统外壳守护插件 (Lua-Ext Edition)
-- Version: 8.0 (Includes FFI definitions for stability)

local pesh = _G.pesh
local M = {}
local log = _G.log

local ffi = require("ffi")
local native = _G.pesh_native
local process = pesh.plugin.load("process")
local async = pesh.plugin.load("async")

require("ffi.req")("Windows.sdk.kernel32")
require("ffi.req")("Windows.sdk.user32")

ffi.cdef[[
    void* CreateEventW(void* lpEventAttributes, int bManualReset, int bInitialState, const wchar_t* lpName);
    void* OpenEventW(unsigned long dwDesiredAccess, int bInheritHandle, const wchar_t* lpName);
    int SetEvent(void* hEvent);
    int CloseHandle(void* hObject);
    void PostQuitMessage(int nExitCode);
]]

local k32 = ffi.load("kernel32")
local u32 = ffi.load("user32")

local SHUTDOWN_EVENT_NAME = "Global\\PEShell_Guardian_Shutdown_Event"

local function get_event_handle(name, open_only)
    local CP_UTF8 = 65001
    local function to_w(s)
        if not s then return nil end
        local len = ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, -1, nil, 0)
        local buf = ffi.new("wchar_t[?]", len)
        ffi.C.MultiByteToWideChar(CP_UTF8, 0, s, -1, buf, len)
        return buf
    end

    if open_only then
        return k32.OpenEventW(0x0002, 0, to_w(name))
    else
        return k32.CreateEventW(nil, 1, 0, to_w(name))
    end
end

local function guardian_coroutine(shell_command, options)
    options = options or {}
    local strategy = options.strategy or "takeover"
    local shell_name = process.get_process_name_from_command(shell_command)

    if not shell_name then
        log.critical("GUARDIAN: Could not determine process name.")
        return
    end

    local shutdown_event = get_event_handle(SHUTDOWN_EVENT_NAME, false)
    local shutdown_wrapper = ffi.new("struct { void* h; }", { h = shutdown_event })

    if strategy == "takeover" then
        log.info("GUARDIAN: Pre-launch CLEANUP for '", shell_name, "'...")
        process.kill_all_by_name(shell_name)
        await(async.sleep, 500)
    end

    local is_first_launch = true
    
    while true do
        local shell_proc = nil
        
        if strategy == "adopt" and is_first_launch then
            shell_proc = process.find(shell_name)
            if shell_proc then log.info("GUARDIAN: Adopted existing PID: ", shell_proc.pid) end
        end
        
        if not shell_proc then
             shell_proc = process.exec_async({ command = shell_command })
        end

        if shell_proc then
            local evt_name = is_first_launch and options.ready_event_name or options.respawn_event_name
            if evt_name then
                local h = get_event_handle(evt_name, true)
                if h ~= nil then 
                    k32.SetEvent(h)
                    ffi.C.CloseHandle(h) 
                end
            end
        end
        
        if shell_proc and shell_proc:is_valid() then
            log.info("GUARDIAN: Monitoring PID: ", shell_proc.pid)
            
            local proc_h = ffi.new("struct { void* h; }", { h = shell_proc:handle() })
            
            local handles = { proc_h, shutdown_wrapper }
            local signaled_index = await(native.wait_for_multiple_objects, handles)
            
            if signaled_index == 1 then
                log.warn("GUARDIAN: Shell terminated.")
                if strategy == "once" then break end
            elseif signaled_index == 2 then
                log.info("GUARDIAN: Shutdown signal received.")
                break
            else
                log.error("GUARDIAN: Wait error.")
                await(async.sleep, 1000)
            end
        else
            log.error("GUARDIAN: Start failed. Retrying...")
            await(async.sleep, 2000)
        end
        
        is_first_launch = false
    end

    log.info("GUARDIAN: Final CLEANUP...")
    process.kill_all_by_name(shell_name)
    ffi.C.CloseHandle(shutdown_event)
    
    u32.PostQuitMessage(0)
end

function M.lock_shell(shell_command, options)
    async.run(guardian_coroutine, shell_command, options)
    return true
end

function M.exit_guardian()
    local h = get_event_handle(SHUTDOWN_EVENT_NAME, true)
    if h ~= nil then
        k32.SetEvent(h)
        ffi.C.CloseHandle(h)
        return true
    end
    return false
end

M.__commands = {
    shel = function(args)
        if not args.cmd[1] then return 1 end
        local cmd = table.concat(args.cmd, " ")
        M.lock_shell(cmd)
        return 0
    end,
    shutdown = function() return M.exit_guardian() and 0 or 1 end
}

return M