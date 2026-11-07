fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

name 'rsg-horsesadmin'
description 'Admin horse management for rsg-horses (RSG Core v2 only)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

files {
    'locales/*.json',
}

dependencies {
    'rsg-core',
    'ox_lib',
    'oxmysql',
    'rsg-horses',
    'rsg-essentials',
}

lua54 'yes'