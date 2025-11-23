-- scripts/test_suite.lua
-- PEShell API Test Suite (Lua-Ext Edition)

local lu = require("luaunit")
local log = _G.log
local pesh = _G.pesh
local ffi = require("ffi")

-- 使用 lua-ext 替代 Penlight
local path = require("ext.path")
local os_ext = require("ext.os")
local fs_ext = require("ext.io") -- 实际上 io 扩展包含文件读写

-- Load Plugins
local process = pesh.plugin.load("process")
local pe = pesh.plugin.load("pe")
local fs = pesh.plugin.load("fs")

-- 临时目录
local temp_dir = path(os.getenv("TEMP") or "."):join("_peshell_test_temp")

function setupSuite()
    log.info("STARTING TEST SUITE")
    -- 清理并重建临时目录
    if temp_dir:exists() then 
        -- 递归删除 (使用 fs 插件或 os_ext 配合 lfs)
        fs.delete(temp_dir:str()) 
    end
    fs.mkdir(temp_dir:str())
end

function teardownSuite()
    fs.delete(temp_dir:str())
    log.info("FINISHED TEST SUITE")
end

-- FS Tests
TestFileSystem = {}
function TestFileSystem:testCopyAndMove()
    local src = temp_dir:join("file.txt")
    local dst = temp_dir:join("file_copy.txt")
    
    -- 写文件
    fs_ext.writefile(src:str(), "content")
    lu.assertTrue(src:exists(), "Source file creation failed")
    
    -- 测试复制
    lu.assertTrue(fs.copy(src:str(), dst:str()), "fs.copy failed")
    lu.assertTrue(dst:exists(), "Destination file missing after copy")
    
    -- 测试移动
    local dst2 = temp_dir:join("file_moved.txt")
    lu.assertTrue(fs.move(dst:str(), dst2:str()), "fs.move failed")
    
    lu.assertFalse(dst:exists(), "Original file still exists after move")
    lu.assertTrue(dst2:exists(), "Moved file missing")
    
    -- 测试删除
    lu.assertTrue(fs.delete(dst2:str()), "fs.delete failed")
    lu.assertFalse(dst2:exists(), "Deleted file still exists")
end

-- PE API Tests
TestPeApi = {}
function TestPeApi:testInitialize()
    -- 这是一个集成测试，主要检查不报错
    -- 真实的文件夹创建很难在 CI 环境完美验证，这里做基础调用检查
    lu.assertTrue(pe.initialize(), "pe.initialize() returned false")
end

-- Process API Tests
TestProcessApi = {}
function TestProcessApi:testExec()
    local cmd = "ping.exe -n 2 127.0.0.1"
    -- exec_async 现在返回 proc_utils 对象
    local proc_obj = process.exec_async({ command = cmd })
    lu.assertNotIsNil(proc_obj, "exec_async failed")
    lu.assertNotIsNil(proc_obj.pid, "Process object missing pid")
    
    -- Wait
    lu.assertTrue(process.wait_for_exit_pump(proc_obj, 5000), "Process wait timed out")
end

return lu.LuaUnit.run()