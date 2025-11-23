-- scripts/prelude.lua
-- PEShell 自动预加载脚本 (Lua-Ext & FFI-Bindings Ready)

-- 1. 设置模块加载路径
do
    local exe_dir = assert(_G.PESHELL_EXE_DIR, "CRITICAL: PESHELL_EXE_DIR not set by host.")
    local package_root = exe_dir:match("(.*[/\\])bin[/\\]?$")
    local scripts_dir = package_root .. 'share/lua/5.1'
    
    local path_template = {
        scripts_dir .. '/?.lua',
        scripts_dir .. '/?/init.lua',
        scripts_dir .. '/lib/?.lua',
        scripts_dir .. '/lib/?/init.lua',
        scripts_dir .. '/core/?.lua',
    }
    package.path = table.concat(path_template, ';') .. ';' .. package.path
    package.cpath = exe_dir .. '/?.dll;' .. package.cpath
end

-- 2. 初始化核心环境 (Lua-Ext)
-- 必须尽早加载，它会修正 arg 表和 Windows Console CP (65001)
local status, ext = pcall(require, 'ext.ext')
if not status then
    io.stderr:write("CRITICAL: Failed to load 'ext.ext'. Ensure 'lua-ext' is in 'lib/ext'.\n")
    io.stderr:write(tostring(ext) .. "\n")
    os.exit(1)
end

-- 3. 初始化日志 (现在可以安全打印中文了)
_G.log = require("core.log")

-- 4. 构建 pesh 全局对象
_G.pesh = {
    plugin = require("core.plugin")
}

-- 5. 定义全局命令注册函数
_G.PESHELL_COMMANDS = {}
function _G.RegisterCommand(name, implementation)
    if _G.PESHELL_COMMANDS[name] then
        log.warn("Command '", name, "' is being redefined.")
    end
    _G.PESHELL_COMMANDS[name] = implementation
end

-- 6. 定义内置核心命令
RegisterCommand("run", function(args)
    if not args.cmd or #args.cmd < 1 then
        log.error("run: Missing script path.")
        return 1
    end
    local script_path = table.remove(args.cmd, 1)
    _G.arg = args.cmd 
    
    -- ext.ext 修复了 loadfile/dofile 的 unicode 支持
    local status, ret = xpcall(dofile, debug.traceback, script_path)
    if not status then
        log.error("Error running script '", script_path, "':\n", tostring(ret))
        return 1
    end
    return tonumber(ret) or 0
end)

RegisterCommand("main", function(args)
    if not args.cmd or #args.cmd < 1 then
        log.error("main: Missing init script path.")
        return 1
    end
    local script_path = table.remove(args.cmd, 1)
    _G.arg = args.cmd
    
    local status, err = xpcall(dofile, debug.traceback, script_path)
    if not status then
        log.error("Error in main script '", script_path, "':\n", tostring(err))
        return 1
    end
    return 0 
end)

-- 7. 核心命令分发器
function _G.DispatchCommand(...)
    local cmd_args = table.pack(...)
    
    if cmd_args.n == 0 or cmd_args[1] == "help" then
        print([[
PEShell v7.0 (Lua-Ext Edition)

Usage: peshell.exe <command> [arguments...]

Available Commands:
  run, main, shel, shutdown, exec, kill, killtree, init, help
]])
        return 0
    end

    local cmd_name = table.remove(cmd_args, 1)
    local command_handler = PESHELL_COMMANDS[cmd_name]
    
    if not command_handler then
        log.debug("Command '", cmd_name, "' not found. Lazy-loading...")
        local load_ok, err = pcall(pesh.plugin.load, cmd_name)
        if load_ok then
            command_handler = PESHELL_COMMANDS[cmd_name]
        else
            log.error("Failed to load plugin '", cmd_name, "': ", err)
        end
    end
    
    if not command_handler then
        log.error("Unknown command '", cmd_name, "'.")
        return 1
    end
    
    local args_table = { cmd = { table.unpack(cmd_args, 1, cmd_args.n) } }
    local status, retcode = pcall(command_handler, args_table)
    
    if not status then
        log.error("Error executing command '", cmd_name, "': ", tostring(retcode))
        return 1
    end
    
    return tonumber(retcode) or 0
end

log.info("Prelude: Lua-Ext environment initialized. Unicode support active.")