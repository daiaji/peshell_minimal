-- scripts/init.lua
-- PEShell PE 初始化主脚本 (Refactored for lua-ext & async)

-- 1. 环境准备
local log = _G.log
local pesh = _G.pesh
local path = require("ext.path")   -- 直接使用 lua-ext 的路径对象
local os_ext = require("ext.os")   -- 使用 lua-ext 的系统扩展

-- 加载核心插件
local process = pesh.plugin.load("process")
local pe = pesh.plugin.load("pe")
local shell = pesh.plugin.load("shell")
local async = pesh.plugin.load("async")

-- 设置控制台编码
os.execute("chcp 65001 > nul")

-- 生成调用追踪 ID
local unique_call_id = string.format("boot-%d", os.time())
log.info("INIT: System Boot Sequence Started [ID:", unique_call_id, "]")

-- ============================================================================
-- 定义初始化主任务 (运行在协程中，支持 await)
-- ============================================================================
local function boot_sequence()
    -- [Step 1] 硬件初始化 (wpeinit)
    log.info("Step 1: Hardware Initialization (wpeinit)...")
    local windir = os_ext.getenv("WinDir")
    if not windir then
        log.critical("Missing %WinDir%. Aborting.")
        return
    end

    local wpeinit_exe = path(windir) / "System32" / "wpeinit.exe"
    
    if wpeinit_exe:exists() then
        -- 启动进程
        local proc = process.exec_async({ command = wpeinit_exe:str() })
        if proc then
            log.info("wpeinit launched. Waiting for completion (Async)...")
            -- [FIX] 使用 await 实现内核级事件等待，无 CPU 轮询
            await(process.wait_for_exit, proc) 
            proc:close()
            log.info("wpeinit finished.")
        else
            log.warn("Failed to launch wpeinit.")
        end
    else
        log.warn("wpeinit.exe not found at: ", wpeinit_exe:str())
    end

    -- [Step 2] PE 用户环境初始化
    log.info("Step 2: User Environment Setup...")
    pe.initialize()
    log.info("Environment initialized.")

    -- [Step 3] 启动 Shell 守护
    log.info("Step 3: Launching Shell Guardian...")
    local explorer_exe = path(windir) / "explorer.exe"

    -- lock_shell 内部也是异步的，它会启动自己的协程，与主循环并行运行
    shell.lock_shell(explorer_exe:str(), {
        strategy = "takeover", 
        unique_call_id = unique_call_id
    })

    log.info("INIT: Boot sequence completed. Host entering guardian mode.")
end

-- ============================================================================
-- 入口点：将主任务放入 Async 调度器运行
-- ============================================================================
async.run(boot_sequence)