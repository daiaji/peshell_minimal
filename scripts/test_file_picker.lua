package.path = "./scripts/?.lua;./scripts/?/init.lua;./scripts/lib/?.lua;./scripts/lib/?/init.lua;" .. package.path

local picker = require("ui.widgets.file_picker")

local fake_fs = {
    list_dirs = function(path)
        assert(path == "C:\\")
        return { "C:\\Windows", "C:\\Temp" }
    end,
    list_files = function(path)
        assert(path == "C:\\")
        return { "C:\\boot.ini", "C:\\readme.txt" }
    end,
}

local model = picker.create({ cwd = "C:\\", mode = "open", filter = "%.txt$", fs = fake_fs })
assert(#model.entries == 3)
local chosen
for _, entry in ipairs(model.entries) do
    if entry.name == "readme.txt" then chosen = picker.choose(model, entry) end
end
assert(chosen == "C:\\readme.txt")
assert(model.open == false)

local draw_fs = {
    list_dirs = function(path)
        if path == "C:\\" then return { "C:\\Temp" } end
        if path == "C:\\Temp" then return {} end
        error("unexpected path: " .. tostring(path))
    end,
    list_files = function(path)
        if path == "C:\\" then return { "C:\\readme.txt" } end
        if path == "C:\\Temp" then return { "C:\\Temp\\note.txt" } end
        error("unexpected path: " .. tostring(path))
    end,
}

local clicked = { ["[D] Temp"] = true }
local calls = {}
local ig = {
    ImVec2 = function(x, y) return { x = x, y = y } end,
    igBegin = function(title)
        calls.title = title
        return true
    end,
    igText = function(_, text)
        calls.text = calls.text or {}
        calls.text[#calls.text + 1] = text
    end,
    igSeparator = function()
        calls.separator = (calls.separator or 0) + 1
    end,
    igSameLine = function()
        calls.same_line = (calls.same_line or 0) + 1
    end,
    igButton = function(label)
        calls.buttons = calls.buttons or {}
        calls.buttons[#calls.buttons + 1] = label
        return clicked[label] == true
    end,
    igEnd = function()
        calls.ended = true
    end,
}

model = picker.create({ cwd = "C:\\", mode = "open", fs = draw_fs })
assert(picker.draw(model, ig) == nil)
assert(model.cwd == "C:\\Temp")
assert(model.open == true)
assert(calls.title == "File Picker")
assert(calls.ended == true)

clicked = { ["    note.txt"] = true }
assert(picker.draw(model, ig) == "C:\\Temp\\note.txt")
assert(model.open == false)

model = picker.create({ cwd = "C:\\Temp", mode = "folder", fs = draw_fs })
clicked = { ["Choose Folder"] = true }
assert(picker.draw(model, ig) == "C:\\Temp")
assert(model.open == false)

return true
