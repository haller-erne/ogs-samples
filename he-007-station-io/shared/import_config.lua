-- If the station database is not found (after installing the SW), this function
-- is called to provide the path to a config backup for automatic import...
-- Returns:
--   nil, errormessage
--   <mode>, <src>[,<dst>]
-- Where <mode> is one of the following
--   1 - import from config. <src> is <fdc-path>, <dst> is not allowed.
--   2 - import from backup. <src> is <fbc-path>, <dst> is <fdc-path> (optional,
--       if missing, defaults to the same path, but changed file extension)
OnStationDbNotFound = function()
    -- Get the full path to the config fbc/fdc
    local p, a = OGS.Project.Paths.abs_dir, {}
    for m in p:gmatch('[^\\/]+') do table.insert(a, m) end
    a[#a] = 'config'   -- up one path and add ./config
    local configFolder = table.concat(a, '/')
    local backupPath = configFolder..'/he-007.fbc'
    local configPath = configFolder..'/he-007.fdc'
    -- check, if the fdc file exists
    local f = io.open(configPath)
    if f ~= nil then
        io.close(f)     -- config file already exists, use it
        return 1, configPath
    else                -- try backup file instead
        return 2, backupPath
    end
end
