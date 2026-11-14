local json = require('cjson')
local M = {}

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

-- Message handler for Browser javascript commands
local function OnProcessViewMsg(name, cmd)
    XTRACE(16, string.format("name=%s, cmd=%s", tostring(name), tostring(cmd)))
    local o = json.decode(cmd)
    if o and o.cmd then
        if o.cmd == 'svg-click' then
            -- expect cmd = { cmd=name, node=nodename }
            local nodeName = o.node
            local rc = rootCauses[nodeName]
            if nodeName and rc then
                -- do the magic...
                HandleSvgClick(nodeName, rc)
                -- Update browser now
                SendSvgUpdate(name)
            end
            return
        elseif o.cmd == 'OnShow' then
            -- expect cmd = { cmd=name }
            tool.DoComplete(rootCauses)
            return
        end
    end
end
-- register the browser callback with core.
-- WARNING: the urls must match **EXACTLY** to the URL-Task property
Browser.RegMsgHandler('StartView', OnProcessViewMsg, 'http://localhost:60000/StartPage.html');
Browser.RegMsgHandler('StartView', OnProcessViewMsg, 'http://127.0.0.1:60000/StartPage.html');
Browser.RegMsgHandler('StartView', OnProcessViewMsg, '/StartPage.html');

return M