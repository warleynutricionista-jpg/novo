fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'space_economy (QBOX modular v2)'
description 'Economia modular: impostos progressivos, tesouro, dívidas, NUI, admin.'
version '2.0.0'

-- ox_lib init roda em client+server via shared_scripts (1x só)
shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
  'shared/init.lua',
  'shared/utils.lua',
  'shared/bridge.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',

  'server/init.lua',
  'server/state.lua',
  'server/treasury.lua',
  'server/tax.lua',
  'server/charcache.lua',
  'server/debts.lua',
  'server/admin.lua',
  'server/integrations.lua',
  'server/events.lua',
}

client_scripts {
  'client/init.lua',
  'client/nui.lua',
  'client/commands.lua',
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/script.js',
}

dependencies {
  'ox_lib',
  'oxmysql',
  'qbx_core',
}
