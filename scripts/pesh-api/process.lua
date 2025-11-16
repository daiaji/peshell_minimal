-- scripts/pesh-api/process.lua
-- 封装 proc_utils 库，提供面向对象的进程管理 API (重构并修正 v3)

local M = {}
local native = pesh_native
local log = require("pesh-api.log")
local argparse = require("pesh-api.argparse")

-- ########## Process Object Metatable ##########
local process_metatable = { __index = {} }

--- 强制终止进程
function process_metatable.__index:kill()
    log.info("Attempting to kill process with PID: ", self.pid)
    return native.process_close(tostring(self.pid), 0)
end

--- 强制终止进程及其所有子进程
function process_metatable.__index:kill_tree()
    log.info("Attempting to kill process tree starting with PID: ", self.pid)
    return native.process_close_tree(tostring(self.pid))
end

--- 异步等待进程结束 (基于句柄)
function process_metatable.__index:wait_for_exit_async(timeout_ms)
    timeout_ms = timeout_ms or -1
    log.debug("Waiting on handle for process PID ", self.pid, " to exit with timeout ", timeout_ms, "ms.")
    
    if not self.handle then
        log.error("Cannot wait for process ", self.pid, ": handle is nil.")
        return false
    end
    
    local signaled_index, err = native.wait_for_multiple_objects({ self.handle }, timeout_ms)
    if signaled_index == 1 then
        return true -- 成功等到进程退出
    else
        log.warn("Wait for process ", self.pid, " failed or timed out. Reason: ", tostring(err))
        return false -- 等待超时或失败
    end
end


--- 显式关闭进程句柄 (良好实践)
function process_metatable.__index:close_handle()
    if self.handle then
        log.trace("Explicitly closing handle for PID ", self.pid)
        native.close_handle(self.handle)
        self.handle = nil -- 防止重复使用已关闭的句柄
    end
end

-- ########## Module-level Functions ##########

---
-- 根据进程名打开一个已存在的进程，并返回一个包含句柄的进程对象
-- @param process_name string: 目标进程的可执行文件名 (e.g., "explorer.exe")
-- @return table|nil: 成功则返回进程对象，否则返回 nil
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

--- 根据进程名或PID查找一个正在运行的进程 (返回的进程对象不含句柄)
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

--- 异步执行一个外部程序
function M.exec_async(params)
    if not params or not params.command then
        log.error("exec_async failed: 'command' parameter is missing.")
        return nil
    end

    log.info("Executing command via create_process: '", params.command, "'")
    local result = native.create_process(
        params.command,
        params.working_dir or nil,
        params.show_mode or 1, -- 1 = SW_SHOWNORMAL
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

---
-- @description (新) 使用 Windows API 解析一个完整的命令行字符串。
-- @param cmd_string string: 完整的命令行, e.g., "ping.exe -t localhost"
-- @return table|nil: 一个包含可执行文件和参数的 table, e.g., { "C:\\Windows\\...\\ping.exe", "-t", "localhost" }
function M.parse_command_line(cmd_string)
    log.trace("Parsing command line: '", cmd_string, "'")
    local parts = native.commandline_to_argv(cmd_string)
    if not parts or #parts == 0 then
        log.warn("Failed to parse command line.")
        return nil
    end

    -- 进一步处理：找到可执行文件的完整路径
    local executable_path = native.search_path(parts[1])
    if executable_path then
        parts[1] = executable_path
    else
        -- 如果 SearchPath 失败，可能是因为路径中包含了引号，需要去掉
        local cleaned_exe = parts[1]:gsub('^"(.*)"$', '%1')
        executable_path = native.search_path(cleaned_exe)
        if executable_path then
            parts[1] = executable_path
        end
    end

    return parts
end


-- ########## Subcommand Definitions ##########
M.__commands = {
    exec = function(...)
        local spec = {
            { "wait",    "w", "boolean", "Wait for the process to exit." },
            { "hide",    "h", "boolean", "Execute the process in a hidden window." },
            { "desktop", "d", "string",  "Specify the target desktop (e.g., WinSta0\\Winlogon)." },
            { "workdir", nil, "string",  "Set the working directory for the process." }
        }
        local options, commands = argparse.parse({ ... }, spec)
        if #commands == 0 then
            log.error("exec: Missing command to execute.")
            return
        end

        local proc = M.exec_async({
            command = table.concat(commands, " "),
            show_mode = options.hide and 0 or 1,
            desktop = options.desktop,
            working_dir = options.workdir
        })

        if proc and options.wait then
            proc:wait_for_exit_async(-1)
            proc:close_handle()
        end
    end,

    kill = function(...)
        if #{ ... } == 0 then log.error("kill: Missing process name or PID."); return 1; end
        local all_ok = true
        for _, target in ipairs({ ... }) do
            -- [修正] 这里应该用 open_by_name 来获取句柄，以便能够终止它
            local p = M.open_by_name(target)
            
            if p then
                if not p:kill() then 
                    log.error("kill: Failed to terminate '", target, "'.")
                    all_ok = false
                end
                p:close_handle()
            else
                log.warn("kill: Process '", target, "' not found or could not be opened.")
                all_ok = false
            end
        end
        return all_ok and 0 or 1
    end,
    
    killtree = function(...)
        if #{ ... } == 0 then log.error("killtree: Missing process name or PID."); return 1; end
        local all_ok = true
        for _, target in ipairs({ ... }) do
            local p = M.find(target)
            if p then
                if not p:kill_tree() then 
                    log.error("killtree: Failed to terminate tree for '", target, "'.") 
                    all_ok = false
                end
            else
                log.warn("killtree: Process '", target, "' not found.")
                all_ok = false
            end
        end
        return all_ok and 0 or 1
    end
}

return M