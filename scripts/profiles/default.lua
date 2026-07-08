return {
    name = 'default-winpe',
    dry_run = true,
    defaults = {
        dry_run = true,
    },
    order = {
        'init_pe',
        'install_drivers',
        'assign_drive_letters',
        'setup_pagefile',
        'setup_display',
        'setup_network',
        'shutdown_cleanup',
    },
    tasks = {
        init_pe = {
            refresh_icons = true,
        },
        install_drivers = {
            root = [[X:\Drivers]],
            mode = 'smart',
        },
        assign_drive_letters = {},
        setup_pagefile = {
            min_ram_mb = 4096,
            size_mb = 1024,
        },
        setup_display = {},
        setup_network = false,
        shutdown_cleanup = false,
    },
}
