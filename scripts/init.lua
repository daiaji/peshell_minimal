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
    -- 在 main 模式下，不应该轻易退出，但这里是个致命错误
    return
end

-- 构造 wpeinit.exe 的完整路径
local wpeinit_cmd = windir .. "\\System32\\wpeinit.exe"
log.debug("wpeinit command line: ", wpeinit_cmd)

-- 执行 wpeinit.exe 并同步等待它完成。
-- 硬件初始化是后续步骤的基础，所以必须等待。
local wpeinit_proc = process.exec_async({ command = wpeinit_cmd, wait = true })

if wpeinit_proc then
    log.info("wpeinit.exe finished.")
else
    log.warn("Failed to start or wait for wpeinit.exe. Hardware may not function correctly.")
end


-- ------------------------------------------------------------------
-- 步骤 2: 初始化 PE 用户环境
-- ------------------------------------------------------------------
log.info("Step 2: Initializing PE user session environment (creating folders)...")
-- 这个函数会创建 Desktop, Start Menu 等一系列必要的文件夹
pe.initialize()
log.info("PE user environment initialized.")


-- ------------------------------------------------------------------
-- 步骤 3: 启动并守护系统外壳 (explorer.exe)
-- ------------------------------------------------------------------
log.info("Step 3: Locking system shell (explorer.exe)...")
local explorer_path = windir .. "\\explorer.exe"

-- 调用 lock_shell。
-- 这个函数会创建一个后台协程来持续监控 explorer.exe，
-- 然后函数自身会立即返回，不会阻塞当前脚本。
shell.lock_shell(explorer_path)

log.info("Shell guardian has been dispatched to the background.")
log.info("Initialization script has completed its tasks. The C++ host will now remain active in guardian mode.")

-- 此脚本到这里就结束了。
-- 但是，由 shell.lock_shell() 创建的后台协程会继续运行，
-- 并且 C++ 宿主的 "persistent message loop" 会确保整个 peshell.exe 进程的存活。
