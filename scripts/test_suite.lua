-- scripts/test_suite.lua
-- PEShell API 自动化测试套件 (v4 - 包含 shell 守护测试)

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
--  测试用例：字符串 API (string.lua)
-- =================================================================
TestStringApi = {}

function TestStringApi:testUtf8Length()
    log.debug("[RUNNING] TestStringApi:testUtf8Length")
    lu.assertEquals(string_api.length("你好世界"), 4, "UTF-8 character length failed")
    lu.assertEquals(string_api.byte_length("你好世界"), 12, "UTF-8 byte length failed")
    lu.assertEquals(string_api.length("hello"), 5, "ASCII character length failed")
end

-- =================================================================
--  测试用例：进程管理 API (process.lua)
-- =================================================================
TestProcessApi = {}

function TestProcessApi:testCommandLineParsing()
    log.debug("[RUNNING] TestProcessApi:testCommandLineParsing")
    -- 测试 1: 简单命令
    local parts1 = process.parse_command_line("notepad.exe")
    lu.assertNotIsNil(parts1, "Should parse simple command")
    lu.assertStrContains(parts1[1], "notepad.exe", false, true, "Executable should be found")

    -- 测试 2: 带参数
    local parts2 = process.parse_command_line("ping.exe -t localhost")
    lu.assertNotIsNil(parts2, "Should parse command with args")
    lu.assertStrContains(parts2[1], "ping.exe", false, true)
    lu.assertEquals(parts2[2], "-t")
    lu.assertEquals(parts2[3], "localhost")

    -- 测试 3: 带引号的路径和参数
    local cmd3 = '"C:\\Program Files\\My App\\app.exe" "first arg" -o "output file"'
    local parts3 = process.parse_command_line(cmd3)
    lu.assertNotIsNil(parts3, "Should parse command with quotes")
    lu.assertEquals(parts3[1], "C:\\Program Files\\My App\\app.exe")
    lu.assertEquals(parts3[2], "first arg")
    lu.assertEquals(parts3[3], "-o")
    lu.assertEquals(parts3[4], "output file")
end

-- =================================================================
--  测试用例：Shell 守护 API (shell.lua) - 集成测试
-- =================================================================
TestShellApi = {}
local dummy_shell_name = "notepad.exe" -- 使用一个无害且常见的程序作为被守护对象

-- 在每个测试前清理环境
function TestShellApi:setUp()
    log.debug("SHELL_TEST: Cleaning up any leftover '", dummy_shell_name, "' processes before test...")
    os.execute("taskkill /f /im " .. dummy_shell_name .. " > nul 2>&1")
end
-- 在每个测试后也清理
TestShellApi.tearDown = TestShellApi.setUp

function TestShellApi:testGuardianRespawn()
    lu.skipIf(os.getenv("CI"), "Skipping shell guardian test in CI environment due to potential instability.")
    
    log.debug("[RUNNING] TestShellApi:testGuardianRespawn")

    -- 1. 启动守护协程
    log.info("SHELL_TEST: Locking shell '", dummy_shell_name, "'...")
    shell.lock_shell(dummy_shell_name)
    async.sleep_async(2000) -- 等待守护进程启动 shell

    -- 2. 验证 shell 是否已启动
    local initial_proc = process.open_by_name(dummy_shell_name)
    lu.assertNotIsNil(initial_proc, "Guardian should have started the shell process.")
    local initial_pid = initial_proc.pid

    -- 3. 杀死 shell
    log.info("SHELL_TEST: Killing the guarded process (PID: ", initial_pid, ") to test respawn...")
    initial_proc:kill()
    initial_proc:close_handle() -- 关闭我们打开的句柄
    async.sleep_async(3000) -- 给守护进程足够的时间来反应和重启

    -- 4. 验证 shell 是否被重新启动
    local respawned_proc = process.open_by_name(dummy_shell_name)
    lu.assertNotIsNil(respawned_proc, "Guardian should have respawned the shell process.")
    lu.assertNotEquals(respawned_proc.pid, initial_pid, "Respawned process should have a new PID.")

    -- 5. 清理
    respawned_proc:kill()
    respawned_proc:close_handle()
    
    -- [关键] 发送退出信号给守护进程，以便下一个测试可以正常开始
    shell.exit_guardian()
    async.sleep_async(1000) -- 等待守护协程清理完毕
end

function TestShellApi:testGuardianGracefulShutdown()
    lu.skipIf(os.getenv("CI"), "Skipping shell guardian test in CI environment due to potential instability.")
    
    log.debug("[RUNNING] TestShellApi:testGuardianGracefulShutdown")

    -- 1. 启动守护协程
    log.info("SHELL_TEST: Locking shell '", dummy_shell_name, "' for shutdown test...")
    shell.lock_shell(dummy_shell_name)
    async.sleep_async(2000)

    -- 2. 验证 shell 是否已启动
    local proc_to_be_closed = process.open_by_name(dummy_shell_name)
    lu.assertNotIsNil(proc_to_be_closed, "Guarded process should be running before shutdown.")
    proc_to_be_closed:close_handle()

    -- 3. 发送退出信号
    log.info("SHELL_TEST: Sending graceful shutdown signal to the guardian...")
    local signal_sent = shell.exit_guardian()
    lu.assertTrue(signal_sent, "exit_guardian() should successfully send the signal.")

    -- 4. 等待守护进程完成清理
    async.sleep_async(3000)

    -- 5. 验证 shell 是否已被关闭
    local proc_after_shutdown = process.find(dummy_shell_name)
    lu.assertIsNil(proc_after_shutdown, "Guarded process should be terminated after graceful shutdown.")
end


-- =================================================================
--  运行所有测试
-- =================================================================
os.exit(lu.run())