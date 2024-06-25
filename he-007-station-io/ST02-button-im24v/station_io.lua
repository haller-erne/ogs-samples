-- LUA module to handle the stations IO interface
--
local bit32 = require('bit32')              -- bit manipulation

-- Best practice is to define a module interface, so othe parts of the code can reuse/access
-- Add all data/functions which shall be accessible from other modules here.
local M = {
    data = {
        in_raw  = 0,        -- input data as read from the device
        in_bit0 = 0,        -- input bit 0
        out_raw = 0,        -- output data to be written to device
    },
    old = {
        in_bit0 = 0,        -- store the old value for change detection
        in_raw  = 0,        -- input data old
        out_raw = 0,        -- output data old
    },
    is_active = nil,
    has_error = nil,
}

---------------------------------------------------------------------------------------
-- Implement the button handler
--
-- The function GetOperationResultByKeyInput() is called from OGS whenever the
-- OK/NOK-button tool is active. This allows connecting external buttons to the
-- OK/NOK function.
--
-- Return -1 = no key, 0 = OK key, 1001 = NOK key
function GetOperationResultByKeyInput(Tool, ActionName, Key, first_call)
    if first_call then
        -- Initial call. Make sure to reset the change detect logic
        M.old.in_bit0 = M.data.in_bit0
        -- Also set the output value to indicate, the tool is active
        -- As the IO offset is 2, the first free bit is 0.2 --> 0x04 --> OP 2.3
        M.data.out_raw = 0x01
        M.is_active = true
    else
        -- Subsequent calls - check for a rising edge of the button input
        if M.old.in_bit0 ~= M.data.in_bit0 then
            -- some change detected
            if M.data.in_bit0 > 0 then
                -- Button pressed (rising edge detected)
                -- Reset OpenProtocol output (tool is not active anymore)
                M.data.out_raw = 0x00
                M.is_active = nil
                -- Return 0 to indicate an OK button press.
                return 0
            end
            M.old.in_bit0 = M.data.in_bit0
        end
    end
    -- No change or first call: return -1 (no button pressed)
    return -1
end

-- Check for abort/skip while ack button is active
local function OnWorkflowStateChanged(info)
    if M.is_active then
        if info.Tool.Type ~= 6 or info.Workflow.State < 2 then
            -- halted, skipped or aborted, so reset output
            M.data.out_raw = 0
            M.is_active = nil
        end
    end
end

-- StatePoll is called cyclically
local function CyclicPoll(info)

    -- exchange data for tool 2 (OpenProtocol CHANNEL_02_xxx)
    local input, err = ToolIOExchange(2,  M.data.out_raw)
    if err then
        if not M.has_error then
            SetLuaAlarm('ToolIO', -2, param_as_str(err))
            M.has_error = true
        end
        M.data.in_raw  = 0
        M.data.in_bit0 = 0
    else
        if M.has_error then
            ResetLuaAlarm('ToolIO')
            M.has_error = nil
        end
        -- Get the data. Note, that OP 1.0 is bit 0, so OP 1.6 is bit 6 --> 0x40
        M.data.in_raw  = input
        M.data.in_bit0 = bit32.band(M.data.in_raw, 0x40)
        -- write IO changes to the trace log
        if M.data.out_raw ~= M.old.out_raw or M.data.in_raw ~= M.old.in_raw then
            XTRACE(16, string.format('IO changed. Input: %04Xh   Output: %04Xh', M.data.in_raw, M.data.out_raw))
            M.old.out_raw = M.data.out_raw
            M.old.in_raw  = M.data.in_raw
        end
    end
end

-- Add a cyclic event handler (called every ~100ms) to handle OpenProtocol IO
if StatePollFunctions ~= nil then
	StatePollFunctions.add(CyclicPoll)
end
-- Add a wrokflow state change event handler to trap abort/skip job
if StateChangedFunctions ~= nil then
	StateChangedFunctions.add(OnWorkflowStateChanged)
end

-- Return the module table, so other modules can use this
return M
