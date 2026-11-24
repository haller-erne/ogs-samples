-- Lowlevel Hilscher CifX interface for OGS
--
-- The main interface is:
--   _M.init(section, onChange): initialize communication settings (from station.ini table)
--   _M.poll(cyclically poll): poll the state machine
--   _M.isCyclicIORunning(): return current communication status
--   _M.toPLC: interface variable - changes here will get written with the next "poll"
--   _M.toOGS: interface variable - has the last read data from the PLC (note, that
--             this is only updated on a relevant change to minimize deserialization
--             overhead)
-- Logical interface for exchanging logical data...
--
--
-- Note, that some low-level stuff (like alive, etc) is handled internally, the
-- onChange callback is only executed, if a relevant change (i.e. something different
-- from Alive) is detected.
--
local cifx = require("luacifx")     -- load the Hilscher lua driver
local basexx = require('basexx')
local struct = require('struct')
local bit32 = require('bit32')

local _M = {
    cfg = nil,                      -- the parameters from station.ini
    h = nil,                        -- the Hilscher driver channel handle
    onChange = nil,                 -- on read changed callback
    state = {                       -- internal state machine
        state = 0,
        cycles = 0,
        cyclic_io_active = nil,
    },
}

-------------------------------------------------------------------------------
-- Create the type annotations from the actual OPC-UA type information
-- TODO: read data type and create lua language server bindings


-------------------------------------------------------------------------------
-- Export the complete data structure OGS --> PLC
_M.toPLC = {
    bytes = '',
    line = { State = {}, Info = {}, },
}

-- PLC --> OGS
_M.toOGS = {
    bytes = '',
    line = { Cmd = {} },
}

-------------------------------------------------------------------------------

---comment
--- Decode the raw input bytes into a structure
---@param rdData string Binary string to be deserialized
---@return table|nil rdTable Decoded table from the raw data
---@return string rdBytes Raw bytes read from the PLC (or error message)
_M.getInputsTbl = function(rdData)

    if not rdData or #rdData < 32 then      -- need at least 32 bytes
        return nil, 'no data (nil)'
    end

    local bits = struct.unpack('<H', rdData)
    local line = {
        Conn = {
            Alive = (bit32.band(bits, 0x0001) ~= 0),
            Mirror = (bit32.band(bits, 0x0002) ~= 0),
            Ticker = 0,
        },
        Cmd = {
            Start_Process = (bit32.band(bits, 0x0004) ~= 0),
            Block_JobEnd = false,
            Result_Ack = false,
            Rework = false,
            WT_InPos = false,
            Scan_Ind = false,
            Button_Ok = false,
            Button_Nok = false,
            ID = rdData:sub(3, 32):gsub("[%s%z]+$", ""),    -- right trim whitespace and $00
            Job = '',
            UserLevel1 = 0,
            UserLevel2 = 0,
            UserName = '',
        },
    }

    return line, rdData
end

---
---
_M.setOutputsTbl = function(to_plc)  -- serialize the "line" table

    local bits = 0
    local Conn = to_plc.Conn
    if Conn.Alive then bits = bits + 0x0001 end
    if Conn.Mirror then bits = bits + 0x0002 end
    local State = to_plc.State
    if State.Ready then bits = bits + 0x0004 end
    if State.Ack_Start then bits = bits + 0x0008 end
    if State.Ack_TypeOk then bits = bits + 0x0010 end
    if State.WorkflowActive then bits = bits + 0x0020 end
    if State.WorkflowDone then bits = bits + 0x0040 end
    if State.WorkflowOk then bits = bits + 0x0080 end
    local wrData = struct.pack('<H', bits)
    wrData = wrData .. string.format("%-30.30s", to_plc.Info.ID)
    local Info = to_plc.Info
    wrData = wrData .. struct.pack('>BBBB', Info.Sequence, Info.Tool, Info.Channel, Info.PrgNum)
    wrData = wrData .. struct.pack('>I', Info.ResultStatus)
    wrData = wrData .. struct.pack('>fff', Info.ResultValue1, Info.ResultValue2, Info.ResultValue3)
    wrData = wrData .. struct.pack('>fff', Info.ResultValue4, Info.ResultValue5, Info.ResultValue6)
    return wrData
