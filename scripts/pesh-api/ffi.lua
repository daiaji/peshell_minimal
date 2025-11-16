-- scripts/pesh-api/ffi.lua
-- LuaJIT FFI 核心桥接模块 (v5.4 - FFI String Conversion Optimization)

local status, ffi = pcall(require, "ffi")
if not status then
    error("FATAL: LuaJIT FFI is not available. This script cannot run.")
end

local C = ffi.C

-- 定义 C 函数原型
ffi.cdef[[
    /* --- Windows API --- */
    void Sleep(int ms);
    unsigned int GetCurrentProcessId();
    unsigned int GetProcessId(void* hProcess);
    int GetModuleFileNameW(void* hModule, wchar_t* lpFilename, int nSize);
    void PostQuitMessage(int nExitCode);
    unsigned int GetLastError();
    int SetEnvironmentVariableW(const wchar_t* lpName, const wchar_t* lpValue);
    int GetEnvironmentVariableW(const wchar_t* lpName, wchar_t* lpBuffer, int nSize);
    
    wchar_t** CommandLineToArgvW(const wchar_t* lpCmdLine, int* pNumArgs);
    void* LocalFree(void* hMem);
    
    void* CreateEventW(void* lpEventAttributes, int bManualReset, int bInitialState, const wchar_t* lpName);
    void* OpenEventW(unsigned int dwDesiredAccess, int bInheritHandle, const wchar_t* lpName);
    int SetEvent(void* hEvent);
    int CloseHandle(void* hObject);
    void* LoadLibraryW(const wchar_t* lpLibFileName);
    int FreeLibrary(void* hModule);

    /* --- COM and Shell Registration --- */
    long CoInitialize(void* pvReserved);
    long RegInstallW(void* hMod, const wchar_t* pszSection, const void* pstTable);

    /* --- 字符串转换 API --- */
    int MultiByteToWideChar(unsigned int CodePage, unsigned int dwFlags, const char* lpMultiByteStr, int cbMultiByte, wchar_t* lpWideCharStr, int cchWideChar);
    int WideCharToMultiByte(unsigned int CodePage, unsigned int dwFlags, const wchar_t* lpWideCharStr, int cchWideChar, char* lpMultiByteStr, int cbMultiByte, const char* lpDefaultChar, int* lpUsedDefaultChar);

    /* --- proc_utils 库函数原型 --- */
    typedef struct { unsigned int pid; void* process_handle; unsigned int last_error_code; } ProcUtils_ProcessResult;
    ProcUtils_ProcessResult ProcUtils_CreateProcess(const wchar_t* command, const wchar_t* working_dir, int show_mode, const wchar_t* desktop_name);
    void* ProcUtils_OpenProcessByName(const wchar_t* process_name, unsigned int desired_access);
    unsigned int ProcUtils_ProcessExists(const wchar_t* process_name_or_pid);
    bool ProcUtils_ProcessClose(const wchar_t* process_name_or_pid, unsigned int exit_code);
    bool ProcUtils_ProcessCloseTree(const wchar_t* process_name_or_pid);
    int ProcUtils_FindAllProcesses(const wchar_t* process_name, unsigned int* out_pids, int pids_array_size);
]]

local M = {
    C = C,
    cdef = ffi.cdef, cast = ffi.cast, string = ffi.string,
    new = ffi.new, metatype = ffi.metatype,
    load = ffi.load,
    proc_utils = ffi.load("proc_utils"),
}

-- 字符串转换辅助函数
function M.to_wide(str)
    if not str or str == "" then return nil end
    local size = C.MultiByteToWideChar(65001, 0, str, -1, nil, 0)
    if size == 0 then return nil end
    local buf = ffi.new("wchar_t[?]", size)
    C.MultiByteToWideChar(65001, 0, str, -1, buf, size)
    return buf
end

function M.from_wide(wstr)
    if not wstr then return nil end
    -- -1 表示 wstr 是一个以 null 结尾的字符串，API会计算其长度
    -- 返回的 size 是包含 null 终止符在内的缓冲区大小
    local size = C.WideCharToMultiByte(65001, 0, wstr, -1, nil, 0, nil, nil)
    if size == 0 then return "" end
    local buf = ffi.new("char[?]", size)
    C.WideCharToMultiByte(65001, 0, wstr, -1, buf, size, nil, nil)
    
    -- [优化] 根据 LuaJIT FFI 文档，当长度已知时，显式传递长度给 ffi.string
    -- 可以避免内部进行 strlen 调用，从而提升性能。
    -- 这里的 size 包含 \0，所以实际字符串长度是 size - 1。
    return ffi.string(buf, size - 1)
end

-- 安全句柄定义 (RAII)
ffi.cdef("typedef struct { void* h; } SafeHandle_t;")
local handle_metatype = ffi.metatype("SafeHandle_t", {
    __gc = function(safe_handle)
        local handle_ptr = safe_handle.h
        -- 确保句柄有效且不是无效句柄值 (INVALID_HANDLE_VALUE)
        if handle_ptr and handle_ptr ~= nil and handle_ptr ~= ffi.cast("void*", -1) then
            C.CloseHandle(handle_ptr)
        end
    end
})

-- 将构造函数包装一下，使其更易用，并处理无效句柄
local function create_safe_handle(handle_ptr)
    if not handle_ptr or handle_ptr == nil or handle_ptr == ffi.cast("void*", -1) then
        return nil
    end
    return handle_metatype({ h = handle_ptr })
end

M.EventHandle = create_safe_handle
M.ProcessHandle = create_safe_handle

return M