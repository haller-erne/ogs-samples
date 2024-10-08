--[[

Provide workflow data

]]--
local bit32 = require("bit32")
local M = {}

local _m = {
    -- local instance data
    oldWfState = 0,
    oldWfJobSeq = 0,
    oldWfActionSeq = 0,
    resultList = {},
    resultMap = {},
    allResults = {},
    lastResult = nil,
}

local _wfData = {
    updates,            -- number of updates since start of workflow
	curJobSeq,          -- currently active/selected job sequence
	curJobRawName,      -- currently active/selected job raw name
    jobs = {            -- array of jobs for this workflow
        {
            Seq = 1,        -- sequential number of jobs 1..N
            RawName = "",   -- raw name as read from the DB
            State = 0,      -- job state (bitmap of 0=unknown, 1=OK, 2=Nok, 4=not processed)
            tasks = {},     -- list of tasks of this job
            actions = {},   -- list of actions for this job
        },
    },
}

-- merge the global (static) .Workflow info and the current callback data wf
-- NOTE: this only updates the "current" job info, not others (for performance reasons)
local UpdateCurrentJobData = function(wf)
    -- update job info
	_wfData.curJobSeq       = wf.JobSeq
	_wfData.curJobRawName   = wf.JobName
	_wfData.curJobBlocked   = wf.JobIsBlocked
	_wfData.curLockReason   = wf.LockReason
    -- update task info
    _wfData.curBoltName     = wf.BoltName
    _wfData.curBoltNum      = wf.BoltNum    -- the database wide unique bolt id
    _wfData.curBoltSeq      = wf.BoltSeq    -- current number/sequence within job
    _wfData.curBoltState    = wf.BoltState  -- 1, 2, 4, ...
    -- operation info
    _wfData.curOp           = wf.Op         -- unique op id
    _wfData.curOpCnt        = wf.OpCounter  --
    _wfData.curOpName       = wf.OpName     -- unique op id
    -- TODO: add more details (AltToolActive, InteractiveRequest, ...)

	-- fill in the actions
	_wfData.curJob          = Workflow.Jobs[wf.JobSeq]      -- refer to the GLOBAL Workflow
	if _wfData.curJob ~= nil then
        -- make the structure more nice by merging the tool info
		local idx = 1
		for k, v in pairs(_wfData.curJob.Actions) do
			v.ActionSeq = k				-- index into Job.Actions[..]
			v.DataKey   = _wfData.curJobRawName .. tostring(k)
			v.Task      = _wfData.curJob.Tasks[v.TaskSeq]
			-- merge the tool info
			v.ToolInfo = gui_lua_support.Tools[v.ToolID]
			--[[
			if v.ToolInfo ~= nil then
				_wfData.chart_cnt = jobdata.chart_cnt + table.getn(v.ToolInfo)
				-- build the chart lookup table and the chart names used
				for i, ti in pairs(v.ToolInfo) do
					local co = {}
					co.key = v.DataKey .. '_' .. i
					co.idx = idx
					co.action = k
					co.merkmal = i	-- index into v.tool.toolinfo[]
					co.name = ti.name
					co.unit = ti.unit
					table.insert(jobdata.charts, co);
					idx = idx + 1
				end
			end
			]]--
		end
	end
end

-- polling or workflow state change
-- @return true in case a new result data has arrived or any relevant
--         change has occurred (like switching jobs)
local function UpdateWorkflow(wf)
    -- check, if we should do anything at all (only on change)
    local hasChanges = nil
    if wf == nil then
        return hasChanges
    end
    -- some generic change checks:
    if wf.JobSeq ~= _m.oldWfJobSeq or wf.BoltSeq ~= _m.oldWfBoltSeq then
