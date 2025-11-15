-- scripts/test_suite.lua
-- PEShell API 自动化测试套件 (v8.3 - Takeover Test)

local lu = require("luaunit")
local log = require("pesh-api.log")
local fs = require("pesh-api.fs")
local string_api = require("pesh-api.string")
local process = require("pesh-api.process")
local pe = require("pesh-api.pe")
local shell = require("pesh-api.shell")
local async = require("pesh-api.async")
local lfs = require("lfs")
local native = _G.pesh_native

local temp_dir = (os.getenv("TEMP") or ".") .. "\\_peshell_test_temp"

-- =================================================================
--  全局测试固件 (Test Suite Fixtures)
-- =================================================================

function setupSuite()
    log.info("===================================================")
    log.info("          PEShell API Test Suite - Started         ")
    log.info("===================================================")
    log.info("Setting up global test environment in '", temp_dir, "'...")
    os.execute('rmdir /s /q "' .. temp_dir .. '" > nul 2>&1')
    lu.assertTrue(lfs.mkdir(temp_dir))
    log.info("Global setup complete.")
end

function teardownSuite()
    log.info("Tearing down global test environment...")
    local success = os.execute('rmdir /s /q "' .. temp_dir .. '"')
    lu.assertEquals(success, 0, "Teardown should successfully remove the temp directory.")
    log.info("Global teardown complete.")
    log.info("===================================================")
    log.info("           PEShell API Test Suite - Finished         ")
    log.info("===================================================")
end

-- =================================================================
--  测试用例：文件系统 API (fs.lua)
-- =================================================================
TestFileSystem = {}

function TestFileSystem:testPathObject()
    log.debug("[RUNNING] TestFileSystem:testPathObject")
    local p = fs.path("C:\\Windows\\System32\\calc.exe")
    lu.assertEquals(p:directory(), "C:\\Windows\\System32", "Path:directory() failed")
    lu.assertEquals(p:drive(), "C:", "Path:drive() failed")
    lu.assertEquals(p:extension(), "exe", "Path:extension() failed")
    lu.assertEquals(p:filename(), "calc.exe", "Path:filename() failed")
    lu.assertEquals(p:name(), "calc", "Path:name() failed")
end

function TestFileSystem:testFsOperations()
    log.debug("[RUNNING] TestFileSystem:testFsOperations")
    local src = temp_dir .. "\\test.txt"
    local cpy = temp_dir .. "\\test_copy.txt"
    local mov_dir = temp_dir .. "\\subdir"
    local mov = mov_dir .. "\\test_moved.txt"
    lu.assertTrue(lfs.mkdir(mov_dir), "Failed to create subdir for move test")
    lu.assertTrue(fs.write_bytes(src, "content"), "Failed to write source file")

    lu.assertTrue(fs.copy(src, cpy), "fs.copy() should succeed")
    lu.assertEquals(fs.get_size(cpy), fs.get_size(src), "Copied file size should match")

    lu.assertTrue(fs.move(cpy, mov), "fs.move() should succeed")
    lu.assertIsNil(fs.get_attributes(cpy), "Original file should not exist after move")
    lu.assertNotIsNil(fs.get_attributes(mov), "Moved file should exist")

    lu.assertTrue(fs.delete(mov), "fs.delete() on file should succeed")
    lu.assertIsNil(fs.get_attributes(mov), "Deleted file should not exist")
end

-- =================================================================
--  测试用例：字符串 API (string.lua)
-- =================================================================
TestStringApi = {}

function TestStringApi:testBasicFunctions()
    log.debug("[RUNNING] TestStringApi:testBasicFunctions")
    local s = "hello,world,test"
    lu.assertEquals(string_api.find_pos(s, "world"), 7, "string.find_pos() failed")
    lu.assertEquals(string_api.sub(s, 7, 5), "world", "string.sub() failed")
    lu.assertEquals(string_api.replace_regex(s, "world", "peshell"), "hello,peshell,test",
        "string.replace_regex() failed")
end

-- ... 其他字符串测试 ...

-- =================================================================
--  测试用例：PE 初始化 API (pe.lua)
-- =================================================================
TestPeApi = {}

function TestPeApi:testMkdirs()
    log.debug("[RUNNING] TestPeApi:testMkdirs")
    local nested_path = temp_dir .. "\\a\\b\\c"
    local success, err = pe._internal.mkdirs(nested_path)
    lu.assertTrue(success, "pe._internal.mkdirs should create nested directories. Error: " .. tostring(err))
    lu.assertEquals(lfs.attributes(nested_path, "mode"), "directory", "Nested directory should exist")
