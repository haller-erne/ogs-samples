local M = {}

M.init = function(project_folder)
    -- Make sure to adjust the paths accordingly!

    -- Twiddle in the internals - see ogs.lua for what is done by default and what
    -- is overridden here...
    local ogs = require("lualib/ogs")
    local old_base_folder = current_project.base_folder
    local new_base_folder = old_base_folder .. '/' .. project_folder

    -- add new project folder to search path (to the beginning)
	current_project.base_folder = new_base_folder
    package.path = current_project.base_folder.."/?.lua;"..package.path
	local cfg_path = new_base_folder .. "/config.lua"

	-- we expect the config file at the given base path, nowhere else!
	local f=io.open(cfg_path,"r")
    if f~=nil then
        io.close(f)
    else
	    error("Config file 'config.lua' not found!\r\nFull path:\r\n"..cfg_path)
	end

    -- setup project info
    local p = ogs.Project.Paths
    p.base_folder = new_base_folder
	p.cfg_path = cfg_path
end

return M