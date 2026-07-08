local M = {}

local DEFAULT_ORDER = {
    'init_pe',
    'install_drivers',
    'assign_drive_letters',
    'setup_pagefile',
    'setup_display',
    'setup_network',
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

local function filter_order(order, profile)
    local enabled = {}
    for _, name in ipairs(order) do
        local cfg = profile.tasks and profile.tasks[name]
        if cfg ~= false then
            table.insert(enabled, name)
        end
    end
    return enabled
end

function M.plan(profile, opts)
    opts = opts or {}
    local tasks = load_tasks(opts)
    local order = profile.order or DEFAULT_ORDER
    local enabled = filter_order(order, profile)
    local planned = {}

    for _, name in ipairs(enabled) do
        local task_cfg = profile.tasks and profile.tasks[name] or {}
        local task = tasks[name]
        if task and task.plan then
            local task_opts = merge_options(profile.defaults, task_cfg)
            task_opts.dry_run = true
            table.insert(planned, task.plan(task_opts))
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

    local order = profile.order or DEFAULT_ORDER
    local enabled = filter_order(order, profile)
    local total = #enabled
    local results = {}
    local cancelled = false

    for i, name in ipairs(enabled) do
        -- Cancel check: if opts.cancelled is a function, call it; if truthy, abort
        if opts.cancelled then
            local is_cancelled
            if type(opts.cancelled) == 'function' then
                is_cancelled = opts.cancelled()
            else
                is_cancelled = opts.cancelled
            end
            if is_cancelled then
                log.info('TASK: cancelled before ', name)
                cancelled = true
                break
            end
        end

        local task_cfg = profile.tasks and profile.tasks[name] or {}
        local task = tasks[name]
        if task and task.run then
            local task_opts = merge_options(profile.defaults, task_cfg)

            -- Confirmation callback for destructive tasks
            if opts.on_confirm and task_opts.confirm ~= false then
                local plan_result
                if task.plan then
                    local po = merge_options({}, task_opts)
                    po.dry_run = true
                    plan_result = task.plan(po)
                end
                local proceed = opts.on_confirm(name, plan_result)
                if not proceed then
                    log.info('TASK: skipped (user declined) ', name)
                    table.insert(results, { ok = true, task = name, skipped = true })
                    goto continue
                end
            end

            -- Progress callback: (name, index, total)
            if opts.on_progress then
                opts.on_progress(name, i, total)
            end

            log.info('TASK: running ', name)
            local result, err = task.run(task_opts)

            -- Task completion callback: (name, result_or_error)
            if opts.on_task_complete then
                opts.on_task_complete(name, result, err)
            end

            if not result then
                return nil, { task = name, error = err }
            end
            table.insert(results, result)
        end

        ::continue::
    end

    return {
        ok = not cancelled,
        cancelled = cancelled,
        profile = profile.name or 'unnamed',
        tasks = results,
    }
end

return M
