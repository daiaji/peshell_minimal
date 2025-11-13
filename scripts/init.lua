-- 引入 API 模块，首先引入日志模块
local log = require("pesh-api.log")

local process = require("pesh-api.process")
local pe = require("pesh-api.pe")
local shell = require("pesh-api.shell")

-- 控制台输出编码设置
os.execute("chcp 65001 > nul")
log.info("PEShell v3.0 Initializer Started.")

-- 1. 执行 wpeinit.exe (用于硬件初始化和网络启动)
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
    log.info("Waiting for wpeinit.exe to complete (PID:", wpeinit_proc.pid, ")...")
    local success = wpeinit_proc:wait_for_exit_async(-1)
    if success then
        log.info("wpeinit.exe finished.")
    else
        log.warn("Timed out or failed while waiting for wpeinit.exe to exit.")
    end
else
    log.warn("Failed to start wpeinit.exe. Hardware may not function correctly.")
end

-- 2. 初始化用户环境 (创建文件夹等)
log.info("Step 2: Initializing PE user session environment...")
pe.initialize()

-- 3. 加载并锁定系统外壳 (explorer.exe)
log.info("Step 3: Locking system shell (explorer.exe)...")
local explorer_path = windir .. "\\explorer.exe"
shell.lock_shell(explorer_path)

log.info("Initialization logic complete. PEShell is now in monitoring mode.")