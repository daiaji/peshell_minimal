-- scripts/core/ffi.lua
-- 中央 FFI 管理器，遵循 LuaJIT 最佳实践

local status, ffi = pcall(require, "ffi")
if not status then error("FATAL: LuaJIT FFI is not available.") end

local M = {}

local defined_groups = {} -- 记录已 cdef 的 FFI 定义组
local loaded_libs = {}    -- 缓存已加载的 DLL 命名空间

M.C = ffi.C

-- 核心 C 定义，用于 ffi 模块自身的功能
ffi.cdef[[
    int MultiByteToWideChar(unsigned int CodePage, unsigned int dwFlags, const char* lpMultiByteStr, int cbMultiByte, wchar_t* lpWideCharStr, int cchWideChar);
    int WideCharToMultiByte(unsigned int CodePage, unsigned int dwFlags, const wchar_t* lpWideCharStr, int cchWideChar, char* lpMultiByteStr, int cbMultiByte, const char* lpDefaultChar, int* lpUsedDefaultChar);
    int CloseHandle(void* hObject);
]]

---
-- 定义一组 C 类型和函数。
-- 为避免重复解析，每个 group_name 只会被 cdef 一次。
-- @param group_name string: 定义组的唯一名称 (例如 'winapi.kernel32')
-- @param cdef_string string: 包含 C 定义的字符串
function M.define(group_name, cdef_string)
    if not defined_groups[group_name] then
        -- log.trace is defined in core/log.lua, but ffi might be loaded before log.
        -- To be safe, we don't use log inside the ffi module itself.
        ffi.cdef(cdef_string)
        defined_groups[group_name] = true
    end
end

---
-- 加载一个共享库 (DLL) 并缓存其命名空间。
-- @param lib_name string: 库名称 (例如 'kernel32', 'proc_utils')
-- @return cdata: FFI 库命名空间
function M.library(lib_name)
    if not loaded_libs[lib_name] then
        loaded_libs[lib_name] = ffi.load(lib_name)
    end
    return loaded_libs[lib_name]
end

-- 核心 ffi.* 函数的别名
M.new = ffi.new
M.cast = ffi.cast
M.string = ffi.string
M.metatype = ffi.metatype

-- 字符串转换辅助函数 (从旧 ffi.lua 移入)
function M.to_wide(str)
    if not str or str == "" then return nil end
    local size = M.C.MultiByteToWideChar(65001, 0, str, -1, nil, 0)
    if size == 0 then return nil end
    local buf = ffi.new("wchar_t[?]", size)
    M.C.MultiByteToWideChar(65001, 0, str, -1, buf, size)
    return buf
end

function M.from_wide(wstr)
    if not wstr then return nil end
    local size = M.C.WideCharToMultiByte(65001, 0, wstr, -1, nil, 0, nil, nil)
    if size == 0 then return "" end
    local buf = ffi.new("char[?]", size)
    M.C.WideCharToMultiByte(65001, 0, wstr, -1, buf, size, nil, nil)
    return ffi.string(buf, size - 1)
end

-- 安全句柄定义 (从旧 ffi.lua 移入)
M.define("core.safehandle", "typedef struct { void* h; } SafeHandle_t;")
local handle_metatype = ffi.metatype("SafeHandle_t", {
    __gc = function(safe_handle)
        local handle_ptr = safe_handle.h
        if handle_ptr and handle_ptr ~= nil and handle_ptr ~= ffi.cast("void*", -1) then
            M.C.CloseHandle(handle_ptr)
        end
    end
})

local function create_safe_handle(handle_ptr)
    if not handle_ptr or handle_ptr == nil or handle_ptr == ffi.cast("void*", -1) then return nil end
    return handle_metatype({ h = handle_ptr })
end

M.EventHandle = create_safe_handle
M.ProcessHandle = create_safe_handle

return M