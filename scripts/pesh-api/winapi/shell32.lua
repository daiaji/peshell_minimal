-- scripts/pesh-api/winapi/shell32.lua

local ffi = require("pesh-api.ffi")
local C = ffi.C
local shell32 = ffi.load("shell32")

-- [优化] 引入 LuaJIT 扩展的 table.new，用于高效地创建预分配大小的表
local tnew = require("table.new")

local M = {}

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
    -- [优化] 使用 tnew 预先分配表的数组部分，避免循环中的内存重分配
    local result = tnew(argc, 0)
    
    -- FFI 返回的指针数组需要手动遍历
    for i = 0, argc - 1 do
        -- [优化] 对于预分配的表，直接使用索引赋值比 table.insert 更快
        result[i + 1] = ffi.from_wide(argv_w[i])
    end

    -- 必须手动释放由 CommandLineToArgvW 分配的内存
    C.LocalFree(argv_w)
    
    return result
end

return M