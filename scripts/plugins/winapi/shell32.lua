-- scripts/plugins/winapi/shell32.lua
-- FFI 定义组：shell32 API，并提供相关的高级封装

local pesh = _G.pesh
local ffi = pesh.ffi

-- [[ 关键修正 ]] 显式加载依赖的插件
local kernel32 = pesh.plugin.load("winapi.kernel32")
local tnew = require("table.new")

local M = {}

-- 定义 C 函数原型
ffi.define("winapi.shell32", [[
    wchar_t** CommandLineToArgvW(const wchar_t* lpCmdLine, int* pNumArgs);
    /* LocalFree is in kernel32, so it's not defined here */
]])

-- 加载并缓存库命名空间
local shell32 = ffi.library("shell32")

---
-- 将命令行字符串解析为参数数组，类似于 C 语言的 argv。
-- @param cmd_line string: 完整的命令行字符串。
-- @return table|nil, string: 成功时返回一个包含所有参数的数组；失败时返回 nil 和错误信息。
function M.commandline_to_argv(cmd_line)
    if not cmd_line or cmd_line == "" then return {} end

    local argc_ptr = ffi.new("int[1]")
    local argv_w = shell32.CommandLineToArgvW(ffi.to_wide(cmd_line), argc_ptr)
    
    if argv_w == nil then
        return nil, "CommandLineToArgvW failed, possibly due to invalid input."
    end

    local argc = argc_ptr[0]
    local result = tnew(argc, 0)
    
    for i = 0, argc - 1 do
        result[i + 1] = ffi.from_wide(argv_w[i])
    end

    -- 调用正确的 LocalFree (位于 kernel32 模块)
    kernel32.LocalFree(argv_w)
    
    return result
end

return M