-- scripts/init.lua
-- PEShell PE 初始化主脚本 (适配插件系统 & Native ProcUtils)

-- prelude.lua has already loaded the core `pesh` object and `log`
local log = _G.log
local pesh = _G.pesh

-- 1. Explicitly load the plugins this script depends on
local process = pesh.plugin.load("process")
local pe = pesh.plugin.load("pe")
local shell = pesh.plugin.load("shell")

-- 2. Generate a unique call ID for tracing this specific run
local unique_call_id = string.format("call-%d-%d", os.time(), math.random(10000, 99999))
log.info("INIT.LUA: Starting initialization sequence with Unique Call ID: [", unique_call_id, "]")

-- 3. Set console output to UTF-8
os.execute("chcp 65001 > nul")
log.info("PEShell v6.1 Initializer Script Started.")

-- 4. Step 1: Execute wpeinit.exe (Hardware Initialization)
log.info("Step 1: Running wpeinit for hardware initialization...")
local windir = os.getenv("WinDir")
if not windir then
    log.critical("Could not get %WinDir% environment variable. Aborting.")
    return
end

local wpeinit_cmd = windir .. "\\System32\\wpeinit.exe"
log.debug("wpeinit command line: ", wpeinit_cmd)

local wpeinit_proc = process.exec_async({ command = wpeinit_cmd })
if wpeinit_proc then
    log.info("wpeinit.exe started, waiting for it to finish...")
    
    -- [FIX] 使用新 API wait_for_exit 代替 wait_for_exit_blocking
    -- -1 表示无限等待
    wpeinit_proc:wait_for_exit(-1)
    
    -- [FIX] 移除 close_handle 调用
    -- 新的 proc_utils_ffi 基于 FFI GC 自动管理句柄 (RAII)。
    -- 显式将其置为 nil 有助于让垃圾回收器更快回收句柄，但不是必须的。
    wpeinit_proc = nil 
    
    log.info("wpeinit.exe finished.")
else
    log.warn("Failed to start or wait for wpeinit.exe. Hardware may not function correctly.")
end

-- 5. Step 2: Initialize PE User Environment
log.info("Step 2: Initializing PE user session environment (creating folders)...")
pe.initialize()
log.info("PE user environment initialized.")

-- 6. Step 3: Start and guard the system shell (explorer.exe)
log.info("Step 3: Locking system shell (explorer.exe)...")
local explorer_path = windir .. "\\explorer.exe"

log.info("INIT.LUA: Invoking shell.lock_shell with Unique Call ID: [", unique_call_id, "]")
shell.lock_shell(explorer_path, {
    strategy = "takeover", 
    unique_call_id = unique_call_id
})

log.info("Shell guardian has been dispatched to the background.")
log.info("Initialization script has completed its tasks. The C++ host will now remain active in guardian mode.")