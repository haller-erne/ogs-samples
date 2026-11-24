-- PLC line interface for OGS
--
-- This module is working as a physical <=> logical layer between OGS and the PLC.
-- The PLC usually uses different names/variables and protocols, so this module
-- loads a "line-lowlevel" interface with functions to access the PLC physical data 
-- and translates it to the OGS behaviour.
--
-- Supported features are:
--  * Starting/Stopping a workflow: A handshake protocol is used to allow the PLC
--    to start and stop a workflow as well as jump to a job. At the end of a
--    workflow, OGS reports the overall result status.
--    NOTE: This module does *not* prevent entering a barcode manually through the
--          keyboard input fields on the start page. If this is needed, implement
--          some blocking logic in barcode.lua
--  * Barcode transfer: Barcodes entered/scanned are written to the PLC interface.
--  * State and data: OGS reports parts of its internal state and data
--
-- The configuration is done in the [LINE_INTERFACE] section in station.ini, the
-- following parameters are needed:
--
-- [LINE_INTERFACE]
-- ; The LINE_INTERFACE section is used by ogs-line-interface.lua to configure the line interface driver.
-- ; 
-- ; Set ENABLED=1 to enable the line interface, 0 to disable it
-- ENABLED=1
-- ;
-- ; IO_DRIVER specifies the low-level driver to use for the line interface. In this case, it is set to 
-- ; the Hilscher low-level driver. This basically defines the lua file to load for the line interface.
-- IO_DRIVER=line-lowlevel-hilscher
-- 
-- [HILSCHER]
-- ; The Hilscher card communication channel to use:
-- ; - For a remote card, use "TCP0_cifX0" typically and make sure to drop the correct cifx32dll.dll 
-- ;   and cifx.ini files in the appropriate directory. The cifxTcpServer.exe must be running on the
-- ;   remote machine.
-- ; - For a local card, use "cifx0" and make sure the cifx driver is installed and the card is 
-- ;   configured correctly using the Hilscher Communication Studio software.
-- CHANNEL=TCP0_cifX0
-- 
-- [line-lowlevel-modbus]
-- ; The Hilscher card communication channel to use:
-- ; - For a remote card, use "TCP0_cifX0" typically and make sure to drop the correct cifx32dll.dll 
-- ;   and cifx.ini files in the appropriate directory. The cifxTcpServer.exe must be running on the
-- ;   remote machine.
-- ; - For a local card, use "cifx0" and make sure the cifx driver is installed and the card is 
-- ;   configured correctly using the Hilscher Communication Studio software.
-- ;WR_REG=[ { "adr": 8001, "len": 1 } ]
-- ;RD_REG=[ { "adr": 8000, "len": 1 } ]
-- DEBUG=4
-- 

--
local plc = nil             -- the actual low-level driver is loaded during init(), see below.

local WorkflowState = {
    Idle = 0,			    --// Idle, no (total)part or job selected, waiting for user to scan barcodes
    WaitJobStart = 1,      	--// Totalpart known, job selected but locked by: user | barcode | another station | ...
    JobActive = 2,          --// Job is currently active.
    JobCompleted = 3,       --// Job was completed/aborted.
    Done = 4,               --// Totalpart/Workflow completely done
    DoneWaitUser = 5,       --// Assembly is done, but not marked in DB as archived and is still available for
                            --//   operations like: delete all results | select Job | delete Job results | Start Job
    JobAborted = 6,         --// current job aborted to execute some User request like: done, skip, delete results,
}                           --//   loosen, change curren Job/Operation
local wfLockReason = {
	notLocked = 0,          --// Job is not locked and can be started immediatly
	waitUser = 1,			--// wait for user request
	waitBarcode = 2,  		--// wait for valid barcode input
	waitExternal = 3,       --// wait for external preconditions
	waitUnlocking = 4,      --// wait for unlocking of current Job on another station
	waitDiagCfg = 5,        --// wait for diagnostic Job configuration is completed and Job started
	waitLogon = 6,          --// wait for logon completion
	waitSupervisor = 7,      --// wait for supervisor to unlock NOK processing
	waitJobRelease = 8      --// wait for Job release (from LUA)
}


