-- scripts/test_async.lua
-- 用于测试全新异步/等待模型的脚本 (v1.3 - Typo Fix)

-- 这个脚本必须在 main 模式下运行
if not (_G.arg and _G.arg[1] == "run_from_main") then
    -- 如果直接 run，则打印提示信息
    local log = require("pesh-api.log")
    log.info("This script is designed to be run via 'peshell main scripts/test_async.lua run_from_main'")
    log.info("It tests the async scheduler which requires the persistent message loop of main mode.")
    return
end

local lu = require("luaunit")
local log = require("pesh-api.log")
local async = require("pesh-api.async")
local fs_async = require("pesh-api.fs_async")
local process = require("pesh-api.process")
local ffi = require("pesh-api.ffi")
local path = require("pl.path")
local file = require("pl.file")
local dir = require("pl.dir")

local temp_dir = path.join(os.getenv("TEMP") or ".", "_peshell_async_test")

-- 主异步测试任务
local function main_task()
    log.info("==============================================")
    log.info("  Starting Asynchronous Test Suite with await")
    log.info("==============================================")

    -- 准备环境
    dir.makepath(temp_dir)
    local source_file = path.join(temp_dir, "source.txt")
    local dest_file = path.join(temp_dir, "dest.txt")
    local test_content = "Async content!"
    file.write(source_file, test_content)

    -- === 测试 1: await 异步文件复制 ===
    log.info("\n[1/4] Testing await on async file copy...")
    local status, msg = pcall(await, fs_async.copy_file_async, source_file, dest_file)
    lu.assertTrue(status, "await(copy) should not throw an error. Got: " .. tostring(msg))
    log.info("  -> SUCCESS: Async copy completed.")
    
    async.sleep_async(50) -- 等待 50ms

    lu.assertEquals(file.read(dest_file), test_content, "Copied content must match.")

    -- === 测试 2: await 异步文件读取 ===
    log.info("\n[2/4] Testing await on async file read...")
    local read_status, content_or_err = pcall(await, fs_async.read_file_async, source_file)
    lu.assertTrue(read_status, "await(read) should not throw an error. Got: " .. tostring(content_or_err))
    lu.assertEquals(content_or_err, test_content, "Asynchronously read content must match source.")
    log.info("  -> SUCCESS: Async read completed and content verified.")

    -- === 测试 3: await 异步进程等待 (使用新API) ===
    log.info("\n[3/4] Testing await on process exit...")
    local proc = process.exec_async({ command = "notepad.exe" })
    lu.assertNotIsNil(proc, "Failed to start notepad.exe")
    
    async.sleep_async(1500) -- 等待窗口出现
    proc:kill()
    log.info("  -> Notepad killed. Now awaiting process exit...")

    status, msg = pcall(await, process.wait_for_exit, proc)
    
    lu.assertTrue(status, "await(process.wait_for_exit) should succeed. Got: " .. tostring(msg))
    proc:close_handle() -- 确保在等待后关闭句柄
    log.info("  -> SUCCESS: Awaited process exit.")
    
    -- === 测试 4: 证明非阻塞性 ===
    log.info("\n[4/4] Demonstrating concurrency...")
    log.info("  -> Starting a long-running async copy in the background...")
    async.run(function() 
        local status_bg, msg_bg = pcall(function()
            await(fs_async.copy_file_async, source_file, dest_file .. ".concurrent")
        end)
        if status_bg then
            log.info("  -> BACKGROUND task finished successfully.")
        else
            log.error("  -> BACKGROUND task failed: ", tostring(msg_bg))
        end
    end)
    log.info("  -> Immediately after starting copy, this message prints.")
    async.sleep_async(50) -- 短暂休眠，让后台任务有机会开始
    log.info("  -> This proves the main flow was not blocked.")
    
    log.info("\n==============================================")
    log.info("  Asynchronous Test Suite Finished")
    log.info("==============================================")
end

-- 运行测试并决定退出码
async.run(function()
    local success, err = pcall(main_task)
    if not success then
        local traceback = debug.traceback(tostring(err), 2)
        log.critical("One or more async tests failed! Error: \n", traceback)
        ffi.C.PostQuitMessage(1)
    else
        log.info("All async tests passed successfully!")
        ffi.C.PostQuitMessage(0)
    end
end)