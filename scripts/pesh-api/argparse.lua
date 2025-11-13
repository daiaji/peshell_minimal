-- scripts/pesh-api/argparse.lua
-- 一个支持 GNU 风格长选项的命令行参数解析器

local M = {}

---
-- 解析命令行参数
-- @param args table: 从命令行传入的参数数组 (如 Lua 的 `...` 或 `arg`)
-- @param spec table: 参数规格定义表。
--        格式: { {long_name, short_name, type, description, default_value}, ... }
--        - long_name (string): 长选项名, e.g., "wait"
--        - short_name (string|nil): 短选项名, e.g., "w"
--        - type (string): "boolean", "string", "number"
--        - description (string): 帮助文本
--        - default_value (any|nil): 选项的默认值
-- @return table, table: options 表和 positional_args 数组
function M.parse(args, spec)
    local options = {}
    local positional_args = {}
    local spec_map_long = {}
    local spec_map_short = {}

    -- 1. 初始化默认值并构建快速查找表
    if spec then
        for _, def in ipairs(spec) do
            local long_name, short_name, _, _, default_value = unpack(def)
            if default_value ~= nil then
                options[long_name] = default_value
            end
            spec_map_long[long_name] = def
            if short_name then
                spec_map_short[short_name] = def
            end
        end
    end

    -- 2. 遍历参数进行解析
    local i = 1
    while i <= #args do
        local arg = args[i]
        local def = nil
        local value_provided_with_equal = nil
        local option_name = nil

        if arg:sub(1, 2) == "--" then
            -- 长选项, e.g., --wait or --desktop=Winlogon
            local base_arg = arg:match("^--([^=]+)")
            value_provided_with_equal = arg:match("^--[^=]+=(.*)")
            def = spec_map_long[base_arg]
            option_name = base_arg
        elseif arg:sub(1, 1) == "-" and #arg > 1 then
            -- 短选项, e.g., -w
            local base_arg = arg:sub(2)
            def = spec_map_short[base_arg]
            option_name = base_arg
        end

        if def then
            -- 这是一个已定义的选项
            local long_name, _, type = unpack(def)
            if type == "boolean" then
                options[long_name] = true
                i = i + 1
            else
                -- 需要值的选项
                local value = value_provided_with_equal
                if not value then
                    -- 值在下一个参数中, e.g., --desktop Winlogon
                    if i + 1 > #args then
                        error("Option '" .. arg .. "' requires a value, but none was provided.")
                    end
                    value = args[i + 1]
                    i = i + 2
                else
                    i = i + 1
                end

                if type == "number" then
                    value = tonumber(value)
                    if not value then
                        error("Value for option '" .. arg .. "' must be a number.")
                    end
                end
                options[long_name] = value
            end
        else
            -- 未在 spec 中定义的选项或位置参数
            table.insert(positional_args, arg)
            i = i + 1
        end
    end

    return options, positional_args
end

return M