local _M = {
    state = 0,
    Messages = {},
    total_state = 0,
    stopping = nil,                 -- for the end of workflow handshake
    assembly_in_process_old = 0,    -- Flankenmerker
    oldStart = nil,                 -- Flankenmerker
    oldInpos = nil,                 -- Flankenmerker f�r WTInPos
    WFID = '',                      -- workflow id - recorded at the rising edge of plc start
    start_pending = nil,
    paused = nil,
}
local _Overrides = {
}

local ResultHandler = {
    WriteWorkflowInfo = function(wf)
        local oi = plc.toPLC.line.Info
        oi.JobName          = wf.PartName
        oi.JobNum           = wf.JobSeq
        oi.TaskName         = wf.BoltName
        oi.TaskNum          = wf.BoltSeq
        oi.OpName           = wf.OpName
        oi.OpNum            = wf.Op
        oi.WorkflowState    = wf.State
        oi.WorkflowResult   = wf.LastResult
        oi.WorkflowLock     = wf.LockReason     -- TODO: add
        oi.NCIndex          = 0                 -- TODO: add
        oi.NCComment        = ''                -- TODO: add
    end,
    WriteResult = function(wf, tool)
        local oi = plc.toPLC.line.Info
        oi.ResultValue1   = wf.ResultValue1
        oi.ResultValue2   = wf.ResultValue2
        oi.ResultValue3   = wf.ResultValue3
        oi.ResultValue4   = wf.ResultValue4
        oi.ResultValue5   = wf.ResultValue5
        oi.ResultValue6   = wf.ResultValue6
        if wf.ResultCode ~= nil then
            oi.ResultStatus = wf.ResultCode
        else
            oi.ResultStatus = -1
        end
        oi.Channel          = wf.Channel            -- tool number 
        oi.PrgNum           = wf.Prg
        oi.Sequence         = (oi.Sequence or 0) + 1
        oi.Stufe            = '2A'                  -- haben wir (momentan) nicht
        oi.Tool             = tool.Type             -- the tool type
        oi.ResultTimestamp  = wf.ResultCounter      -- ticker
    end,
    result_ack = {
        ticker = 0,
        counter = 0
    },
    ClearResultAck = function(this)
        if this.result_ack.alarm then
            ResetLuaAlarm('ResultAck')
        end
        this.result_ack = { ticker = 0 , counter = 0}
    end,
    CheckResultAckStart = function(this, wf)
        local toPlcInfo = plc.toPLC.info
        local toOgsLine = plc.toPLC.line
        if toOgsLine.cmd == nil then
            return  -- not yes initialized
        end
        if wf.ResultCounter == -1 then
            this:ClearResultAck()
        else
            if toPlcInfo.ResultTimestamp  ~=  wf.ResultCounter then
                -- new result
                this:ClearResultAck()
                toPlcInfo.ResultTimestamp  = wf.ResultCounter;     -- ticker
                XTRACE(16, "PLC: new result: "..param_as_str(wf.ResultCounter))
                if toOgsLine.cmd.ResultAck == 0 then
                    this.result_ack.ack = true  -- automatic acknowledge (default)
                else
                    this.result_ack.ack = false
                    this.result_ack.ticker = os.clock()
                end
            end
        end
    end
}

local hasAlarm = nil
local function PLC_ReadChanged(toOgs, message)
    if toOgs == nil then
        SetLuaAlarm("plc connection", - 2, message)
        hasAlarm = true
        -- do whatever else is needed, if we loose the connection
        -- reset some variables
--        _M.oldStart = nil
    else
        if hasAlarm then
            -- we are connected again!
            ResetLuaAlarm("plc connection")
            hasAlarm = nil
        end
        -- do the read changed data handling

    end

end


