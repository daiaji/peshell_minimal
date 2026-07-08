local M = {}

local DEFAULT_ORDER = {
    'init_pe',
    'install_drivers',
    'assign_drive_letters',
    'setup_pagefile',
    'setup_display',
    'shutdown_cleanup',
}

local function default_logger()
    local log = _G.log
    if log then return log end
    return {
        info = function(...) print(...) end,
        warn = function(...) print(...) end,
        error = function(...) print(...) end,
    }
end

local function load_tasks(opts)
    if opts and opts.tasks then return opts.tasks end
    return require 'win-kit.tasks'
end

local function merge_options(base, extra)
    local merged = {}
    for k, v in pairs(base or {}) do merged[k] = v end
    for k, v in pairs(extra or {}) do merged[k] = v end
    return merged
end

function M.plan(profile, opts)
    opts = opts or {}
    local tasks = load_tasks(opts)
    local order = profile.order or DEFAULT_ORDER
    local planned = {}

    for _, name in ipairs(order) do
        local task_cfg = profile.tasks and profile.tasks[name]
        if task_cfg ~= false then
            task_cfg = task_cfg or {}
            local task = tasks[name]
            if task and task.plan then
                local task_opts = merge_options(profile.defaults, task_cfg)
                task_opts.dry_run = true
                table.insert(planned, task.plan(task_opts))
            end
        end
    end

    return {
        ok = true,
        dry_run = true,
        profile = profile.name or 'unnamed',
        tasks = planned,
    }
end

function M.run(profile, opts)
    opts = opts or {}
    local log = opts.logger or default_logger()
    local tasks = load_tasks(opts)

    if profile.dry_run or opts.dry_run then
        return M.plan(profile, opts)
    end

    local results = {}
    local order = profile.order or DEFAULT_ORDER

    for _, name in ipairs(order) do
        local task_cfg = profile.tasks and profile.tasks[name]
        if task_cfg ~= false then
            task_cfg = task_cfg or {}
            local task = tasks[name]
            if task and task.run then
                local task_opts = merge_options(profile.defaults, task_cfg)
                log.info('TASK: running ', name)
                local result, err = task.run(task_opts)
                if not result then
                    return nil, { task = name, error = err }
                end
                table.insert(results, result)
            end
        end
    end

    return {
        ok = true,
        profile = profile.name or 'unnamed',
        tasks = results,
    }
end

return M
