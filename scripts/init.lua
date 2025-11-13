-- 引入我们的 API 模块
local process = require("pesh-api.process")
local pe = require("pesh-api.pe")
local shell = require("pesh-api.shell")

-- 控制台输出编码设置，确保中文能正确显示
os.execute("chcp 65001 > nul")
print("PEShell v3.0 Initializer Started.")

-- 1. 执行 wpeinit.exe (用于硬件初始化和网络启动)
print("Step 1: Running wpeinit for hardware initialization...")
local windir = os.getenv("WinDir")
if not windir then
    print("Error: Could not get %WinDir% environment variable.")
    return
end
local wpeinit_cmd = windir .. "\\System32\\wpeinit.exe"

local wpeinit_proc = process.exec_async({ command = wpeinit_cmd })

if wpeinit_proc then
    print("Waiting for wpeinit.exe to complete (PID: " .. wpeinit_proc.pid .. ")...")
    -- 等待 wpeinit 进程结束
    local success = wpeinit_proc:wait_for_exit_async(-1) -- -1 表示无限等待
    if success then
        print("wpeinit.exe finished.")
    else
        print("Warning: Timed out or failed while waiting for wpeinit.exe to exit.")
    end
else
    print("Warning: Failed to start wpeinit.exe. Hardware may not function correctly.")
end

-- 2. 初始化用户环境 (创建文件夹等)
print("Step 2: Initializing PE user session environment...")
pe.initialize()

-- 3. 加载并锁定系统外壳 (explorer.exe)
print("Step 3: Locking system shell (explorer.exe)...")
local explorer_path = windir .. "\\explorer.exe"
shell.lock_shell(explorer_path)

-- shell.lock_shell 是一个无限循环，所以脚本会在这里“驻留”以守护桌面
print("Initialization logic complete. PEShell is now in monitoring mode.")