local function poll(info)
    local wf = info.Workflow
    local err = nil

    -- check for start job
    local plcStart = plc.GetIO_WF_Start()
    local oldStart = _M.oldStart -- or plcStart        -- initialize
    local plcInPos = plc.GetIO_WF_WTInPos()
    local oldInpos = _M.oldInpos -- or plcInPos
    if (not oldStart) and plcStart then               -- rising edge of PLC start command
        -- Start! Process barcode
        local ID, Job = plc.GetIO_WF_ID()           -- get part ID and (optionally job name)
        XTRACE(16, "PLC: Command: Start: SN="..ID.." JN="..Job) --.." Tool="..plc_to_ogs.JobPara.ToolName)
        if assembly_in_process ~= 0 then -- /*or ads_order.in_process*/ then
            -- Check for job select/change
            if ID == _M.WFID and Job ~= '' then
                -- jump to job is requested!
                local ret = WorkflowJumpToTask(Job, 2)
                if ret == 2 then
                    err = true                      -- invalid start command - job not found
                else
                    _M.start_pending = os.clock()   -- wait OGS to be running again
                end
            else
                XTRACE(2, "PLC: Start: ERROR: Started while the previous order has not yet been processed: "..ID)
                --ogs_to_plc.JobStatus = 1001  -- ERROR: started while previous order running
                err = true  -- Fehler:
            end
        else
            -- try to parse the barcode and start a process
            local ret = BarCode_AddNew('PLC', '', ID)
            if ret <= 0 then        -- error, cannot parse barcode
                --ogs_to_plc.JobStatus = 1002  -- ERROR: invalid barcode
                err = true
            else
                -- OK! We should now be started (or some error occurred)
                _M.WFID = ID
                _M.start_pending = os.clock() -- do a timeout check, if we are actually started (valid model?)!
                Barcode_LastToolIdCode = ''
            end
        end
        if err then
            _M.start_pending    = nil
            plc.SetIO_WF_AckStartFailed()
            SetLuaAlarm("PLC", -1, "Invalid PLC start command received!")
        else
            ResetLuaAlarm("PLC")
            XTRACE(16, "OGS: Command: Start: waiting for OGS started...")
            plc.SetIO_WF_AckStarting()
            ResultHandler:ClearResultAck()
        end
    elseif oldStart and (not plcStart) then
        -- Abbruch/Halt/Pause/Stop!
        local ID, Job = plc.GetIO_WF_ID()         -- get part ID and (optionally job name)
        if ID == _M.WFID and Job ~= '' then
            XTRACE(16, string.format("PLC: Command: Halt/Pause: %s, Job=%s", ID, Job))
            -- Halt/Pause
            -- TODO: switch OGS in wait for job selection mode...
            plc.SetIO_WF_Paused()
            _M.paused = true
        else
            XTRACE(16, "PLC: Command: Stop/Abort: "..ID)
            _M.start_pending = nil
            --os.WorkflowActive       = 0
            if assembly_in_process ~= 0 then
                -- Abbruch
                --ogs_to_plc.JobStatus      = 2001  -- PLC abort
                WorkflowJumpToTask('#done#')
            else
                plc.SetIO_WF_Finished()
            end
        end
    end

    -- handle delayed job switch (only switch, if OGS is in the correct state)
    if _M.paused and _M.start_pending then
        if ((wf.State == WorkflowState.WaitJobStart and (wf.LockReason ~= wfLockReason.notLocked
            or wf.LockReason ~= wfLockReason.waitJobRelease)) or (wf.State == WorkflowState.JobActive)) then
            XTRACE(16, "PLC: new job selected")
            plc.SetIO_WF_AckStartedOk()
            -- TODO: release OGS from paused state?
            _M.paused = nil
            _M.start_pending = nil
        end
    end

    --if plc_to_ogs_old.FaultAck == 0 and plc_to_ogs.FaultAck ~= 0 then
    --    -- at the rising edge, try to acknowledge all pending alarms
    --    AckLuaAlarm();
    --end

    -- write workflow state to PLC
    plc.SetIO_Ready(true)
    plc.SetIO_WF_Running(assembly_in_process ~= 0)
    plc.SetIO_UserLevels(UserManager.user_level, UserManager.master_level, UserManager.user, UserManager.master)
    plc.SetIO_Errors(0)
    plc.SetIO_ID('')
    plc.SetIO_WF_Info(wf)
    if wf == nil then return end
    if assembly_in_process == 1 then
        if Barcode_GetID then
            local id = active_barcodes[1].val .. active_barcodes[2].val .. Barcode_GetID()  -- active_barcodes[1].val .. active_barcodes[2].val .. active_barcodes[3].val
            plc.SetIO_ID(id)
        end
    end

    -- cyclicylly update plc data from our OGS state
    ResultHandler.WriteWorkflowInfo(wf)
    -- check, if we need a result acknowledge handshake
    ResultHandler:CheckResultAckStart(wf)
    -- more specific stuff...

    -- check for start or stop completion
    if assembly_in_process == 0 then
        if _M.start_pending and (os.clock() - _M.start_pending) > 2 then
            XTRACE(1, "PLC: Start timeout - likely wrong model detected!")
            _M.start_pending = nil      -- start failed - likely wrong type
            _M.stopping = true
            plc.SetIO_WF_AckStartFailed()
        end
    end
    -- check for process end
	if assembly_in_process ~= _M.assembly_in_process_old then
        if assembly_in_process == 0 then
            if not _M.stopping then
                XTRACE(16, "PLC: Workflow ended")
            end
            _M.stopping = true
            plc.SetIO_WF_Done(_M.total_state)
            XTRACE(16, string.format("PLC: Workflow stopped, OK=%d", _M.total_state))
        else
            XTRACE(16, "PLC: Assembly started")
            _M.total_state = 0          -- unknown
            _M.start_pending = nil      -- successfully started
            _M.paused = nil
            plc.SetIO_WF_AckStartedOk()
        end
        _M.assembly_in_process_old = assembly_in_process
    end
    -- finishing handshake
    if _M.stopping and assembly_in_process == 0 then
        -- if plcStart == 0 then
        if (not plcStart) or (oldInpos and (not plcInPos)) then
            -- done, Acknowledge to PLC
            _M.stopping = nil
            plc.SetIO_WF_Finished()
            XTRACE(16, "PLC: Acknowledge: PLC Stopped, start back to 0")
        end
    end

	if _M.Station and _M.Station == 1 then
		if plcInPos == 0 and plc.GetIO_WF_Done() == 1 then
			plc.SetIO_WF_Finished()
			XTRACE(16, "PLC: Acknowledge: WT left station, start back to 0")
		end
	end

    _M.oldStart = plcStart  -- keep old value for next change
    _M.oldInpos = plcInPos  -- keep old value for next change
