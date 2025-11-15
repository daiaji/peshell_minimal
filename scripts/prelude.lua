-- scripts/prelude.lua
-- PEShell 自动预加载脚本
-- 职责：
-- 1. 创建全局命名空间和命令注册表。
-- 2. 自动扫描并加载所有 API 模块。
-- 3. 自动注册模块声明的子命令。
-- 4. 注册框架级的核心命令 (main, run, help)。

-- ########## 关键修复 ##########
-- 在使用 lfs 之前，必须先通过 require 加载它。
-- C++ 代码已经通过 package.preload 将其注册，所以这里可以直接调用。
local lfs = require("lfs")
-- ############################

-- 创建全局的命令注册表和 API 命名空间
_G.PESHELL_COMMANDS = {}
_G.pesh = {}

-- 引入日志作为第一个 API
local log_status, log_mod = pcall(require, "pesh-api.log")
if not log_status then
    print("CRITICAL ERROR: Failed to load core log module: " .. tostring(log_mod))
    return
end
pesh.log = log_mod

---
-- 全局函数，用于注册一个子命令
-- @param name string: 命令名
-- @param implementation function: 实现该命令的函数
function RegisterCommand(name, implementation)
    if _G.PESHELL_COMMANDS[name] then
        pesh.log.warn("Command '", name, "' is being redefined.")
    end
    _G.PESHELL_COMMANDS[name] = implementation
end

-- 自动扫描并加载所有 pesh-api 模块
-- 获取当前脚本所在的目录
local api_path = debug.getinfo(1, "S").source:match("@(.+)[\\/]") .. "pesh-api"
pesh.log.info("Prelude: Scanning for API modules in '", api_path, "'...")

-- 现在 lfs 已经加载，可以安全地调用 lfs.dir
for file in lfs.dir(api_path) do
    if file:match("%.lua$") then
        local module_name = file:gsub("%.lua$", "")
        pesh.log.trace("Prelude: Loading API module '", module_name, "'...")

        local status, mod = pcall(require, "pesh-api." .. module_name)
        if status then
            if type(mod) == "table" and mod.__commands then
                pesh.log.debug("Prelude: Registering commands from module '", module_name, "'...")
                for cmd_name, cmd_func in pairs(mod.__commands) do
                    RegisterCommand(cmd_name, cmd_func)
                    pesh.log.trace("  - Command '", cmd_name, "' registered.")
                end
            end
            pesh[module_name] = mod
        else
            pesh.log.error("Prelude: Failed to load API module '", module_name, "': ", tostring(mod))
        end
    end
end

pesh.log.info("Prelude: All API modules loaded and commands registered.")
pesh.log.info("Prelude: Registering framework-level commands...")

-- ### 框架级命令实现 ###

---
-- 子命令：main
local function main_command(...)
    local args = { ... }
    local init_script = args[1]
    if not init_script then
        pesh.log.critical("main: No initialization script specified. Aborting.")
        return 1
    end
    pesh.log.info("main: Starting PE guardian mode with script '", init_script, "'.")
    local success, err = pcall(dofile, init_script)
    if not success then
        pesh.log.critical("main: An error occurred while executing the initialization script '", init_script, "':\n", tostring(err))
        return 1
    end
    return 0
end

---
-- 子命令：run
local function run_command(...)
    local args = { ... }
    if #args == 0 then
        pesh.log.error("run: No script file specified.")
        return 1
    end
    local script_to_run = table.remove(args, 1)
    _G.arg = args
    local success, err = pcall(dofile, script_to_run)
    if not success then
        pesh.log.error("run: An error occurred while running script '", script_to_run, "':\n", tostring(err))
        return 1 -- 返回非零值表示错误
    end
    return 0 -- 返回0表示成功
end

---
-- 子命令：help
local function help_command()
    local help_text = [[
PEShell v3.1 - A fully modular WinPE automation engine.

Usage:
  peshell.exe <command> [options] [arguments]

Available Commands:
]]
    local sorted_commands = {}
    for cmd_name in pairs(_G.PESHELL_COMMANDS) do
        table.insert(sorted_commands, cmd_name)
    end
    table.sort(sorted_commands)
    for _, cmd_name in ipairs(sorted_commands) do
        help_text = help_text .. "  " .. cmd_name .. "\n"
    end
    help_text = help_text .. "\nRun 'peshell.exe' with no arguments to see this message."
    print(help_text)
    return 0
end

-- 注册框架级命令
RegisterCommand("main", main_command)
RegisterCommand("run", run_command)
RegisterCommand("help", help_command)

pesh.log.info("Prelude: Framework commands registered.")