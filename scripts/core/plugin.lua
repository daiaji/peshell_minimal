-- scripts/core/plugin.lua
-- 插件管理器，实现延迟加载和命令自动注册

local M = {}
local loaded_plugins = {} -- 缓存已加载的插件模块

---
-- 加载一个插件。
-- @param plugin_name string: 插件名称
-- @return table: 插件返回的模块表
function M.load(plugin_name)
    if loaded_plugins[plugin_name] then
        return loaded_plugins[plugin_name]
    end

    log.debug("Plugin: Loading '", plugin_name, "'...")
    
    local module_path = "plugins." .. plugin_name:gsub("[/\\]", ".")
    
    local status, plugin_module = pcall(require, module_path)

    if not status then
        error("Failed to load plugin '" .. plugin_name .. "': " .. tostring(plugin_module), 2)
    end
    
    -- 自动注册命令
    if type(plugin_module) == "table" and plugin_module.__commands then
        for cmd_name, cmd_func in pairs(plugin_module.__commands) do
            _G.RegisterCommand(cmd_name, cmd_func)
            log.trace("Plugin: Registered command '", cmd_name, "' from plugin '", plugin_name, "'.")
        end
    end

    loaded_plugins[plugin_name] = plugin_module
    log.info("Plugin: '", plugin_name, "' loaded successfully.")
    return plugin_module
end

return M