end

-- =================================================================
--  测试用例：进程管理 API (process.lua)
-- =================================================================
TestProcessApi = {}

-- ... 其他进程测试 ...
function TestProcessApi:testExecAndKillWithHandle()
    log.debug("[RUNNING] TestProcessApi:testExecAndKillWithHandle")
    local proc = process.exec_async({ command = "notepad.exe" })
    lu.assertNotIsNil(proc, "exec_async should return a process object")
    lu.assertNotIsNil(proc.handle, "Process object should have a valid handle")

    local found_proc = process.open_by_name("notepad.exe")
    lu.assertNotIsNil(found_proc, "Newly created process should be findable by its name")
    lu.assertEquals(found_proc.pid, proc.pid)
    found_proc:close_handle()

    lu.assertTrue(proc:kill(), "kill() method should return true on success")
    
    local exited, err_msg = proc:wait_for_exit_async(3000)
    lu.assertTrue(exited, "Process should terminate after being killed. Reason: " .. tostring(err_msg))
    
    proc:close_handle()
    lu.assertIsNil(proc.handle, "Handle should be nil after explicit close")
    lu.assertIsNil(process.find(proc.pid), "Killed process should no longer be found")
end
-- =================================================================
--  测试用例：Shell 守护 API
-- =================================================================
TestShellApi = {}

local function precise_cleanup(process_name_to_clean)
    local self_pid = process.get_current_pid()
    log.debug("Precise cleanup for '", process_name_to_clean, "', self PID is ", self_pid)
    local all_procs = process.find_all(process_name_to_clean)
    if all_procs then
        for _, pid in ipairs(all_procs) do
            if pid ~= self_pid then
                log.warn("  -> Cleaning up leftover process with PID: ", pid)
                native.process_close_tree(tostring(pid))
            end
        end
    end
end

function TestShellApi:setUp()
    -- 每个测试前都执行一次清理，确保环境干净
    log.debug("SETUP (TestShellApi): Cleaning up guardian test processes...")
    precise_cleanup("peshell.exe")
    native.process_close_tree("ping.exe")
end

function TestShellApi:tearDown()
    log.debug("TEARDOWN (TestShellApi): Cleaning up guardian test processes...")
    precise_cleanup("peshell.exe")
    native.process_close_tree("ping.exe")
end

function TestShellApi:testGuardianLifecycle()
    log.debug("[RUNNING] TestShellApi:testGuardianLifecycle")
    local peshell_exe_path = process.get_self_path()
    local target_process_cmd = "ping.exe -t 127.0.0.1"
    local target_process_name = "ping.exe"

    -- 1. 准备 IPC 事件
    local unique_id = native.get_current_pid() .. "_" .. math.random(10000, 99999)
    local ready_event_name = "Global\\PEShell_Test_Ready_" .. unique_id
    local respawn_event_name = "Global\\PEShell_Test_Respawn_" .. unique_id
    local ready_event = native.create_event(ready_event_name)
    local respawn_event = native.create_event(respawn_event_name)
    lu.assertNotIsNil(ready_event, "Failed to create the readiness event.")
    lu.assertNotIsNil(respawn_event, "Failed to create the respawn event.")
    
    local guardian_cmd = string.format('"%s" main scripts/test_guardian_init.lua "%s" %s %s', 
        peshell_exe_path, target_process_cmd, ready_event_name, respawn_event_name)
    local shutdown_cmd = string.format('"%s" run scripts/shutdown.lua', peshell_exe_path)

    -- 2. 启动守护进程并等待就绪信号
    log.info("  [1/4] Launching guardian and waiting for READY signal...")
    local guardian_proc = process.exec_async({ command = guardian_cmd })
    lu.assertNotIsNil(guardian_proc, "Failed to launch the guardian process.")
    guardian_proc:close_handle()

    local signaled_index = native.wait_for_multiple_objects({ ready_event }, 10000)
    native.close_handle(ready_event)
    lu.assertEquals(signaled_index, 1, "Guardian process failed to signal READY within 10s.")
    log.info("  -> READY signal received.")
    
    local p1 = process.find(target_process_name)
    lu.assertNotIsNil(p1, "Guardian signaled READY, but the target process was not found.")
    log.info("  -> VERIFIED! Target process (PID:", p1.pid, ") is running.")

    -- 3. 验证重生
    log.info("  [2/4] Testing respawn...")
    p1:kill()
    
    signaled_index = native.wait_for_multiple_objects({ respawn_event }, 10000)
    native.close_handle(respawn_event)
    lu.assertEquals(signaled_index, 1, "Guardian failed to signal RESPAWN within 10s.")
    log.info("  -> RESPAWN signal received.")

    local p2 = process.find(target_process_name)
    lu.assertNotIsNil(p2, "Guardian signaled RESPAWN, but the new target process was not found.")
    lu.assertNotEquals(p1.pid, p2.pid, "Respawned process should have a new PID.")
    log.info("  -> VERIFIED! Target respawned with new PID: ", p2.pid)

    -- 4. 发送关闭信号并验证
    log.info("  [3/4] Sending shutdown signal...")
    local shutdown_proc = process.exec_async({ command = shutdown_cmd })
    if shutdown_proc then shutdown_proc:wait_for_exit_async(5000); shutdown_proc:close_handle() end
    
    log.info("  [4/4] Verifying shutdown...")
    async.sleep_async(2000) -- 等待守护进程完成清理
    lu.assertIsNil(process.find(target_process_name), "Guardian failed to terminate target after shutdown.")
    log.info("  -> VERIFIED! Guardian has cleaned up correctly.")
