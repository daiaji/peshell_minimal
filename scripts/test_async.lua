-- scripts/test_async.lua
-- 异步/等待模型测试脚本 (Lua-Ext Edition)

if not (_G.arg and _G.arg[1] == "run_from_main") then
    local log = require("core.log")
    log.info("Usage: peshell main scripts/test_async.lua run_from_main")
    return
end

local lu = require("luaunit")
local log = _G.log
local pesh = _G.pesh

-- Load plugins
local async = pesh.plugin.load("async")
local fs_async = pesh.plugin.load("fs_async")
local process = pesh.plugin.load("process")

-- Replace Penlight with Lua-Ext
local path = require("ext.path")
local fs_ext = require("ext.io") -- 包含 readfile/writefile
local os_ext = require("ext.os") -- 包含 mkdir 等

-- Construct temp path
local temp_dir = path(os.getenv("TEMP") or "."):join("_peshell_async_test")

-- 主异步测试任务
local function main_task()
    log.info("=== Starting Asynchronous Test Suite (Lua-Ext) ===")

    -- Use ext.os for mkdir
    if not temp_dir:exists() then os_ext.mkdir(temp_dir:str()) end
    
    local source_file = temp_dir:join("source.txt"):str()
    local dest_file = temp_dir:join("dest.txt"):str()
    local test_content = "Async content!"
    
    -- Use ext.io for file write
    fs_ext.writefile(source_file, test_content)

    log.info("[1/4] Testing await on async file copy...")
    local status, msg = pcall(await, fs_async.copy_file_async, source_file, dest_file)
    lu.assertTrue(status, "await(copy) failed: " .. tostring(msg))
    
    await(async.sleep, 50)
    
    -- Use ext.io for file read check
    lu.assertEquals(fs_ext.readfile(dest_file), test_content, "Copied content mismatch")

    log.info("[2/4] Testing await on async file read...")
    local read_status, content_or_err = pcall(await, fs_async.read_file_async, source_file)
    lu.assertTrue(read_status, "await(read) failed")
    lu.assertEquals(content_or_err, test_content, "Async read content mismatch")

    log.info("[3/4] Testing await on process exit...")
    local proc = process.exec_async({ command = "notepad.exe" })
    lu.assertNotIsNil(proc, "Failed to start notepad.exe")
    
    await(async.sleep, 1500)
    
    proc:terminate(0)
    log.info("  -> Notepad killed. Awaiting exit...")
    
    status, msg = pcall(await, process.wait_for_exit, proc)
    lu.assertTrue(status, "await(wait_for_exit) failed: " .. tostring(msg))
    
    log.info("[4/4] Demonstrating concurrency...")
    async.run(function() 
        local status_bg, msg_bg = pcall(function()
            await(fs_async.copy_file_async, source_file, dest_file .. ".concurrent")
        end)
        if status_bg then log.info("  -> BACKGROUND task finished.") end
    end)
    
    await(async.sleep, 50)
    
    log.info("=== Async Test Suite Finished ===")
end

pesh.plugin.load("async").run(function()
    local success, err = pcall(main_task)
    if not success then
        log.critical("Async tests failed: ", err)
        -- 使用 FFI 调用 PostQuitMessage
        local ffi = require("ffi")
        local u32 = ffi.load("user32")
        u32.PostQuitMessage(1)
    else
        local ffi = require("ffi")
        local u32 = ffi.load("user32")
        u32.PostQuitMessage(0)
    end
end)