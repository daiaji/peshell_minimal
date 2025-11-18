-- scripts/plugins/process/init.lua
-- Process 插件 (v3.0 - Pure FFI based on proc_utils_ffi)

local pesh = _G.pesh
local M = {}

-- 1. 依赖
local log = _G.log
local ffi = pesh.ffi
local native = _G.pesh_native
local path = require("pl.path")
local kernel32 = pesh.plugin.load("winapi.kernel32")

-- [NEW] 加载纯 Lua FFI 库 (位于 share/lua/5.1/lib)
local status, proc = pcall(require, "proc_utils_ffi")
if not status then
    error("CRITICAL: Failed to load 'proc_utils_ffi'. Ensure it is in the library path. Error: " .. tostring(proc))
end

-- 2. 适配层

-- 内部辅助：获取底层的 cdata<HANDLE>
local function get_raw_handle(process_obj)
    if not process_obj then return nil end
    -- proc_utils v3 OOP: process:handle() 返回 cdata<HANDLE>
    return process_obj:handle() 
end

---
-- 将 OOP 进程对象适配为 peshell 插件期望的接口
-- (例如注入兼容旧代码的方法)
local function augment_process_object(p_obj)
    if not p_obj then return nil end

    -- 注入 wait_for_exit_blocking 以兼容旧代码
    p_obj.wait_for_exit_blocking = function(self, timeout_ms)
        timeout_ms = timeout_ms or -1
        return self:wait_for_exit(timeout_ms)
    end

    -- 注入 close_handle 以兼容旧代码 (虽然 proc_utils_ffi 是 RAII 自动管理的)
    p_obj.close_handle = function(self)
        -- proc_utils_ffi 依赖 __gc。这里不做任何操作。
        -- 如果非常必要显式释放，proc_utils_ffi 需要提供 invalidate 方法。
        -- 目前这里作为空操作，避免旧代码报错。
        log.trace("process:close_handle() called (No-op, managed by RAII).")
    end

    return p_obj
end

function M.exec_async(params)
    local command = params.command
    local workdir = params.working_dir
    local show_mode = params.show_mode -- proc_utils 支持 constants.SW_*
    
    -- 使用 proc.exec 工厂函数
    local p_obj, err_code, err_msg = proc.exec(command, workdir, show_mode)
    
    if not p_obj then
        local final_msg = string.format("Failed to execute '%s'. Error: %s (Code: %s)", 
            command, tostring(err_msg), tostring(err_code))
        log.error(final_msg)
        return nil, final_msg
    end

    log.info("Process started successfully. PID: ", p_obj.pid)
    return augment_process_object(p_obj)
end

function M.find(name_or_pid)
    -- proc.exists 返回 PID (number) 或 0
    local pid = proc.exists(name_or_pid)
    if pid == 0 then return nil end
    
    -- 打开进程获取对象
    local p_obj, err, msg = proc.open_by_pid(pid)
    if not p_obj then
        log.warn("Process exists (PID:", pid, ") but could not open handle: ", msg)
        return nil
    end
    
    return augment_process_object(p_obj)
end

function M.find_all(name)
    local pids, err = proc.find_all(name)
    if not pids then return {} end
    return pids -- 返回 {pid1, pid2, ...} table
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
-- 异步等待进程退出 (供 await 使用)
-- 需要将 FFI handle 转换为 C++ 可识别的 SafeHandle 结构
function M.wait_for_exit(co, process_obj)
    if not process_obj then
        error("wait_for_exit called with nil process object")
    end
    
    local raw_handle = get_raw_handle(process_obj)
    if not raw_handle then
        log.warn("wait_for_exit: Process object has no valid handle.")
        -- 可能会导致后续 C++ worker 报错
    end
    
    -- C++ 端 (main.cpp) 的 process_wait_worker 期望一个 SafeHandle*
    -- 即指向 struct { void* h; } 的指针。
    -- 我们需要在 Lua 端构造这个结构体。
    -- "core.safehandle" 在 core/ffi.lua 中被定义。
    -- 我们必须确保 ffi.lua 已经加载并定义了这个类型。
    -- peshell.ffi.ProcessHandle 就是这个类型的构造函数。
    
    local safe_h = ffi.ProcessHandle(raw_handle)
    
    -- 注意：这里传递给 C++ 的是 safe_h 这个 cdata。
    -- C++ 会取其指针，强转为 SafeHandle*，读取 .h 成员。
    -- 由于 dispatch_worker 是异步的，我们需要确保 safe_h 在任务完成前不被 GC。
    -- 但是 native.dispatch_worker 目前并未在 Lua 端建立锚点机制 (参见 ai_correction_guidelines)。
    -- 这是一个潜在的风险点。但在当前 peshell 实现中，dispatch_worker 立即将 handle 值
    -- 复制到 C++ lambda 中 (handle_obj->h)，所以是安全的。
    
    native.dispatch_worker("process_wait_worker", safe_h, co)
end

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

-- 兼容旧 API open_by_name
function M.open_by_name(process_name)
    local p_obj = proc.open_by_name(process_name)
    return augment_process_object(p_obj)
end

-- 兼容旧 API get_current_pid
function M.get_current_pid()
    return kernel32.GetCurrentProcessId()
end

-- 3. 导出命令
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
        local show_val = hide_window and 0 or 1 -- SW_HIDE=0
        
        local p_obj = M.exec_async({ command = cmd_line, show_mode = show_val })
        
        if p_obj then
            if wait_for_exit then
                -- 使用同步等待
                p_obj:wait_for_exit(-1)
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
            -- 尝试作为 PID
            local pid = tonumber(target)
            if pid then
                if not proc.terminate_by_pid(pid, 0) then all_ok = false end
            else
                -- 作为名称
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