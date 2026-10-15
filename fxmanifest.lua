fx_version 'cerulean'
game 'gta5'

name 'spz-admin'
description 'SPiceZ admin tools (ox_lib menu) — player management, spectate or ride along with any player in any routing bucket, bucket browser, self tools, noclip and dev tools (coord copy, entity inspector).'
version '1.2.0'
author 'SPiceZ-Core'
lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/utils.lua',
    'client/view.lua',
    'client/noclip.lua',
    'client/dev.lua',
    'client/troll.lua',
    'client/menu.lua',
}

server_scripts {
    'server/main.lua',
    'server/admins.lua',
    'server/view.lua',
    'server/rank.lua',
}

dependencies {
    'ox_lib',
}
