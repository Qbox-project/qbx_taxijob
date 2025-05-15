fx_version 'cerulean'
game 'gta5'

description 'QBX_TaxiJob'
repository 'https://github.com/Qbox-project/qbx_taxijob'
version '1.0.0'

shared_scripts {
	'@ox_lib/init.lua',
	'@qbx_core/modules/lib.lua'	
}

client_scripts {
	'@qbx_core/modules/playerdata.lua',
	'client/main.lua',
}

server_script 'server/main.lua'

ui_page 'html/meter.html'

files {
	'html/meter.css',
	'html/meter.html',
	'html/meter.js',
	'config/client.lua',
	'config/shared.lua',
	'locales/*.json'
}

provide 'qb-taxijob'
lua54 'yes'
use_experimental_fxv2_oal 'yes'
ox_lib 'locale'
dependency 'qbx_core'
