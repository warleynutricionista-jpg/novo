fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Kakarot'
description 'Employee management system allowing players to hire/fire other players'
version '2.1.2'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'locales/pt-br.lua',
    'locales/*.lua',
    'config.lua',
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- bridge primeiro:
    'server/sv_bank_bridge.lua',
    -- depois os arquivos que te reescrevi:
    'server/sv_boss.lua',
    'server/sv_gang.lua',
    -- ...demais arquivos do seu r
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/gangmenu.html',
    'ui/Bossmenu.html'
}
