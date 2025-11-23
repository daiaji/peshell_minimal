-- scripts/test_suite.lua
-- PEShell API Test Suite (Cleaned & Decoupled)
-- Version: 16.0

local lu = require("luaunit")
local log = _G.log
local pesh = _G.pesh
local ffi = require("ffi")

local path = require("ext.path")
local os_ext = require("ext.os")
local fs_ext = require("ext.io")

-- [DECOUPLED] Load kernel32 from binding lib. 
-- It now includes CreateEventW, SetEnvironmentVariableW, etc.
require("ffi.req")("Windows.sdk.kernel32")
local k32 = ffi.load("kernel32")

-- Only helper structs specific to this test suite remain here
ffi.cdef[[
    typedef struct { void* h; } SafeHandle_t;
]]

local process = pesh.plugin.load("process")
local pe = pesh.plugin.load("pe")
local fs = pesh.plugin.load("fs")
local async = pesh.plugin.load("async")

local function to_w(str)
    if not str then return nil end
    local CP_UTF8 = 65001
    local len = k32.MultiByteToWideChar(CP_UTF8, 0, str, -1, nil, 0)
    local buf = ffi.new("wchar_t[?]", len)
    k32.MultiByteToWideChar(CP_UTF8, 0, str, -1, buf, len)
    return buf
end

-- [RAII] SafeHandle
local safe_handle_mt = {
    __gc = function(t)
        if t.h ~= nil and t.h ~= ffi.cast("void*", -1) then
            k32.CloseHandle(t.h)
            t.h = nil
        end
    end,
    __index = {
        close = function(t)
            if t.h ~= nil and t.h ~= ffi.cast("void*", -1) then
                k32.CloseHandle(t.h)
                t.h = nil
                ffi.gc(t, nil)
                return true
            end
            return false
        end
    }
}
local SafeHandle = ffi.metatype("SafeHandle_t", safe_handle_mt)
local function AutoHandle(raw_h) return SafeHandle(raw_h) end

local temp_dir = nil

local function safe_setup()
    log.info("STARTING TEST SUITE")
    temp_dir = fs.unique_path(nil, "_peshell_test")
    log.info("Test Suite Temp Dir: ", temp_dir:str())
    
    local ok, err = temp_dir:mkdir(true)
    if not ok then
        error("Failed to create temp dir: " .. tostring(err))
    end
end

function setupSuite()
    local status, err = xpcall(safe_setup, debug.traceback)
    if not status then
        log.critical("CRITICAL ERROR IN SETUP SUITE:\n", err)
        error(err)
    end
end

function teardownSuite()
    collectgarbage("collect")
    _G.pesh_native.sleep(50)

    if temp_dir and temp_dir:exists() then
        fs.delete(temp_dir)
    end
    log.info("FINISHED TEST SUITE")
end

-- =============================================================================
-- File System Tests
-- =============================================================================
TestFileSystem = {}

function TestFileSystem:testCopyAndMove()
    log.debug("TEST: TestFileSystem:testCopyAndMove")
    
    local src = temp_dir / "file.txt"
    local dst = temp_dir / "file_copy.txt"
    
    fs_ext.writefile(src:str(), "content")
    lu.assertTrue(src:exists(), "Source file creation failed")
    
    local ok, err = fs.copy(src, dst)
    lu.assertTrue(ok, "fs.copy failed: " .. tostring(err))
    lu.assertTrue(dst:exists(), "Destination file not created")
    
    local dst2 = temp_dir / "file_moved.txt"
    local ok_mv, err_mv = fs.move(dst, dst2)
    lu.assertTrue(ok_mv, "fs.move failed")
    lu.assertFalse(dst:exists(), "Original file still exists")
    lu.assertTrue(dst2:exists(), "Moved file not found")
    
    fs.delete(dst2)
end

-- =============================================================================
-- PE API Tests
-- =============================================================================
TestPeApi = {}

