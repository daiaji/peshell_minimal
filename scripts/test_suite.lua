-- scripts/test_suite.lua
-- PEShell API 自动化测试套件 (v13.0 - Plugin Architecture)

local lu = require("luaunit")
-- 核心服务
local log = _G.log
local pesh = _G.pesh
local ffi = pesh.ffi
local native = _G.pesh_native

-- Penlight 模块
local path = require("pl.path")
local dir = require("pl.dir")

-- 按需加载所有测试需要的插件
local process = pesh.plugin.load("process")
local pe = pesh.plugin.load("pe")
local k32 = pesh.plugin.load("winapi.kernel32")

local temp_dir = path.join(os.getenv("TEMP") or ".", "_peshell_test_temp")

-- =================================================================
--  全局测试固件
-- =================================================================
function setupSuite()
    log.info("===================================================")
    log.info("  PEShell Unit & Integration Test Suite - Started  ")
    log.info("===================================================")
    if path.isdir(temp_dir) then dir.rmtree(temp_dir) end
    dir.makepath(temp_dir)
end

function teardownSuite()
    if path.isdir(temp_dir) then dir.rmtree(temp_dir) end
    log.info("===================================================")
    log.info("   PEShell Unit & Integration Test Suite - Finished  ")
    log.info("===================================================")
end

-- =================================================================
--  测试用例：PE 初始化 API
-- =================================================================
TestPeApi = {}
function TestPeApi:testInitializeCreatesFolders()
    log.debug("[RUNNING] TestPeApi:testInitializeCreatesFolders")
    local mock_userprofile = path.join(temp_dir, "MockUser")
    k32.SetEnvironmentVariableW(ffi.to_wide("USERPROFILE"), ffi.to_wide(mock_userprofile))
    pe.initialize()
    local desktop_path = path.join(mock_userprofile, "Desktop")
    lu.assertTrue(path.isdir(desktop_path), "PE initialize should create Desktop directory.")
    k32.SetEnvironmentVariableW(ffi.to_wide("USERPROFILE"), nil)
end

-- =================================================================
--  测试用例：基础进程 API
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
    
    native.sleep(1500)
    -- 使用高级 API 验证
    lu.assertNotIsNil(process.find(test_process_name), test_process_name .. " should exist after launch")

    lu.assertTrue(proc:kill(), "kill() method should return true on success")
    
    local exited, wait_err = proc:wait_for_exit_blocking(5000)
    lu.assertTrue(exited, "Process should have exited after kill. Error: " .. tostring(wait_err))
    
    proc:close_handle()
    lu.assertIsNil(proc.handle.h, "Handle pointer should be nil after explicit close")
end

-- =================================================================
--  测试用例：守护进程功能
-- =================================================================
TestShellGuardian = {}

local function cleanup_lingering_processes()
    log.debug("CLEANUP: Cleaning up potential leftover processes...")
    process.kill_all_by_name("ping.exe")
    local self_pid = k32.GetCurrentProcessId()
    local peshell_pids = process.find_all("peshell.exe")
    for _, pid in ipairs(peshell_pids) do
        if pid ~= self_pid then
            log.warn("  -> Cleaning up leftover peshell.exe with PID: ", pid)
            -- 使用高级 API
            local p_to_kill = process.find(tostring(pid))
            if p_to_kill then p_to_kill:kill() end
        end
    end
end

function TestShellGuardian:setUp() cleanup_lingering_processes() end
function TestShellGuardian:tearDown() cleanup_lingering_processes() end

function TestShellGuardian:testGuardianLifecycle()
    log.debug("[RUNNING] TestShellGuardian:testGuardianLifecycle")
    local peshell_exe_path = process.get_self_path()
    local target_process_cmd = "ping.exe -t 127.0.0.1"
    local target_process_name = "ping.exe"

    local unique_id = k32.GetCurrentProcessId() .. "_" .. math.random(10000, 99999)
    local ready_event_name = "Global\\PEShell_Test_Ready_" .. unique_id
    local respawn_event_name = "Global\\PEShell_Test_Respawn_" .. unique_id
    
    -- [[ 关键修正 ]] 使用安全的 RAII handle
    local ready_event = ffi.EventHandle(k32.CreateEventW(nil, 1, 0, ffi.to_wide(ready_event_name)))
    local respawn_event = ffi.EventHandle(k32.CreateEventW(nil, 1, 0, ffi.to_wide(respawn_event_name)))
    lu.assertNotIsNil(ready_event)
    lu.assertNotIsNil(respawn_event)
    
    -- [[ 关键修正 ]] 修复脚本路径
    local test_script_path = "share/lua/5.1/test_guardian_init.lua"
    local guardian_cmd = string.format('"%s" main "%s" "%s" %s %s', 
        peshell_exe_path, test_script_path, target_process_cmd, ready_event_name, respawn_event_name)
    local shutdown_cmd = string.format('"%s" shutdown', peshell_exe_path)

    log.info("  [1/4] Launching external guardian process...")
    local guardian_proc = process.exec_async({ command = guardian_cmd })
    lu.assertNotIsNil(guardian_proc)
    guardian_proc:close_handle() -- 我们不直接操作守护进程, let it run

    log.info("  -> Waiting for READY signal...")
    local signaled_index, err = native.wait_for_multiple_objects_blocking({ ready_event }, 15000)
    lu.assertEquals(signaled_index, 1, "Guardian failed to signal READY within 15s. Error: " .. tostring(err))
    log.info("  -> READY signal received.")
    
    local p1 = process.find(target_process_name)
    lu.assertNotIsNil(p1, "Target process should be running after READY signal.")

    log.info("  [2/4] Testing respawn...")
    p1:kill()
    
    log.info("  -> Waiting for RESPAWN signal...")
    signaled_index, err = native.wait_for_multiple_objects_blocking({ respawn_event }, 15000)
    lu.assertEquals(signaled_index, 1, "Guardian failed to signal RESPAWN within 15s. Error: " .. tostring(err))
    log.info("  -> RESPAWN signal received.")

    local p2 = process.find(target_process_name)
    lu.assertNotIsNil(p2, "Target process should have been respawned.")
    lu.assertNotEquals(p1.pid, p2.pid, "Respawned process should have a new PID.")

    log.info("  [3/4] Sending shutdown signal...")
    local shutdown_proc, _ = process.exec_async({ command = shutdown_cmd })
    if shutdown_proc then
        shutdown_proc:wait_for_exit_blocking(5000)
        shutdown_proc:close_handle() 
    end
    
    log.info("  [4/4] Verifying shutdown...")
    native.sleep(2000)
    lu.assertIsNil(process.find(target_process_name), "Target process should be terminated after shutdown.")
end

-- =================================================================
--  运行所有测试
-- =================================================================
return lu.LuaUnit.run()