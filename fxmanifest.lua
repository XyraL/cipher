fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cipher'
author 'you'
description 'Cipher — modular encrypted criminal device. First app: Gang Ops.'
version '0.1.0'

-- Works on QBox (qbx_core) OR QBCore (qb-core). The bridge auto-detects.
-- Shared deps both frameworks support cleanly:
dependencies {
    'ox_lib',
    'oxmysql',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/apps.lua',
}

client_scripts {
    'bridge/framework.lua',
    'client/main.lua',
    'client/device.lua',
    'client/territory.lua',
    'client/admin.lua',
    'client/placeables.lua',
    'client/drugs.lua',
    'client/dealer.lua',
    'client/crafting.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/framework.lua',
    'server/main.lua',
    'server/gangs.lua',
    'server/territory.lua',
    'server/notoriety.lua',
    'server/vault.lua',
    'server/placeables.lua',
    'server/bank.lua',
    'server/tasks.lua',
    'server/admin.lua',
    'server/crafting.lua',
    'server/dealer.lua',
    'server/drugs.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/admin.js',
    'web/craft.js',
}