end

-- Catch the job completion event and forward signals to the PLC
_Overrides.JobCompletedEvent = JobCompletedEvent
function JobCompletedEvent(JobSeq, JobName, JobScope, JobCode, JobState, TotalState)
    -- JobState/TotalState:  UNKNOWN = 0x00, OK = 0x01, NOK = 0x02, NOT_PROCESSED = 0x04
    local isDone	= 1
    local isOk   	= 0
    if JobState == 1 then
        isOk = 1
    end
    plc.SetIO_WF_JobState(isDone, isOk)
    if _Overrides.JobCompletedEvent then
        _Overrides.JobCompletedEvent(JobSeq, JobName, JobScope, JobCode, JobState, TotalState)
    end
end

_Overrides.Barcode_StopAssembly = Barcode_StopAssembly
function Barcode_StopAssembly(TotalState)
    -- JobState/TotalState:  UNKNOWN = 0x00, OK = 0x01, NOK = 0x02, NOT_PROCESSED = 0x04
    _M.total_state = TotalState
    if _Overrides.Barcode_StopAssembly then
        _Overrides.Barcode_StopAssembly(TotalState)
    end
end

-- return values: [<string>,] <bool>
-- <string> : Text to show if release is not granted
-- <bool>   : release granted/not granted
-- _Overrides.GetJobReleaseByName = GetJobReleaseByName
function GetJobReleaseByName(JobName)

    if plc.GetIO_Job_BlockEnd() then
        return 'Warte auf Freigabe durch SPS'
    end
    local isDone	= 0
    local isOk   	= 0
    plc.SetIO_WF_JobState(isDone, isOk)
    return true  -- release

