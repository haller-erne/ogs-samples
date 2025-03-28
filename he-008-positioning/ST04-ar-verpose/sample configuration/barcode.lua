XTRACE(16, "Loading barcode.lua...", "barcode.lua", 1)
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
	barcodes[1] = { name="VIN (11 digits)", len=11, required=1, desc="VID",   row=1, width=8 }
	
end
-----------------------------------------------------------------------------------------
function BarCode_AddNew(source, name, rawCode)
	-- return the "tag" value if a valid barcode was given
	-- else return an error code (value < 0)
	-- if successful, update the global barcodes table val element
	-- NOTE: the "source" parameter indicates the driver issuing the
	--       AddNew command , e.g. "SignalR", "Scanner", "Keyboard"
	rawCode = sanitize(rawCode)
	if source == 'Scanner' then
		-- TODO: process the "raw" code into a value
		val = rawCode

		tag = 0
		if     #val == barcodes[1].len then tag = 1			-- Model
		else return -1 end

		barcodes[tag].raw = rawCode
		barcodes[tag].val = val
		barcodes[tag].source = source
		barcode_changed = 1
		Barcode_SetFirstIfTblEmpty()
		return tag
	elseif source == 'Rfid' then
		-- forward to user logon
		UserManager.RfidLogon(rawCode)
		return 0
	elseif source == 'GUI' then  
		name = param_as_str(name)
		if name == '' then
			-- barcode scanner in "keyboard" mode to accept master account for temporary privilege operation (Thailand Triumph)
			UserManager.GUILogon(rawCode)  
			return 0
		end	
		return BarCode_InsertByName(source, name, rawCode)
	else
		-- unknown source
		return 0
	end
end
----------------------------------------------------------------------
-- Extract the "database workflow selector" for selecting a model/family 
-- Return a blank string ('') if not valid or incomplete
-- Return a non-empty string to start a database lookup and start a process
function BarCode_GetWorkflowSelector()
    local model = param_as_str(barcodes[1].val):sub(9,11)
    if BarCode_CheckTag(1, param_as_str(barcodes[1].val)) then
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

