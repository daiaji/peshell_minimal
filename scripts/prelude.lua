-- scripts/prelude.lua
-- PEShell 自动预加载脚本
-- 职责：
-- 1. 创建全局命名空间和命令注册表。
-- 2. 自动扫描并加载所有 API 模块。
-- 3. 自动注册模块声明的子命令。
-- 4. 注册框架级的核心命令 (main, run, help)。

-- 创建全局的命令注册表和 API 命名空间
_G.PESHELL_COMMANDS = {}
_G.pesh = {}

-- 引入日志作为第一个 API
-- 这里使用 pcall 是为了在日志模块本身出错时也能提供反馈
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

for file in lfs.dir(api_path) do
    -- 确保是 lua 文件，且不是自身(如果prelude也在api目录)或其他特殊文件
    if file:match("%.lua$") then
        local module_name = file:gsub("%.lua$", "")
        pesh.log.trace("Prelude: Loading API module '", module_name, "'...")

        -- 使用 pcall 保护加载过程，防止一个模块的错误影响整个程序
        local status, mod = pcall(require, "pesh-api." .. module_name)
        if status then
            -- 约定：如果模块返回一个 table，并且 table 中有 `__commands` 字段，
            -- 那么就自动注册这些命令。
            if type(mod) == "table" and mod.__commands then
                pesh.log.debug("Prelude: Registering commands from module '", module_name, "'...")
                for cmd_name, cmd_func in pairs(mod.__commands) do
                    RegisterCommand(cmd_name, cmd_func)
                    pesh.log.trace("  - Command '", cmd_name, "' registered.")
                end
            end
            -- 将模块本身也挂载到 pesh 命名空间下，供脚本内部调用
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
-- PE 环境的守护入口，加载并执行初始化脚本。
-- @param ...: 命令行参数，第一个应为初始化脚本的路径
local function main_command(...)
    local args = { ... }
    local init_script = args[1]

    if not init_script then
        pesh.log.critical("main: No initialization script specified. Aborting.")
        return
    end

    pesh.log.info("main: Starting PE guardian mode with script '", init_script, "'.")

    -- 使用 dofile 执行初始化脚本
    local success, err = pcall(dofile, init_script)
    if not success then
        pesh.log.critical("main: An error occurred while executing the initialization script '", init_script, "':\n",
            tostring(err))
    end
end

---
-- 子命令：run
-- 执行一个 peshell (lua) 脚本。
-- @param ...: 脚本路径和传递给脚本的参数
local function run_command(...)
    local args = { ... }
    if #args == 0 then
        pesh.log.error("run: No script file specified.")
        return
    end

    local script_to_run = table.remove(args, 1)

    -- 将剩余的参数放入全局 'arg' 表中，供被调用的脚本使用
    _G.arg = args

    local success, err = pcall(dofile, script_to_run)
    if not success then
        pesh.log.error("run: An error occurred while running script '", script_to_run, "':\n", tostring(err))
    end
end

---
-- 子命令：help (默认命令)
-- 显示帮助信息。
local function help_command()
    -- 我们可以在这里动态生成帮助信息，列出所有已注册的命令
    local help_text = [[
PEShell v3.1 - A fully modular WinPE automation engine.

Usage:
  peshell.exe <command> [options] [arguments]

Available Commands:
]]
    -- 对命令进行排序以获得更好的输出
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
end

-- 注册框架级命令
RegisterCommand("main", main_command)
RegisterCommand("run", run_command)
RegisterCommand("help", help_command)

pesh.log.info("Prelude: Framework commands registered.")
