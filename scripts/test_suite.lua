-- scripts/test_suite.lua
-- PEShell API 自动化测试套件 (v3 - 基于 LuaUnit)

-- 引入 LuaUnit 和所有待测试的模块
local lu = require("luaunit")
local log = require("pesh-api.log")
local fs = require("pesh-api.fs")
local string_api = require("pesh-api.string")
local process = require("pesh-api.process")
local pe = require("pesh-api.pe")
local lfs = require("lfs")

local temp_dir = (os.getenv("TEMP") or ".") .. "\\_peshell_test_temp"

-- =================================================================
--  全局测试固件 (Test Suite Fixtures)
-- =================================================================

-- 在所有测试开始前运行一次
function setupSuite()
    log.info("===================================================")
    log.info("          PEShell API Test Suite - Started         ")
    log.info("===================================================")
    log.info("Setting up global test environment in '", temp_dir, "'...")
    os.execute('rmdir /s /q "' .. temp_dir .. '" > nul 2>&1')
    lu.assertTrue(lfs.mkdir(temp_dir))
    log.info("Global setup complete.")
end

-- 在所有测试结束后运行一次
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

    lu.assertEquals(os.rename(cpy, mov), true, "os.rename (fs.move) should succeed")
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

function TestStringApi:testSplit()
    log.debug("[RUNNING] TestStringApi:testSplit")
    local parts = string_api.split("a,b,c", ",")
    -- assertItemsEquals 检查两个表包含相同的元素，不关心顺序
    lu.assertItemsEquals(parts, { "a", "b", "c" })
end

function TestStringApi:testUtf8Length()
    log.debug("[RUNNING] TestStringApi:testUtf8Length")
    lu.assertEquals(string_api.length("你好世界"), 4, "UTF-8 character length failed")
    lu.assertEquals(string_api.byte_length("你好世界"), 12, "UTF-8 byte length failed")
    lu.assertEquals(string_api.length("hello"), 5, "ASCII character length failed")
end

-- =================================================================
--  测试用例：PE 初始化 API (pe.lua) - 新增
-- =================================================================
TestPeApi = {}

function TestPeApi:testMkdirs()
    log.debug("[RUNNING] TestPeApi:testMkdirs")
    local nested_path = temp_dir .. "\\a\\b\\c"

    -- 直接调用 pe.lua 中导出的内部函数
    local success, err = pe._internal.mkdirs(nested_path)

    lu.assertTrue(success, "pe._internal.mkdirs should create nested directories. Error: " .. tostring(err))
    lu.assertEquals(lfs.attributes(nested_path, "mode"), "directory", "Nested directory should exist")
end

-- =================================================================
--  测试用例：进程管理 API (process.lua) - 新增
-- =================================================================
TestProcessApi = {}

function TestProcessApi:testFindProcess()
    log.debug("[RUNNING] TestProcessApi:testFindProcess")
    -- 假设 svchost.exe 总是存在于 Windows PE/系统 中
    local proc = process.find("svchost.exe")
    lu.assertNotIsNil(proc, "Should be able to find a running 'svchost.exe' process")
    lu.assertIsNumber(proc.pid, "Process object should have a numeric PID")
end

function TestProcessApi:testExecAndKill()
    log.debug("[RUNNING] TestProcessApi:testExecAndKill")
    -- 启动一个无害的进程，如 notepad
    local proc = process.exec_async({ command = "notepad.exe" })
    lu.assertNotIsNil(proc, "exec_async should return a process object")

    -- 确认进程确实在运行
    local found_proc = process.find(proc.pid)
    lu.assertNotIsNil(found_proc, "Newly created process should be findable by its PID")
    lu.assertEquals(found_proc.pid, proc.pid)

    -- 终止它
    lu.assertTrue(proc:kill(), "kill() method should return true on success")

    -- 等待并确认它已退出
    local exited = proc:wait_for_exit_async(3000) -- 等待最多3秒
    lu.assertTrue(exited, "Process should terminate after being killed")

    -- 再次查找，应该找不到了
    lu.assertIsNil(process.find(proc.pid), "Killed process should no longer be found")
end

-- =================================================================
--  运行所有测试
-- =================================================================
-- LuaUnit 会自动发现所有名为 "Test..." 的全局表和名为 "test..." 的全局函数
-- os.exit() 会将测试结果（成功为0，失败为非0）作为退出码返回给调用者（如 CI 系统）
os.exit(lu.run())
