-- scripts/test_suite.lua
-- PEShell API 自动化测试套件 (v12.2 - Fixture Stability Fix)

local lu = require("luaunit")
local log = require("pesh-api.log")
local ffi = require("pesh-api.ffi")
local C = ffi.C
local proc_utils = ffi.proc_utils

-- Penlight 模块
local path = require("pl.path")
local dir = require("pl.dir")

-- pesh-api 模块
local process = require("pesh-api.process")
local pe = require("pesh-api.pe")
local native = _G.pesh_native
local k32 = require("pesh-api.winapi.kernel32")

local temp_dir = path.join(os.getenv("TEMP") or ".", "_peshell_test_temp")

-- =================================================================
--  全局测试固件
-- =================================================================
function setupSuite()
    log.info("===================================================")
    log.info("  PEShell Unit & Integration Test Suite - Started  ")
    log.info("===================================================")
    -- 每次运行时都确保环境是干净的
    if path.isdir(temp_dir) then dir.rmtree(temp_dir) end
    dir.makepath(temp_dir)
end

-- [修正] 移除 teardownSuite。
-- setupSuite 在每次开始时都会清理环境，这已足够。
-- teardownSuite 在复杂的集成测试后触发了 luaunit 的内部错误。
-- function teardownSuite()
--     if path.isdir(temp_dir) then dir.rmtree(temp_dir) end
--     log.info("===================================================")
--     log.info("   PEShell Unit & Integration Test Suite - Finished  ")
--     log.info("===================================================")
-- end

-- =================================================================
--  测试用例：PE 初始化 API (保持不变)
-- =================================================================
TestPeApi = {}
function TestPeApi:testInitializeCreatesFolders()
    log.debug("[RUNNING] TestPeApi:testInitializeCreatesFolders")
    local mock_userprofile = path.join(temp_dir, "MockUser")
    -- 使用 ffi 调用 SetEnvironmentVariableW 来确保设置的是 Unicode 环境变量
    C.SetEnvironmentVariableW(ffi.to_wide("USERPROFILE"), ffi.to_wide(mock_userprofile))
    pe.initialize()
    local desktop_path = path.join(mock_userprofile, "Desktop")
    lu.assertTrue(path.isdir(desktop_path), "PE initialize should create Desktop directory.")
    C.SetEnvironmentVariableW(ffi.to_wide("USERPROFILE"), nil)
end

-- =================================================================
--  测试用例：基础进程 API (使用阻塞式等待)
-- =================================================================
TestProcessApi = {}
function TestProcessApi:testExecAndKill()
    log.debug("[RUNNING] TestProcessApi:testExecAndKill")
    local test_command = "ping.exe -t 127.0.0.1"
    local test_process_name = "ping.exe"

    local proc, err_msg = process.exec_async({ command = test_command })
    lu.assertNotIsNil(proc, "process.exec_async should return a process object. Got: " .. tostring(err_msg))
    lu.assertNotIsNil(proc.handle, "Process object should have a valid handle")
    lu.assertTrue(proc.pid > 0, "Process object should have a valid PID")
    
    native.sleep(1500) -- 等待进程启动

    lu.assertTrue(proc_utils.ProcUtils_ProcessExists(ffi.to_wide(test_process_name)) > 0, test_process_name .. " should exist after launch")

    lu.assertTrue(proc:kill(), "kill() method should return true on success")
    
    local exited, wait_err = proc:wait_for_exit_blocking(5000)
    lu.assertTrue(exited, "Process should have exited after kill. Error: " .. tostring(wait_err))
    
    proc:close_handle()
    lu.assertIsNil(proc.handle.h, "Handle pointer should be nil after explicit close")
end


-- =================================================================
--  测试用例：守护进程功能 (进程隔离集成测试)
-- =================================================================
TestShellGuardian = {}

local function cleanup_lingering_processes()
    log.debug("CLEANUP: Cleaning up potential leftover processes...")
    process.kill_all_by_name("ping.exe")
    -- 精确清理，避免杀死当前测试进程
    local self_pid = C.GetCurrentProcessId()
    local peshell_pids = process.find_all("peshell.exe")
    for _, pid in ipairs(peshell_pids) do
        if pid ~= self_pid then
            log.warn("  -> Cleaning up leftover peshell.exe with PID: ", pid)
            proc_utils.ProcUtils_ProcessClose(ffi.to_wide(tostring(pid)), 0)
        end
    end
