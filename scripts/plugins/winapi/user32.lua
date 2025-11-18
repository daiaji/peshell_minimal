-- scripts/plugins/winapi/user32.lua
-- FFI 定义组：user32 API

local ffi = _G.pesh.ffi

ffi.define("winapi.user32", [[
    void PostQuitMessage(int nExitCode);
    int MessageBoxA(void *w, const char *txt, const char *cap, int type);
]])

return ffi.library("user32")