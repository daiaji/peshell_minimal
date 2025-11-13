-- pesh-api/process.lua
-- 封装 proc_utils 库，提供面向对象的进程管理 API

local M = {}
local native = pesh_native
local async = require("pesh-api.async")
local log = require("pesh-api.log")

local process_metatable = { __index = {} }

--[[
@description 强制终止进程。
@return boolean: 成功返回 true，否则返回 false。
]]
function process_metatable.__index:kill()
    log.info("Attempting to kill process with PID: ", self.pid)
    local result = native.process_close(tostring(self.pid), 0)
    if result then
        log.info("Successfully sent kill signal to PID: ", self.pid)
    else
        log.error("Failed to kill process with PID: ", self.pid)
    end
    return result
end

--[[
@description 异步等待进程结束。
@param timeout_ms number: 等待的毫秒数，-1 表示无限等待。
@return boolean: 进程在超时前结束返回 true，否则返回 false。
]]
function process_metatable.__index:wait_for_exit_async(timeout_ms)
    timeout_ms = timeout_ms or -1
    log.debug("Waiting for process PID ", self.pid, " to exit with timeout ", timeout_ms, "ms.")
    return native.process_wait_close(tostring(self.pid), timeout_ms)
end

--[[
@description 根据进程名或PID查找一个正在运行的进程。
@param name_or_pid string|number: 进程的名称 (如 "explorer.exe") 或 PID。
@return table|nil: 如果找到，返回一个进程对象；否则返回 nil。
]]
function M.find(name_or_pid)
    log.trace("Finding process: '", tostring(name_or_pid), "'")
    local pid = native.process_exists(tostring(name_or_pid))
    if pid == 0 then
        log.trace("Process '", tostring(name_or_pid), "' not found.")
        return nil
    end

    log.trace("Process '", tostring(name_or_pid), "' found with PID: ", pid)
    local process_obj = {
        pid = pid,
    }
    setmetatable(process_obj, process_metatable)
    return process_obj
end

--[[
@description 异步执行一个外部程序。
@param params table: 包含执行参数的表。
    - command (string): 必须，要执行的完整命令行。
    - working_dir (string): 可选，程序的工作目录。
    - show_mode (number): 可选，窗口显示模式 (如 0=SW_HIDE, 1=SW_SHOWNORMAL)。
    - desktop (string): 可选，目标桌面 (如 "WinSta0\\Winlogon")。
@return table|nil: 成功启动返回一个进程对象，否则返回 nil。
]]
function M.exec_async(params)
    if not params or not params.command then
        log.error("exec_async failed: 'command' parameter is missing.")
        return nil
    end

    log.info("Executing command: '", params.command, "'")
    local pid = native.exec(
        params.command,
        params.working_dir or nil,
        params.show_mode or 1, -- 默认为 SW_SHOWNORMAL
        false,                 -- exec_async 永远是非阻塞的
        params.desktop or nil
    )

    if pid and pid > 0 then
        log.info("Process started successfully with PID: ", pid)
        -- 等待一小段时间，确保操作系统已经完全创建了进程对象
        async.sleep_async(200)
        return M.find(pid)
    end

    log.error("Failed to execute command: '", params.command, "'")
    return nil
end

return M