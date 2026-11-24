------------------------------------------------------------------------------------------
function Barcode_InitTable()
	-- Fields to set for barcodes:
    --   .name      Name as shown in the OGS GUI
    --   .len       Max. length of field (might (later) be a table). Note that this should
    --              be set to the maximum with of the ID if used for variable field lengths
    --   .required  Set to 1 if this is a required field
    --   .desc      Descriptive text, unused so far
    --   .row       Display layout in OGS GUI, set row
    --   .with      Display layout in OGS GUI, set relative with (of all fields in the same row)
	-- 
	barcodes[1] = { name="Model (use Barcode Sheet)", len=4, required=1, desc="Type code", 	        row=1, width=8 }
	barcodes[2] = { name="Serial (3-digit alnum)",    len=3, required=1, desc="vehicle ID number", 	row=1, width=19 }
	
end
-----------------------------------------------------------------------------------------
-- Handle newly scanned barcodes:
local oldBarCode_AddNew = BarCode_AddNew
function BarCode_AddNew(source, name, rawCode)
	-- return the "tag" value if a valid barcode was given
	-- else return an error code (value < 0)
	-- if successful, update the global barcodes table val element
	-- NOTE: the "source" parameter indicates the driver issuing the
	--       AddNew command , e.g. "SignalR", "Scanner", "Keyboard"
	rawCode = sanitize(rawCode)
	if source == 'PLC' then
		-- process the "raw" code into a value - split combined codes, format, ...
		local val = rawCode:match( "^%s*(.-)%s*$" )		-- remove trailing/leading blanks
		-- check for combined model+serial barcode scans (e.g. 2D barcode)
		if #val == barcodes[1].len + barcodes[2].len then
			local t = string.sub(val, 1, barcodes[1].len)
			barcodes[1].raw = t
			barcodes[1].val = t
			barcodes[1].source = source
			t = string.sub(val, barcodes[1].len+1, -1)
			barcodes[2].raw = t
			barcodes[2].val = t
			barcodes[2].source = source
			Barcode_SetFirstIfTblEmpty()
			return 2
		end
		return 0	-- need both codes as a string
    end

    -- call the original handler for all other cases
    return oldBarCode_AddNew(source, name, rawCode)
end
----------------------------------------------------------------------
-- Extract the "database workflow selector" for selecting a model/family 
-- Return a blank string ('') if not valid or incomplete
-- Return a non-empty string to start a database lookup and start a process
function BarCode_GetWorkflowSelector()
    local model = param_as_str(barcodes[1].val)
    local sn    = param_as_str(barcodes[2].val)
	if BarCode_CheckTag(1, model) and 
       BarCode_CheckTag(2, sn)   then
       return model
	end
    return ''  -- workflow selector is not ready    
end
----------------------------------------------------------------------
function BarCode_GetOperationID(CurrOp, CurrPartID)

-- now ID code is limited to 40 sings:
-- CurrOp 																		[1-5] 
	local JobName  = TrimOrFill( CurrOp.JobName, 20, '-') 					--	[6-25]
	local BoltOp															--	[26-32]
	local Username = TrimOrFillLeft( UserManager_GetCurrentUser(), 8, ' ') 	--	[33_40]
    if  CurrOp.Loosen == 0 then
		BoltOp = string.format('%s_%02d%02d', TrimOrFillLeft(CurrOp.BoltName,2,'0'), CurrOp.Number, CurrOp.Total)
	else
		BoltOp = string.format('%s_%02d%02d', TrimOrFillLeft(CurrOp.BoltName,2,'0'), CurrOp.Number, 0)
	end
	return string.format('%s%s%s%s', CurrPartID, JobName, BoltOp, Username)

end
------------------------------------------------------------------------------------------

