-- scripts/pesh-api/process.lua
-- 封装 proc_utils 库，提供面向对象的进程管理 API (v2.1 - 增加 kill_all 功能)

local M = {}
local native = pesh_native
local log = require("pesh-api.log")
local argparse = require("pesh-api.argparse")
local fs = require("pesh-api.fs")

-- ########## Process Object Metatable ##########
local process_metatable = { __index = {} }
function process_metatable.__index:kill()
    log.info("Attempting to kill process with PID: ", self.pid)
    return native.process_close(tostring(self.pid), 0)
end
function process_metatable.__index:kill_tree()
    log.info("Attempting to kill process tree starting with PID: ", self.pid)
    return native.process_close_tree(tostring(self.pid))
end
function process_metatable.__index:wait_for_exit_async(timeout_ms)
    timeout_ms = timeout_ms or -1
    log.debug("Waiting on handle for process PID ", self.pid, " to exit with timeout ", timeout_ms, "ms.")
    if not self.handle then
        log.error("Cannot wait for process ", self.pid, ": handle is nil.")
        return false, "handle is nil"
    end
    local signaled_index, err = native.wait_for_multiple_objects({ self.handle }, timeout_ms)
    if signaled_index == 1 then
        return true
    else
        log.warn("Wait for process ", self.pid, " failed or timed out. Reason: ", tostring(err))
        return false, err
    end
end
function process_metatable.__index:close_handle()
    if self.handle then
        log.trace("Explicitly closing handle for PID ", self.pid)
        native.close_handle(self.handle)
        self.handle = nil
    end
end

-- ########## Module-level Functions ##########

function M.get_self_path()
    return native.get_exe_path()
end

function M.get_current_pid()
    return native.get_current_pid()
end

function M.find_all(name)
    log.trace("Finding all processes named: '", tostring(name), "'")
    return native.find_all_processes(tostring(name))
end

---
-- [新增] 查找并杀死所有同名进程。
-- @param process_name string: 目标进程的名称 (e.g., "explorer.exe")
-- @return boolean: 如果成功或没有找到进程则返回 true。
function M.kill_all_by_name(process_name)
    log.warn("Attempting to kill all existing processes named '", process_name, "'...")
    local pids = M.find_all(process_name)
    if not pids or #pids == 0 then
        log.info("No existing '", process_name, "' processes found to kill.")
        return true -- 没有需要杀的，也算成功
    end

    local all_killed = true
    for _, pid in ipairs(pids) do
        log.debug("  -> Terminating PID: ", pid)
        if not native.process_close(tostring(pid), 0) then
            log.error("    -> Failed to terminate PID: ", pid)
            all_killed = false
        end
    end
    return all_killed
end


function M.get_process_name_from_command(full_command)
    local parts = native.commandline_to_argv(full_command)
    if not parts or #parts == 0 then
        log.warn("get_process_name: Failed to parse command line: ", full_command)
        return nil
    end
    local executable_path = parts[1]
    return fs.path(executable_path):filename()
end

function M.open_by_name(process_name)
    log.trace("Attempting to open existing process by name: '", process_name, "'")
    local result = native.open_process_by_name(process_name)
    if result and result.pid > 0 then
        log.trace("Successfully opened process '", process_name, "' (PID: ", result.pid, "), Handle: ", tostring(result.handle))
        local process_obj = { pid = result.pid, handle = result.handle }
        setmetatable(process_obj, process_metatable)
        return process_obj
    end
    log.trace("Process '", process_name, "' not found or could not be opened.")
    return nil
end

function M.find(name_or_pid)
    log.trace("Finding process: '", tostring(name_or_pid), "'")
    local pid = native.process_exists(tostring(name_or_pid))
    if pid == 0 then
        log.trace("Process '", tostring(name_or_pid), "' not found.")
        return nil
    end
    log.trace("Process '", tostring(name_or_pid), "' found with PID: ", pid)
    local process_obj = { pid = pid, handle = nil }
    setmetatable(process_obj, process_metatable)
    return process_obj
end

function M.exec_async(params)
    if not params or not params.command then
        log.error("exec_async failed: 'command' parameter is missing.")
        return nil
    end
    log.info("Executing command via create_process: '", params.command, "'")
    local result = native.create_process(
        params.command,
        params.working_dir or nil,
        params.show_mode or 1,
        params.desktop or nil
    )
    if result and result.pid > 0 then
        log.info("Process started successfully with PID: ", result.pid, " and Handle: ", tostring(result.handle))
        local process_obj = { pid = result.pid, handle = result.handle }
        setmetatable(process_obj, process_metatable)
        return process_obj
    end
    log.error("Failed to execute command: '", params.command, "'")
    return nil
end

M.__commands = {
    exec = function(...)
        local spec = {
            { "wait",    "w", "boolean", "Wait for the process to exit." },
            { "hide",    "h", "boolean", "Execute the process in a hidden window." },
            { "desktop", "d", "string",  "Specify the target desktop (e.g., WinSta0\\Winlogon)." },
            { "workdir", nil, "string",  "Set the working directory for the process." }
        }
        local options, commands = argparse.parse({ ... }, spec)
        if #commands == 0 then log.error("exec: Missing command to execute."); return 1; end
        local proc = M.exec_async({
            command = table.concat(commands, " "),
            show_mode = options.hide and 0 or 1,
            desktop = options.desktop,
            working_dir = options.workdir
        })
        if proc then
             if options.wait then
                proc:wait_for_exit_async(-1)
            end
            proc:close_handle()
            return 0
        end
        return 1
    end,
    kill = function(...)
        if #{ ... } == 0 then log.error("kill: Missing process name or PID."); return 1; end
        for _, target in ipairs({ ... }) do
            local p = M.find(target)
            if p then
                if not p:kill() then log.error("kill: Failed to terminate '", target, "'.") end
            else
                log.warn("kill: Process '", target, "' not found.")
            end
        end
        return 0
    end,
    killtree = function(...)
        if #{ ... } == 0 then log.error("killtree: Missing process name or PID."); return 1; end
        for _, target in ipairs({ ... }) do
            local p = M.find(target)
            if p then
                if not p:kill_tree() then log.error("killtree: Failed to terminate tree for '", target, "'.") end
            else
                log.warn("killtree: Process '", target, "' not found.")
            end
        end
        return 0
    end
}

return M