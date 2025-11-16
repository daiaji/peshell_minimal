-- scripts/pesh-api/winapi/kernel32.lua (v2.2 - FFI Call Optimization)

local ffi = require("pesh-api.ffi")
local C = ffi.C
local kernel32 = ffi.load("kernel32")

local M = {}

-- 包装 GetLastError，使其更易用 (这个封装是有价值的，保留)
local function get_last_error_msg()
    local err_code = C.GetLastError()
    return string.format("Win32 Error %d", err_code)
end

function M.create_event(name, manual_reset, initial_state)
    local h_ptr = kernel32.CreateEventW(nil, manual_reset and 1 or 0, initial_state and 1 or 0, ffi.to_wide(name))
    if h_ptr == nil then
        return nil, get_last_error_msg()
    end
    return ffi.EventHandle(h_ptr)
end

function M.open_event(name, access)
    access = access or 0x0002 -- EVENT_MODIFY_STATE
    local h_ptr = kernel32.OpenEventW(access, 0, ffi.to_wide(name))
    if h_ptr == nil then
        return nil, get_last_error_msg()
    end
    return ffi.EventHandle(h_ptr)
end

function M.set_event(event_handle)
    if not event_handle or event_handle.h == nil then return false, "Invalid event handle" end
    if kernel32.SetEvent(event_handle.h) == 0 then
        return false, get_last_error_msg()
    end
    return true
end

function M.get_module_file_name()
    local buf = ffi.new("wchar_t[?]", 260)
    if kernel32.GetModuleFileNameW(nil, buf, 260) > 0 then
        return ffi.from_wide(buf)
    end
    return nil, get_last_error_msg()
end

-- [优化] 直接导出 FFI 函数，遵循 LuaJIT 官方性能指南
M.get_current_pid = C.GetCurrentProcessId
M.sleep = C.Sleep

return M