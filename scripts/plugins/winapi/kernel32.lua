-- scripts/plugins/winapi/kernel32.lua
-- FFI 定义组：kernel32 API

local ffi = _G.pesh.ffi

ffi.define("winapi.kernel32", [[
    void Sleep(int ms);
    unsigned long GetTickCount(void);
    unsigned int GetCurrentProcessId();
    unsigned int GetProcessId(void* hProcess);
    int GetModuleFileNameW(void* hModule, wchar_t* lpFilename, int nSize);
    unsigned int GetLastError();
    int SetEnvironmentVariableW(const wchar_t* lpName, const wchar_t* lpValue);
    int GetEnvironmentVariableW(const wchar_t* lpName, wchar_t* lpBuffer, int nSize);
    void* CreateEventW(void* lpEventAttributes, int bManualReset, int bInitialState, const wchar_t* lpName);
    void* OpenEventW(unsigned int dwDesiredAccess, int bInheritHandle, const wchar_t* lpName);
    int SetEvent(void* hEvent);
    void* LoadLibraryW(const wchar_t* lpLibFileName);
    int FreeLibrary(void* hModule);
    void* LocalFree(void* hMem);
]])

return ffi.library("kernel32")