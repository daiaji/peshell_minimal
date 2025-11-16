-- scripts/pesh-api/process.lua (v6.4 - Added True Async Wait)
local M = {}
local ffi = require("pesh-api.ffi")
local log = require("pesh-api.log")
local path = require("pl.path")
local native = _G.pesh_native
local shell32 = require("pesh-api.winapi.shell32")

local C = ffi.C
local proc_utils = ffi.proc_utils

-- ########## Process Object Metatable ##########
local process_metatable = { __index = {} }

function process_metatable.__index:kill()
    log.info("Attempting to kill process with PID: ", self.pid)
    return proc_utils.ProcUtils_ProcessClose(ffi.to_wide(tostring(self.pid)), 0)
end

function process_metatable.__index:kill_tree()
    log.info("Attempting to kill process tree starting with PID: ", self.pid)
    return proc_utils.ProcUtils_ProcessCloseTree(ffi.to_wide(tostring(self.pid)))
end

function process_metatable.__index:wait_for_exit_async(co)
    if not self.handle or self.handle.h == nil then
        error("Cannot wait for process " .. tostring(self.pid) .. ": handle is nil", 2)
    end
    local handle_obj_shell = ffi.new("SafeHandle_t", { h = self.handle.h })
    native.wait_for_multiple_objects(co, { handle_obj_shell })
end

function process_metatable.__index:wait_for_exit_blocking(timeout_ms)
    if not self.handle or self.handle.h == nil then
        log.error("Cannot wait for process (blocking) " .. tostring(self.pid) .. ": handle is nil")
        return false, "handle is nil"
    end
    timeout_ms = timeout_ms or -1
    local handle_obj_shell = ffi.new("SafeHandle_t", { h = self.handle.h })
    local signaled_index, err = native.wait_for_multiple_objects_blocking({ handle_obj_shell }, timeout_ms)
    if signaled_index == 1 then
        return true
    end
    return false, err
end


function process_metatable.__index:close_handle()
    if self.handle and self.handle.h ~= nil then
        log.trace("Explicitly closing handle for PID ", self.pid)
        C.CloseHandle(self.handle.h)
        self.handle.h = nil
    end
end

-- ########## Module-level Functions ##########

---
-- [新增] 以异步方式等待一个进程结束。
-- 专用于与全局 await 函数配合使用。
-- @param co coroutine: 由 await 传入的当前协程。
-- @param process_obj table: 由本模块创建的进程对象。
function M.wait_for_exit(co, process_obj)
    if not process_obj or not process_obj.handle or not process_obj.handle.h then
        -- C++ worker 会处理无效句柄，并立即唤醒协程报告错误
        log.warn("Dispatching wait worker with an invalid process object for PID ", tostring(process_obj and process_obj.pid))
    end
    log.debug("Dispatching worker to wait for PID ", process_obj and process_obj.pid or "N/A")
    -- 传递 handle cdata 本身
    native.dispatch_worker("process_wait_worker", process_obj.handle, co)
end

function M.get_self_path()
    local buf = ffi.new("wchar_t[?]", 260)
    if C.GetModuleFileNameW(nil, buf, 260) > 0 then
        return ffi.from_wide(buf)
    end
    return nil
end

function M.get_current_pid()
    return C.GetCurrentProcessId()
end

function M.find_all(name)
    local name_w = ffi.to_wide(tostring(name))
    local count = proc_utils.ProcUtils_FindAllProcesses(name_w, nil, 0)
    if count <= 0 then return {} end

    local pids_buf = ffi.new("unsigned int[?]", count)
    local found = proc_utils.ProcUtils_FindAllProcesses(name_w, pids_buf, count)
    if found <= 0 then return {} end

    local result = {}
    for i = 0, found - 1 do
        table.insert(result, pids_buf[i])
    end
    return result
end

