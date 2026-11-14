-- LUA custom tool to download a snapshot jpeg from a webcam over http get
--
local _M = {
	type = 'snapshot',     -- type identifier (as in INI file)
}
local helpers = require('lua_tool_helpers')
local dir = require('pl.dir')
local files = require('pl.file')
local ln = require('luanet')

-------------------------------------------------------------
-- Tool event: Initialize tool - called once during OGS init
-- return 'OK' or some error text if the initialization failes.
function _M.init(channel)
    -- Decode/get my configuration (from station.ini)
    local cfg = {
		url        		= channel.ini_params.URL,
		username   		= channel.ini_params.Username,
		password   		= channel.ini_params.Password,
		target_folder 	= channel.ini_params.TARGET_DIR,
		timeout       	= tonumber(channel.ini_params.TIMEOUT) or 10,
		start_time    	= 0,
    }
    -- Do whatever is needed to initialize your driver
    channel.cfg = cfg         	-- store the channels config data
    channel.fmt = {				-- define the formatting
        units = { unit1 = '', dec1 = 0, unit2 = '', dec2 = 0 },
        results = { ok='OK', nok='NOK' },   --fmt = '%(M1)3.0f ms' },
        footer = { fmt = 'Snapshot', },     -- could use ok= and nok= instead!
        prg = { fmt = 'Snapshot' },
    }
	channel.last_picture_name = ''
	local _, err = dir.makepath(channel.cfg.target_folder)
	if err then
		XTRACE(1, 'Lua Tool Snapshot '..param_as_str(channel.tool)..' : '..err)
		return 'Cannot create target_folder!'
	end
    return 'OK'               -- init successfully done
end

-------------------------------------------------------------
-- create the target file name
local function PrepareImageFileName(idcode)
	-- Dateinamenskonvention: 0000000000000000000000000_20211201_145203_00.jpg => BIN_Timestamp_00.jpeg
	local bin = idcode or active_barcodes[1].val
	local t = os.date('*t')
	local t_as_str = string.format('%04d%02d%02d_%02d%02d%02d',t.year,t.month,t.day,t.hour,t.min,t.sec)
	local picture_name = string.format('%s_%s_00.jpg', bin, t_as_str)
	--lua_tool_snapshot.last_picture_name = picture_name
	return picture_name
end
----------------------------------------------------------------------------
-- return the image, fails after the given timeout (default to 1.0s)
local function readImage(url, timeout, user, pass)
    timeout = tonumber(timeout)

	local body, code, headers = ln.get(url, user, pass)

    if body == nil then
        return nil, 'invalid response code '..tostring(code)
    end
    return 1, body

end

-------------------------------------------------------------
-- Tool event: Called whenever the tool is to be enabled
-- @ output: true|false  - tool enabled/not enabled
--                         (will be called again until enabled!)
function _M.enable(channel)
    local cfg = channel.cfg     -- access the channel config data
	-- get the parameters for the job/task/action
	local props = {
		-- job = get_object_property(1),
		-- task = get_object_property(2),
		action = get_object_property(3)
	}
	-- we do nothing here, except initialize the handle
	ResetLuaAlarm('Snapshot')
	channel.h = nil
	channel.start_time = os.clock()
	return true
end

----------------------------------------------------------------------------
-- Tool event: Cyclically called while the tool is enabled
-- return the tool task state
function _M.execute(channel)
    local cfg = channel.cfg     -- access the channel config data
	if not channel.h then
		-- start a http GET request
		local handle = ln.get_async(cfg.url, '', cfg.username, cfg.password, cfg.timeout*1000)
		if not handle then
			channel.task_state = lua_task_fault
		else
			channel.h = handle
		end
	else
		-- wait for the request to complete...
		local result = nil
		local state,code,resp,sttext = ln.poll_async_response(channel.h)
		if state == nil then    -- cannot find request - it was aborted before
			SetLuaAlarm('Snapshot', -1, 'Error requesting snapshot')
			result = 1			-- NOK
		else
			if state >= 100 then
				-- request is complete, so decode now!
				if code ~= 200 then
					SetLuaAlarm('Snapshot', -1, 'Error response from server')
					result = 2
				else
					local filename = PrepareImageFileName(active_barcodes[1].val)
					local fullname = string.format('%s/%s', cfg.target_folder, filename)
					local res, err = files.write(fullname, resp, 'b')
					if res then
						result = 0		-- success!
					else
						SetLuaAlarm('Snapshot', -1, 'File save error');
						result = 3
					end
				end
			else
				-- not finished yet
				if os.clock() - channel.start_time > cfg.timeout then
					SetLuaAlarm('Snapshot', -1, 'Timeout reading snapshot')
					ln.abort_async_request(channel.h)
					result = 4
				end
			end
		end

		-- Check for tool finished
		if result then
			-- done
			-- Build a result data table and notify the OGS core
			local values = {
				helpers.HUGE_VAL,   -- M1 actual value
				helpers.HUGE_VAL, 	-- M2 actual value
				0.0,           -- M1 min
				0.0,           -- M1 max
				0.0,           -- M2 min
				0.0            -- M2 max
			}
			local error_code = result -- ok
			lua_tool_result_response(channel.tool, error_code, 0, '2A', values)
			return lua_task_completed
		end
	end
    return channel.task_state   -- wait more.
end

----------------------------------------------------------------------------------------------
--[[
-- process raw values from DLL
-- @param tool: channel number as configured in station.ini
-- @output: values ready to show and to save into database
function _M.process_tool_result(tool)
	local ResultValues = gui_lua_support.ResultValues
	if tool ~= ResultValues.Tool then
		return 0
	end
	ResultValues.Timestamp = lua_tool_snapshot.last_picture_name
	return 1 --  processing completed
end
]]
-------------------------------------------------------------
-- register this tool with OGS (heLuaTool.dll)
helpers.register_tool(_M)
-- add the custom formatting helpers
helpers.AddDefaultFormatters(_M)
-- return the module
return _M
