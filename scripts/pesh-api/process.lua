-- scripts/pesh-api/process.lua
-- 封装 proc_utils 库，提供面向对象的进程管理 API (重构版)

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

--- [重构核心] 异步等待进程结束 (现在基于句柄)
function process_metatable.__index:wait_for_exit_async(timeout_ms)
    timeout_ms = timeout_ms or -1
    log.debug("Waiting on handle for process PID ", self.pid, " to exit with timeout ", timeout_ms, "ms.")
    
    if not self.handle then
        log.error("Cannot wait for process ", self.pid, ": handle is nil. Falling back to polling (less efficient).")
        return native.process_wait_close(tostring(self.pid), timeout_ms)
    end
    
    -- 调用新的、基于句柄的、带消息循环的等待函数
    return native.wait_for_handle(self.handle, timeout_ms)
end

--- [新增] 显式关闭进程句柄 (良好实践)
function process_metatable.__index:close_handle()
    if self.handle then
        log.trace("Explicitly closing handle for PID ", self.pid)
        native.close_handle(self.handle)
        self.handle = nil -- 防止重复使用已关闭的句柄
    end
end

-- ########## Module-level Functions ##########

--- 根据进程名或PID查找一个正在运行的进程 (返回的进程对象不含句柄)
function M.find(name_or_pid)
    log.trace("Finding process: '", tostring(name_or_pid), "'")
    local pid = native.process_exists(tostring(name_or_pid))
    if pid == 0 then
        log.trace("Process '", tostring(name_or_pid), "' not found.")
        return nil
    end

    log.trace("Process '", tostring(name_or_pid), "' found with PID: ", pid)
    -- 注意：通过 find 创建的对象没有句柄，因此不能使用 wait_for_exit_async 的句柄版本
    local process_obj = { pid = pid, handle = nil }
    setmetatable(process_obj, process_metatable)
    return process_obj
end

--- [重构核心] 异步执行一个外部程序
function M.exec_async(params)
    if not params or not params.command then
        log.error("exec_async failed: 'command' parameter is missing.")
        return nil
    end

    log.info("Executing command via create_process: '", params.command, "'")
    -- 调用新的 create_process 绑定，它返回一个包含 pid 和 handle 的表
    local result = native.create_process(
        params.command,
        params.working_dir or nil,
        params.show_mode or 1, -- 1 = SW_SHOWNORMAL
        params.desktop or nil
    )

    if result and result.pid > 0 then
        log.info("Process started successfully with PID: ", result.pid, " and Handle: ", tostring(result.handle))
        -- 创建进程对象，现在它同时拥有 pid 和 handle
        local process_obj = { pid = result.pid, handle = result.handle }
        setmetatable(process_obj, process_metatable)
        
        -- 不再需要任何 sleep！函数返回时，进程已完全创建并可被操作。
        return process_obj
    end

    log.error("Failed to execute command: '", params.command, "'")
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
        if #{ ... } == 0 then log.error("kill: Missing process name or PID."); return; end
        for _, target in ipairs({ ... }) do
            local p = M.find(target)
            if p then
                if not p:kill() then log.error("kill: Failed to terminate '", target, "'.") end
            else
                log.warn("kill: Process '", target, "' not found.")
            end
        end
    end,
    
    killtree = function(...)
        if #{ ... } == 0 then log.error("killtree: Missing process name or PID."); return; end
        for _, target in ipairs({ ... }) do
            local p = M.find(target)
            if p then
                if not p:kill_tree() then log.error("killtree: Failed to terminate tree for '", target, "'.") end
            else
                log.warn("killtree: Process '", target, "' not found.")
            end
        end
    end
}

return M