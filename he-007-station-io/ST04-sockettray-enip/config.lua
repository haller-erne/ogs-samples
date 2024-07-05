-- add the shared folder (..\shared)
OGS.Project.AddPath('../shared')

-- Check, if the debugger is connected (detect, if running under VSCode Second Lua Local Debug)
require('lua-local-debugger')

requires = {
	"import_config",
	"barcode",
	"user_manager",
	"station_io",
	"enip-turck-tben",
}
current_project.logo_file = '../shared/logo-rexroth.png'
current_project.billboard = 'http://127.0.0.1:60000/billboard.html'



