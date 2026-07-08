package.path = './scripts/?.lua;./scripts/?/init.lua;./scripts/lib/?.lua;./scripts/lib/?/init.lua;' .. package.path

local runner = require 'tasks.runner'
local profile = require 'profiles.default'

local function task(name)
    return {
        plan = function(opts)
            return { ok = true, task = name, dry_run = opts.dry_run == true, steps = { { action = name } } }
        end,
        run = function(opts)
            return { ok = true, task = name, dry_run = opts.dry_run == true }
        end,
    }
end

local stub_tasks = {
    init_pe = task('init_pe'),
    install_drivers = task('install_drivers'),
    assign_drive_letters = task('assign_drive_letters'),
    setup_pagefile = task('setup_pagefile'),
    setup_display = task('setup_display'),
    shutdown_cleanup = task('shutdown_cleanup'),
}

local plan = assert(runner.plan(profile, { tasks = stub_tasks }))
assert(plan.ok == true)
assert(plan.dry_run == true)
assert(#plan.tasks == 5)
assert(plan.tasks[1].task == 'init_pe')
assert(plan.tasks[5].task == 'setup_display')

print('profile runner tests: 1 run, 0 failed')
