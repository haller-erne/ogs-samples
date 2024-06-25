-- LUA module to handle the stations IO interface
--
local mb_io = require('station_io_modbus')  -- load the modbus IO driver
local struct = require("struct")            -- see http://www.inf.puc-rio.br/~roberto/struct/
local bit32 = require('bit32')              -- bit manipulation

-- Best practice is to define a module interface, so othe parts of the code can reuse/access
-- Add all data/functions which shall be accessible from other modules here.
local M = {
    data = {
        in_raw  = 0,        -- input data as read from the device (two bytes)
        in_word = 0,        -- input data decoded as 16-Bit register
        in_bit0 = 0,        -- input bit 0
    },
    old = {
        in_bit0 = 0,        -- store the old value for change detection
    }
}

-- Device I/O callback handler: called whenever the connection state of a device has changed.
-- The parameter dev is a table representing the actual device, relevant information is:
--   dev.cfg.name   name of the device as defined in station ini (section name)
--   dev.connected  connection state
local OnConnChanged = function(dev)
    if dev.cfg.name == 'REXROTH_ETH_BK' then
        if dev.connected then
            XTRACE(16, "Connection with modbus module REXROTH_ETH_BK is running!")
        else
            XTRACE(4, "Connection with modbus module REXROTH_ETH_BK lost connection!")
            -- TODO: might reset internal data/state or indicate an error
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
    if dev.cfg.name == 'REXROTH_ETH_BK' then
        -- Decode the input data from the IO module
        -- The module provides on 16-Bit register --> 2 bytes
        M.data.in_raw   = dev.data.i:sub(1, 2)                  -- get bytes 0 and 1
        M.data.in_word  = struct.unpack('<H', M.data.in_raw)    -- convert the bytestring to a 16-bit word
        M.data.in_bit0  = bit32.band(M.data.in_word, 0x0001)    -- get the bit0 value from the 16-bit word

    -- elseif dev.cfg.name == 'IOLINK_CARBO' then           -- handle other device data changes
    end
end

-- connect the driver callback events to our local function handlers
mb_io.OnConnChanged = OnConnChanged
mb_io.OnDataChanged = OnDataChanged


---------------------------------------------------------------------------------------
-- Implement the button handler
--
-- The function GetOperationResultByKeyInput() is called from OGS whenever the
-- OK/NOK-button tool is active. This allows connecting external buttons to the
-- OK/NOK function.
--
-- Return -1 = no key, 0 = OK key, 1001 = NOK key
function GetOperationResultByKeyInput (Tool, ActionName, Key, first_call)
    if first_call then
        -- Initial call. Make sure to reset the change detect logic
        M.old.in_bit0 = M.data.in_bit0
    else
        -- Subsequent calls - check for a rising edge of the button input
        if M.old.in_bit0 ~= M.data.in_bit0 then
            -- some change detected
            if M.data.in_bit0 > 0 then
                -- Button pressed (rising edge detected)
                -- Return 0 to indicate an OK button press.
                return 0
            end
            M.old.in_bit0 = M.data.in_bit0
        end
    end
    -- No change or first call: return -1 (no button pressed)
    return -1
end

-- Return the module table, so other modules can use this
return M
