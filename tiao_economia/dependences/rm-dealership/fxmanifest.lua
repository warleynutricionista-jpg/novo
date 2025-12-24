fx_version 'cerulean'
game 'gta5'

author 'Rafaell#0202'

shared_scripts {
    '@ox_lib/init.lua',
    'locale/*.lua',
    'config.lua'
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    --'html/images/*.png'
}

dependencies {
    'qb-core',
    'ox_lib',
    'ox_target',
    'mri_Qcarkeys',
    'sleepless_interact',
    'oxmysql'
}

lua54 'yes' 
