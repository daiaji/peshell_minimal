-- scripts/core/log.lua
-- 提供一个简单、统一的日志接口给所有 Lua 脚本

local M = {}
local native = pesh_native

-- 内部辅助函数，使用 table.pack 安全地处理可变参数
local function pack_and_concat(...)
    local args = table.pack(...)
    if args.n == 0 then return "" end

    for i = 1, args.n do
        args[i] = tostring(args[i])
    end
    return table.concat(args, " ", 1, args.n)
end

function M.trace(...)
    native.log_trace(pack_and_concat(...))
end

function M.debug(...)
    native.log_debug(pack_and_concat(...))
end

function M.info(...)
    native.log_info(pack_and_concat(...))
end

function M.warn(...)
    native.log_warn(pack_and_concat(...))
end

function M.error(...)
    native.log_error(pack_and_concat(...))
end

function M.critical(...)
    native.log_critical(pack_and_concat(...))
end

return M