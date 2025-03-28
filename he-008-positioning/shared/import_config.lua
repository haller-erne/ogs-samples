--------------------------------------------------------------------------------------------------
---Helper to import the tool images from the ../shared/config/images folder. Tool
---images must live in the <project>/images folder, so try to synchronize them...
---@param old_path string Source path (full file path including directory and name)
---@param new_path string Destination path (full file path)
---@return boolean success true on success, false otherwise
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
---helper to check, if a file exists
---@param path string Full path or directory of file to check ()if only directory, then add name)
---@param name string|nil name added to path
---@return boolean fileExists true, if file exists and is readyble, false otherwise
local function FileExists(path, name)
    if name then
        path = path .. '/' .. name
    end
    local h = io.open(path, "rb")
    if not h then
	    return false
    end
    return true
end
--------------------------------------------------------------------------------------------------
---helper to get the file name from a full path
---@param src string Full path of a file
---@return string fileName Filename and Extension (without directory)
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
---Helper to import the tool images from the ../shared/config/images folder. Tool
---images must live in the <project>/images folder, so try to synchronize them...
---@param srcpath string Source path (directory only)
---@param dstpath string Destination path (directory only)
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
    local parent = a[#a-1]
    a[#a] = 'config'   -- up one path and add ./config
    local configFolder = table.concat(a, '/')
    -- as there is no station.fdb, likely the images are missing, too.
    SynchronizeImages(configFolder..'/tools', OGS.Project.Paths.abs_dir..'/images')
    -- now check for config files (*.fdc) or config backup files (*.fbc)
    local names = {} -- create a set of names to check
    table.insert(names, parent)     -- the full name of the parent folder (.fdc/.fdb)
    local s1, s2 = parent:match('(he%-%d+)(%-.*)')
    if s1 and s2 then table.insert(names, s1) end   -- add the "he-008" (from "he-008-something")
    local fdc, fbc
    for _,v in pairs(names) do  -- check, if a fdc exists (preferred), else the fdb
        if FileExists(configFolder, v..'.fdc') then fdc = v..'.fdc' break end
        if FileExists(configFolder, v..'.fdb') then fbc = v..'.fdb' break end
    end
    if fdc then
        return 1, configFolder..'/'..fdc
    end
    if fbc then
        return 2, configFolder..'/'..fbc    -- try backup folder
    end
    return 0
end
