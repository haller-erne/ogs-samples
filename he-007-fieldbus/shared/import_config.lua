--------------------------------------------------------------------------------------------------
-- Helper to import the tool images from the ../shared/config/images folder. Tool
-- images must live in the <project>/images folder, so try to synchronize them...
--
local function CopyFile(old_path, new_path)
    local old_file = io.open(old_path, "rb")
    local new_file = io.open(new_path, "wb")
    local old_file_sz, new_file_sz = 0, 0
    if not old_file or not new_file then
	    return false
    end
    while true do
		local block = old_file:read(2^13)
		if not block then
			old_file_sz = old_file:seek( "end" )
			break
		end
		new_file:write(block)
    end
    old_file:close()
    new_file_sz = new_file:seek( "end" )
    new_file:close()
    return new_file_sz == old_file_sz
end
--------------------------------------------------------------------------------------------------
-- helper to get the file name from a full path
local function LuaExtractFileName(src)
    local rev = src:reverse()
    local lastslash = rev:find("%\\")
    local lastbackslash = rev:find("%/")
    if not lastslash then lastslash = 1024 end
    if not lastbackslash then lastbackslash = 1024 end
    if lastbackslash < lastslash then
        return src:sub(-lastbackslash+1)
    else
        return src:sub(-lastslash+1)
    end
end
--------------------------------------------------------------------------------------------------
-- Helper to import the tool images from the ../shared/config/images folder. Tool
-- images must live in the <project>/images folder, so try to synchronize them...
--
local function SynchronizeImages(srcpath, dstpath)
	-- check directory
	local paths, files = GetFileList(srcpath, 'tool*.png')
	if paths ~= nil then
		if files == nil then -- OGS backward compatibility
            files = {}
            for i, filename in pairs(paths) do
                files[i] = LuaExtractFileName(filename)
            end
		end
		for i, filename in pairs(paths) do
			local fname = dstpath..'/'..files[i]
			CopyFile(filename, fname)
		end
	end
end
--------------------------------------------------------------------------------------------------
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
    local backupPath = configFolder..'/he-010.fbc'
    local configPath = configFolder..'/he-010.fdc'
    -- as there is no station.fdb, likely the images are missing, too.
    SynchronizeImages(configFolder..'/tools', OGS.Project.Paths.abs_dir..'/images')
    -- check, if the fdc file exists
    local f = io.open(configPath)
    if f ~= nil then
        io.close(f)     -- config file already exists, use it
        return 1, configPath
    else                -- try backup file instead
        return 2, backupPath
    end
end
