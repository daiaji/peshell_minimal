-- scripts/plugins/process/init.lua
-- Process 插件 (Lua-Ext & FFI-Bindings Edition)
-- Version: 10.0

local pesh = _G.pesh
local M = {}

local log = _G.log
local path = require("ext.path")
local cli = require("ext.cli")
local ffi = require("ffi")
local os_ext = require("ext.os")

local status, proc = pcall(require, "proc_utils_ffi")
if not status then 
    error("CRITICAL: Failed to load 'proc_utils_ffi'. Error: " .. tostring(proc)) 
end

require("ffi.req")("Windows.sdk.kernel32")
local k32 = ffi.load("kernel32")

-- ============================================================
-- Core API
-- ============================================================

function M.exec_async(params)
    local command = params.command
    local workdir = params.working_dir
    local show_mode = params.show_mode or proc.constants.SW_SHOWNORMAL
    local desktop = params.desktop
    
    local p_obj, err_code, err_msg = proc.exec(command, workdir, show_mode, desktop)
    
    if not p_obj then
        local final_msg = string.format("Failed to execute '%s'. Error: %s (Code: %s)", 
            command, tostring(err_msg), tostring(err_code))
        log.error(final_msg)
        return nil, final_msg
    end

    log.info("Process started successfully. PID: ", p_obj.pid)
    return p_obj
end

function M.find(name_or_pid)
    local pid = proc.exists(name_or_pid)
    if pid == 0 then return nil end
    
    local p_obj, err, msg = proc.open_by_pid(pid)
    if not p_obj then
        log.warn("Process exists (PID:", pid, ") but could not open handle: ", msg)
        return nil
    end
    return p_obj
end

function M.find_all(name)
    return proc.find_all(name)
end

function M.kill_all_by_name(process_name, use_graceful)
    log.warn("Killing all processes named '", process_name, "'...")
    local pids = M.find_all(process_name)
    if not pids or #pids == 0 then 
        log.info("No processes found to kill.")
        return true 
    end
    
    local all_ok = true
    for _, pid in ipairs(pids) do
        local success = false
        if use_graceful then
            success = proc.terminate_gracefully(pid, 3000)
        else
            success = proc.terminate_by_pid(pid, 0)
        end
        
        if not success then
            log.warn("Failed to terminate PID: ", pid)
            all_ok = false
        end
    end
    return all_ok
end

M.wait_for_exit = function(co, process_obj)
    if not process_obj then error("wait_for_exit called with nil process object") end
    local h = process_obj:handle()
    local wait_struct = ffi.new("struct { void* h; }", { h = h })
    _G.pesh_native.wait_for_multiple_objects(co, { wait_struct })
end

function M.wait_for_exit_pump(process_obj, timeout_ms)
    if not process_obj or not process_obj.wait_for_exit then 
        return false 
    end
    timeout_ms = timeout_ms or -1
    local start_tick = k32.GetTickCount()
    
    while true do
        if process_obj:wait_for_exit(0) then return true end
        
        if timeout_ms >= 0 then
            if (k32.GetTickCount() - start_tick) > timeout_ms then return false end
        end
        
        if os_ext.sleep_pump then
            os_ext.sleep_pump(50)
        else
            _G.pesh_native.sleep(50) 
        end
    end
end

function M.get_self_path()
    return proc.current():get_path()
end

function M.get_process_name_from_command(full_command)
    if not full_command then return nil end
    -- Use ext.path to extract name robustly
    local args = require("ffi.req")("Windows.sdk.shell32").commandline_to_argv(full_command)
    if args and args[1] then
        return path(args[1]):name()
    end
    return nil
end

M.__commands = {
    exec = function(args)
        local flags, rest_args = cli.parse(args.cmd, {
            wait = { type = "boolean", alias = "w" },
            hide = { type = "boolean", alias = "h" },
            desktop = { type = "string", alias = "d" },
            workdir = { type = "string" }
        })
        
        if #rest_args == 0 then 
            log.error("exec: Missing command.")
            return 1
        end
        
        local cmd_line = table.concat(rest_args, " ")
        local show_val = flags.hide and proc.constants.SW_HIDE or proc.constants.SW_SHOWNORMAL
        
        local p_obj = M.exec_async({ 
            command = cmd_line, 
            show_mode = show_val,
            desktop = flags.desktop,
            working_dir = flags.workdir
        })
        
        if p_obj then
            if flags.wait then M.wait_for_exit_pump(p_obj, -1) end
            return 0
        end
        return 1
    end,
    
    kill = function(args)
        local flags, targets = cli.parse(args.cmd, {
            graceful = { type = "boolean", alias = "g" }
        })
        
        if not targets or #targets == 0 then return 1 end
        
        local all_ok = true
        for _, target in ipairs(targets) do
            local pid = tonumber(target)
            if pid then
                if flags.graceful then
                    if not proc.terminate_gracefully(pid, 3000) then all_ok = false end
                else
                    if not proc.terminate_by_pid(pid, 0) then all_ok = false end
                end
            else
                if not M.kill_all_by_name(target, flags.graceful) then all_ok = false end
            end
        end
        return all_ok and 0 or 1
    end,
    
    killtree = function(args)
        local targets = args.cmd
        if not targets or #targets == 0 then return 1 end
        local all_ok = true
        for _, target in ipairs(targets) do
            local p_obj = M.find(target)
            if p_obj then
                if not p_obj:terminate_tree() then all_ok = false end
            else
                log.warn("Process not found: ", target)
            end
        end
        return all_ok and 0 or 1
    end
}

return M