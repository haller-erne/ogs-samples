-- add the shared folder (..\shared)
OGS.Project.AddPath('../shared')

-- Start the debugger (automatically detects, if running under VSCode Lua Local Debug)
require('lua-local-debugger')

requires = {
	"barcode",
	"user_manager",
	"sim",
	"resultdata",
	"custom_nok_handling",
	"station_io",
}
current_project.logo_file = ''
current_project.billboard = 'local://logo.png'



