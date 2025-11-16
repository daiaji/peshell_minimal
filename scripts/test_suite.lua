-- scripts/test_suite.lua
-- PEShell API 自动化测试套件 (v5 - 全功能集成测试)

-- 引入 LuaUnit 和所有待测试的模块
local lu = require("luaunit")
local log = require("pesh-api.log")
local fs = require("pesh-api.fs")
local string_api = require("pesh-api.string")
local process = require("pesh-api.process")
local pe = require("pesh-api.pe")
local shell = require("pesh-api.shell")
local async = require("pesh-api.async")
local lfs = require("lfs")

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
--  单元测试 (快速、无副作用)
-- =================================================================
TestFileSystem = {}
function TestFileSystem:testPathObject()
    log.debug("[RUNNING] TestFileSystem:testPathObject")
    local p = fs.path("C:\\Windows\\System32\\calc.exe")
    lu.assertEquals(p:directory(), "C:\\Windows\\System32")
    lu.assertEquals(p:drive(), "C:")
    lu.assertEquals(p:extension(), "exe")
    lu.assertEquals(p:filename(), "calc.exe")
    lu.assertEquals(p:name(), "calc")
end

TestPeApi = {}
function TestPeApi:testMkdirs()
    log.debug("[RUNNING] TestPeApi:testMkdirs")
    local nested_path = temp_dir .. "\\a\\b\\c"
    local success, err = pe._internal.mkdirs(nested_path)
    lu.assertTrue(success, "pe._internal.mkdirs should create nested directories. Error: " .. tostring(err))
    lu.assertEquals(lfs.attributes(nested_path, "mode"), "directory")
end

TestStringApi = {}
function TestStringApi:testUtf8Length()
    log.debug("[RUNNING] TestStringApi:testUtf8Length")
    lu.assertEquals(string_api.length("你好世界"), 4)
    lu.assertEquals(string_api.byte_length("你好世界"), 12)
end

TestProcessApi = {}
function TestProcessApi:testCommandLineParsing()
    log.debug("[RUNNING] TestProcessApi:testCommandLineParsing")
    local parts1 = process.parse_command_line("ping.exe -t localhost")
    lu.assertNotIsNil(parts1, "Should parse command with args")
    lu.assertStrContains(parts1[1], "ping.exe", false, true)
    lu.assertEquals(parts1[2], "-t")
    lu.assertEquals(parts1[3], "localhost")
end

-- =================================================================
--  集成测试：Shell 守护核心功能
-- =================================================================
TestShellApiCore = {}
local dummy_shell_name = "notepad.exe"
local dummy_shell_path = os.getenv("WinDir") .. "\\System32\\" .. dummy_shell_name

function TestShellApiCore:setUp()
    log.debug("SHELL_CORE_TEST: Cleaning up '", dummy_shell_name, "' before test...")
    os.execute("taskkill /f /im " .. dummy_shell_name .. " > nul 2>&1")
    -- 确保守护进程的关闭事件不存在，避免测试间干扰
    shell.exit_guardian() 
    async.sleep_async(500)
end
TestShellApiCore.tearDown = TestShellApiCore.setUp

function TestShellApiCore:testGuardianRespawn()
    lu.setTimeout(20) -- 设置20秒超时
    log.debug("[RUNNING] TestShellApiCore:testGuardianRespawn")

    lu.assertTrue(shell.lock_shell(dummy_shell_path), "lock_shell should start successfully")
    async.sleep_async(2500) -- 等待 shell 启动

    local initial_proc = process.open_by_name(dummy_shell_name)
    lu.assertNotIsNil(initial_proc, "Guardian should have started the shell process.")
    local initial_pid = initial_proc.pid

    log.info("SHELL_CORE_TEST: Killing guarded process (PID:", initial_pid, ") to test respawn...")
    initial_proc:kill()
    initial_proc:close_handle()
    async.sleep_async(3500) -- 给守护进程反应时间

    local respawned_proc = process.open_by_name(dummy_shell_name)
    lu.assertNotIsNil(respawned_proc, "Guardian should have respawned the shell process.")
    lu.assertNotEquals(respawned_proc.pid, initial_pid, "Respawned process should have a new PID.")

    respawned_proc:kill()
    respawned_proc:close_handle()
    lu.assertTrue(shell.exit_guardian(), "Guardian should be shutdown gracefully.")
    async.sleep_async(1000)
end

