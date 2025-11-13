-- scripts/test_runner.lua
-- 一个用于全面测试 'peshell run' 子命令能力的综合脚本。
-- 版本 2.0 - 修正了 lfs API 调用

-- 引入所有我们将要测试的 API 模块
local log = require("pesh-api.log")
local process = require("pesh-api.process")
local async = require("pesh-api.async")
local lfs = require("lfs") -- lfs 模块提供 os 库所没有的文件系统功能

-- =================================================================
--  测试流程开始
-- =================================================================

log.info("===================================================")
log.info("  PEShell 'run' Command Test Script v2.0 - Started")
log.info("===================================================")

-- 1. 测试参数传递
-- -----------------------------------------------------------------
log.info("\n[1/5] Testing Argument Passing...")
-- 'arg' 是由 prelude.lua 中的 run_command 准备好的全局表
if _G.arg and #_G.arg > 0 then
    log.info("  -> Success: Script received arguments.")
    for i, v in ipairs(_G.arg) do
        log.info("     - Argument #", i, ": '", v, "'")
    end
else
    log.warn("  -> Info: No additional arguments were passed to this script.")
    log.info("     - Try running: peshell.exe run scripts\\test_runner.lua hello 123")
end


-- 2. 测试日志和异步延迟
-- -----------------------------------------------------------------
log.info("\n[2/5] Testing Logging & Async Sleep...")
log.debug("  -> This is a debug message.")
log.info("  -> Pausing for 2 seconds using async.sleep_async...")
async.sleep_async(2000)
log.info("  -> Success: Woke up after 2 seconds.")


-- 3. 测试文件系统 API (lfs 和 os)
-- -----------------------------------------------------------------
log.info("\n[3/5] Testing File System API (lfs & os)...")
-- 使用 lfs 获取临时目录路径
local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or lfs.currentdir()
local test_filename = temp_dir .. "\\peshell_run_test.tmp"
local test_content = "Hello from peshell run! Timestamp: " .. os.time()

log.info("  -> Attempting to write to temporary file: '", test_filename, "'")
local file, err = io.open(test_filename, "w")
if not file then
    log.error("  -> Failure: Could not open file for writing: ", tostring(err))
else
    file:write(test_content)
    file:close()
    log.info("  -> Success: File written.")
end

log.info("  -> Verifying file content...")
local file_read, err_read = io.open(test_filename, "r")
if not file_read then
    log.error("  -> Failure: Could not open file for reading: ", tostring(err_read))
else
    local content_read = file_read:read("*a")
    file_read:close()
    if content_read == test_content then
        log.info("  -> Success: File content matches.")
    else
        log.error("  -> Failure: File content mismatch!")
    end
end

-- ########## 关键修复 ##########
-- 使用标准的 os.remove() 来删除文件，而不是 lfs.rm()
log.info("  -> Deleting temporary file using os.remove()...")
local success, err_delete = os.remove(test_filename)
if success then
    log.info("  -> Success: Temporary file deleted.")
else
    log.error("  -> Failure: Could not delete temporary file: ", tostring(err_delete))
end
-- ############################


-- 4. 测试进程管理 API
-- -----------------------------------------------------------------
log.info("\n[4/5] Testing Process Management API...")
local notepad_process_name = "notepad.exe"

log.info("  -> Launching '", notepad_process_name, "' as a test process...")
local notepad_proc = process.exec_async({ command = notepad_process_name })

if not notepad_proc then
    log.error("  -> Failure: Could not start '", notepad_process_name, "'.")
else
    log.info("  -> Success: '", notepad_process_name, "' started with PID: ", notepad_proc.pid)
    log.info("     - Waiting for 3 seconds before closing it...")
    async.sleep_async(3000)

    log.info("  -> Now, attempting to kill the process by its PID...")
    local kill_success = notepad_proc:kill()
    if kill_success then
        log.info("  -> Success: Kill signal sent to PID ", notepad_proc.pid)
    else
        log.error("  -> Failure: Failed to send kill signal.")
    end

    log.info("  -> Verifying that the process has terminated...")
    -- 等待最多2秒，确认进程已关闭
    local closed = notepad_proc:wait_for_exit_async(2000)
    if closed then
        log.info("  -> Success: Process has terminated as expected.")
    else
        log.warn("  -> Warning: Process did not terminate within the verification window.")
    end
end


-- 5. 测试完成与退出
-- -----------------------------------------------------------------
log.info("\n[5/5] All tests completed.")
log.info("===================================================")
log.info("  This script will now finish. The peshell.exe")
log.info("  process should exit shortly after this message.")
log.info("===================================================")
