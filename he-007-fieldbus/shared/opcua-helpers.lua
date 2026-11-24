-- Encoding/decoding helpers
local opcua = require('luaopcua')   -- load our LuaOPCUA.dll Open62541 wrapper
local basexx = require('basexx')

local M = {
    opcuaconnection_timeout = 10,
}

local struct = require("struct")    -- see http://www.inf.puc-rio.br/~roberto/struct/

local function term(s)
    -- terminate the string at the first embedded binary zero (if any)
    local f = s:find('\0')
    if f then
        return s:sub(1, f-1)
    end
    return s
end

-- Helper functions to encode/decode a LUA data type to an OPCUA data type and vice versa.
-- The encode member functions return a binary string of the actual size
-- The decode member functions return the deceoded data and the actual length of the data processed
M.BinStream = {
    ---Encode string into an OPC-UA string with a given max. length (possibly truncated)
    ---@param val string String to encode into a length prefixed binary string
    ---@param maxLen integer max. allowed length
    ---@return string opcua-string Binary string in OPCUA length-prefixed format (array of UTF-8 chars)
    encodeStr = function(val, maxLen)
        if not val then val = '' end
        if #val > maxLen then val = val:sub(1, maxLen) end
        return struct.pack('<L', #val) .. val
    end,
    ---Encode string into an OPC-UA character array with fixed size, right-padded with blanks
    ---@param val string String to encode into a fixed length OPC-UA char array
    ---@param len integer fixed array length
    ---@return string opcua-string Binary char array in OPCUA format with given number of characters
    encodeChars = function(val, len)
        if not val then val = '' end
        if #val > len then val = val:sub(1, len) end
        if #val < len then val = val end
        return struct.pack('<L', len) .. string.rep(' ', len - #val)
    end,
    ---Decode OPC-UA string into LUA string
    ---@param bstr string OPC-UA binary string to decode into LUA string
    ---@return string String LUA string
    ---@return integer ConsumedBytes Number of bytes consumed from the bstr buffer
    decodeStr = function(bstr)
        local len = struct.unpack('<L', bstr)
        local val = bstr:sub(5, 4+len)
        val = term(val)
        return val, 4+len
    end,
    ---Decode OPC-UA array of characters into LUA string
    ---@param bstr string OPC-UA binary string to decode into LUA string
    ---@return string String LUA string
    ---@return integer ConsumedBytes Number of bytes consumed from the bstr buffer
    decodeChars = function(bstr)
        local len = struct.unpack('<L', bstr)
        local val = bstr:sub(4, 3+len)
        val = term(val)
        return val, 4+len
    end,
}

---BoolToByte: convert a boolean value to 0/1
---@param bVal boolean|nil Boolean value to convert
---@return integer ByteVal 0/1 depending on input value
M.b2B = function(bVal)
    if bVal and bVal ~= 0 then
        return 1
    else
        return 0
    end
end

M.pad = function(s, l)          -- add padding
    if #s >= l then return s end     -- no padding needed
    local r = s..string.rep("\0",l-#s)
    return r
end

M.toBits = function(num, bits)  -- convert integer to bit-table
    -- returns a table of bits
    local t={} -- will contain the bits
    local bitcnt = bits
    for b=bits,1,-1 do
        local rest=math.fmod(num,2)
        t[bitcnt+1-b]=rest
        num=(num-rest)/2
    end
    if num==0 then return t else return {'Not enough bits to represent this number'}end
end

M.toBitsRev = function(num, bits)  -- convert integer to bit-table
    -- returns a table of bits
    local t={} -- will contain the bits
    for b=bits,1,-1 do
        local rest=math.fmod(num,2)
        t[b]=rest
        num=(num-rest)/2
    end
    if num==0 then return t else return {'Not enough bits to represent this number'}end
end

---@class OpcuaConfig
---@field Name string The "name" of the connection (typically the section name from station.ini)
---@field tbl table<string,string> The full configuration section as a key value table
---@field URL string The OPC-UA server url, e.g. opc.tcp://myserver:4840
---@field UserName string Username for OPC-UA server login (blank string if not used)
---@field Password  string Password for OPC-UA server login (blank string if not used)
---@field NS integer Namespace fpr OPC-UA server variables (toPlcVar and toOgsVar)
---@field toPlcVar string Node name of the OPC-UA variable to be written to the PLC
---@field toPlcDty string (optional) Node datatype for toPlcVar (should normally be empty string)
---@field toOgsVar string Node name of the OPC-UA variable to be read from the PLC
---@field toOgsDty string (optional) Node datatype for toOgsVar (should normally be empty string)
---@field ioCycle integer read/write cycle time (in Milliseconds)
---@field debug integer Debuglevel (0 = no debug output, 1 = info, 2 = verbose, 3 = debug)


--- Read the OPCUA connection parameters from an ini-section or from a LUA table
--- Return a configuration object or nil,error
---@param sectionOrTable string|table
---@return nil|OpcuaConfig config On success returns config table, else nil
---@return nil|string error On error returns error message
M.ReadConnectionConfig = function(sectionOrTable)
    local tbl, section
    if type(sectionOrTable) ~= 'string' then
        tbl = sectionOrTable
        section = ''
    else
        tbl = ReadIniSection(sectionOrTable)
        section = sectionOrTable
    end
	if type(tbl.SERVER_URL) ~= 'string' then
		return nil, 'Missing parameter "SERVER_URL" in INI-section "'..section..'"'
	end
    if type(tbl.SERVER_NS) ~= 'string' then
		return nil, 'Missing parameter "SERVER_NS" in INI-section "'..section..'"'
	end
	if type(tbl.TO_PLC_VAR) ~= 'string' then
		return nil, 'Missing parameter "TO_PLC_VAR" in INI-section "'..section..'"'
	end
	if type(tbl.TO_OGS_VAR) ~= 'string' then
		return nil, 'Missing parameter "TO_OGS_VAR" in INI-section "'..section..'"'
	end
    ---@type OpcuaConfig
    local cfg = {
        Name        = section,
        tbl         = CloneTable(tbl),              -- just in case we need it later
        URL         = tbl.SERVER_URL,
        UserName    = tbl.SERVER_USERNAME or '',
        Password    = tbl.SERVER_PASSWORD or '',
        NS          = tonumber(tbl.SERVER_NS) or 0,
        ioCycle     = tonumber(tbl.CYCLE_MS) or 100,
        toPlcVar    = tbl.TO_PLC_VAR,
        toPlcDty    = tbl.TO_PLC_DTY or '',
        toOgsVar    = tbl.TO_OGS_VAR,
        toOgsDty    = tbl.TO_OGS_DTY or '',
        debug       = tonumber(tbl.DEBUG) or 0,
    }
    return cfg
end

---@class OpcuaIOData
---@field bytes string Raw data bytes
---@field data table Lua table with IO data

---@class OpcuaConnection
---@field cfg OpcuaConfig The onfiguration for this connection
---@field client any The OPCUA DLL object instance
---@field toOGS OpcuaIOData Cyclic IO data read from the PLC
---@field toPLC OpcuaIOData Cyclic IO data to be written to the PLC
---@field running boolean True, if cyclic IO is active
---@field state integer Internal connection state
---@field cycles integer Number of cycles since last successful connect
---@field tAliveRcv number Last alive toggle received (os.clock())
---@field tAliveXmt number Last alive toggle sent (os.clock())
---@field last_alive boolean Last cycle alive state from PLC
---@field start_timer number Internal timer for startup check
---@field last_err integer Last error code
---@field hasAliveAlarm boolean Flag, if currently an alive alarm is active

---Create a connection object to be used for cycliuc OPCUA data exchange
---Requires providing a config object created with ReadConnectionConfig()
---@param cfg OpcuaConfig Config object created by ReadConnectionConfig()
---@return OpcuaConnection connection New cyclic OPCUA connection
M.CreateConnection = function(cfg)
    ---@type OpcuaConnection
    local connection = {
        client      = opcua.CyclicIO.new(
                        -- message security mode (1 = NONE, 2 = SIGN only, 3 = SIGN AND ENCRYPT)
                        tonumber(cfg.tbl.SERVER_SECURITY) or 1,
                        -- 'c:\\temp\\certificate.der': certificate file (in OpenSSL DER format)
                        cfg.tbl.SERVER_CERT_FILE or '',
                        -- 'c:\\temp\\privateky.der': private key file (in OpenSSL DER format)
                        cfg.tbl.SERVER_CERT_KEY or ''
                    ),
        cfg         = cfg,
        toOGS       = { bytes='', data = {} },
        toPLC       = { bytes='', data = {} },
        running     = false,
        state       = 0,
        cycles      = 0,
        tAliveRcv   = 0,
        tAliveXmt   = 0,
        last_alive  = false,
        start_timer = 0,
        last_err    = 0,
        hasAliveAlarm = false
    }
    return connection
end

---Start the cyclic OPCUA connection with the given parameters
---@param connection OpcuaConnection New cyclic OPCUA connection
---@param timeout integer|nil Timeout for the OPCUA connection (in milliseconds)
---@param secureChannelLifeTime integer Secure channel timeout (in seconds)
---@return any
M.StartConnection = function(connection, timeout, secureChannelLifeTime)
    -- get the DLL OPCUA config object, so we can modify the default settings
    local config = connection.client.config
    timeout = timeout or 5000
    secureChannelLifeTime = secureChannelLifeTime or (10*60)
    config:setTimeout(timeout)
    config:setSecureChannelLifeTime(secureChannelLifeTime * 1000)

    -- configure and start the cyclic data exchange
    local cfg = connection.cfg
    return connection.client:start(
        cfg.URL, cfg.NS,
        cfg.toPlcVar, cfg.toPlcDty,
        cfg.toOgsVar, cfg.toOgsDty,
        cfg.ioCycle,
        cfg.UserName, cfg.Password)
end

---comment
---@param connection OpcuaConnection
---@param fnChange any
---@return integer
---@return boolean
M.PollConnection = function(connection, fnChange)
    local client = connection.client
    local alarmKey = "OpcUA["..connection.cfg.Name.."]"
    -- check, if cyclic IO is running
    local running = client:getState()
    local newdata = false

    if connection.state == 0 then
        connection.tAliveRcv = os.clock()
        connection.tAliveXmt = os.clock()
        if running then
            XTRACE(16, alarmKey.." connected to "..connection.cfg.URL)
            connection.last_err = nil;
            connection.start_timer = nil
            connection.state = 10
            connection.cycles = 0
            -- get the initial values
            local rdTable = client:getInputsTbl()   -- rdTable, rdData, rdState = client:getInputsTbl()
            connection.toOGS.bytes = ''     -- force change
            connection.toOGS.data = rdTable or {}
            local wrTable = client:getOutputsTbl()  -- wrTable, wrdData, wrState = client:getOutputsTbl()
            connection.toPLC.bytes = ''     -- force change
            connection.toPLC.data = wrTable or {}
            connection.tAliveRcv = os.clock()
        end
        if connection.start_timer ~= nil and os.clock() - connection.start_timer > M.opcuaconnection_timeout then
            local err = alarmKey.." Couldn't establish connection to "..connection.cfg.URL
            XTRACE(2, err)
            fnChange(connection, nil, err)  -- notify disconnect
            connection.start_timer = nil
        end

    elseif connection.state == 10 then
        -- check connection
        if not running then
            -- lost the connection
            connection.last_err = -1;
            local err = alarmKey.." PLC disconnected from "..connection.cfg.URL
            XTRACE(2, err)
            fnChange(connection, nil, err)  -- notify disconnect
            connection.state = 0
        else
            -- get input data from PLC
            local rdData, rdState = client:getInputs()
            if rdState == 0 then
                -- we have valid data!
                local to_ogs = connection.toOGS
                if rdData ~= to_ogs.bytes then
                    -- Something has changed (including alive and mirror) - so now get the deserialized data
                    local rdTable, rdBytes, _ = client:getInputsTbl()   -- _ = rdState
                    if not rdTable then
                        -- error!
                        local err = alarmKey..' Failed to decode input data: ' .. (rdBytes or '?')
                        XTRACE(2, err)
                        fnChange(connection, nil, err)  -- notify disconnect
                        connection.state = 0
                    else
                        if connection.cfg.debug and connection.cfg.debug > 2 then
                            XTRACE(16, alarmKey..string.format('   rd: #size=%d: %s', #rdBytes, basexx.to_hex(rdBytes)))
                        end
                        -- TODO: optimize: filter timestamp and alive
                        to_ogs.data = rdTable                                   -- set the decoded data
                        if connection.last_alive ~= to_ogs.data.Conn.Alive then -- check PLC alive signal
                            connection.tAliveRcv = os.clock()
                            connection.last_alive = to_ogs.data.Conn.Alive
                            if connection.hasAliveAlarm then
                                XTRACE(2, alarmKey.." Reconnected to "..connection.cfg.URL)
                                fnChange(connection, to_ogs)
                            end
                            connection.hasAliveAlarm = false
                        end
                        connection.toPLC.data.Conn.Mirror = to_ogs.data.Conn.Alive
                        -- check, if anything except the first 8 bytes (the Conn header) has changed
                        if to_ogs.bytes == nil or (to_ogs.bytes:sub(9, #to_ogs.bytes) ~= rdData:sub(9, #rdData))
                        then
                            newdata = true
                            if connection.cfg.debug then
                                XTRACE(16, alarmKey..string.format('   rd: #size=%d: %s', #rdData,
                                    basexx.to_hex(rdData)))
                            end
                            fnChange(connection, to_ogs)
                        end
                        to_ogs.bytes = rdData
                    end
                end
                connection.last_err = nil;
            end

            -- serialize and convert to OPCUA
            local to_plc = connection.toPLC               -- get the structured data
            local rv = client:setOutputsTbl(to_plc.data)  -- serialize the "data" table
            -- TODO: debug output (requires updated LuaOPCUA.dll)
--[[        if bytes ~= to_plc.bytes then
                -- be verbose and log changes
                if to_plc.bytes ~= nil and (string.sub(to_plc.bytes, 3) ~= string.sub(bytes, 3))  -- ignore alive
                then
                    if _M.cfg.debug then
                        XTRACE(16, string.format('     wr: #size=%d: %s', #bytes, basexx.to_hex(bytes)))
                        --XTRACE(16,  string.format("    wr: AckStart=%d, AckTypOk=%s, WFDone=%d, WFOK=%d, SysErr=%d",
                        -- to_plc.line.State.Ack_Start, to_plc.line.State.Ack_TypeOk, to_plc.line.State.WorkflowActive,
                        -- to_plc.line.State.WorkflowDone, to_plc.line.State.WorkflowOk, to_plc.line.State.SystemError))
                    end
                end
                to_plc.bytes = bytes                -- remember old write data
            end
]]--
            if rv == 0 then
                connection.last_err = nil;
                if rdState == 0 then
                    connection.cycles = connection.cycles + 1
                end
            else
                connection.last_err = rv
                local err = alarmKey..' PLC write error '..(tostring(rv) or '')
                XTRACE(2, err)
                fnChange(connection, nil, err)  -- notify dsconnectz
                connection.state = 0
            end
        end
    end

    -- send our own alive signal (500ms)
    if connection.state >= 10 and (os.clock() - connection.tAliveXmt) > 0.5 then
        connection.toPLC.data.Conn.Alive = not connection.toPLC.data.Conn.Alive
        connection.tAliveXmt = os.clock()
    end

    -- check for timeout
    if connection.state >= 10 and (os.clock() - connection.tAliveRcv) > 5.0 then
        -- TIMEOUT!
        if not connection.hasAliveAlarm then
            connection.hasAliveAlarm = true
            local err = alarmKey..' Alive timeout!'
            XTRACE(2, err)
            fnChange(connection, nil, err)  -- notify dsconnectz
            connection.state = 0            -- reset and wait for reconnect
        end
    end

    connection.running = (connection.state == 10)
    return connection.last_err, newdata
end


return M