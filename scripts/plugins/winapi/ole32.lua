-- scripts/plugins/winapi/ole32.lua
-- FFI 定义组: ole32.dll API

local ffi = _G.pesh.ffi

ffi.define("winapi.ole32", [[
    long CoInitialize(void* pvReserved);
]])

return ffi.library("ole32")