function TestShellApiCore:testGuardianGracefulShutdown()
    lu.setTimeout(20)
    log.debug("[RUNNING] TestShellApiCore:testGuardianGracefulShutdown")

    lu.assertTrue(shell.lock_shell(dummy_shell_path))
    async.sleep_async(2500)

    local proc_to_be_closed = process.open_by_name(dummy_shell_name)
    lu.assertNotIsNil(proc_to_be_closed, "Guarded process should be running.")
    proc_to_be_closed:close_handle()

    log.info("SHELL_CORE_TEST: Sending graceful shutdown signal...")
    lu.assertTrue(shell.exit_guardian(), "exit_guardian() should send signal successfully.")
    async.sleep_async(3500)

    local proc_after_shutdown = process.find(dummy_shell_name)
    lu.assertIsNil(proc_after_shutdown, "Guarded process should be terminated after graceful shutdown.")
end

-- =================================================================
--  集成测试：Shell 守护“接管”功能
-- =================================================================
TestShellApiAdoption = {}
local adoption_target_name = "ping.exe"
local adoption_target_path = os.getenv("WinDir") .. "\\System32\\" .. adoption_target_name
local adoption_args = "-t 127.0.0.1"

function TestShellApiAdoption:setUp()
    log.debug("SHELL_ADOPT_TEST: Cleaning up '", adoption_target_name, "' before test...")
    os.execute("taskkill /f /im " .. adoption_target_name .. " > nul 2>&1")
    shell.exit_guardian()
    async.sleep_async(500)
end
TestShellApiAdoption.tearDown = TestShellApiAdoption.setUp

function TestShellApiAdoption:testAdoptionAndControl()
    lu.setTimeout(20)
    log.debug("[RUNNING] TestShellApiAdoption:testAdoptionAndControl")

    -- 1. 先手动启动一个目标进程
    log.info("SHELL_ADOPT_TEST: Pre-launching '", adoption_target_name, "'...")
    local pre_existing_proc = process.exec_async({ command = adoption_target_path .. " " .. adoption_args })
    lu.assertNotIsNil(pre_existing_proc, "Pre-existing process should be launched successfully.")
    async.sleep_async(1000) -- 确保进程已运行

    -- 2. 启动守护进程，它应该“领养”这个已存在的进程
    log.info("SHELL_ADOPT_TEST: Locking shell, expecting it to adopt PID: ", pre_existing_proc.pid)
    lu.assertTrue(shell.lock_shell(adoption_target_path))
    async.sleep_async(2500) -- 等待守护进程完成一轮检查

    -- 3. 验证进程仍然是同一个 (PID 没变)
    local adopted_proc = process.open_by_name(adoption_target_name)
    lu.assertNotIsNil(adopted_proc, "Guardian should be monitoring the adopted process.")
    lu.assertEquals(adopted_proc.pid, pre_existing_proc.pid, "The PID should be the same, proving adoption.")
    adopted_proc:close_handle()

    -- 4. 测试控制权：通过发送关闭信号来终止被领养的进程
    log.info("SHELL_ADOPT_TEST: Sending graceful shutdown to test control over adopted process...")
    lu.assertTrue(shell.exit_guardian())
    async.sleep_async(3500)

    -- 5. 验证进程已被守护进程的清理逻辑终止
    lu.assertIsNil(process.find(pre_existing_proc.pid), "Adopted process should be terminated by guardian's cleanup.")
    pre_existing_proc:close_handle() -- 清理我们最初创建的句柄
end

-- =================================================================
--  集成测试：Shell 守护边界条件
-- =================================================================
TestShellApiBoundary = {}
TestShellApiBoundary.setUp = TestShellApiCore.setUp
TestShellApiBoundary.tearDown = TestShellApiCore.tearDown

function TestShellApiBoundary:testGuardianWithInvalidPath()
    lu.setTimeout(10)
    log.debug("[RUNNING] TestShellApiBoundary:testGuardianWithInvalidPath")
    
    local invalid_path = "C:\\path\\to\\nonexistent\\program.exe"
    log.info("SHELL_BOUNDARY_TEST: Locking shell with an invalid path: '", invalid_path, "'")

    -- 调用 lock_shell，它应该返回 false 并且不启动守护协程
    local success = shell.lock_shell(invalid_path)
    lu.assertIsFalse(success, "lock_shell should return false for a non-existent executable.")
    
    -- 等待一小会，确保没有意外的进程或协程启动
    async.sleep_async(2000)
    
    -- 验证没有 notepad.exe (或任何其他守护进程) 启动
    lu.assertIsNil(process.find(dummy_shell_name), "No shell process should be started for an invalid path.")
end

-- =================================================================
--  运行所有测试
-- =================================================================
os.exit(lu.run())