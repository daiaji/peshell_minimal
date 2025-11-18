-- scripts/plugins/winapi/advpack.lua
-- FFI 定义组: advpack.dll API

local ffi = _G.pesh.ffi

ffi.define("winapi.advpack", [[
    long RegInstallW(void* hMod, const wchar_t* pszSection, const void* pstTable);
]])

return ffi.library("advpack")