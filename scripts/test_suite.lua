-- scripts/test_suite.lua
-- PEShell API 自动化测试套件 (修正版 v2)

local log = require("pesh-api.log")
local fs = require("pesh-api.fs")
local string_api = require("pesh-api.string")
local lfs = require("lfs")

local test_results = { passed = 0, failed = 0, total = 0 }
local temp_dir = (os.getenv("TEMP") or ".") .. "\\_peshell_test_temp"

-- =================================================================
--  测试辅助函数
-- =================================================================

local function assert(condition, message)
    test_results.total = test_results.total + 1
    if not condition then
        test_results.failed = test_results.failed + 1
        -- 抛出错误，这将终止脚本并被 CI 捕获
        error("Assertion failed: " .. message, 2)
    else
        test_results.passed = test_results.passed + 1
        log.trace("  - Assert PASSED: ", message)
    end
end

-- =================================================================
--  测试设置与清理
-- =================================================================

local function setup()
    log.info("Setting up test environment in '", temp_dir, "'...")
    -- 清理可能存在的旧目录
    os.execute('rmdir /s /q "' .. temp_dir .. '" > nul 2>&1')
    lfs.mkdir(temp_dir)
    lfs.mkdir(temp_dir .. "/subdir")
    fs.write_bytes(temp_dir .. "/test.txt", "line1\nline2")
    fs.write_bytes(temp_dir .. "/empty.dat", "")
    log.info("Setup complete.")
end

local function teardown()
    log.info("Tearing down test environment...")
    local success = os.execute('rmdir /s /q "' .. temp_dir .. '"')
    if success == 0 then
        log.info("Teardown complete.")
    else
        log.warn("Teardown failed to remove temporary directory.")
    end
end

-- =================================================================
--  测试用例
-- =================================================================

local function test_fs_path_object()
    log.debug("[RUNNING] test_fs_path_object")
    local p = fs.path("C:\\Windows\\System32\\calc.exe")
    assert(p:directory() == "C:\\Windows\\System32", "Path:directory()")
    assert(p:drive() == "C:", "Path:drive()")
    assert(p:extension() == "exe", "Path:extension()")
    assert(p:filename() == "calc.exe", "Path:filename()")
    assert(p:name() == "calc", "Path:name()")
    log.info("[PASSED] test_fs_path_object")
end

local function test_fs_operations()
    log.debug("[RUNNING] test_fs_operations")
    local src = temp_dir .. "\\test.txt"
    local cpy = temp_dir .. "\\test_copy.txt"
    local mov = temp_dir .. "\\subdir\\test_moved.txt"

    assert(fs.copy(src, cpy), "fs.copy()")
    assert(fs.get_size(cpy) == fs.get_size(src), "fs.get_size() on copied file")

    assert(fs.move(cpy, mov), "fs.move()")
    assert(not fs.get_attributes(cpy), "Original file should not exist after move")
    assert(fs.get_attributes(mov), "Moved file should exist")

    assert(fs.delete(mov), "fs.delete()")
    assert(not fs.get_attributes(mov), "Deleted file should not exist")
    log.info("[PASSED] test_fs_operations")
end

local function test_fs_binary_io()
    log.debug("[RUNNING] test_fs_binary_io")
    local bin_file = temp_dir .. "\\binary.dat"
    local content = "\x01\x02\x03\x00\x04"
    assert(fs.write_bytes(bin_file, content), "fs.write_bytes()")
    local read_content = fs.read_bytes(bin_file)
    assert(read_content == content, "fs.read_bytes() content matches")
    assert(fs.get_size(bin_file) == 5, "fs.get_size() on binary file")
    log.info("[PASSED] test_fs_binary_io")
end

local function test_string_api()
    log.debug("[RUNNING] test_string_api")
    local s = "hello,world,test"

    assert(string_api.find_pos(s, "world") == 7, "string.find_pos()")
    assert(string_api.sub(s, 7, 5) == "world", "string.sub()")

    local parts = string_api.split(s, ",")
    assert(#parts == 3 and parts[1] == "hello" and parts[3] == "test", "string.split()")

    local replaced = string_api.replace_regex(s, "world", "peshell")
    assert(replaced == "hello,peshell,test", "string.replace_regex()")

    -- ########## 关键修正 ##########
    -- 使用我们新实现的、能够正确处理 UTF-8 的 string_api.length 函数
    assert(string_api.length("你好") == 2, "string.length() for UTF-8 characters")
    -- ############################

    assert(string_api.byte_length("你好") == 6, "string.byte_length() for UTF-8 bytes")
    log.info("[PASSED] test_string_api")
end

-- =================================================================
--  主测试流程
-- =================================================================

-- 使用 pcall 包装整个测试流程，确保 teardown 总能被执行
local status, err = pcall(function()
    setup()

    -- 运行所有测试用例
    test_fs_path_object()
    test_fs_operations()
    test_fs_binary_io()
    test_string_api()
    -- ... 在此添加更多测试函数

    teardown()
end)

log.info("===================================================")
log.info("                 TEST SUITE RESULTS                ")
log.info("---------------------------------------------------")
log.info("  Total Assertions: ", test_results.total)
log.info("  Passed:           ", test_results.passed)
log.info("  Failed:           ", test_results.failed)
log.info("===================================================")

if not status then
    log.critical("A critical error occurred during the test run:")
    log.critical(err)
    os.exit(1) -- 返回非零退出码，以使 CI 失败
elseif test_results.failed > 0 then
    log.error("One or more assertions failed.")
    os.exit(1) -- 返回非零退出码，以使 CI 失败
else
    log.info("All tests passed successfully!")
    os.exit(0)
end
