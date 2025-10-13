fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Painel_ORG'
author 'thomas'
description 'Painel de Organizações (Qbox/QBCore + ox_lib + oxmysql)'
version '2.0.5'

ui_page 'build/web/index.html'

files {
    'build/web/index.html',
    'build/web/config.css',
    'web/*.js',
    'web/assets/*',
    'web/background/*',   -- <- garante o papel de parede no pacote
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge_core.lua',
    'server/main.lua',
    'server/modules/*.lua',
}

client_scripts {
    'client/main.lua',
    'client/modules/*.lua',
}

dependencies {
    'ox_lib',
    'oxmysql'
}
