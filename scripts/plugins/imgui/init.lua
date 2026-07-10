-- scripts/plugins/imgui/init.lua
-- ImGui capability probe plugin. Rendering backend is intentionally separate.

local log = _G.log
local M = {}

function M.probe()
    local imgui = require("ui.imgui")
    return imgui.status()
end

function M.native_smoke(opts)
    opts = opts or {}
    local host = require("ui.native_host")
    local native, native_err = host.create_win32_d3d11({
        title = opts.title or "PEShell ImGui Smoke",
        width = opts.width or 960,
        height = opts.height or 640,
    })
    if not native then return nil, native_err end

    local runtime = require("ui.runtime")
    local rt, rt_err = runtime.create({
        backend = "win32_d3d11",
        hwnd = native.hwnd,
        device = native.device,
        device_context = native.device_context,
        swap_chain = native.swap_chain,
        d3d = native.d3d,
        destroy = native.destroy,
    })
    if not rt then
        native.destroy()
        return nil, rt_err or "ui.runtime.create failed"
    end

    local frames = opts.frames or 120
    local rendered = 0
    local message_box = require("ui.widgets.message_box")
    local file_picker = require("ui.widgets.file_picker")
    local gui_mod = require("ui.gui")
    local message = message_box.create({
        title = "PEShell",
        message = "ImGui native host smoke test",
        buttons = "ok_cancel",
    })
    local picker = file_picker.create({
        cwd = opts.cwd or ".",
        mode = "open",
        fs = opts.fs,
    })
    local gui = gui_mod.create({ title = "PEShell GUI" })
    gui:AddText("vTitle", "AHK-like GUI smoke")
    gui:AddEdit("vImage", opts.image or "X:\\install.wim")
    local progress = gui:AddProgress("vProgress", "Deploy")
    progress:SetRange(0, 100)
    progress:SetValue(25)
    gui:Show()
    local ok, err = pcall(function()
        while frames > 0 and runtime.frame(rt, function(cimgui, imgui_err)
            if not cimgui then error(imgui_err or "imgui unavailable") end
            message_box.draw(message, cimgui)
            file_picker.draw(picker, cimgui)
            gui:Draw(cimgui)
            rendered = rendered + 1
        end) do
            frames = frames - 1
        end
    end)
    runtime.shutdown(rt)
    if not ok then return nil, err end
    return { frames = rendered, message = message.selected, file = picker.selected, gui = gui:Submit() }
end

M.__commands = {
    ["imgui-probe"] = function()
        local status = M.probe()
        if status.available then
            log.info("ImGui available. Version: ", tostring(status.version))
            return 0
        end
        log.warn("ImGui unavailable: ", tostring(status.error))
        return 2
    end,
    ["imgui-native-smoke"] = function()
        local result, err = M.native_smoke()
        if result then
            log.info("ImGui native smoke rendered frames: ", tostring(result.frames))
            return 0
        end
        log.warn("ImGui native smoke failed: ", tostring(err))
        return 2
    end,
}

return M
