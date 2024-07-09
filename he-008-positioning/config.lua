-- Define where the actual project files are stored.
-- This allowes to quickly swith between project saved in different subfolder
-- (point the monitor.lua configuration to here and change the project_folder here).
--
--local project_folder = 'ST01-digital-io'
--local project_folder = 'ST02-iolink-sensors'
local project_folder = 'ST03-ar-tracking'

-- Do NOT change the following lines!
require("shared.loadconfig").init(project_folder)
require(project_folder..".config")