end

--- [新增] 验证接管 (Takeover) 策略的测试用例
function TestShellApi:testGuardianTakeover()
    log.debug("[RUNNING] TestShellApi:testGuardianTakeover")
    
    local peshell_exe_path = process.get_self_path()
    local target_process_cmd = "ping.exe -t 127.0.0.1"
    local target_process_name = "ping.exe"
    
    -- 1. 预先启动一个“流氓”进程
    log.info("  [1/4] Starting a 'rogue' target process first...")
    local rogue_proc = process.exec_async({ command = target_process_cmd })
    lu.assertNotIsNil(rogue_proc, "Failed to start the initial rogue process.")
    local rogue_pid = rogue_proc.pid
    log.info("  -> Rogue process started with PID: ", rogue_pid)
    async.sleep_async(1000) -- 等待其稳定运行

    -- 2. 准备 IPC 事件并启动守护进程
    local unique_id = native.get_current_pid() .. "_" .. math.random(10000, 99999)
    local ready_event_name = "Global\\PEShell_Test_Takeover_Ready_" .. unique_id
    local ready_event = native.create_event(ready_event_name)
    
    local guardian_cmd = string.format('"%s" main scripts/test_guardian_init.lua "%s" %s', 
        peshell_exe_path, target_process_cmd, ready_event_name)

    log.info("  [2/4] Launching guardian with default 'takeover' strategy...")
    local guardian_proc = process.exec_async({ command = guardian_cmd })
    lu.assertNotIsNil(guardian_proc, "Failed to launch the guardian process.")
    guardian_proc:close_handle()
    
    -- 3. 等待守护进程就绪，并验证行为
    local signaled_index = native.wait_for_multiple_objects({ ready_event }, 10000)
    native.close_handle(ready_event)
    lu.assertEquals(signaled_index, 1, "Guardian failed to signal READY within 10s.")
    log.info("  -> Guardian is READY.")

    -- [核心验证]
    log.info("  [3/4] Verifying 'takeover' behavior...")
    lu.assertIsNil(process.find(tostring(rogue_pid)), "The rogue process should have been terminated by the guardian.")
    log.info("  -> VERIFIED! Rogue process (PID:", rogue_pid, ") was killed.")
    
    local new_proc = process.find(target_process_name)
    lu.assertNotIsNil(new_proc, "A new target process should have been started by the guardian.")
    lu.assertNotEquals(new_proc.pid, rogue_pid, "The new process must have a different PID.")
    log.info("  -> VERIFIED! A new target process (PID:", new_proc.pid, ") is running.")

    -- 4. 清理
    log.info("  [4/4] Final cleanup via shutdown command...")
    local shutdown_cmd = string.format('"%s" run scripts/shutdown.lua', peshell_exe_path)
    local shutdown_proc = process.exec_async({ command = shutdown_cmd })
    if shutdown_proc then shutdown_proc:wait_for_exit_async(5000); shutdown_proc:close_handle() end
    
    async.sleep_async(2000) -- 等待守护进程完全退出并清理
    lu.assertIsNil(process.find(target_process_name), "Target process should be cleaned up after guardian shutdown.")
end

-- =================================================================
--  运行所有测试
-- =================================================================
os.exit(lu.run())