end

function TestShellGuardian:setUp()
    cleanup_lingering_processes()
end

-- [修正] tearDown 应该有独立的、清晰的实现，而不是直接调用 setUp
function TestShellGuardian:tearDown()
    cleanup_lingering_processes()
end

function TestShellGuardian:testGuardianLifecycle()
    log.debug("[RUNNING] TestShellGuardian:testGuardianLifecycle")
    local peshell_exe_path = process.get_self_path()
    local target_process_cmd = "ping.exe -t 127.0.0.1"
    local target_process_name = "ping.exe"

    -- 1. 准备IPC事件
    local unique_id = C.GetCurrentProcessId() .. "_" .. math.random(10000, 99999)
    local ready_event_name = "Global\\PEShell_Test_Ready_" .. unique_id
    local respawn_event_name = "Global\\PEShell_Test_Respawn_" .. unique_id
    
    local ready_event, _ = k32.create_event(ready_event_name, true, false)
    local respawn_event, _ = k32.create_event(respawn_event_name, true, false)
    lu.assertNotIsNil(ready_event)
    lu.assertNotIsNil(respawn_event)
    
    -- 2. 构造命令，启动一个独立的守护进程
    local guardian_cmd = string.format('"%s" main share/lua/5.1/test_guardian_init.lua "%s" %s %s', 
        peshell_exe_path, target_process_cmd, ready_event_name, respawn_event_name)
    local shutdown_cmd = string.format('"%s" shutdown', peshell_exe_path)

    log.info("  [1/4] Launching external guardian process...")
    local guardian_proc = process.exec_async({ command = guardian_cmd })
    lu.assertNotIsNil(guardian_proc)
    guardian_proc:close_handle() -- 关闭句柄，我们不直接操作守护进程

    -- 3. 使用阻塞式API等待就绪信号
    log.info("  -> Waiting for READY signal...")
    local ready_handles = { ffi.new("SafeHandle_t", { h = ready_event.h }) }
    local signaled_index, err = native.wait_for_multiple_objects_blocking(ready_handles, 15000)
    lu.assertEquals(signaled_index, 1, "Guardian failed to signal READY within 15s. Error: " .. tostring(err))
    log.info("  -> READY signal received.")
    
    local p1 = process.find(target_process_name)
    lu.assertNotIsNil(p1, "Target process should be running after READY signal.")

    -- 4. 测试重生逻辑
    log.info("  [2/4] Testing respawn...")
    p1:kill()
    
    log.info("  -> Waiting for RESPAWN signal...")
    local respawn_handles = { ffi.new("SafeHandle_t", { h = respawn_event.h }) }
    signaled_index, err = native.wait_for_multiple_objects_blocking(respawn_handles, 15000)
    lu.assertEquals(signaled_index, 1, "Guardian failed to signal RESPAWN within 15s. Error: " .. tostring(err))
    log.info("  -> RESPAWN signal received.")

    local p2 = process.find(target_process_name)
    lu.assertNotIsNil(p2, "Target process should have been respawned.")
    lu.assertNotEquals(p1.pid, p2.pid, "Respawned process should have a new PID.")

    -- 5. 测试关闭逻辑
    log.info("  [3/4] Sending shutdown signal...")
    local shutdown_proc, _ = process.exec_async({ command = shutdown_cmd })
    if shutdown_proc then
        shutdown_proc:wait_for_exit_blocking(5000)
        shutdown_proc:close_handle() 
    end
    
    -- 6. 验证清理
    log.info("  [4/4] Verifying shutdown...")
    native.sleep(2000) -- 给守护进程足够的时间来清理和退出
    lu.assertIsNil(process.find(target_process_name), "Target process should be terminated after shutdown.")
end

-- =================================================================
--  运行所有测试
-- =================================================================

-- 恢复为标准的 LuaUnit 命令行执行模式，它会自动发现并运行所有 Test* 表
os.exit(lu.LuaUnit.run())