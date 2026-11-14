local json = require('cjson')
local mime = require('mime')
local tool = require('lua_tool_webcam')
--local wfd = require('workflow_data')
-- this is needed to register the browser callback - TODO: change this to include a (better) key
local M = {
    webroot = Webserver.GetRoot()
}
local wf_state = 0
local wf = {}

local function SendWorkflowData(name)
--    local wf_data = wfd.GetData()                   -- get the "full" block
--    local wf_mqtt = GetMqttWorkflowData(wf_data)    -- copy only what we need :-)
--    MQTT:Publish("/heOpMon/wfd", 0, json.encode(wf_mqtt))
    local data = wfd.GetData()
    local ok, res = pcall(json.encode, data)
    if not ok then
        error(res)
    end
    Browser.ExecJS_async(name, "UpdateData('"..res.."');")
end

-- resutlsn something like
--      34VB091231231-Foto-1-nil        (if photo does not yet exist)
--      34VB091231231-Foto-1-2837742    (if photo was already saved)
local function GetPhotoId(wf)
    local photoid = wf.PartSerial .. '-' .. wf.JobName .. '-' .. wf.BoltSeq -- .. '-' .. tostring(wf.PartTransaktion)
    return photoid
end

local function getJsData()
    local photoid = GetPhotoId(wf)
    local data = {
        state = wf_state,
        wf = wf,
        imgid = photoid,
        -- TODO: use /WebCamImages virtual folder and map to local file system
        --       See below Webserver.RegUrl('/WebCamImages', OnWebRequestLua)
        imgurl = '/images/'..photoid..'.jpg'..'?id='..tostring(os.time())   -- force uncached load...
    }
    local old = json.encode_invalid_numbers("null")
    local ok, res = pcall(json.encode, data)
    if not ok then
        error(res)
    end
    json.encode_invalid_numbers(old)
    return res
end

local function SendWfState()
    -- Check workflow state (if running or stopped...)
    local res = getJsData()
    Browser.ExecJS_async("ProcessView", "OGS.TriggerWebcam('"..res.."');")
end

local function SendFileSaved(url)
    --Update the picture
    local res = getJsData()
    Browser.ExecJS_async("ProcessView", "OGS.FileSaved('"..res.."');")
end


local function OnStatePoll(info)
    wf = info.Workflow
    if wf.State ~= wf_state then
        XTRACE(16, "wf change: %d", tonumber(wf.State))
        wf_state = wf.State
        if M.visible then
            SendWfState()
        end
    end
--[[    -- check our workflow for changes
    local hasChanges = wfd.StatePoll(info)
	local wf_data = wfd.GetData()
    if not wf_data or not wf_data.jobs or not wf_data.jobs[1] or not wf_data.jobs[1].Actions then
        return
    end
	if hasChanges then
        SendWorkflowData("ProcessView")
    end]]
end

local function OnStateChanged(info)
    wf = info.Workflow
    if wf.State ~= wf_state then
        XTRACE(16, "wf change: %d", tonumber(wf.State))
        wf_state = wf.State
        if M.visible then
            SendWfState()
        end
    end
--[[
    local hasChanges = wfd.StateChange(info)  -- update the workflow data
	local wf_data = wfd.GetData()
	if not wf_data or not wf_data.jobs or not wf_data.jobs[1] or not wf_data.jobs[1].Actions then
        return
    end
	local wf = info.Workflow
	if wf.State ~= wf_state or hasChanges then
        SendWorkflowData("ProcessView");
    end]]
end

local function OnShutdown()
	XTRACE(16, "WWF: Shutdown...")
end

-- Message handler for Browser javascript commands
local function OnProcessViewMsg(browser, cmd)
    XTRACE(16, string.format("name=%s, cmd=%s", tostring(browser), tostring(cmd)))
    local o = json.decode(cmd)
    if o and o.cmd then
        if o.cmd == 'SaveImage' then
            -- expect cmd = { cmd=name, img=dataurl }
            local photoid = GetPhotoId(wf)
            local filename = "\\images\\"..photoid..".jpg"
            -- "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQ...
            if o.img ~= nil then
                -- str:pos(',')
                local b64 = o.img:sub(24)
                local rawjpg = mime.unb64(b64)
                local new_file = io.open(M.webroot .. filename, "w+b")
                if new_file then
                    new_file:write(rawjpg)
                    new_file:close()
                end
            end
            SendFileSaved();    -- SendWfState()
            return
        elseif o.cmd == 'ok-clicked' then
            tool.DoComplete()
            SendWfState()
            return
        elseif o.cmd == 'OnHide' then
            M.visible = false
            return
        elseif o.cmd == 'OnShow' then
            M.visible = true
            SendWfState()
            return
        end
    end
end
-- register the browser callback with core.
-- WARNING: the urls must match **EXACTLY** to the URL-Task property
Browser.RegMsgHandler('ProcessView', OnProcessViewMsg, 'http://localhost:60000/WebCam.html');
Browser.RegMsgHandler('ProcessView', OnProcessViewMsg, 'http://127.0.0.1:60000/WebCam.html');
Browser.RegMsgHandler('ProcessView', OnProcessViewMsg, '/WebCam.html');


-------------------------------------------------------------
-- Serve the photo file on demand
local function OnWebRequestLua(abspath, qrystr, verb, body)
    XTRACE(16, string.format("HTTP: request to %s, qry=%s, verb=%s, body=%s", 
        tostring(abspath), tostring(qrystr), tostring(verb), tostring(body)))
    -- repare the response and return it
    return nil
end
Webserver.RegUrl('/WebCamImages', OnWebRequestLua)


-- register the callbacks with core.
if StatePollFunctions ~= nil then
	StatePollFunctions.add(OnStatePoll)
end
if StateChangedFunctions ~= nil then
	StateChangedFunctions.add(OnStateChanged)
end
if StateShutdownFunctions ~= nil then
	StateShutdownFunctions.add(OnShutdown)
end

return M