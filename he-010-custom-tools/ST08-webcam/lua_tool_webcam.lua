-- LUA tool for the root cause map
local _M = {
    type = 'WebCam',     -- type id (must match the DRIVER= in INI file)
}
local helpers = require('lua_tool_helpers')

-------------------------------------------------------------
-- Tool event: Initialize tool - called once during OGS init 
-- return 'OK' or some error text if the initialization failes.
function _M.init(channel)
    -- Decode/get my configuration (from station.ini)
    local cfg = {
        -- ComPort = channel.ini_params.COM_PORT,      -- COM port
    }
    -- Do whatever is needed to initialize your driver
    -- ...
    channel.cfg = cfg         -- store the channels config data
    return 'OK'               -- init successfully done
end

----------------------------------------------------------------------------
-- Tool event: Cyclically called while the tool is enabled
-- return the tool task state
function _M.execute(channel)
    -- Check for tool finished
    if not _M.finished then       -- no data available from the tool
        return channel.task_state   -- wait more.
    end
    -- Build a result data table and notify the OGS core
    local values = {
        0.0,           -- M1 actual value
        0.0,           -- M2 actual value
        0.0,           -- M1 min
        0.0,           -- M1 max
        0.0,           -- M2 min
        0.0            -- M2 max
    }
    local error_code = 0 -- ok
    lua_tool_result_response(channel.tool, error_code, 0, '2A', values)
    return lua_task_completed
end

-------------------------------------------------------------
-- Tool event: Called whenever the tool is to be enabled
-- @ output: true|false  - tool enabled/not enabled 
--                         (will be called again until enabled!)
function _M.enable(channel)
    local cfg = channel.cfg     -- access the channel config data
    -- Do whatever is needed
    -- Could eventually navigate to the root cause webpage URL
    _M.finished = false
    return true                 -- tool is enabled
end

-------------------------------------------------------------
-- External interface
function _M.DoComplete(filename, jpgblob)
    -- maybe move the file save/read logic from the web_processview_lua to here
    -- and merge the files...
    _M.finished = true
end

-------------------------------------------------------------
-- register this tool with OGS (heLuaTool.dll)
helpers.register_tool(_M)
-- return the module
return _M