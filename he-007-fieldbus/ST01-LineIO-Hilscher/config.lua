-- ***************************************************************************
-- 
-- LUA project configuration
-- 
-- This file is loaded by OGS when the project is initialized. It allows to
-- configure barcode handling, user levels and other behaviors. You can 
-- also override standard functions and extend with additional features.
--
-- ***************************************************************************

-- add the shared folder (..\shared)
OGS.Project.AddPath('../shared')

-- Check, if we are running under a debugger and activate it eventually
-- See https://haller-erne.github.io/ogs/appnotes/debugging/ for more info.
require("lualib/libdebug/lua-local-debugger")

-- Load additional LUA files to implement OGS behaviours
requires = {
	"barcode",				-- load barcode.lua to define barcode processing
	"user_manager",			-- load user_manager.lua to define user rights
	"ogs-line-interface",	-- the Hilscher card line interface
}

-- Setup the top-right logo file
current_project.logo_file = 'webroot/rexroth.png'
-- Define the start screen webbrowser URL
current_project.billboard = 'index.html'

