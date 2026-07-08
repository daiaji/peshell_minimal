-- pesh_ffi_core.lua
-- Host Adapter for PEShell (Legacy Interface Wrapper)
-- This file now delegates all heavy logic to win-utils and lua-ext.

local ffi = require("ffi")

if ffi.os ~= "Windows" then
    return nil, "This library only runs on Windows."
end

-- Load the new modular utilities
local win = require("win-utils.init")
local binary = require("ext.binary")
local io = require("ext.io")

-- Legacy API Adapter for Host Compatibility
local M = {
    -- Map old namespaces to new modules
    registry = win.registry,
    net      = win.net,
    fs       = win.fs,
    disk     = win.disk,
    
    -- Shell namespace split fix:
    -- M.shell must support both create_shortcut AND browse_folder
    shell = {
        browse_folder = win.shell.browse_folder,
        create_shortcut = win.shortcut.create
    },
    
    -- [FIXED] Explicit mapping for legacy hook names
    hooks = {
        -- New generic methods
        register = win.hotkey.register,
        unregister = win.hotkey.unregister,
        dispatch = win.hotkey.dispatch,
        create_callback = win.hotkey.create_callback,
        
        -- Legacy aliases (Vital for Host compatibility)
        register_hotkey = win.hotkey.register,
        unregister_hotkey = win.hotkey.unregister,
    },
    
    -- TextIO and Buffer were moved to lua-ext
    textio = {
        read_file = io.readfile,
        write_file = io.writefile,
        lines = io.lines
    },
    
    buffer = binary
}

return M