function M.kill_all_by_name(process_name)
    log.warn("Attempting to kill all existing processes named '", process_name, "'...")
    local pids = M.find_all(process_name)
    if not pids or #pids == 0 then
        log.info("No existing '", process_name, "' processes found to kill.")
        return true
    end
    local all_killed = true
    for _, pid in ipairs(pids) do
        log.debug("  -> Terminating PID: ", pid)
        if not proc_utils.ProcUtils_ProcessClose(ffi.to_wide(tostring(pid)), 0) then
            log.warn("    -> Failed to terminate PID: ", pid, " (process may have already exited).")
            all_killed = false
        end
    end
    return all_killed
end

function M.get_process_name_from_command(full_command)
    local parts = shell32.commandline_to_argv(full_command)
    if not parts or #parts == 0 then return nil end
    return path.basename(parts[1])
end

function M.open_by_name(process_name)
    local desired_access = 0x00100000 -- SYNCHRONIZE
    local handle_ptr = proc_utils.ProcUtils_OpenProcessByName(ffi.to_wide(process_name), desired_access)
    if handle_ptr == nil then return nil end
    
    local pid = C.GetProcessId(handle_ptr)
    if pid == 0 then
        C.CloseHandle(handle_ptr)
        return nil
    end

    local process_obj = { pid = pid, handle = ffi.ProcessHandle(handle_ptr) }
    setmetatable(process_obj, process_metatable)
    return process_obj
end

function M.find(name_or_pid)
    local pid = proc_utils.ProcUtils_ProcessExists(ffi.to_wide(tostring(name_or_pid)))
    if pid == 0 then return nil end
    local process_obj = { pid = pid, handle = nil }
    setmetatable(process_obj, process_metatable)
    return process_obj
end

function M.exec_async(params)
    local result = proc_utils.ProcUtils_CreateProcess(
        ffi.to_wide(params.command), ffi.to_wide(params.working_dir),
        params.show_mode or 1, ffi.to_wide(params.desktop)
    )
    if result.pid > 0 then
        log.info("Process started successfully with PID: ", result.pid)
        local process_obj = { pid = result.pid, handle = ffi.ProcessHandle(result.process_handle) }
        setmetatable(process_obj, process_metatable)
        return process_obj
    end
    local err_msg = "Failed to execute command: '" .. params.command .. 
                    "'. Win32 Error: " .. result.last_error_code
    log.error(err_msg)
    return nil, err_msg
end

M.__commands = {
    exec = function(args)
        local wait_for_exit = false
        local hide_window = false
        local cmd_parts = {}
        for _, part in ipairs(args.cmd) do
            if part == "-w" then wait_for_exit = true
            elseif part == "-h" then hide_window = true
            else table.insert(cmd_parts, part)
            end
        end

        if #cmd_parts == 0 then
            log.error("exec: Missing command to execute."); return 1;
        end
        
        local proc, err = M.exec_async({
            command = table.concat(cmd_parts, " "),
            show_mode = hide_window and 0 or 1,
        })

        if proc then
            if wait_for_exit then
                local exited, wait_err = proc:wait_for_exit_blocking()
                if not exited then log.error("exec: Wait failed: ", tostring(wait_err)) end
            end
            proc:close_handle()
            return 0
        end
        return 1
    end,
    kill = function(args)
        local targets = args.cmd
        if not targets or #targets == 0 then log.error("kill: Missing process name or PID."); return 1; end
        local all_ok = true
        for _, target in ipairs(targets) do
            local p = M.find(target)
            if p then
                if not p:kill() then 
                    log.error("kill: Failed to terminate '", target, "'.")
                    all_ok = false
                end
            else
                log.warn("kill: Process '", target, "' not found.")
            end
        end
        return all_ok and 0 or 1
    end,
    killtree = function(args)
        local targets = args.cmd
        if not targets or #targets == 0 then log.error("killtree: Missing process name or PID."); return 1; end
        local all_ok = true
        for _, target in ipairs(targets) do
            local p = M.find(target)
            if p then
                if not p:kill_tree() then
                    log.error("killtree: Failed to terminate tree for '", target, "'.")
                    all_ok = false
                end
            else
                log.warn("killtree: Process '", target, "' not found.")
            end
        end
        return all_ok and 0 or 1
    end
}

return M