end
_M.getOutputsTbl = function ()
    return {
        Conn = { Alive = false, Mirror = false, Ticker = 0 },
        State = { Ready = false, Ack_Start = false, Ack_TypeOk = false, WorkflowActive = false, WorkflowDone = false, WorkflowOk = false },
        Info = { 
            ID='', Sequence=0, Tool=0, Channel=0, PrgNum=0, ResultStatus=0,
            ResultValue1=0, ResultValue2=0, ResultValue3=0, ResultValue4=0, ResultValue5=0, ResultValue6=0 
        },
    }
end

-------------------------------------------------------------------------------
local function SetAlarm(level, message)
    SetLuaAlarm("plc connection", level, message)
end
local function ResetAlarm()
    ResetLuaAlarm("plc connection")
end
-------------------------------------------------------------------------------
-- Initialize the OPCUA interface and setup an onChange callback
-- return nil or error
_M.init = function(section, onChange)

	local tbl = ReadIniSection(section)
	if type(tbl) ~= 'table' then
		return string.format('INI-section: "%s" not found', section)
	end
	if type(tbl.CHANNEL) ~= 'string' then
		return string.format('missing parameter "CHANNEL" in INI-section "%s"', section)
	end
    local cfg = {
        tbl         = CloneTable(tbl),              -- just in case we need it later
        cifx        = tbl.CHANNEL,
        toPlcVar    = tbl.TO_PLC_VAR,
        toPlcDty    = tbl.TO_PLC_DTY or '',
        toOgsVar    = tbl.TO_OGS_VAR,
        toOgsDty    = tbl.TO_OGS_DTY or '',
        debug       = tonumber(tbl.DEBUG),
    }
    _M.cfg  = cfg
    local h,err,msg = cifx.new_channel(cfg.cifx, 0)
    if not h then
        local msg = string.format("Failed to open Hilscher channel %s: %s (%s)", cfg.cifx, tostring(err) or '??', tostring(msg) or '??')
        XTRACE(1, msg);
        return msg
    end
    _M.h = h
    _M.onChange = onChange
    _M.state.state = 0

    -- set the host state to "host ready" (1)
    local hs_old,err,msg = h:setHostState(1)
    if not hs_old then
        local msg = string.format("Failed to set the Hilscher card host state: %s (%s)", tostring(err) or '??', tostring(msg) or '??')
        XTRACE(1, msg);
        return msg
    end
    -- set the bus state to "bus on" (1)
    local bs_old,err,msg = h:setBusState(1)
    if not bs_old then
        local msg = string.format("Failed to set the Hilscher card bus state: %s (%s)", tostring(err) or '??', tostring(msg) or '??')
        XTRACE(1, msg);
        return msg
    end

    return nil -- OK!
end

-- Call the onChange user callback (if any)
local function notifyChange(data, message)
    if _M.onChange then
        _M.onChange(data, message)
    else    -- implement default alarms
        if not data then
            SetAlarm(-2, message)
        else
            if _M.state.cycles == 0 or (not _M.state.hasAliveAlarm) then
                ResetAlarm() 
            end
        end
    end
end
-- Call the onChange handler, if there is no connection (anymore)
local function notifyDisconnect(message)
    notifyChange(nil, message)
end

-- returns err, newdata
_M.poll = function()
    local newdata = false
    local state = _M.state

    -- check, if cyclic IO is running
    local bs,err,msg = _M.h:getBusState()
    local running = (bs == 1)
    _M.state.cyclic_io_active = running

    if state.state == 0 then
        state.i_old = ''
        state.tAliveRcv = os.clock()
        state.tAliveXmt = os.clock()
        if running then
            XTRACE(16, "PLC: connected to ".._M.cfg.cifx)
            state.last_err = nil
            state.start_timer = nil
            state.state = 10
            state.cycles = 0
            -- get the initial values
