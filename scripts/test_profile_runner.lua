package.path = './scripts/?.lua;./scripts/?/init.lua;./scripts/lib/?.lua;./scripts/lib/?/init.lua;' .. package.path

local runner = require 'tasks.runner'
local profile = require 'profiles.default'

local pass = 0
local fail = 0

local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
        pass = pass + 1
    else
        fail = fail + 1
        io.stderr:write(string.format('  FAIL %s: %s\n', name, tostring(err)))
    end
end

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
    setup_network = task('setup_network'),
    shutdown_cleanup = task('shutdown_cleanup'),
    boot_repair = task('boot_repair'),
}

-- Test 1: plan() returns canonical shape
check('plan returns canonical shape', function()
    local plan = assert(runner.plan(profile, { tasks = stub_tasks }))
    assert(plan.ok == true)
    assert(plan.dry_run == true)
    assert(#plan.tasks == 5)  -- init_pe + install_drivers + assign_drive_letters + setup_pagefile + setup_display
    assert(plan.tasks[1].task == 'init_pe')
    assert(plan.tasks[5].task == 'setup_display')
end)

-- Test 2: run(dry_run=true) delegates to plan
check('run dry_run delegates to plan', function()
    local result = assert(runner.run(profile, { tasks = stub_tasks, dry_run = true }))
    assert(result.ok == true)
    assert(result.dry_run == true)
end)

-- Test 3: on_progress callback fires for each task
check('on_progress fires for each task', function()
    local non_dry_profile = {
        name = 'test-progress',
        order = { 'init_pe', 'install_drivers' },
        tasks = { init_pe = {}, install_drivers = {} },
    }
    local progress_calls = {}
    local result = runner.run(non_dry_profile, {
        tasks = stub_tasks,
        on_progress = function(name, i, total)
            table.insert(progress_calls, { name = name, i = i, total = total })
        end,
    })
    assert(result.ok == true)
    assert(#progress_calls == 2)
    assert(progress_calls[1].name == 'init_pe')
    assert(progress_calls[1].i == 1)
    assert(progress_calls[1].total == 2)
    assert(progress_calls[2].name == 'install_drivers')
    assert(progress_calls[2].i == 2)
end)

-- Test 4: cancelled flag aborts before next task
check('cancelled aborts before next task', function()
    local non_dry_profile = {
        name = 'test-cancel',
        order = { 'init_pe', 'install_drivers', 'setup_pagefile' },
        tasks = { init_pe = {}, install_drivers = {}, setup_pagefile = {} },
    }
    local cancel_flag = false
    local result = runner.run(non_dry_profile, {
        tasks = stub_tasks,
        cancelled = function() return cancel_flag end,
        on_progress = function(name)
            if name == 'init_pe' then cancel_flag = true end
        end,
    })
    assert(result.cancelled == true)
    assert(#result.tasks == 1)  -- only init_pe ran
end)

-- Test 5: on_confirm can skip a task
check('on_confirm can skip a task', function()
    local non_dry_profile = {
        name = 'test-confirm',
        order = { 'init_pe', 'install_drivers' },
        tasks = { init_pe = {}, install_drivers = {} },
    }
    local result = runner.run(non_dry_profile, {
        tasks = stub_tasks,
        on_confirm = function(name)
            if name == 'install_drivers' then return false end
            return true
        end,
    })
    assert(result.ok == true)
    assert(#result.tasks == 2)
    assert(result.tasks[2].skipped == true)
end)

-- Test 6: on_task_complete fires with result
check('on_task_complete fires with result', function()
    local non_dry_profile = {
        name = 'test-complete',
        order = { 'init_pe' },
        tasks = { init_pe = {} },
    }
    local completed = {}
    runner.run(non_dry_profile, {
        tasks = stub_tasks,
        on_task_complete = function(name, result, err)
            table.insert(completed, { name = name, result = result, err = err })
        end,
    })
    assert(#completed == 1)
    assert(completed[1].name == 'init_pe')
    assert(completed[1].result.ok == true)
end)

print(string.format('profile runner tests: %d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
