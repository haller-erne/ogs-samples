------------------------------------------------------------------------------------------
-- Setup the barcode data fields
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
	barcodes[1] = { name="Model (4-digit code, e.g. A-01)", len=4, required=1, desc="Type code", 	row=1, width=10 }
	barcodes[2] = { name="Serial (10-digit code)", len=10, required=1, desc="vehicle ID number", 	row=1, width=19 }

end

------------------------------------------------------------------------------------------
-- Extract the "database workflow selector" for selecting a model/family
-- Return a blank string ('') if not valid or incomplete
-- Return a non-empty string to start a database lookup and start a process
function BarCode_GetWorkflowSelector()
    local model = param_as_str(barcodes[1].val)
    local sn    = param_as_str(barcodes[2].val)
	if BarCode_CheckTag(1, model) and BarCode_CheckTag(2, sn) then
        -- Model and Serial number codes are valid (correct length)
        -- Return the model code (as only this is used for DB lookup)
        return model
	end
    -- Workflow selector is not valid/complete (need both barcode with correct length
    -- before actually starting database lookup)
    return ''
end
------------------------------------------------------------------------------------------

