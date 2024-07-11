-- Define the parameters to connect to the Turck TBEN-S1-8DXP EtherNet/IP
-- remote I/O module.

-- Load the Ethernet_devices module to add the table
-- luacheck: globals ethernet_devices
local known_devices = require('ethernet_devices')
if ethernet_devices then known_devices = ethernet_devices end

-------------------------------------------------------------------------------
--           Turck TBEN-S1-8DXP digital I/O module
------------------------------------------------------------------------------
local ParamsTurckTBEN_S1_8DXP = {
	-- O->T parameters: PLC --> Device, "PLC Outputs"
    ---------------------------------------------------------------------------
	--ConnectionMode    OT_Mode;		-- Connection mode: POINT2POINT(2,default), MULTICAST(1)
	OT_Inst             = 0x68,			-- O->T Instance ID (Consuming I/O path)
	OT_Size             = 6,			-- O->T data size (in bytes)
	--RealTimeFormat    OT_RTFormat;   	-- O->T R/I-Header(3)/Heartbeat(2)/Modeless(1)/Zerolen(1)
	--Priority		    OT_Priority;
	OT_ExclusiveOwner   = true,         -- true = exclusive owner
	OT_VariableLength   = false,        -- true = variable length allowed
    ---------------------------------------------------------------------------
	-- T->O parameters: Device -> PLC, "PLC Inputs"
	--ConnectionMode  TO_Mode;			-- Cconnection mode: MULTICAST(1,default), POINT2POINT(2)
	TO_Inst             = 0x67,			-- T->O Instance ID (Producing I/O path)
	TO_Size             = 10,			-- T->O data size (in bytes)
	--RealTimeFormat	TO_RTFormat;    -- T->O R/I-Header(3)/Heartbeat(2)/Modeless(1)/Zerolen(1)
	--Priority		TO_Priority;
	TO_ExclusiveOwner   = true,         -- true = exclusive owner
	TO_VariableLength   = false,        -- true = variable length allowed
    ---------------------------------------------------------------------------
	-- Configuration Assembly (optional)
	Cfg_Inst            = 0x01,       	-- 0 = unused
	Cfg_Data            = {},  	        -- configuration data
    ---------------------------------------------------------------------------
	-- Startup parameter writes (optional) - only as workaround for (buggy) Rexroth devices
	-- Parameters are given as a sequence of bytes for writing using SetAttributeSingle.
	-- For each Par_Count elements, the following data must be provided:
	-- 		[byte]	Class
	--		[byte]	Instance
	--		[byte]	Attr
	--		[byte]	Number of data bytes to write
	--		[bytes] [actual data bytes to write]
	--
	Par_Data            = {},  -- parameter data in the above format
    ---------------------------------------------------------------------------
	-- common parameters
	Rate                = 50,			-- data rate in [ms]
	Keying              = {}        	-- Electronic key segment
}

-- Extend the global OGS EtherNet/IP device table
-- Make sure to set the same name as used in station.ini [STATION_IO_ENIP] section!
known_devices["TurckTBEN_S1_8DXP"] = ParamsTurckTBEN_S1_8DXP


