-- scripts/test_suite.lua
-- PEShell API Test Suite (Refactored for Lua-Ext & FFI-Bindings)
-- Version: 9.1 (Fix USERPROFILE path separators)

local lu = require("luaunit")
local log = _G.log
local pesh = _G.pesh
local ffi = require("ffi")

-- [DEPENDENCY] Lua-Ext
local path = require("ext.path")
local os_ext = require("ext.os")
local fs_ext = require("ext.io")

-- [DEPENDENCY] FFI Bindings
require("ffi.req")("Windows.sdk.kernel32")
local k32 = ffi.load("kernel32")

-- [FIX] Explicitly define used APIs
ffi.cdef[[
    int SetEnvironmentVariableW(const wchar_t* lpName, const wchar_t* lpValue);
    void* CreateEventW(void* lpEventAttributes, int bManualReset, int bInitialState, const wchar_t* lpName);
    int CloseHandle(void* hObject);
    unsigned long GetTickCount(void);
    unsigned long GetCurrentProcessId();
]]

-- [DEPENDENCY] Plugins
local process = pesh.plugin.load("process")
local pe = pesh.plugin.load("pe")
local fs = pesh.plugin.load("fs")
local async = pesh.plugin.load("async")

-- [HELPER] Unicode Conversion
local function to_w(str)
    if not str then return nil end
    local CP_UTF8 = 65001
    local len = ffi.C.MultiByteToWideChar(CP_UTF8, 0, str, -1, nil, 0)
    local buf = ffi.new("wchar_t[?]", len)
    ffi.C.MultiByteToWideChar(CP_UTF8, 0, str, -1, buf, len)
    return buf
end

local safe_handle_mt = {
    __gc = function(t)
        if t.h and t.h ~= nil and t.h ~= ffi.cast("void*", -1) then
            ffi.C.CloseHandle(t.h)
            t.h = nil
        end
    end
}
local function AutoHandle(raw_h)
    return setmetatable({ h = raw_h }, safe_handle_mt)
end

-- [SETUP] Temporary Directory
local temp_dir = path(os.getenv("TEMP") or ".") / "_peshell_test_temp"

local function safe_setup()
    log.info("STARTING TEST SUITE")
    local dir_str = tostring(temp_dir)
    
    if temp_dir:exists() then 
        local ok, err = fs.delete(dir_str)
        if not ok then
            error("Failed to clean temp dir: " .. tostring(err))
        end
    end
    
    local ok, err = fs.mkdir(dir_str)
    if not ok then
        if not temp_dir:exists() then
            error("Failed to create temp dir: " .. tostring(err))
        end
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
    if temp_dir:exists() then 
        fs.delete(tostring(temp_dir)) 
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
    
    fs_ext.writefile(tostring(src), "content")
    lu.assertTrue(src:exists(), "Source file creation failed")
    
    local ok, err = fs.copy(tostring(src), tostring(dst))
    lu.assertTrue(ok, "fs.copy failed: " .. tostring(err))
    lu.assertTrue(dst:exists(), "Destination file not created")
    
    local dst2 = temp_dir / "file_moved.txt"
    local ok_mv, err_mv = fs.move(tostring(dst), tostring(dst2))
    lu.assertTrue(ok_mv, "fs.move failed: " .. tostring(err_mv))
    
    lu.assertFalse(dst:exists(), "Original file still exists after move")
    lu.assertTrue(dst2:exists(), "Moved file not found")
    
    local ok_del, err_del = fs.delete(tostring(dst2))
    lu.assertTrue(ok_del, "fs.delete failed: " .. tostring(err_del))
    lu.assertFalse(dst2:exists(), "Deleted file still exists")
end

-- =============================================================================
-- PE API Tests
-- =============================================================================
TestPeApi = {}

