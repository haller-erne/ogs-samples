local json = require('cjson')
--local tool = require('lua_tool_rootcause')
local M = {}

--[[
-- read the list of root causes and their dependencies
local rootCauses = require("rootcauses")

-- Buid a command message for the browser to update the SVG visualization
local function SendSvgUpdate(browser)
--    local wf_data = wfd.GetData()                   -- get the "full" block
--    local wf_mqtt = GetMqttWorkflowData(wf_data)    -- copy only what we need :-)
--    MQTT:Publish("/heOpMon/wfd", 0, json.encode(wf_mqtt))
    local nodes = {}
    for k,v in pairs(rootCauses) do
        local node = {
            name = k,
            checked = v.checked or false
        }
        table.insert(nodes, node)
    end
    local data = {
        nodes = nodes
    }
    local ok, res = pcall(json.encode, data)
    if not ok then
        error(res)
    end
    Browser.ExecJS_async(browser, "OGS.Update('"..res.."');")
end

-- define so it can be called recursively
local SetNodeCheckstate = null
local function SetNodeCheckstate(rcNode, state)
    rcNode.checked = state 
    if rcNode.onCheck then
        for k,v in pairs(rcNode.onCheck) do
            local item = rootCauses[v]
            if item then
                if item.onCheck then
                    SetNodeCheckstate(item, state)
                else
                    item.checked = state
                end
            end
        end
    end
end

-- Toggle checked state of the relevant elements
local function HandleSvgClick(nodeName, rc)
    local state = not rc.checked    -- toggle with each click
    if rc.reset then
        for k,v in pairs(rootCauses) do
            v.checked = false
        end
    else
        SetNodeCheckstate(rc, state)
    end
end
]]

-- Message handler for Browser javascript commands
local function OnWebViewMsg(name, cmd)
    XTRACE(16, string.format("name=%s, cmd=%s", tostring(name), tostring(cmd)))
    local o = json.decode(cmd)
    if o and o.cmd then
        if o.cmd == 'OnShow' then
            local cameraType = 'environment'    -- camera selection: user/environment
            Browser.ExecJS_async(name, 'OGS.StartCamera("'..cameraType..'");')
        elseif o.cmd == 'OnScanData' then
            -- expect cmd = { cmd=name, decodedText: decodedText, decodedResult: decodedResult }
            if o.decodedText then
                if o.decodedText == 'https://doo.net/checkin/vaeDGrYp' then
                    -- The SchraubTec badge code
                    o.decodedText = 'A-021111111111'
                end
                local ret = BarCode_AddNew('Scanner', 'WebScan', o.decodedText)
                local data = {
                    ret = ret,
                    decodedText = o.decodedText
                }
                local ok, res = pcall(json.encode, data)
                if not ok then
                    error(res)
                end
                local sCmd = "OGS.ShowScanResult('"..res.."');"
                --Browser.ExecJS_async(name, 'OGS.ShowScanResult("'..res..'");')
                Browser.ExecJS_async(name, sCmd)
            end
            return
        end
    end
end
-- register the browser callback with core.
-- WARNING: the urls must match **EXACTLY** to the URL-Task property

-- note, this uses the start page URL (current_project.billboard = 'http://localhost:5173/index.html')
Browser.RegMsgHandler('StartView', OnWebViewMsg, current_project.billboard);

return M
