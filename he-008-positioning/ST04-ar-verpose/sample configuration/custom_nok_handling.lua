---------------------------------------------------------------------------------------
-- Implement NOK counter handling
local NOK_Counters = { 
    MaxAllowedNok = 3,      -- block tool after 3 NOKs for a single bolt
    counter = {},           -- clear NOK counters
    user_level = 0
}

-- Get the current NOK count
local function GetCurrentNOKCounter()

    local job, task, action = get_current_action()
    if job > 0 and task > 0 then
        local JobName = Workflow.Jobs[job].Name
        local TaskName = Workflow.Jobs[job].Tasks[task].Name
        local key = JobName..TaskName
        if NOK_Counters.counter[key] then return NOK_Counters.counter[key] end
    end
    return 0
end

-- Called from OGS to override default NOK counter handling
function ProcessNOKCounters(error_code)

	if NOK_Counters.user_level > 1 then return end -- do not count NOKs if supervisor logged on

    local job, task, action = get_current_action()
    if job > 0 and task > 0 then
        local JobName = Workflow.Jobs[job].Name
        local TaskName = Workflow.Jobs[job].Tasks[task].Name
        local key = JobName..TaskName
        if error_code == 0 then  -- this is OK -> clear error counter
            NOK_Counters.counter[key] = nil
            ResetLuaAlarm('NOKAlarm');
        else
            if not NOK_Counters.counter[key] then
                NOK_Counters.counter[key] = 1
            else
                NOK_Counters.counter[key] = NOK_Counters.counter[key] + 1
            end
        end
    end
end

-- local NOK strategy (per operation)
--  process_nok_loosen = 0  default
--  process_nok_skip   = 1
--  process_nok_repeat = 2
--  process_nok_dont_check_rights = 16
--  < 2  - use global/default behaviour (NOK_STRATEGIE from station.ini)
function GetNokBehaviour(Tool, State, JobName, TaskName,  RundownName, rework)

    --[[ -- Add tool specific NOK handling here
        if rework > 0 and Tool >= 31 then
            return process_nok_repeat + process_nok_dont_check_rights
        end

        if Tool == 29 then  -- check loader state
            return process_nok_repeat + process_nok_dont_check_rights
        end

        return process_nok_loosen
    ]]--
    local key = JobName..TaskName
    if NOK_Counters.counter[key] and NOK_Counters.counter[key] >= NOK_Counters.MaxAllowedNok  then
        SetLuaAlarm('NOKAlarm', -1, 'NOK limit exceeded! Call superviser!');
        if rework > 0 then
            return process_nok_repeat
        else
            return process_nok_loosen
        end
    end
   return process_nok_dont_check_rights or process_nok_repeat

end