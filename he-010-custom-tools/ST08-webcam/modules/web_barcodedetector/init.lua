--- Web Barcode Detector Module
--- This modue provides functionality for detecting barcodes using a web camera.
--- 
--- To make it easier to use this module, a virtual webroot is registered, so you 
--- can access the barcode/webcam default webpage at "/web_barcodedetector/index.html"
--- (which is automatically delegated to .\web\dist\index.html).
--- 
--- The module is loaded by requiring it in your Lua code, for example:
--- ```lua
--- local web_barcodedetector = require('web_barcodedetector')
--- ``` 
--- Note, that this requires having the `...;?/init.lua` in your `package.path`.
--- 
---@module web_barcodedetector

local M = {
    config = {
        url = nil,          -- URL which can be used to access the web interface
        baseDir = nil,      -- full path to folder where this Lua file resides
        htmlDir = nil,      -- full path to the HTML directory for the web interface
    },
    OnNewBarcodeScanned = function(barcodeText) end
}
local json = require('cjson')

--------------------------------------------------------------------------------
-- Web server registration
--------------------------------------------------------------------------------

-- Internal message handler for Browser javascript commands
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
                -- call the user-overridable barcode scan handler
                local ret = M.OnNewBarcodeScanned(o.decodedText)
                local data = {
                    ret = ret,
                    decodedText = o.decodedText
                }
                -- notify the web page with the processing result
                local ok, res = pcall(json.encode, data)
                if not ok then
                    error(res)
                end
                local sCmd = "OGS.ShowScanResult('"..res.."');"
                Browser.ExecJS_async(name, sCmd)
            end
            return
        end
    end
end

---Barcode scan handler. By default this forwards the scanned barcode to the barcode
---handler function Barcode_AddNew() and simulates a "Scanner" input.
---The function is exposed through the module, so you can override it, if needed.
---@param barcodeText string The scanned barcode text
---@return any AddNewResult The result of the barcode handler function
M.OnNewBarcodeScanned = function(barcodeText)
    -- This function will be called whenever a new barcode is scanned
    local ret = BarCode_AddNew('Scanner', 'WebScan', barcodeText)
    return ret
end

---Register an additional event handler for the given WebBrowser view
---@param BrowserName 'StartView'|'ProcessView'|'SidePanel'|'InstructionView' Name of the web browser instance/view
M.RegisterBrowser = function(BrowserName, url)
    Browser.RegMsgHandler(BrowserName, OnWebViewMsg, url);
end

--------------------------------------------------------------------------------
-- Web server registration
--------------------------------------------------------------------------------

local function initModule()

    -- Check, if the webserver is enabled - if not, then we can skip everything
    local webroot = ReadIniValue('Webserver', 'URL')
    if (not webroot) or (not Webserver.MapUrl) then
        -- Webserver is not enabled or OGS is too old (Webserver.MapUrl is not available).
        return M
    end

    -- Map the virtual webserver root
    -- Get the full directory of the current Lua file 
    M.config.baseDir = debug.getinfo(1, "S").source:sub(2, -#'init.lua'-1)
    M.config.htmlDir = M.config.baseDir .. [[web/dist]]
    if file_exists(M.config.htmlDir..[[/index.html]]) then
        M.config.url = 'web_barcodedetector/index.html'
        Webserver.MapUrl('/web_barcodedetector', M.config.htmlDir)
    end

    -- Register the web view message handler for the start view
    Browser.RegMsgHandler('StartView', OnWebViewMsg, current_project.billboard);
    Browser.RegMsgHandler('StartView', OnWebViewMsg, webroot..'/web_barcodedetector/index.html');

    return M
end

return initModule()
