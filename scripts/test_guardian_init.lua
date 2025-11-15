-- scripts/test_guardian_init.lua
-- 一个极简的初始化脚本，专用于自动化测试守护进程的生命周期。

local log = require("pesh-api.log")
local shell = require("pesh-api.shell")

log.info("TEST GUARDIAN: Minimal init script started.")

-- 从 _G.arg 全局表中获取由 C++ 宿主传递的命令行参数
local args = _G.arg or {}
local target_process_cmd = args[1]
local ready_event_name = args[2]
local respawn_event_name = args[3] -- 新增：接收重生事件名称

if not target_process_cmd then
    log.critical("TEST GUARDIAN: No target process command was provided in the arguments.")
    return
end

log.info("TEST GUARDIAN: Locking shell with command: '", target_process_cmd, "'")
if ready_event_name then
    log.info("TEST GUARDIAN: Will signal readiness on event: '", ready_event_name, "'")
end
if respawn_event_name then
    log.info("TEST GUARDIAN: Will signal respawns on event: '", respawn_event_name, "'")
end

-- [关键] 将收到的参数打包成 options 表并显式传递
shell.lock_shell(target_process_cmd, {
    ready_event_name = ready_event_name,
    respawn_event_name = respawn_event_name
})

log.info("TEST GUARDIAN: Guardian dispatched. This script will now finish, but the host process will remain active.")