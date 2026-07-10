local M = {}

local function vec2(ig, x, y)
    return { x = x, y = y }
end

local BUTTONS = {
    ok = { "OK" },
    ok_cancel = { "OK", "Cancel" },
    yes_no = { "Yes", "No" },
}

function M.create(opts)
    opts = opts or {}
    return {
        title = opts.title or "Message",
        message = opts.message or opts.text or "",
        buttons = BUTTONS[opts.buttons or "ok"] or BUTTONS.ok,
        selected = nil,
        open = true,
    }
end

function M.choose(model, label)
    if not model or not model.open then return nil end
    for _, button in ipairs(model.buttons) do
        if button == label then
            model.selected = label
            model.open = false
            return label
        end
    end
    return nil
end

function M.draw(model, ig)
    if not model or not model.open then return model and model.selected end
    if not ig then return nil end

    local visible = ig.igBegin(model.title, nil, 0)
    if visible then
        ig.igText("%s", model.message)
        ig.igSeparator()
        for i, label in ipairs(model.buttons) do
            if i > 1 then ig.igSameLine(0, -1) end
            if ig.igButton(label, vec2(ig, 0, 0)) then
                M.choose(model, label)
            end
        end
    end
    ig.igEnd()
    return model.selected
end

return M
