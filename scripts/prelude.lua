-- scripts/prelude.lua
-- PEShell 自动预加载脚本 (v5.0 - DLL Model & Simplified Dispatcher)

-- 1. 设置模块加载路径 (由 C++ 注入 PESHELL_EXE_DIR)
do
    local exe_dir = assert(_G.PESHELL_EXE_DIR, "CRITICAL: PESHELL_EXE_DIR not set by host application.")
    local lib_dir = exe_dir .. '/lib'
    
    -- 设置 Lua 脚本搜索路径
    package.path = table.concat({
        exe_dir .. '/scripts/?.lua',
        exe_dir .. '/scripts/?/init.lua',
        lib_dir .. '/?.lua',
        lib_dir .. '/?/init.lua',
        package.path
    }, ';')
    
    -- 设置 C 模块 (DLL) 搜索路径
    package.cpath = table.concat({
        exe_dir .. '/?.dll',      -- 在 exe 同级目录查找 (proc_utils.dll, lfs.dll, etc.)
        lib_dir .. '/?.dll',      -- 在 lib 目录查找 (未来可能的 C 模块)
        package.cpath
    }, ';')
end

-- 2. 加载 Penlight 并使其准备好全局按需加载
local pl_status, pl = pcall(require, 'pl')
if not pl_status then
    print("CRITICAL ERROR: Failed to load Penlight: " .. tostring(pl))
    return
end

-- 3. 加载核心日志模块并全局化
local log_status, log_mod = pcall(require, "pesh-api.log")
if not log_status then
    print("CRITICAL ERROR: Failed to load core log module: " .. tostring(log_mod))
    return
end
_G.log = log_mod

-- 4. 初始化全局命令表和 API 命名空间
_G.PESHELL_COMMANDS = {}
_G.pesh = {}

-- 注册命令的辅助函数
function RegisterCommand(name, implementation)
    if _G.PESHELL_COMMANDS[name] then
        log.warn("Command '", name, "' is being redefined.")
    end
    _G.PESHELL_COMMANDS[name] = implementation
end

-- 5. 扫描并加载所有 pesh-api 模块
local function load_api_modules()
    log.info("Prelude: Scanning for API modules...")
    -- 注意：这里的 lfs 是动态加载的 lfs.dll
    local lfs = require("lfs")
    local api_path = _G.PESHELL_EXE_DIR .. "/scripts/pesh-api"
    
    for file in lfs.dir(api_path) do
        if file:match("%.lua$") then
            local module_name = file:gsub("%.lua$", "")
            log.trace("Prelude: Loading API module '", module_name, "'...")
            local status, mod = pcall(require, "pesh-api." .. module_name)
            if status then
                if type(mod) == "table" and mod.__commands then
                    log.debug("Prelude: Registering commands from '", module_name, "'...")
                    for cmd_name, cmd_func in pairs(mod.__commands) do
                        RegisterCommand(cmd_name, cmd_func)
                        log.trace("  - Command '", cmd_name, "' registered.")
                    end
                end
                pesh[module_name] = mod
            else
                log.error("Prelude: Failed to load API module '", module_name, "': ", tostring(mod))
            end
        end
    end
end
load_api_modules()

-- 6. 定义核心命令
RegisterCommand("run", function(args)
    if not args.cmd or #args.cmd < 1 then
        log.error("run: Missing script path.")
        return 1
    end
    local script_path = table.remove(args.cmd, 1)
    _G.arg = args.cmd -- 剩下的作为参数
    
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
    
    local status, ret = xpcall(dofile, debug.traceback, script_path)
    if not status then
        log.error("Error in main script '", script_path, "':\n", tostring(ret))
        return 1
    end
    return 0 -- 成功时必须返回 0，让 C++ Host 进入消息循环
end)

RegisterCommand("shutdown", function()
    local shutdown_script = _G.PESHELL_EXE_DIR .. "/scripts/shutdown.lua"
    return dofile(shutdown_script)
end)

-- 7. 核心命令分发器 (简化版)
function _G.DispatchCommand(...)
    local cmd_args = {...}
    
    local help_message = [[
PEShell v5.0 (DLL Model) - A modular WinPE automation engine.

Usage: peshell.exe <command> [arguments...]

Available Commands:
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

    if #cmd_args == 0 or cmd_args[1] == "help" then
        print(help_message)
        return 0
    end

    local cmd_name = table.remove(cmd_args, 1)
    local command_handler = PESHELL_COMMANDS[cmd_name]
    
    if not command_handler then
        log.error("Unknown command '", cmd_name, "'. Use 'help' to see available commands.")
        return 1
    end

    -- 构造一个简单的 args 表，包含所有剩余参数
    local args_table = { cmd = cmd_args }
    -- (为了兼容性，可以解析简单的 -w, -h 等标志)
    -- 此处为简化模型，所有参数都在 args_table.cmd 中
    
    local status, retcode = pcall(command_handler, args_table)
    
    if not status then
        log.error("Error executing command '", cmd_name, "': ", tostring(retcode))
        return 1
    end
    
    return retcode or 0
end

log.info("Prelude: Initialization complete. Ready to dispatch command.")