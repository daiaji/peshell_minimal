-- scripts/test_guardian_init.lua
-- 一个极简的初始化脚本，专用于自动化测试守护进程的生命周期。(适配插件系统)

local log = _G.log
local shell = _G.pesh.plugin.load("shell")

log.info("TEST GUARDIAN: Minimal init script started.")

local args = _G.arg or {}
local target_process_cmd = args[1]
local ready_event_name = args[2]
local respawn_event_name = args[3]

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

shell.lock_shell(target_process_cmd, {
    ready_event_name = ready_event_name,
    respawn_event_name = respawn_event_name
})

log.info("TEST GUARDIAN: Guardian dispatched. This script will now finish, but the host process will remain active.")