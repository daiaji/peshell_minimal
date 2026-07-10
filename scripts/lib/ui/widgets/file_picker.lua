local M = {}

local function vec2(ig, x, y)
    return { x = x, y = y }
end

local function default_fs()
    return require("plugins.fs")
end

local function sort_items(items)
    table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)
    return items
end

function M.create(opts)
    opts = opts or {}
    local model = {
        mode = opts.mode or "open",
        cwd = opts.cwd or opts.initial_dir or ".",
        selected = opts.selected,
        filter = opts.filter,
        entries = {},
        error = nil,
        open = true,
        fs = opts.fs or default_fs(),
    }
    return M.refresh(model)
end

function M.refresh(model)
    local entries = {}
    local dirs, dir_err = model.fs.list_dirs(model.cwd)
    if dirs then
        for _, path in ipairs(dirs) do entries[#entries + 1] = { type = "dir", path = path, name = path:match("[^\\/]+$") or path } end
    elseif dir_err then model.error = dir_err end

    if model.mode ~= "folder" then
        local files, file_err = model.fs.list_files(model.cwd)
        if files then
            for _, path in ipairs(files) do
                local name = path:match("[^\\/]+$") or path
                if not model.filter or name:lower():match(model.filter:lower()) then
                    entries[#entries + 1] = { type = "file", path = path, name = name }
                end
            end
        elseif file_err then model.error = file_err end
    end

    model.entries = sort_items(entries)
    return model
end

function M.enter(model, entry)
    if entry.type ~= "dir" then return false, "entry is not a directory" end
    model.cwd = entry.path
    return M.refresh(model)
end

function M.choose(model, entry)
    if model.mode == "folder" and entry.type ~= "dir" then return nil end
    if model.mode == "open" and entry.type ~= "file" then return nil end
    model.selected = entry.path
    model.open = false
    return model.selected
end

function M.cancel(model)
    model.open = false
    model.selected = nil
    return true
end

function M.draw(model, ig)
    if not model or not model.open then return model and model.selected end
    if not ig then return nil end

    local visible = ig.igBegin("File Picker", nil, 0)
    if visible then
        ig.igText("%s", model.cwd or "")
        if model.error then ig.igText("%s", model.error) end
        ig.igSeparator()

        for _, entry in ipairs(model.entries or {}) do
            local label = (entry.type == "dir" and "[D] " or "    ") .. entry.name
            if ig.igButton(label, vec2(ig, 0, 0)) then
                if entry.type == "dir" then
                    M.enter(model, entry)
                    break
                else
                    M.choose(model, entry)
                    break
                end
            end
        end

        ig.igSeparator()
        if model.mode == "folder" and ig.igButton("Choose Folder", vec2(ig, 0, 0)) then
            model.selected = model.cwd
            model.open = false
        end
        if model.mode == "save" then
            if model.selected then ig.igText("%s", model.selected) end
            if ig.igButton("Save", vec2(ig, 0, 0)) and model.selected then
                model.open = false
            end
            ig.igSameLine(0, -1)
        end
        if ig.igButton("Cancel", vec2(ig, 0, 0)) then M.cancel(model) end
    end
    ig.igEnd()
    return model.selected
end

return M
