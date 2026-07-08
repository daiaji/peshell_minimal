package.path = "./scripts/?.lua;./scripts/?/init.lua;./scripts/lib/?.lua;./scripts/lib/?/init.lua;" .. package.path

local message_box = require("ui.widgets.message_box")

local model = message_box.create({ title = "T", message = "Hello", buttons = "yes_no" })
assert(model.open)
assert(#model.buttons == 2)
assert(message_box.choose(model, "Yes") == "Yes")
assert(model.selected == "Yes")
assert(model.open == false)

local calls = {}
local ig = {
    igBegin = function(title)
        calls.begin_title = title
        return true
    end,
    igText = function(_, message)
        calls.text = message
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
        return label == "Cancel"
    end,
    igEnd = function()
        calls.ended = true
    end,
}

model = message_box.create({ title = "Draw", message = "Body", buttons = "ok_cancel" })
assert(message_box.draw(model, ig) == "Cancel")
assert(model.open == false)
assert(calls.begin_title == "Draw")
assert(calls.text == "Body")
assert(calls.buttons[1] == "OK")
assert(calls.buttons[2] == "Cancel")
assert(calls.ended == true)

return true