-- TODO: implement a better change detection logic here!
        hasChanges = true
    end
	if hasChanges or (wf.State ~= _m.oldWfState) then
	    hasChanges = true
		if _m.oldWfState == 0 and wf.State > 0 then
		    -- A new workflow has started. Copy the workflow definitions 
            -- and states as read from the DB from the GLOBAL Workflow LUA table
            _wfData = {}
            _wfData.CurrentTotalname      = Workflow.CurrentTotalname
            _wfData.CurrentPartname       = Workflow.CurrentPartname
            _wfData.CurrentRoot           = Workflow.CurrentRoot
            _wfData.CurrentTotaltyp       = Workflow.CurrentTotaltyp
            _wfData.LastTotalResult       = Workflow.LastTotalResult
            _wfData.CurrentPartnumber     = Workflow.CurrentPartnumber
            _wfData.PartDesc              = Workflow.PartDesc
            _wfData.LastTotalident        = Workflow.LastTotalident
            _wfData.IsPartChoiceBarcode   = Workflow.IsPartChoiceBarcode
            _wfData.IsQuickProcessing     = Workflow.IsQuickProcessing
            local jobs = {}
            for i,job in pairs(Workflow.Jobs) do    -- use the GLOBAL workflow to copy definitions!
                local d = {}
                d.Seq       = job.Seq
                d.RawName   = job.RawName
                d.State     = job.State
                d.TaskCnt   = job.TaskCnt
                d.ActionCnt = job.ActionCnt
                d.Tasks     = job.Tasks
                d.Actions   = job.Actions
                d.Properties= job.Properties
				jobs[d.Seq] = d
--[[
                -- Now collect some info from the tasks/actions - note that we
                -- *always* have a single task/action here (autogenerated)
                d.ActionCnt     = job.ActionCnt
                d.Action        = job.Actions[1]
                --d.TaskCnt       = job.TaskCnt
                --d.Task          = job.Tasks[0]
                -- update the overall OK/NOK count
                d.CntOk         = 0
                for a,act in pairs(job.Actions) do
                    if act.State == 1 then      -- 0=unknown, 1=OK, 2=Nok, 4=not yet processed
                        d.CntOk = d.CntOk + 1
                    end
                end
]]--
            end
			_wfData.updates = 0
			_wfData.jobs = jobs
			UpdateCurrentJobData(wf)
		else
		    -- some other workflow change occurred - likely change of job/operation
            -- make sure to update the job state accordingly
			if not _wfData.updates then _wfData.updates = 0 end
            if _wfData.jobs ~= nil then

-- TODO: implement a better change detection logic here!

                -- update state in jobdata
                if _wfData.jobs[wf.JobSeq] ~= nil and wf.JobState >= 0 then
                    -- update state.
                    _wfData.jobs[wf.JobSeq].State = wf.JobState
                end
                -- update current job
                _wfData.updates = _wfData.updates + 1
                UpdateCurrentJobData(wf)
            end
		end
    end
	_m.oldWfState = wf.State
	_m.oldWfJobSeq = wf.JobSeq
	_m.oldWfBoltSeq = wf.BoltSeq
    return hasChanges
end

function _m.clear()
    _m.allResults = {}
    _m.resultList = {}
    _m.resultMap = {}
    _m.lastResult = nil
end
function _m.getKey(lr)
    -- ARGH! SAP only allows uppercase names...???!!!
    local key = string.upper(string.format('%s_%s_%02d%s', lr.JobName, lr.TaskName, lr.OpNum, lr.OpName))
    key = key:gsub('%s+', '')   -- remove all spaces
    key = key:gsub('%p+', '')   -- remove all punctuation
    -- max 30 characters are allowed
    key = key:sub(1, 28)
    return key
end
function _m.addResult(lr)
    _m.lastResult = lr
    -- store all results in order of execution
    table.insert(_m.allResults, lr)
    -- store the last result
    local key = _m.getKey(lr)
    local idx = _m.resultMap[key]
    if idx ~= nil then
        _m.resultList[idx] = lr
    else
        -- append (and remember the value)
        table.insert(_m.resultList, lr)
        _m.resultMap[key] = #_m.resultList
    end
end

