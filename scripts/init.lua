-- scripts/init.lua
-- PEShell PE 初始化主脚本
-- 职责：协调所有必要的初始化步骤，启动并守护桌面环境。

-- 引入所有需要的 API 模块
local log = require("pesh-api.log")
local process = require("pesh-api.process")
local pe = require("pesh-api.pe")
local shell = require("pesh-api.shell")

-- 设置控制台输出为 UTF-8，以正确显示日志
os.execute("chcp 65001 > nul")
log.info("PEShell v3.1 Initializer Script Started.")

-- ------------------------------------------------------------------
-- 步骤 1: 执行 wpeinit.exe (硬件初始化)
-- ------------------------------------------------------------------
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
    -- [[ 核心修正 ]]
    -- 在同步脚本中，必须使用阻塞式等待，以确保任务按顺序执行。
    -- -1 表示无限期等待，直到进程退出。
    wpeinit_proc:wait_for_exit_blocking(-1)
    wpeinit_proc:close_handle()
    log.info("wpeinit.exe finished.")
else
    log.warn("Failed to start or wait for wpeinit.exe. Hardware may not function correctly.")
end


-- ------------------------------------------------------------------
-- 步骤 2: 初始化 PE 用户环境
-- ------------------------------------------------------------------
log.info("Step 2: Initializing PE user session environment (creating folders)...")
pe.initialize()
log.info("PE user environment initialized.")


-- ------------------------------------------------------------------
-- 步骤 3: 启动并守护系统外壳 (explorer.exe)
-- ------------------------------------------------------------------
log.info("Step 3: Locking system shell (explorer.exe)...")
local explorer_path = windir .. "\\explorer.exe"

-- 调用 lock_shell。
-- 它将自动使用默认的 "takeover" 策略：先杀死所有现有的 explorer.exe，
-- 然后再启动一个新的实例进行守护，确保环境干净。
shell.lock_shell(explorer_path)

log.info("Shell guardian has been dispatched to the background.")
log.info("Initialization script has completed its tasks. The C++ host will now remain active in guardian mode.")