function TestPeApi:testInitialize()
    log.debug("TEST: TestPeApi:testInitialize")
    
    local mock_user = temp_dir / "MockUser"
    
    -- [FIX] Force Windows backslashes for USERPROFILE to ensure compatibility
    local mock_user_win = tostring(mock_user):gsub("/", "\\")
    
    k32.SetEnvironmentVariableW(to_w("USERPROFILE"), to_w(mock_user_win))
    
    pe.initialize()
    
    local desktop_path = mock_user / "Desktop"
    lu.assertTrue(desktop_path:isdir(), "PE Initialize failed to create Desktop folder: " .. tostring(desktop_path))
    
    k32.SetEnvironmentVariableW(to_w("USERPROFILE"), nil)
end

-- =============================================================================
-- Process API Tests
-- =============================================================================
TestProcessApi = {}

function TestProcessApi:testExecAndTerminate()
    log.debug("TEST: TestProcessApi:testExecAndTerminate")
    local cmd = "ping.exe -n 100 127.0.0.1"
    local name = "ping.exe"
    
    local proc = process.exec_async({ command = cmd })
    lu.assertNotIsNil(proc, "exec_async returned nil")
    lu.assertNotIsNil(proc.pid, "Process object missing PID")
    
    local h = proc:handle()
    lu.assertNotIsNil(h, "Invalid handle from proc:handle()")
    
    async.sleep_blocking(1000)
    
    local found = process.find(name)
    lu.assertNotIsNil(found, "Could not find process by name")
    lu.assertTrue(found:is_valid(), "Found process handle is invalid")
    
    lu.assertTrue(proc:terminate(0), "terminate(0) failed")
    
    local exited = process.wait_for_exit_pump(proc, 5000)
    lu.assertTrue(exited, "Process did not exit in time")
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
            if p then p:terminate(0) end 
        end
    end
end

function TestShellGuardian:setUp() cleanup_guardian() end
function TestShellGuardian:tearDown() cleanup_guardian() end

function TestShellGuardian:testGuardianLifecycle()
    log.debug("TEST: TestShellGuardian:testGuardianLifecycle")
    
    local self_path = process.get_self_path()
    local target_cmd = "ping.exe -n 9999 127.0.0.1" 
    local target_name = "ping.exe"

    local uid = tostring(k32.GetCurrentProcessId()) .. "_" .. tostring(math.random(1000,9999))
    local ev_ready_name = "Global\\TestReady_" .. uid
    local ev_respawn_name = "Global\\TestRespawn_" .. uid
    
    local raw_h_ready = k32.CreateEventW(nil, 1, 0, to_w(ev_ready_name))
    local raw_h_respawn = k32.CreateEventW(nil, 1, 0, to_w(ev_respawn_name))
    
    local h_ready = AutoHandle(raw_h_ready)
    local h_respawn = AutoHandle(raw_h_respawn)
    
    local script = "share/lua/5.1/test_guardian_init.lua"
    local guardian_args = string.format('"%s" main "%s" "%s" %s %s', 
        self_path, script, target_cmd, ev_ready_name, ev_respawn_name)
        
    local g_proc = process.exec_async({ command = guardian_args })
    lu.assertNotIsNil(g_proc, "Failed to launch guardian")
    
    local idx = _G.pesh_native.wait_for_multiple_objects_blocking({ h_ready }, 15000)
    lu.assertEquals(idx, 1, "Timeout waiting for READY signal")
    
    local p1 = process.find(target_name)
    lu.assertNotIsNil(p1, "Target process should be running after READY")
    
    p1:terminate(0)
    
    idx = _G.pesh_native.wait_for_multiple_objects_blocking({ h_respawn }, 15000)
    lu.assertEquals(idx, 1, "Timeout waiting for RESPAWN signal")
    
    local p2 = process.find(target_name)
    lu.assertNotIsNil(p2, "Target process should have been respawned")
    
    local shut_cmd = string.format('"%s" shutdown', self_path)
    local s_proc = process.exec_async({ command = shut_cmd })
    if s_proc then 
        process.wait_for_exit_pump(s_proc, 5000) 
    end
    
    async.sleep_blocking(2000)
    
    local p_gone = process.find(target_name)
    lu.assertIsNil(p_gone, "Target should be gone after shutdown")
    
    if g_proc:is_valid() then g_proc:terminate(0) end
end

return lu.LuaUnit.run()