end


local function init()
    -- read the configuration from the [LINE_INTERFACE] section
    local ini_section = 'LINE_INTERFACE'
	local tbl = ReadIniSection(ini_section)
	if type(tbl) ~= 'table' then
		error(string.format('INI-section: "%s" not found', ini_section))
	end
	if type(tbl.IO_DRIVER) ~= 'string' then
		error(string.format('missing parameter "IO_DRIVER" in INI-section "%s"', ini_section))
	end
    local cfg = {
        tbl         = CloneTable(tbl),              -- just in case we need it later
        enabled     = tonumber(tbl.ENABLED) or 1,
        module      = tbl.IO_DRIVER,
        config      = tbl.IO_CONFIG or tbl.IO_DRIVER,
        debug       = tonumber(tbl.DEBUG) or 0,
        messages    = tbl.MESSAGES or nil
    }
    _M.cfg  = cfg
    plc = require(cfg.module)                       -- "hilscher-line-lowlevel"

    -- initialize LL driver
    local ret = plc.init(cfg.config, PLC_ReadChanged)
    if ret ~= nil then
        -- some error
        error('Cannot initialize PLC: '..ret)
    end
    -- read the messages from station.ini
    if cfg.messages then
        local tbl = ReadIniSection(cfg.messages)
        for i = 1,32 do
            local key = string.format("MESSAGE_%02d", i)
            if tbl[key] ~= nil then
                local entry = tbl[key]
                local comma = entry:find(',')
                local m = { lvl = 1, msg = key, visible = false }
                if comma ~= nil and comma > 1 then
                    m.lvl = tonumber(string.sub(entry, 1, comma-1))
                    m.msg = string.sub(entry, comma+1)
                    if m.lvl > 0 then
                        m.lvl = -m.lvl
                    end
                end
                _M.Messages[i] = m
            end
        end
    end
	_M.Station = tonumber (ReadIniValue('GENERAL','STATION'))

end

-- cyclically handle PLC interface changes
local function PLC_StatePoll(info)
	if _M.state == 0 then
        init()
        _M.state = 1
    elseif _M.state == 1 then
        -- poll the LL driver
        plc.poll()
        -- if we are connected (so we have at least read once and the lua data
        -- is initialized), then now do the real work
        if plc.isConnected() then   -- cyclic io is running!
            _M.state = 2
        end
    elseif _M.state == 2 then
        -- initialized everything successfully, so cyclically process now
        -- poll the LL driver
        plc.poll()
        -- poll our state machine
        if not plc.isConnected() then
            _M.state = 1
        else
            poll(info)
        end
    end
end

local function PLC_StateChanged(info)
    -- TODO: check for tool results and forward them over PLC
    local wf = info.Workflow
    local tool = info.Tool
    if wf.Why == 1 and wf.State == 2 then
        -- new result received
        if tool.Type >= 1 and tool.Type <= 3 then
            -- new tightening result!
            ResultHandler.WriteResult(wf, tool)
        end
    end
end


-------------------------------------------------------------------------------
-- Hookup OGS callbacks
if StatePollFunctions ~= nil then
	StatePollFunctions.add(PLC_StatePoll)
end
if StateChangedFunctions ~= nil then
	StateChangedFunctions.add(PLC_StateChanged)
end
--if StateShutdownFunctions ~= nil then
--	StateShutdownFunctions.add(PLC_Shutdown)
--end

return _M