-- New tool result received
local function UpdateResult(wf, tool)
    -- the following parameters are valid now:
    --   wf.ResultCode
	--   wf.ResultValue1
	--   ...

	-- Patch in the current task state
	local job = _wfData.jobs[wf.JobSeq]
	job.State = wf.JobState
	if wf.Op > 0 then
	    job.Tasks[wf.BoltSeq].State = wf.BoltState
	end

    -- new result received
    -- see system.lua:
    -- TOOL_TYPE = {
    --    ERGOSPIN=1, GWK=2, NEXO=3, ByHAND=4, NEWTYPE=5, CONFIRMATION=6, MODBUS=7, BARCODE_READER=8, CUSTOM_TOOL=9
    -- }
    XTRACE(16, "RESULT: new result received!")
    if tool.Type >= 1 and tool.Type <= 3 then
        -- new tightening result - send to SAP!
        local lr = {}
        lr.Type             = tool.Type
        lr.Tool             = tool
        lr.JobName          = wf.PartName
        lr.JobNum           = wf.JobSeq
        lr.TaskName         = wf.BoltName
        lr.TaskNum          = wf.BoltNum
        lr.OpName           = wf.OpName
        lr.OpNum            = wf.Op
        lr.ResultValue = {}
        lr.ResultValue[1]   = wf.ResultValue1
        lr.ResultValue[2]   = wf.ResultValue2
        lr.ResultValue[3]   = wf.ResultValue3
        lr.ResultValue[4]   = wf.ResultValue4
        lr.ResultValue[5]   = wf.ResultValue5
        lr.ResultValue[6]   = wf.ResultValue6
        if wf.ResultCode ~= nil then
            lr.ResultStatus = wf.ResultCode
        else
            lr.ResultStatus = -1
        end
        lr.Channel          = wf.Channel
        lr.PrgNum           = wf.Prg
        lr.Sequence         = wf.Seq
        lr.Stufe            = '2A'
        lr.ResultTimestamp  = wf.ResultCounter     -- ticker
        _m.addResult(lr)
    end

end

local calcJobState = function(job)
    local nokCount = 0
    local okCount = 0
    local nvCount = 0
    for i = 1,#job.Tasks do
        local state = job.Tasks[i].State
        if bit32.band(state, 4) > 0 then nvCount = nvCount + 1 end
        if bit32.band(state, 2) > 0 then nokCount = nokCount + 1 end
        if bit32.band(state, 1) > 0 then okCount = okCount + 1 end
    end
    local ret = 0
    if nvCount > 0 then ret = ret + 4 end
    if nokCount > 0 then ret = ret + 2 end
    if okCount > 0 then ret = ret + 1 end
    return ret
end
local clearJob = function(job)
    for i = 1,#job.Tasks do
        job.Tasks[i].State = 4
    end
end

-- override
local oldClearResultsEvent = ClearResultsEvent
function ClearResultsEvent(part, root, jobSeq, jobName, taskSeq, taskName)
    if jobSeq == 0 then
        -- clear all
        for i = 1,#_wfData.jobs do
            clearJob(_wfData.jobs[i])
            _wfData.jobs[i].State = calcJobState(_wfData.jobs[i])
        end
    else
        local job = _wfData.jobs[jobSeq]
        if job ~= nil then
            if taskSeq == 0 then
                -- clear job
                clearJob(job)
            else
                -- clear task
                job.Tasks[taskSeq].State = 4
            end
        end
        job.State = calcJobState(job)
    end
    if oldClearResultsEvent ~= nil then
        return oldClearResultsEvent(part, root, jobSeq, jobName, taskSeq, taskName)
    else
        return true
    end
end

-- StateChange is called whenever a state changes or a tool result is received
-- @return non-nil if a new result is available
M.StateChange = function(info)

    local hasChanges = UpdateWorkflow(info.Workflow)
    -- check, if there is a new result
    if info.Why > 0 and info.Workflow.State == 2 then
        -- New data notification and "real" rundown/tool result
        UpdateResult(info.Workflow, info.Tool)
        return true
    end
    return hasChanges
end

-- StatePoll is cyclically called every 100-200ms
-- @returns non-nil, if something has changed
M.StatePoll = function(info)

    local hasChanges = UpdateWorkflow(info.Workflow)
    return hasChanges
end

M.GetData = function()
    return _wfData
end

M.clear = function()
    _m.clear()
end

M.getResultList = function()
    --_m.allResults = {}
    return _m.resultList
    --_m.resultMap = {}
    --_m.lastResult = nil
end


return M