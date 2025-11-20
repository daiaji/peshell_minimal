-- scripts/test_suite.lua
-- PEShell API Test Suite (v14.0 - Native proc_utils OOP)

local lu = require("luaunit")
local log = _G.log
local pesh = _G.pesh
local ffi = pesh.ffi
local native = _G.pesh_native
local path = require("pl.path")
local dir = require("pl.dir")

local process = pesh.plugin.load("process")
local pe = pesh.plugin.load("pe")
local k32 = pesh.plugin.load("winapi.kernel32")

local temp_dir = path.join(os.getenv("TEMP") or ".", "_peshell_test_temp")

function setupSuite()
    log.info("STARTING TEST SUITE")
    if path.isdir(temp_dir) then dir.rmtree(temp_dir) end
    dir.makepath(temp_dir)
end

function teardownSuite()
    if path.isdir(temp_dir) then dir.rmtree(temp_dir) end
    log.info("FINISHED TEST SUITE")
end

-- PE API Tests
TestPeApi = {}
function TestPeApi:testInitialize()
    log.debug("TEST: TestPeApi:testInitialize")
    local mock_user = path.join(temp_dir, "MockUser")
    k32.SetEnvironmentVariableW(ffi.to_wide("USERPROFILE"), ffi.to_wide(mock_user))
    pe.initialize()
    lu.assertTrue(path.isdir(path.join(mock_user, "Desktop")))
    k32.SetEnvironmentVariableW(ffi.to_wide("USERPROFILE"), nil)
end

-- Process API Tests
TestProcessApi = {}
function TestProcessApi:testExecAndTerminate()
    log.debug("TEST: TestProcessApi:testExecAndTerminate")
    local cmd = "ping.exe -t 127.0.0.1"
    local name = "ping.exe"
    
    -- 1. Exec
    local proc = process.exec_async({ command = cmd })
    lu.assertNotIsNil(proc, "exec_async returned nil")
    lu.assertTrue(proc.pid > 0, "Invalid PID")
    -- 验证 handle() 方法返回非空 cdata
    lu.assertNotIsNil(proc:handle(), "Invalid handle from proc:handle()")
    
    native.sleep(1000)
    
    -- 2. Find
    local found = process.find(name)
    lu.assertNotIsNil(found, "Could not find process by name")
    
    -- 3. Terminate (New API: terminate instead of kill)
    lu.assertTrue(proc:terminate(0), "terminate(0) failed")
    
    -- 4. Wait (New API: wait_for_exit synchronous method)
    local exited = proc:wait_for_exit(5000)
    lu.assertTrue(exited, "Process did not exit in time")
end

-- Guardian Tests
TestShellGuardian = {}

local function cleanup()
    -- 清理可能残留的 ping.exe
    process.kill_all_by_name("ping.exe")
    
    -- 清理残留的守护进程 peshell.exe
    local self_pid = k32.GetCurrentProcessId()
    local pids = process.find_all("peshell.exe")
    for _, pid in ipairs(pids) do
        if pid ~= self_pid then 
            local p = process.find(tostring(pid))
            if p then p:terminate(0) end 
        end
    end
end

function TestShellGuardian:setUp() cleanup() end
function TestShellGuardian:tearDown() cleanup() end

function TestShellGuardian:testGuardianLifecycle()
    log.debug("TEST: TestShellGuardian:testGuardianLifecycle")
    local self_path = process.get_self_path()
    local target_cmd = "ping.exe -t 127.0.0.1"
    local target_name = "ping.exe"

    local uid = tostring(k32.GetCurrentProcessId()) .. "_" .. tostring(math.random(1000,9999))
    local ev_ready = "Global\\TestReady_" .. uid
    local ev_respawn = "Global\\TestRespawn_" .. uid
    
    -- 创建测试用的事件句柄
    local h_ready = ffi.EventHandle(k32.CreateEventW(nil, 1, 0, ffi.to_wide(ev_ready)))
    local h_respawn = ffi.EventHandle(k32.CreateEventW(nil, 1, 0, ffi.to_wide(ev_respawn)))
    
    local script = "share/lua/5.1/test_guardian_init.lua"
    local guardian_args = string.format('"%s" main "%s" "%s" %s %s', 
        self_path, script, target_cmd, ev_ready, ev_respawn)
        
    -- 1. 启动外部 Guardian
    local g_proc = process.exec_async({ command = guardian_args })
    lu.assertNotIsNil(g_proc, "Failed to launch guardian")
    
    -- 2. 等待 READY 信号
    local idx = native.wait_for_multiple_objects_blocking({ h_ready }, 15000)
    lu.assertEquals(idx, 1, "Timeout waiting for READY signal")
    
    -- 验证目标进程已启动
    local p1 = process.find(target_name)
    lu.assertNotIsNil(p1, "Target process should be running after READY")
    
    -- 3. 杀死目标进程以触发重生
    p1:terminate(0)
    
    -- 4. 等待 RESPAWN 信号
    idx = native.wait_for_multiple_objects_blocking({ h_respawn }, 15000)
    lu.assertEquals(idx, 1, "Timeout waiting for RESPAWN signal")
    
    local p2 = process.find(target_name)
    lu.assertNotIsNil(p2, "Target process should have been respawned")
    lu.assertNotEquals(p1.pid, p2.pid, "Respawned PID should be different")
    
    -- 5. 发送 Shutdown 命令
    local shut_cmd = string.format('"%s" shutdown', self_path)
    local s_proc = process.exec_async({ command = shut_cmd })
    if s_proc then s_proc:wait_for_exit(5000) end
    
    native.sleep(2000)
    
    -- 验证 Guardian 和 Target 都已退出
    lu.assertIsNil(process.find(target_name), "Target should be gone after shutdown")
    
    -- 清理 g_proc 句柄 (虽然不是必须的，因为是外部进程)
    if g_proc:is_valid() then g_proc:terminate(0) end
end

return lu.LuaUnit.run()