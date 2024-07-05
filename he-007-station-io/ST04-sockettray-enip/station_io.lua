local enip_io = require('station_io_enip')
local struct = require("struct")    -- see http://www.inf.puc-rio.br/~roberto/struct/
                                    -- see also: https://github.com/25A0/blob
local basexx = require('basexx')
local bit32 = require('bit32')      -- bit manipulation

local M = {
    data = {
        in_raw  = 0,                -- the raw input byte
        socket  = 0,                -- selected socket (input 0.0 and 0.1)
    },
    requested_socket = 0,           -- OGS workflow request socket
}

-- Device I/O callback handler: called whenever the connection state of a device has changed.
-- The parameter dev is a table representing the actual device, relevant information is:
--   dev.cfg.name   name of the device as defined in station ini (section name)
--   dev.connected  connection state
local OnConnChanged = function(dev)
    if dev.cfg.name == 'TURCK_IO' then
        if dev.connected then
            XTRACE(16, "Connection with EtherNet/IP IO module is running!")
        else
            XTRACE(4, "Connection with EtherNet/IP IO module lost connection!")
            -- reset internal data/state or indicate an error
            M.data.socket = 0
        end
    end
end

-- Device I/O callback handler: called whenever read data of a device has changed.
-- The parameter dev is a table representing the actual device, relevant information is:
--   dev.cfg.name   name of the device as defined in station ini (section name)
--   dev.data.i     data read from the device (in form of a binary string)
--   dev.data.q     data to be send to the device (as a binary string)
local OnDataChanged = function(dev)
    --XTRACE(16, "Data changed: "..dev.cfg.name)
    if dev.cfg.name == 'TURCK_IO' then
        -- for debugging, log the new data as hexdump
        XTRACE(16, string.format("%s: In changed: %s", dev.cfg.name, basexx.to_hex(dev.data.i)))
        -- Decode data from the device and store it globally
        M.data.in_raw   = struct.unpack('<h', dev.data.i:sub(3,4))  -- word 1 is input data
        local socket_in = bit32.band(M.data.in_raw, 0x0003)         -- bits 0, 1 --> socket 1, 2
        if socket_in ~= M.data.socket then
            -- show that the socket inputs have changed:
            XTRACE(16, string.format("%s: Socket changed: %d -> %d", dev.cfg.name, socket_in, M.data.socket))
            M.data.socket = socket_in
        end
    end
end

-- connect the driver callback events to our local function handlers
enip_io.OnConnChanged = OnConnChanged
enip_io.OnDataChanged = OnDataChanged

---------------------------------------------------------------------------------------
-- Implement the virtual socket tray for socket group 2
-- See station.ini how this group is defined and mapped to tool #3
local lua_mstkn_group  = 2

-- Called from OGS whenever a new socket is requested
-- This can be used to light some LEDs for operator indication, etc...
function SetLuaSocket(group,socket)
	if group ~= lua_mstkn_group then
        -- this is not our group, so ignore (default handling)
        return false
    end
    -- this is our group, so save the requested socket number
    M.requested_socket = socket
	return true
end

-- Called from OGS, whenever OGS needs the current selected socket
-- Return values:
--   < 0 -> invalid group
--   = 0 -> no selection
--   > 0 -> selected socket
function GetLuaSocket(group)
	if group == lua_mstkn_group then
        -- check I/O if correct
        local socket = M.data.socket
        if socket then
            return socket   -- return the currently selected socket number (1, 2)
        end
		return 0    -- no selection
	end
	return -1 -- invalid group
end

-- Called from OGS to check the socket device communication state
-- return values:
--   msACTIVE 		= 0
--   msTIMEOUT		= 1
--   msBAD_PORT 	= 2
--   msSUSPENDED 	= 3
--   msACCEPT_ERROR = 4
--   msINVALID_DATA = 5
--   msWIN32FAIL 	= 6
function GetLuaSocketState(group)
	if group ~= lua_mstkn_group then
        -- this is not our group
        return 0 -- msACTIVE
    end
    -- get the current EtherNet/IP communication state
    local dev = enip_io.dev['TURCK_IO']
    if dev.connected then
        return 0 -- msACTIVE
    else
	    return 1 -- msTIMEOUT
    end
end

return M