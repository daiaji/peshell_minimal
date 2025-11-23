-- scripts/test_guardian_init.lua
-- 守护进程生命周期测试脚本 (适配插件系统)

local log = _G.log
-- 确保 shell 插件已加载
local shell = _G.pesh.plugin.load("shell")

log.info("TEST GUARDIAN: Minimal init script started.")

-- _G.arg 由 prelude.lua 注入
local args = _G.arg or {}
local target_process_cmd = args[1]
local ready_event_name = args[2]
local respawn_event_name = args[3]

if not target_process_cmd then
    log.critical("TEST GUARDIAN: No target command provided.")
    return
end

log.info("TEST GUARDIAN: Locking shell: '", target_process_cmd, "'")

-- 调用 shell 插件的守护逻辑
shell.lock_shell(target_process_cmd, {
    ready_event_name = ready_event_name,     -- 首次启动成功后触发的事件
    respawn_event_name = respawn_event_name, -- 进程重生后触发的事件
    strategy = "takeover"                    -- 强制接管策略
})

log.info("TEST GUARDIAN: Dispatched. Script ending, host remains.")