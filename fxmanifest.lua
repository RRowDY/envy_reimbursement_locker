fx_version 'adamant'
game 'gta5'
lua54 'yes'

author 'RRowDY / Joshua'
description 'Reimbursement locker system for Envy'
version '1.0.0'

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/admin.css',
    'html/admin.js'
}

dependencies {
    'es_extended',
    'ox_inventory'
}

