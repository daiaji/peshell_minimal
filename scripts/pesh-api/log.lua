-- pesh-api/log.lua
-- 提供一个简单、统一的日志接口给所有 Lua 脚本

local M = {}
-- [优化] 根据 LuaJIT FFI 性能指南，只缓存命名空间本身，
-- 而不是缓存单个函数。JIT 编译器能更好地优化对命名空间的直接访问。
local native = pesh_native

--[[
@description 记录一条 trace 级别的日志，用于非常详细的调试。
@param ...: 任意数量的参数，将被转换成字符串并拼接。
]]
function M.trace(...)
    native.log_trace(tostring(table.concat({ ... }, " ")))
end

--[[
@description 记录一条 debug 级别的日志，用于开发过程中的调试信息。
@param ...: 任意数量的参数。
]]
function M.debug(...)
    native.log_debug(tostring(table.concat({ ... }, " ")))
end

--[[
@description 记录一条 info 级别的日志，用于记录程序运行的关键信息。
@param ...: 任意数量的参数。
]]
function M.info(...)
    native.log_info(tostring(table.concat({ ... }, " ")))
end

--[[
@description 记录一条 warning 级别的日志，用于表示可能出现的问题。
@param ...: 任意数量的参数。
]]
function M.warn(...)
    native.log_warn(tostring(table.concat({ ... }, " ")))
end

--[[
@description 记录一条 error 级别的日志，用于记录已发生的错误。
@param ...: 任意数量的参数。
]]
function M.error(...)
    native.log_error(tostring(table.concat({ ... }, " ")))
end

--[[
@description 记录一条 critical 级别的日志，用于记录导致程序无法继续的严重错误。
@param ...: 任意数量的参数。
]]
function M.critical(...)
    native.log_critical(tostring(table.concat({ ... }, " ")))
end

return M