-- scripts/prelude.lua
-- PEShell 自动预加载脚本 (v5.3 - Self-Contained & Optimized)

-- 1. 设置模块加载路径
do
    -- PESHELL_EXE_DIR 由 C++ 宿主设置为 <package_root>/bin
    local exe_dir = assert(_G.PESHELL_EXE_DIR, "CRITICAL: PESHELL_EXE_DIR not set by host application.")
    
    -- 在自包含模型中，所有 Lua 模块都在 bin 目录的兄弟目录 share/ 下
    -- 注意：在 Lua 中，'..' 用于路径操作时代表上级目录
    local share_dir = exe_dir .. '/../share'

    -- package.path 用于搜索 .lua 文件 (我们自己的模块和依赖项都在这里)
    package.path = table.concat({
        share_dir .. '/lua/5.1/?.lua',
        share_dir .. '/lua/5.1/?/init.lua',
        package.path
    }, ';')
    
    -- package.cpath 用于搜索 .dll 文件 (所有 C 模块都已被 CI 流程统一放到 bin 目录)
    package.cpath = table.concat({
        exe_dir .. '/?.dll',
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
    local lfs = require("lfs")
    
    -- [[ 核心优化 ]]
    -- 在自包含结构中，我们可以直接构建 pesh-api 目录的路径。
    -- `debug.getinfo(1,"S").source` 获取当前文件的路径信息。
    local current_script_path = debug.getinfo(1,"S").source:match("^@?(.*)")
    -- 从文件路径中提取目录路径
    local current_dir = current_script_path:match("(.*[/\\])")
    local api_path = current_dir .. "pesh-api"
    
    if lfs.attributes(api_path, "mode") ~= "directory" then
        log.error("Prelude: Could not find 'pesh-api' directory at '", api_path, "'.")
        return
    end

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
    local shutdown_script_path = package.searchpath("shutdown", package.path)
    if not shutdown_script_path then
        log.error("Could not find shutdown.lua")
        return 1
    end
    return dofile(shutdown_script_path)
end)

-- 7. 核心命令分发器 (简化版)
function _G.DispatchCommand(...)
    local cmd_args = {...}
    
    local help_message = [[
PEShell v5.5 (Self-Contained Model) - A modular WinPE automation engine.

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
    
    local args_table = { cmd = cmd_args }
    
    local status, retcode = pcall(command_handler, args_table)
    
    if not status then
        log.error("Error executing command '", cmd_name, "': ", tostring(retcode))
        return 1
    end
    
    return retcode or 0
end

log.info("Prelude: Initialization complete. Ready to dispatch command.")