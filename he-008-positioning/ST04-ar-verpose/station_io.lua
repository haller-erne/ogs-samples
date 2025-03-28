local struct = require("struct")    -- see http://www.inf.puc-rio.br/~roberto/struct/
                                    -- see also: https://github.com/25A0/blob
local basexx = require('basexx')
local bit32 = require('bit32')      -- bit manipulation
local positioning = require('positioning')  -- positioning driver

local M = {
    data = {
        i_raw = '',                 -- the raw input bytes
        q_raw = '',
        i = {
            job = '',
            task = '',
            bits = 0,
            serno = 0
        },
        q = {
            job = '         ',
            bits = 0,
        }
    },
}

---------------------------------------------------------------------------------------
-- cyclic IO handler
local mbserver = nil
local mbalive = 0
local function HandleCyclicIO()
    -- encode the 42 bytes output data and decode the 48 bytes input
    if not mbserver then
        mbserver = ModbusIf()
    end

    -- read holding register 41025-41042 (address 1024+0...15)
    -- ART device-ID 0 inputs
    local r0 = mbserver:GetRegsStr(1024, 16, 0)
    if r0 ~= M.data.i_raw then
        M.data.i = {
            job  = struct.unpack("<c8", r0:sub(1,8)),
            task = struct.unpack("<c8", r0:sub(9,16)),
            bits = struct.unpack("<B", r0:sub(17,17)),
            serno = struct.unpack("<H", r0:sub(19,20)),
        }
        XTRACE(16, string.format("Verpose: Job=%s, Task=%s, Dump=%s", M.data.i.job, M.data.i.task, basexx.to_hex(r0)))
        M.data.i_raw = r0
    end
    -- Setup ART outputs
    local w0 = struct.pack("<c8BB", M.data.q.job, M.data.q.bits, 0)
    M.data.q_raw = w0
    -- copy the registers to 40001-40016 (address 0...15)
    mbserver:SetRegs(0, w0, 0)
end

-- add padding
local pad = function(s, l)
    if #s >= l then return s end     -- no padding needed
    local r = s..string.rep(" ",l-#s)
    return r
end

---------------------------------------------------------------------------------------
-- Hook up the cyclic poll function
local function OnStatePoll(info)
    local wf = info.Workflow
    HandleCyclicIO()

    local output = 0

    -- check if positioning is active...
	local pos = positioning.curtask.PosCtrl
	local tool = positioning.curtask.Tool
	if tool == 2 and pos and pos > 0 then
        -- enable verpose
        local job = pad(wf.JobName:sub(1,8), 8)
        M.data.q.bits = 0x01
        M.data.q.job = job
        -- check tool 1 inpos flag
        local task = pad(positioning.curtask.task:sub(1,8), 8)
        local inpos = 0
		if task == M.data.i.task and job == M.data.i.job then
			inpos = 1
		end
        if M.data.inpos ~= inpos then
            XTRACE(16, string.format("inpos = %u (%s)", inpos, M.data.i.task))
			M.data.inpos = inpos
        end
        positioning.UpdatePos_InPos(2, inpos)
    else
        -- disable the verpose camera
        M.data.q.bits = 0x00
	end

end
if StatePollFunctions ~= nil then
	StatePollFunctions.add(OnStatePoll)
end

return M