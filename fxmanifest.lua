fx_version 'cerulean'
game 'gta5'

description 'QBX-TaxiJob'
version '1.0.0'

ui_page 'html/meter.html'

shared_scripts {
	'@qbx-core/shared/locale.lua',
	'@ox_lib/init.lua',
	'locales/en.lua',
	'locales/*.lua',
	'config.lua',
}

client_script 'client/main.lua'

server_script 'server/main.lua'

files {
	'html/meter.css',
	'html/meter.html',
	'html/meter.js',
	'html/reset.css',
	'html/g5-meter.png'
}

provide 'qb-taxijob'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

dependency 'qbx-core'
