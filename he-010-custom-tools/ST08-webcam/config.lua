-- add the shared folder (..\shared)
OGS.Project.AddPath('../shared')

-- Check, if the debugger is connected (detect, if running under VSCode Second Lua Local Debug)
require('lua-local-debugger')

requires = {
	"import_config",
	"barcode",
	"user_manager",
	--"button_camera",
	--"button_ble",
	"web_processview_webcam",
	"lua_tool_webcam",				-- (preliminary) tool to read a webcam video stream and save it to a file
	--"lua_tool_camera_keyence",
	"web_barcodescanner",			-- show the webcam screen and wait for a barcode to be scanned
	--"lua_tool_delay",
	"lua_tool_snapshot",			-- download a camera image from a URL and save it to a file
}
current_project.logo_file = 'logo.png'
--current_project.billboard = 'http://127.0.0.1:60000/billboard.html'
--current_project.billboard = 'http://127.0.0.1:60000/web_barcodescanner/dist/index.html'
current_project.billboard = 'http://127.0.0.1:60000/web_barcodedetector/dist/index.html'

