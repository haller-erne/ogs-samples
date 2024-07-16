-- LUA module to handle the stations IO interface
--
local enip_io = require('station_io_enip')
local struct = require("struct")        -- see http://www.inf.puc-rio.br/~roberto/struct/
                                        -- see also: https://github.com/25A0/blob
local basexx = require('basexx')        -- hex dumps
local bit32 = require('bit32')          -- bit manipulation
local positioning = require('positioning')  -- positioning driver

-- Best practice is to define a module interface, so othe parts of the code can reuse/access
-- Add all data/functions which shall be accessible from other modules here.
local M = {
    rot = { raw = 0, inc = 0 },     -- rotary sensor data
    lin = { raw = 0, inc = 0 },     -- len/extension sensor data
    tilt = { x = 0, y = 0 },        -- tilt sensor values (optional)
}

---------------------------------------------------------------------------------------
-- Device I/O callback handler: called whenever the connection state of a device has changed.
-- The parameter dev is a table representing the actual device, relevant information is:
--   dev.cfg.name   name of the device as defined in station ini (section name)
--   dev.connected  connection state
local OnConnChanged = function(dev)
    if dev.name == 'EAL580_LIN' then
        if dev.connected then
            XTRACE(16, "Connection with EtherNet/IP IO EAL580_LIN module is running!")
        else
            XTRACE(4, "Connection with EtherNet/IP IO EAL580_LIN module lost connection!")
            -- TODO: might reset internal data/state
            positioning.ErrorNoData(2)  -- notify positioning driver, that tool 2 has no data
        end
    end
    if dev.name == 'EAL580_ROT' then
        if dev.connected then
            XTRACE(16, "Connection with EtherNet/IP IO EAL580_ROT module is running!")
        else
            XTRACE(4, "Connection with EtherNet/IP IO EAL580_ROT module lost connection!")
            -- TODO: might reset internal data/state
            positioning.ErrorNoData(2)  -- notify positioning driver, that tool 2 has no data
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
    local fHasChange = false
    if dev.cfg.name == 'EAL580_LIN' then
        -- Decode all data from the rotation sensor for the extension (linear) axis
        M.lin.raw = dev.data.i
        M.lin.inc = struct.unpack("<L", M.lin.raw:sub(1,4))
        XTRACE(16, string.format("%s: %s", dev.cfg.name, basexx.to_hex(M.lin.raw)))
        fHasChange = true
    elseif dev.cfg.name == 'EAL580_ROT' then
        -- Decode all data from the rotation sensor for the rotation axis
        M.rot.raw = dev.data.i
        M.rot.inc = struct.unpack("<L", M.rot.raw:sub(1,4))
        XTRACE(16, string.format("%s: %s", dev.cfg.name, basexx.to_hex(M.rot.raw)))
        fHasChange = true
    end
    -- if there is any change, then update positioning
    if fHasChange then
        -- Update the position information for tool 2
        -- As we have two incremental sensors (one for rotation, one for length/distance),
        -- call the positioning drivers UpdatePos_RotIncLenInc() function:
        positioning.UpdatePos_RotIncLenInc(2, M.rot.inc, M.lin.inc, M.tilt.x, M.tilt.y, 0)
    end
end

-- connect the driver callback events to our local function handlers
enip_io.OnConnChanged = OnConnChanged
enip_io.OnDataChanged = OnDataChanged

---------------------------------------------------------------------------------------
-- Return the module table, so other modules can use this
return M
