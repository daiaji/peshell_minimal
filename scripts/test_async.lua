-- scripts/test_async.lua
-- 用于测试全新异步/等待模型的脚本 (Modernized & Cleaned)
-- Version: 9.1 (Consistent string conversion)

if not (_G.arg and _G.arg[1] == "run_from_main") then
    local log = require("core.log")
    log.info("This script is designed to be run via 'peshell main scripts/test_async.lua run_from_main'")
    log.info("It tests the async scheduler which requires the persistent message loop of main mode.")
    return
end

local lu = require("luaunit")
local log = _G.log
local pesh = _G.pesh
local ffi = require("ffi")

-- Load plugins
local async = pesh.plugin.load("async")
local fs_async = pesh.plugin.load("fs_async")
local process = pesh.plugin.load("process")

local path = require("ext.path")
local fs_ext = require("ext.io")
local os_ext = require("ext.os")

local temp_dir = path(os.getenv("TEMP") or ".") / "_peshell_async_test"

local function main_task()
    log.info("==============================================")
    log.info("  Starting Asynchronous Test Suite with await")
    log.info("==============================================")

    if not temp_dir:exists() then os_ext.mkdir(tostring(temp_dir), true) end
    
    local source_file = tostring(temp_dir / "source.txt")
    local dest_file = tostring(temp_dir / "dest.txt")
    
    local test_content = "Async content!"
    fs_ext.writefile(source_file, test_content)

    log.info("\n[1/4] Testing await on async file copy...")
    local status, msg = pcall(await, fs_async.copy_file_async, source_file, dest_file)
    lu.assertTrue(status, "await(copy) should not throw an error. Got: " .. tostring(msg))
    log.info("  -> SUCCESS: Async copy completed.")
    
    await(async.sleep, 50)
    lu.assertEquals(fs_ext.readfile(dest_file), test_content, "Copied content must match.")

    log.info("\n[2/4] Testing await on async file read...")
    local read_status, content_or_err = pcall(await, fs_async.read_file_async, source_file)
    lu.assertTrue(read_status, "await(read) should not throw an error. Got: " .. tostring(content_or_err))
    lu.assertEquals(content_or_err, test_content, "Asynchronously read content must match source.")
    log.info("  -> SUCCESS: Async read completed and content verified.")

    log.info("\n[3/4] Testing await on process exit...")
    local proc = process.exec_async({ command = "notepad.exe" })
    lu.assertNotIsNil(proc, "Failed to start notepad.exe")
    
    await(async.sleep, 1500)
    
    proc:terminate(0)
    log.info("  -> Notepad killed. Now awaiting process exit...")
    
    status, msg = pcall(await, process.wait_for_exit, proc)
    lu.assertTrue(status, "await(process.wait_for_exit) should succeed. Got: " .. tostring(msg))
    log.info("  -> SUCCESS: Awaited process exit.")
    
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
    
    await(async.sleep, 50)
    log.info("  -> This proves the main flow was not blocked.")
    
    log.info("\n==============================================")
    log.info("  Asynchronous Test Suite Finished")
    log.info("==============================================")
end

pesh.plugin.load("async").run(function()
    local success, err = pcall(main_task)
    
    local u32 = ffi.load("user32")
    
    if not success then
        local traceback = debug.traceback(tostring(err), 2)
        log.critical("One or more async tests failed! Error: \n", traceback)
        u32.PostQuitMessage(1)
    else
        log.info("All async tests passed successfully!")
        u32.PostQuitMessage(0)
    end
end)