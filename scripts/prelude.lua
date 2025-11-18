-- scripts/prelude.lua (v6.3 - Modernized Path Setup)
-- PEShell 自动预加载脚本

-- 1. 设置模块加载路径
do
    local exe_dir = assert(_G.PESHELL_EXE_DIR, "CRITICAL: PESHELL_EXE_DIR not set by host.")
    -- <package_root>/bin -> <package_root>/
    local package_root = exe_dir:match("(.*[/\\])bin[/\\]?$")
    local scripts_dir = package_root .. 'share/lua/5.1'
    local luarocks_dir = package_root .. 'share/lua/5.1'
    
    -- [利用 Lua 5.2+ 兼容特性] 使用更清晰的模板方式构建路径，避免复杂的单行拼接
    local path_template = {
        scripts_dir .. '/?.lua',          -- For top-level scripts like test_suite
        scripts_dir .. '/?/init.lua',     -- For plugin packages
        scripts_dir .. '/core/?.lua',     -- For core modules
        -- [[ 新增 ]] 支持 lib 目录下的纯 Lua 第三方库
        scripts_dir .. '/lib/?.lua',      
        luarocks_dir .. '/?.lua',         -- For LuaRocks dependencies (e.g., pl)
        luarocks_dir .. '/?/init.lua',
    }
    package.path = table.concat(path_template, ';') .. ';' .. package.path
    
    local cpath_template = {
        exe_dir .. '/?.dll',              -- For C modules like lfs.dll
    }
    package.cpath = table.concat(cpath_template, ';') .. ';' .. package.cpath
end

-- 2. 加载并全局化核心服务
_G.log = require("core.log")
_G.pesh = {
    ffi = require("core.ffi"),
    plugin = require("core.plugin")
}

-- 3. 定义全局命令注册函数
_G.PESHELL_COMMANDS = {}
function _G.RegisterCommand(name, implementation)
    if _G.PESHELL_COMMANDS[name] then
        log.warn("Command '", name, "' is being redefined.")
    end
    _G.PESHELL_COMMANDS[name] = implementation
end

-- 4. 定义内置核心命令 (这些命令自身不依赖功能插件)
RegisterCommand("run", function(args)
    if not args.cmd or #args.cmd < 1 then
        log.error("run: Missing script path.")
        return 1
    end
    local script_path = table.remove(args.cmd, 1)
    _G.arg = args.cmd -- The rest are arguments for the script
    
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
    return 0 -- Must return 0 to let C++ host enter the message loop
end)

-- 5. 核心命令分发器
function _G.DispatchCommand(...)
    local cmd_args = table.pack(...)
    
    local help_message = [[
PEShell v6.2 (Plugin Model) - A modular WinPE automation engine.

Usage: peshell.exe <command> [arguments...]

Available Commands (dynamically loaded on first use):
  run <script> [<args...>]   Execute a Lua script.
  main <script> [<args...>]  Run in PE guardian mode with an init script.
  shel [--adopt] <cmd...>    Lock a program as the system shell.
  shutdown                   Signal the guardian process to exit gracefully.
  exec [-w] [-h] ... <cmd>   Execute an external program.
  kill <name_or_pid...>      Terminate one or more processes.
  killtree <name_or_pid...>  Terminate a process and its entire process tree.
  init                       Initialize the PE user environment.
  help                       Show this help message.
]]

    if cmd_args.n == 0 or cmd_args[1] == "help" then
        print(help_message)
        return 0
    end

    local cmd_name = table.remove(cmd_args, 1)
    local command_handler = PESHELL_COMMANDS[cmd_name]
    
    if not command_handler then
        log.debug("Command '", cmd_name, "' not found. Attempting to lazy-load as plugin...")
        local load_ok, loaded_module_or_err = pcall(pesh.plugin.load, cmd_name)
        if load_ok then
            command_handler = PESHELL_COMMANDS[cmd_name] -- Re-check if the plugin registered the command
        else
            log.error("Failed to load plugin for command '", cmd_name, "': ", tostring(loaded_module_or_err))
        end
    end
    
    if not command_handler then
        log.error("Unknown command '", cmd_name, "'. Use 'help' to see available commands.")
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

log.info("Prelude: Core services initialized. Ready for command dispatch and lazy loading.")