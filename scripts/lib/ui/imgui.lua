-- Minimal cimgui loader for PEShell UI experiments.
-- This module deliberately avoids owning a window/render backend.

local ffi = require("ffi")

local M = {}

local load_error
local lib

local function try_require_binding()
    local ok, binding = pcall(require, "ffi.cimgui")
    if ok then return binding end
    return nil, binding
end

local function try_load_library()
    local candidates = {
        "cimgui",
        "cimgui_sdl",
        "libcimgui",
        "libcimgui_sdl3",
    }
    local errors = {}
    for _, name in ipairs(candidates) do
        local ok, loaded = pcall(ffi.load, name)
        if ok then return loaded end
        errors[#errors + 1] = name .. ": " .. tostring(loaded)
    end
    return nil, table.concat(errors, "\n")
end

function M.load()
    if lib then return lib end

    local binding, binding_err = try_require_binding()
    if binding then
        lib = binding
        return lib
    end

    local loaded, load_err = try_load_library()
    if loaded then
        lib = loaded
        return lib
    end

    load_error = "cimgui unavailable. Missing ffi.cimgui binding or cimgui DLL. require error: " .. tostring(binding_err) .. "\n" .. tostring(load_err)
    return nil, load_error
end

function M.available()
    return M.load() ~= nil
end

function M.status()
    local loaded, err = M.load()
    if not loaded then
        return { available = false, error = err }
    end
    local version = nil
    local ok, result = pcall(function() return ffi.string(loaded.igGetVersion()) end)
    if ok then version = result end
    return { available = true, version = version or "unknown" }
end

function M.create_context(shared_font_atlas)
    local loaded, err = M.load()
    if not loaded then return nil, err end
    local ctx = loaded.igCreateContext(shared_font_atlas or nil)
    if ctx == nil then return nil, "igCreateContext returned nil" end
    return ctx
end

function M.destroy_context(ctx)
    local loaded, err = M.load()
    if not loaded then return false, err end
    loaded.igDestroyContext(ctx)
    return true
end

return M