function TestPeApi:testInitialize()
    log.debug("TEST: TestPeApi:testInitialize")
    
    local mock_user = temp_dir / "MockUser"
    mock_user:mkdir(true)
    
    local original_profile = os_ext.getenv("USERPROFILE")
    os_ext.setenv("USERPROFILE", mock_user:str())
    
    pe.initialize()
    
    local desktop_path = mock_user / "Desktop"
    lu.assertTrue(desktop_path:isdir(), "PE Initialize failed to create Desktop folder")
    
    if original_profile then
        os_ext.setenv("USERPROFILE", original_profile)
    end
end

-- =============================================================================
-- Process API Tests
-- =============================================================================
TestProcessApi = {}

function TestProcessApi:testExecAndTerminate()
    log.debug("TEST: TestProcessApi:testExecAndTerminate")
    local cmd = "ping.exe -n 100 127.0.0.1"
    
    local proc = process.exec_async({ command = cmd })
    lu.assertNotIsNil(proc, "exec_async returned nil")
    lu.assertNotIsNil(proc.pid, "Process object missing PID")
    
    async.sleep_blocking(500)
    
    local found = process.find("ping.exe")
    lu.assertNotIsNil(found, "Could not find process by name")
    
    lu.assertTrue(proc:terminate(0), "terminate(0) failed")
    
    local exited = process.wait_for_exit_pump(proc, 2000)
    lu.assertTrue(exited, "Process did not exit in time")
    
    if proc then proc:close() end
end

-- =============================================================================
-- Guardian Tests
-- =============================================================================
TestShellGuardian = {}

local function cleanup_guardian()
    process.kill_all_by_name("ping.exe")
    local self_pid = k32.GetCurrentProcessId()
    local pids = process.find_all("peshell.exe")
    for _, pid in ipairs(pids) do
        if pid ~= self_pid then 
            local p = process.find(tostring(pid))
            if p then p:terminate(0); p:close() end 
        end
    end
end

function TestShellGuardian:setUp() cleanup_guardian() end
function TestShellGuardian:tearDown() cleanup_guardian() end

function TestShellGuardian:testGuardianLifecycle()
    log.debug("TEST: TestShellGuardian:testGuardianLifecycle")
    
    local self_path = process.get_self_path()
    local target_cmd = "ping.exe -n 9999 127.0.0.1" 
    
    local uid = tostring(k32.GetCurrentProcessId()) .. "_" .. tostring(math.random(1000,9999))
    local ev_ready = "Global\\Ready_" .. uid
    local ev_respawn = "Global\\Respawn_" .. uid
    
    local h_ready = k32.CreateEventW(nil, 1, 0, to_w(ev_ready))
    local h_respawn = k32.CreateEventW(nil, 1, 0, to_w(ev_respawn))
    
    local script = "share/lua/5.1/test_guardian_init.lua"
    local args = string.format('"%s" main "%s" "%s" %s %s', 
        self_path, script, target_cmd, ev_ready, ev_respawn)
        
    local g_proc = process.exec_async({ command = args })
    lu.assertNotIsNil(g_proc, "Failed to launch guardian")
    
    local function wrap_h(h) return ffi.new("struct { void* h; }", { h = h }) end

    local idx = _G.pesh_native.wait_for_multiple_objects_blocking({ wrap_h(h_ready) }, 15000)
    lu.assertEquals(idx, 1, "Timeout waiting for READY")
    
    local p1 = process.find("ping.exe")
    lu.assertNotIsNil(p1, "Target process missing after READY")
    if p1 then p1:terminate(0); p1:close() end
    
    idx = _G.pesh_native.wait_for_multiple_objects_blocking({ wrap_h(h_respawn) }, 15000)
    lu.assertEquals(idx, 1, "Timeout waiting for RESPAWN")
    
    local p2 = process.find("ping.exe")
    lu.assertNotIsNil(p2, "Target process missing after RESPAWN")
    if p2 then p2:close() end
    
    local shut_cmd = string.format('"%s" shutdown', self_path)
    local s_proc = process.exec_async({ command = shut_cmd })
    if s_proc then 
        process.wait_for_exit_pump(s_proc, 5000)
        s_proc:close()
    end
    
    async.sleep_blocking(1000)
    
    if g_proc and g_proc:is_valid() then 
        g_proc:terminate(0)
        g_proc:close()
    end
    
    k32.CloseHandle(h_ready)
    k32.CloseHandle(h_respawn)
end

return lu.LuaUnit.run()