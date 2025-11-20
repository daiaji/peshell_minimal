-- scripts/plugins/process/init.lua
-- Process 插件 (v5.2 - With Message Pumping Wait)

local pesh = _G.pesh
local M = {}

-- 1. 依赖
local log = _G.log
local ffi = pesh.ffi
local native = _G.pesh_native
local path = require("pl.path")
local kernel32 = pesh.plugin.load("winapi.kernel32")

-- 2. 加载纯 Lua FFI 库
local status, proc = pcall(require, "proc_utils_ffi")
if not status then
    error("CRITICAL: Failed to load 'proc_utils_ffi'. Error: " .. tostring(proc))
end

-- 3. 定义非拥有型句柄结构
ffi.define("process_plugin_non_owning_handle", [[
    typedef struct { void* h; } NonOwningHandle_t;
]])

local non_owning_mt = {} 
local NonOwningHandle = ffi.metatype("NonOwningHandle_t", non_owning_mt)

---
-- 获取用于 C++ 异步等待的句柄包装
-- @param process_obj table: proc_utils 的 Process 对象
function M.get_waitable_handle(process_obj)
    if not process_obj then return nil end
    -- proc_utils 对象有 :handle() 方法返回 cdata<HANDLE>
    local raw_h = process_obj:handle()
    if not raw_h then return nil end
    return NonOwningHandle(raw_h)
end

-- ============================================================
-- 核心 API 实现 (适配 proc_utils)
-- ============================================================

function M.exec_async(params)
    local command = params.command
    local workdir = params.working_dir
    -- 映射 show_mode: 0 -> SW_HIDE, 1 -> SW_SHOWNORMAL
    local show_mode = params.show_mode or proc.constants.SW_SHOWNORMAL
    
    -- 调用 proc_utils 工厂
    local p_obj, err_code, err_msg = proc.exec(command, workdir, show_mode)
    
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
    -- proc.exists 返回 PID 或 0
    local pid = proc.exists(name_or_pid)
    if pid == 0 then return nil end
    
    -- 打开进程获取对象
    local p_obj, err, msg = proc.open_by_pid(pid)
    if not p_obj then
        log.warn("Process exists (PID:", pid, ") but could not open handle: ", msg)
        return nil
    end
    return p_obj
end

function M.find_all(name)
    local pids = proc.find_all(name)
    return pids or {} 
end

function M.kill_all_by_name(process_name)
    log.warn("Killing all processes named '", process_name, "'...")
    local pids = M.find_all(process_name)
    if not pids or #pids == 0 then 
        log.info("No processes found to kill.")
        return true 
    end
    
    local all_ok = true
    for _, pid in ipairs(pids) do
        if not proc.terminate_by_pid(pid, 0) then
            log.warn("Failed to terminate PID: ", pid)
            all_ok = false
        end
    end
    return all_ok
end

---
-- [异步] 等待进程退出 (供 await 使用)
-- 使用 C++ 线程池，不阻塞 Lua VM，但也不泵送消息（因为是在后台线程等待）
-- @param co coroutine: 当前协程
-- @param process_obj table: proc_utils 对象
function M.wait_for_exit(co, process_obj)
    if not process_obj then error("wait_for_exit called with nil process object") end
    local waitable = M.get_waitable_handle(process_obj)
    if not waitable then
        log.warn("wait_for_exit: Process object has no valid handle.")
    end
    native.dispatch_worker("process_wait_worker", waitable, co)
end

---
-- [同步] 带消息泵的等待 (UI Friendly Blocking Wait)
-- 专用于 init.lua 等主线程脚本，防止在等待时界面冻结。
-- @param process_obj table: proc_utils 对象
-- @param timeout_ms number: 超时毫秒数，-1 为无限
-- @return boolean: true 表示进程已退出，false 表示超时
function M.wait_for_exit_pump(process_obj, timeout_ms)
    if not process_obj or not process_obj.wait_for_exit then 
        log.error("wait_for_exit_pump: Invalid process object.")
        return false 
    end

    timeout_ms = timeout_ms or -1
    local start_tick = kernel32.GetTickCount()
    
    while true do
        -- 1. 非阻塞检查进程状态 (传入 0 表示立即返回)
        -- proc_utils_ffi 的 wait_for_exit 封装了 WaitForSingleObject
        if process_obj:wait_for_exit(0) then
            return true
        end
        
        -- 2. 检查超时
        if timeout_ms >= 0 then
            local current_tick = kernel32.GetTickCount()
            -- 处理 GetTickCount 溢出 (49.7天) 的简单回绕逻辑
            local elapsed = current_tick - start_tick
            if elapsed > timeout_ms then
                return false
            end
        end
        
        -- 3. 睡眠并泵送消息
        -- native.sleep 内部使用 MsgWaitForMultipleObjects，保证 UI 不卡死
        native.sleep(50)
    end
end

-- ============================================================
-- 辅助函数
-- ============================================================

function M.get_self_path()
    local buf = ffi.new("wchar_t[?]", 260)
    if kernel32.GetModuleFileNameW(nil, buf, 260) > 0 then
        return ffi.from_wide(buf)
    end
    return nil
end

function M.get_process_name_from_command(full_command)
    local shell32_plugin = pesh.plugin.load("winapi.shell32")
    local parts = shell32_plugin.commandline_to_argv(full_command)
    if not parts or #parts == 0 then return nil end
    return path.basename(parts[1])
end

function M.get_current_pid()
    return kernel32.GetCurrentProcessId()
end

function M.open_by_name(name)
    return proc.open_by_name(name)
end

-- ============================================================
-- 命令导出 (CLI)
-- ============================================================
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
        if #cmd_parts == 0 then log.error("exec: Missing command."); return 1; end
        
        local cmd_line = table.concat(cmd_parts, " ")
        local show_val = hide_window and proc.constants.SW_HIDE or proc.constants.SW_SHOWNORMAL
        
        local p_obj = M.exec_async({ command = cmd_line, show_mode = show_val })
        
        if p_obj then
            if wait_for_exit then
                -- CLI 模式下也建议使用带泵的等待
                M.wait_for_exit_pump(p_obj, -1)
            end
            return 0
        end
        return 1
    end,
    
    kill = function(args)
        local targets = args.cmd
        if not targets or #targets == 0 then return 1 end
        local all_ok = true
        for _, target in ipairs(targets) do
            local pid = tonumber(target)
            if pid then
                if not proc.terminate_by_pid(pid, 0) then all_ok = false end
            else
                if not M.kill_all_by_name(target) then all_ok = false end
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