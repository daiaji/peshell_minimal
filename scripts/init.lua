-- scripts/init.lua
-- PEShell PE 初始化主脚本 (Lua-Ext & ProcUtils-FFI)

local log = _G.log
local pesh = _G.pesh
local os_ext = require("ext.os") -- 使用 lua-ext 的 os 模块

-- 1. 显式加载依赖插件
local process = pesh.plugin.load("process")
local pe = pesh.plugin.load("pe")
local shell = pesh.plugin.load("shell")

-- 2. 生成调用 ID (Trace)
local unique_call_id = string.format("call-%d-%d", os.time(), math.random(10000, 99999))
log.info("INIT.LUA: Starting initialization sequence [ID:", unique_call_id, "]")

-- 3. 设置控制台 UTF-8 (即使 ext.ext 做了处理，这步在 PE 下依然推荐)
os.execute("chcp 65001 > nul")

-- 4. Step 1: 硬件初始化 (wpeinit)
log.info("Step 1: Running wpeinit for hardware initialization...")
-- os.getenv 已经由 lua-ext 增强支持 Unicode
local windir = os.getenv("WinDir")
if not windir then
    log.critical("Could not get %WinDir% environment variable. Aborting.")
    return
end

local wpeinit_cmd = windir .. "\\System32\\wpeinit.exe"
local wpeinit_proc = process.exec_async({ command = wpeinit_cmd })

if wpeinit_proc then
    log.info("wpeinit.exe started, waiting for completion...")
    -- 使用带消息泵的同步等待，防止 UI 冻结
    process.wait_for_exit_pump(wpeinit_proc, -1)
    wpeinit_proc = nil -- 释放句柄
    log.info("wpeinit.exe finished.")
else
    log.warn("Failed to start wpeinit.exe.")
end

-- 5. Step 2: 初始化 PE 用户环境
log.info("Step 2: Initializing PE user session environment...")
pe.initialize()
log.info("PE user environment initialized.")

-- 6. Step 3: 启动并守护 Shell (explorer.exe)
log.info("Step 3: Locking system shell (explorer.exe)...")
local explorer_path = windir .. "\\explorer.exe"

-- 采用 "takeover" 策略：先清理旧进程，再启动并守护
shell.lock_shell(explorer_path, {
    strategy = "takeover", 
    unique_call_id = unique_call_id
})

log.info("Shell guardian dispatched. PEShell host remaining active.")