--            local rdTable, rdData, rdState = _M.h:getInputsTbl()
            _M.toOGS.bytes = ''     -- force change
            _M.toOGS.line = rdTable or { Conn = {}, Cmd = {}, }
            local wrTable, wrdData, wrState = _M.getOutputsTbl()
            _M.toPLC.bytes = ''     -- force change
            _M.toPLC.line = wrTable or { Conn = {}, State = {}, Info = {}, }
            state.tAliveRcv = os.clock()
        end
        if state.start_timer ~= nil and os.clock() - state.start_timer > 20 then
            XTRACE(2, "PLC: timeout waiting for bus running ".._M.cfg.cifx)
            notifyDisconnect("PLC: Couldn't establish connection")
            state.start_timer = nil
        end

    elseif state.state == 10 then
        -- check connection
        if not running then
            -- lost the connection
            state.last_err = -1;
            XTRACE(2, "PLC: disconnected!")
            notifyDisconnect("PLC: disconnected!")
            state.state = 0
        else
            -- get (raw) input data from PLC
            local rdData, err, msg = _M.h:IORead() -- (0, 32)	
            if rdData then
                -- We have valid data! Now check for changes
                local to_ogs = _M.toOGS
                if rdData ~= to_ogs.bytes then
                    -- Something has changed (including alive and mirror) - so now get the deserialized data
                    local rdTable, rdBytes = _M.getInputsTbl(rdData)
                    if not rdTable then
                        -- error!
                        XTRACE(2, 'PLC: failed to decode input data: ' .. (rdBytes or '?'))
                        state.state = 0
                    else
                        if _M.cfg.debug and _M.cfg.debug > 2 then XTRACE(16, string.format('     rd: #size=%d: %s', #rdBytes, basexx.to_hex(rdBytes))) end
                        -- TODO: optimize: filter timestamp and alive
                        to_ogs.line = rdTable                                  -- set the decoded data as the "line" member table
                        if state.last_alive ~= to_ogs.line.Conn.Alive then     -- check our the toggling PLC alive signal
                            state.tAliveRcv = os.clock()
                            state.last_alive = to_ogs.line.Conn.Alive
                            if state.hasAliveAlarm then
                                XTRACE(2, "OpcUA: Connection running again!")
                                notifyChange(to_ogs)
                            end
                            state.hasAliveAlarm = false
                        end
                        _M.toPLC.line.Conn.Mirror = to_ogs.line.Conn.Alive
                        -- check, if anything except the first 8 bytes (the Conn header) has changed
                        if to_ogs.bytes == nil or (to_ogs.bytes:sub(9, #to_ogs.bytes) ~= rdData:sub(9, #rdData))
                        then
                            newdata = true
                            if _M.cfg.debug then XTRACE(16, string.format('     rd: #size=%d: %s', #rdData, basexx.to_hex(rdData))) end
                            notifyChange(to_ogs)
                        end
                        to_ogs.bytes = rdData
                    end
                end
                state.last_err = nil;
            end

            -- serialize and convert to OPCUA
            local to_plc = _M.toPLC                     -- get the structured data
            to_plc = to_plc or { State = {}, Info = {}, }
            local rv = _M.setOutputsTbl(to_plc.line)  -- serialize the "line" table
            -- TODO: debug output (requires updated LuaOPCUA.dll)
            local ret,err,msg = _M.h:IOWrite(rv)
--[[        if bytes ~= to_plc.bytes then
                -- be verbose and log changes
                if to_plc.bytes ~= nil and (string.sub(to_plc.bytes, 3) ~= string.sub(bytes, 3))  -- ignore alive and mirror
                then
                    if _M.cfg.debug then
                        XTRACE(16, string.format('     wr: #size=%d: %s', #bytes, basexx.to_hex(bytes)))
                        --XTRACE(16,  string.format("    wr: AckStart=%d, AckTypOk=%s, WFDone=%d, WFOK=%d, SysErr=%d",
                        --    to_plc.line.State.Ack_Start, to_plc.line.State.Ack_TypeOk, to_plc.line.State.WorkflowActive,
                        --    to_plc.line.State.WorkflowDone, to_plc.line.State.WorkflowOk, to_plc.line.State.SystemError))
                    end
                end
                to_plc.bytes = bytes                -- remember old write data
            end
]]--
            if ret then
                state.last_err = nil;
                if rdData == 0 then
                    state.cycles = state.cycles + 1
                end
            else
                state.last_err = err
                SetAlarm(-2, "OpcUA: PLC write error!")
                XTRACE(2, "OpcUA: WR: Error: "..tostring(err))
                state.state = 0
            end
        end
    end

    -- send our own alive signal (500ms)
    if state.state >= 10 and (os.clock() - state.tAliveXmt) > 0.5 then
        _M.toPLC.line.Conn.Alive = not _M.toPLC.line.Conn.Alive
        state.tAliveXmt = os.clock()
    end

    -- check for timeout
    if state.state >= 10 and (os.clock() - state.tAliveRcv) > 5.0 then
        -- TIMEOUT!
        if not state.hasAliveAlarm then
            state.hasAliveAlarm = true
            XTRACE(2, "OpcUA: Alive Timeout!")
            notifyDisconnect("OpcUA: timeout, lost connection to PLC!")
        end
    end

    return state.last_err, newdata
end

_M.isConnected = function()
    -- inst.state >= 10
    return _M.state.cyclic_io_active
end

-- OGS->PLC
_M.SetIO_Ready = function(rdy)          -- set the ready signal
    local os = _M.toPLC.line.State      -- do not ack the start yet (process internally first)
    os.Ready            = rdy
end

-- Workflow start and stop handshaking
-- The start sequence is either
--      AckStarting --> AckStartFailed
-- or   AckStarting --> AckStartedOk
_M.SetIO_WF_AckStarting = function()    -- only reset the previous WF result signals,
    XTRACE(16, "OPCUA: SetIO_WF_AckStarting")
    local os = _M.toPLC.line.State      -- do not ack the start yet (process internally first)
    os.Ack_Start        = false
    os.Ack_TypeOk       = false
    os.WorkflowDone     = false
    os.WorkflowOk       = false
    os.JobDone          = false
    os.JobOk            = false
    os.WorkflowResult   = 0
end
_M.SetIO_WF_AckStartFailed = function() -- Report a failed WF start and set an error code
    XTRACE(16, "OPCUA: SetIO_WF_AckStartFailed")
    local os = _M.toPLC.line.State
    --os.FaultActive    = 1
    --os.FaultNo        = 301 -- invalid start parameter set
    os.Ack_Start        = true
    os.Ack_TypeOk       = false
    os.WorkflowDone     = true
    os.WorkflowOk       = false
end
_M.SetIO_WF_AckStartedOk = function()   -- acknowledge successful WF start
    XTRACE(16, "OPCUA: SetIO_WF_AckStartedOk")
    local os = _M.toPLC.line.State
    os.Ack_Start        = true
    os.Ack_TypeOk       = true
    os.WorkflowDone     = false
    os.WorkflowOk       = false
end
_M.SetIO_WF_Paused = function()
    XTRACE(16, "OPCUA: SetIO_WF_Paused")
    local os = _M.toPLC.line.State
    os.Ack_Start        = false
    os.Ack_TypeOk       = false
    os.WorkflowDone     = false
    os.WorkflowOk       = false
end
_M.SetIO_WF_Done = function(total_state)
    XTRACE(16, "OPCUA: SetIO_WF_Done")
    local os = _M.toPLC.line.State
    os.JobDone          = false
    os.JobOk            = false
    os.WorkflowDone     = true
    if total_state == 1 then
        os.WorkflowOk   = true
    else
        os.WorkflowOk   = false
    end
    os.WorkflowResult   = total_state
end
_M.SetIO_WF_Finished = function()
    XTRACE(16, "OPCUA: SetIO_WF_Finished")
    local os = _M.toPLC.line.State
    os.Ack_Start        = false
    os.Ack_TypeOk       = false
    os.WorkflowDone     = false
    os.WorkflowOk       = false
    os.JobDone          = false
    os.JobOk            = false
end
_M.SetIO_WF_Running = function(isRunning)
    local os = _M.toPLC.line.State
    os.WorkflowActive   = isRunning
end
_M.SetIO_WF_JobState = function(JobDone, JobOk)
    local os = _M.toPLC.line.State
    os.JobDone          = JobDone
    os.JobOk            = JobOk
end

_M.SetIO_WF_Info = function(wf)
    local os = _M.toPLC.line.State
    os.WorkflowState    = wf.State
    local oi = _M.toPLC.line.Info
    oi.JobNum           = wf.JobNumber
    oi.TaskNum          = wf.BoltSeq        -- BoltNum is DB-ID
	oi.OpNum            = wf.Op             -- OpCounter?
	oi.JobName          = wf.JobName        --
	oi.TaskName         = wf.BoltName       --
	oi.OpName           = wf.OpName
	oi.ID               = wf.PartSerial     -- better: ToolID?
	-- SetResults(wf)
	oi.Channel          = wf.Channel
	oi.PrgNum           = wf.Prg
    -- TODO: additional data not yet mapped on the PLC end
	--oi.PosCtrl          = wf.PosCtrl
    --oi.Why              = wf.Why
    -- TODO: parameters where we currently don't have data in wf
	--oi.Tool             = 0
	--oi.Socket           = 0
end

_M.SetIO_Errors = function(ErrorCode)
    local os = _M.toPLC.line.State
    --os.ErrorCode        = ErrorCode
end
_M.SetIO_ID = function(ID)
    local oi = _M.toPLC.line.Info
    oi.ID               = ID
end

_M.SetIO_UserLevels = function(user, admin, user_name, admin_name)
    local os = _M.toPLC.line.State
    if os.UserLevel then
        -- old data structure
        if admin and (admin ~= 0) then
            os.UserLevel    = admin
        else
            os.UserLevel    = user
        end
        if user_name ~= nil then
            os.UserName     = user_name
        end
    else
        os.UserLevel1   = user or 0
        os.UserLevel2   = admin or 0
        os.UserName1    = user_name or ''
        os.UserName2    = admin_name or ''
    end
end

_M.SetIO_TaktTime = function(elapsed, scheduled, tbeg, tend)
    local oi = _M.toPLC.line.Info
    oi.ElapsedTimeSec   = elapsed
    oi.ScheduledTimeSec = scheduled
    oi.PlannedBegSec    = tbeg
    oi.PlannedEndSec    = tend
end

_M.SetIO_Button = function(btn, val)
    local os = _M.toPLC.line.State
    if os then
        os.Button_Req = val
    end
end

_M.SetIO_Alarms = function(alarmActive, alarms)
    local os = _M.toPLC.line.State
    os.AlarmActive = alarmActive
    local oa = _M.toPLC.line.Alarm
    if alarms then
        oa.Alarms = alarms
    end
end

-- PLC --> OGS
_M.GetIO_UserLevel = function()
    local pc = _M.toOGS.line.Cmd
    return pc.UserLevel1, pc.UserName
end

_M.GetIO_Alarms = function()
    local pc = _M.toOGS.line.Alarm
    if pc then
        return pc.Alarms or 0, pc.MsgLevel or 0, pc.MsgText or ''
    end
    return 0, 0, ''
end

_M.GetIO_WF_Start = function()
    local pc = _M.toOGS.line.Cmd
    return pc.Start_Process
end
_M.GetIO_WF_ID = function()
    local pc = _M.toOGS.line.Cmd
    return pc.ID, pc.Job
end
_M.GetIO_Job_BlockEnd = function()
    local pc = _M.toOGS.line.Cmd
    return pc.Block_JobEnd
end
_M.GetIO_WF_WTInPos = function()    -- WT ist in Position
    local ic = _M.toOGS.line.Cmd
    return ic.WT_InPos
end
_M.GetIO_Button = function()
    if _M.toOGS.line then
        local pc = _M.toOGS.line.Cmd
	    if pc then
	        return pc.Button_Ok, pc.Button_Nok
	    end
    end
    return false, false
end


_M.GetIO_WF_Done = function()    -- readback
    local os = _M.toPLC.line.State
    return os.WorkflowDone
end
return _M