fx_version 'cerulean'
game 'gta5'

ui_page 'html/meter.html'

shared_scripts {
	'@qb-core/shared/locale.lua',
	'locales/en.lua',
	'config.lua',
	'@ox_lib/init.lua'
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

dependencies {
	'qb-core',
	'ox_lib'
}

lua54 'yes'