-- scripts/pesh-api/winapi/user32.lua
local ffi = require("pesh-api.ffi")
local C = ffi.C
local user32 = ffi.load("user32")

local M = {}

function M.message_box(text, caption, msg_type)
    return user32.MessageBoxA(nil, text, caption, msg_type or 0)
end

-- [优化] 直接导出 FFI 函数，以获得最佳 JIT 优化效果
M.post_quit_message = C.PostQuitMessage

return M