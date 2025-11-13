-- pesh-api/log.lua
-- 提供一个简单、统一的日志接口给所有 Lua 脚本

local M = {}
local native = pesh_native

-- 为了性能，将函数引用保存在局部变量中
local log_trace = native.log_trace
local log_debug = native.log_debug
local log_info = native.log_info
local log_warn = native.log_warn
local log_error = native.log_error
local log_critical = native.log_critical

--[[
@description 记录一条 trace 级别的日志，用于非常详细的调试。
@param ...: 任意数量的参数，将被转换成字符串并拼接。
]]
function M.trace(...)
    log_trace(tostring(table.concat({ ... }, " ")))
end

--[[
@description 记录一条 debug 级别的日志，用于开发过程中的调试信息。
@param ...: 任意数量的参数。
]]
function M.debug(...)
    log_debug(tostring(table.concat({ ... }, " ")))
end

--[[
@description 记录一条 info 级别的日志，用于记录程序运行的关键信息。
@param ...: 任意数量的参数。
]]
function M.info(...)
    log_info(tostring(table.concat({ ... }, " ")))
end

--[[
@description 记录一条 warning 级别的日志，用于表示可能出现的问题。
@param ...: 任意数量的参数。
]]
function M.warn(...)
    log_warn(tostring(table.concat({ ... }, " ")))
end

--[[
@description 记录一条 error 级别的日志，用于记录已发生的错误。
@param ...: 任意数量的参数。
]]
function M.error(...)
    log_error(tostring(table.concat({ ... }, " ")))
end

--[[
@description 记录一条 critical 级别的日志，用于记录导致程序无法继续的严重错误。
@param ...: 任意数量的参数。
]]
function M.critical(...)
    log_critical(tostring(table.concat({ ... }, " ")))
end

return M