-- pesh-api/process.lua
-- 封装 proc_utils 库，提供面向对象的进程管理 API (完整版)

local M = {}
local native = pesh_native
local async = require("pesh-api.async")
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

--- 异步等待进程结束
function process_metatable.__index:wait_for_exit_async(timeout_ms)
    timeout_ms = timeout_ms or -1
    log.debug("Waiting for process PID ", self.pid, " to exit with timeout ", timeout_ms, "ms.")
    return native.process_wait_close(tostring(self.pid), timeout_ms)
end

--- 获取进程的完整路径
function process_metatable.__index:get_path()
    return native.process_get_path(self.pid)
end

--- 获取父进程对象
function process_metatable.__index:get_parent()
    local parent_pid = native.process_get_parent(tostring(self.pid))
    if parent_pid and parent_pid > 0 then
        return M.find(parent_pid)
    end
    return nil
end

--- 设置进程优先级
function process_metatable.__index:set_priority(priority_char)
    return native.process_set_priority(tostring(self.pid), priority_char)
end

-- ########## Module-level Functions ##########

--- 根据进程名或PID查找一个正在运行的进程
function M.find(name_or_pid)
    log.trace("Finding process: '", tostring(name_or_pid), "'")
    local pid = native.process_exists(tostring(name_or_pid))
    if pid == 0 then
        log.trace("Process '", tostring(name_or_pid), "' not found.")
        return nil
    end

    log.trace("Process '", tostring(name_or_pid), "' found with PID: ", pid)
    local process_obj = { pid = pid }
    setmetatable(process_obj, process_metatable)
    return process_obj
end

--- 异步执行一个外部程序
function M.exec_async(params)
    if not params or not params.command then
        log.error("exec_async failed: 'command' parameter is missing.")
        return nil
    end

    log.info("Executing command: '", params.command, "'")
    local pid = native.exec(
        params.command,
        params.working_dir or nil,
        params.show_mode or 1,
        params.wait or false,
        params.desktop or nil
    )

    if pid and pid > 0 then
        log.info("Process started successfully with PID: ", pid)
        async.sleep_async(200) -- 短暂等待以确保系统完全创建进程对象
        return M.find(pid)
    end

    log.error("Failed to execute command: '", params.command, "'")
    return nil
end

--- 同步等待一个进程出现
function M.wait_for_process(process_name, timeout_ms)
    timeout_ms = timeout_ms or -1
    log.info("Waiting for process '", process_name, "' to appear...")
    local pid = native.process_wait(process_name, timeout_ms)
    if pid and pid > 0 then
        log.info("Process '", process_name, "' has appeared with PID: ", pid)
        return M.find(pid)
    end
    log.warn("Timed out waiting for process '", process_name, "'.")
    return nil
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
        M.exec_async({
            command = table.concat(commands, " "),
            wait = options.wait,
            show_mode = options.hide and 0 or 1,
            desktop = options.desktop,
            working_dir = options.workdir
        })
    end,

    kill = function(...)
        if #{ ... } == 0 then
            log.error("kill: Missing process name or PID.")
            return
        end
        for _, target in ipairs({ ... }) do
            local p = M.find(target)
            if p then
                if not p:kill() then log.error("kill: Failed to terminate process '", target, "'.") end
            else
                log.warn("kill: Process '", target, "' not found.")
            end
        end
    end,

    killtree = function(...)
        if #{ ... } == 0 then
            log.error("killtree: Missing process name or PID.")
            return
        end
        for _, target in ipairs({ ... }) do
            local p = M.find(target)
            if p then
                 if not p:kill_tree() then log.error("killtree: Failed to terminate process tree for '", target, "'.") end
            else
                log.warn("killtree: Process '", target, "' not found.")
            end
        end
    end
}

return M