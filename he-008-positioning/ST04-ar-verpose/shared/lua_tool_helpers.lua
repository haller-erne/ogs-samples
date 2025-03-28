local json = require('json')

local M = {
  _TYPE='module',
  _NAME='lua_tool_helpers',
  _VERSION='1.0-0'
}

--[[

Sample tool parameters for formatting (in station.ini)
NOTE: This supports different formats depending on the result ok/nok:
      If the json result has an "ok" or "nok" member, then this is used
      for formatting - if not, then the "fmt" is used instead.

[LuaTool_MyLuaTool]
FMT_UNITS={ "unit1":"uOhm", "unit2":"", "dec1":"1", "dec2":"0"}
FMT_RESULTS={ "fmt":"%(M1)3.1f uOhm" }
FMT_FOOTER={ "ok":"%(M1min)3.1f <= %(M1)3.1f uOhm <= %(M1max)3.1f", "nok":"NOK!"}
FMT_PRG={ "fmt":"P = %(Prg)d" }

]]--

-- Initialize the optional parameters for formatting
-- read the "standard" formatting parameters
M.read_fmt_config = function(channel)
  local ini = channel.ini_params
  local fmt = {}
  if ini.FMT_UNITS ~= nil then
    fmt.units = json.decode(ini.FMT_UNITS)
  end
  if ini.FMT_RESULTS ~= nil then
    fmt.results = json.decode(ini.FMT_RESULTS)
  end
  if ini.FMT_FOOTER ~= nil then
    fmt.footer = json.decode(ini.FMT_FOOTER)
  end
  if ini.FMT_PRG ~= nil then
    fmt.prg = json.decode(ini.FMT_PRG)
  end
  return fmt
end

-- get the tool units for display in the right-hand job result list
M.get_tool_units = function(channel, fmt)
    if fmt.units ~= nil then
      local o = fmt.units
      --"unit1"="Nm", "dec1"=2, "unit2"="°", "fmt"="%(M1)3.1f%Nm / %(M2)7.2f%", "footer"="%(M3)3.1f% -> %(M4)3.1f%"}
      return o.unit1, o.unit2, o.dec1, o.dec2
    end
    -- default
    return '', ' ', 2, 1     --  'MOhm', 'V', '2','2'
end

-- Return a formatted string
M.format = function(channel, fmt)
	local rv = gui_lua_support.ResultValues
	if channel.tool ~= rv.Tool then
		  return 'invalid tool'
	end

  if fmt ~= nil and (fmt.fmt or fmt.ok or fmt.nok) then
        local data = {
            M1 = rv.Param1, M1min = rv.Param1_min, M1max = rv.Param1_max,
            M2 = rv.Param2, M2min = rv.Param2_min, M2max = rv.Param2_max,
            Prg = rv.Prg, Tool = rv.Tool, QC = rv.QC, Step = rv.Step,
        }
        local sret
        if fmt.ok and rv.QC == 1 then
          sret = M.interp(fmt.ok, data)
        elseif fmt.nok and rv.QC ~= 1 then
          sret = M.interp(fmt.nok, data)
        else
          sret = M.interp(fmt.fmt, data)
        end
        --sret = string.format('%3.1fuOhm', tonumber(data.M1))
        --"unit1"="Nm", "dec1"=2, "unit2"="°", "fmt"="%(M1)3.1f%Nm / %(M2)7.2f%", "footer"="%(M3)3.1f% -> %(M4)3.1f%"}
        return sret
    end
    return 'not configured'
end

M.tonumber_def = function(v, def)
  if v == nil then
    return def
  end
  local n = tonumber(v)
  return n
end

-- get the quality/result code from a given actual value and limits
-- returns 2 if act < min
-- returns 4 if act > max
-- returns  0 if min <= act <= max
-- returns 8 otherwise
M.get_code_from_limits = function(act, min, max)
  if act == nil then
    return 8
  end
  if min and max then
     if act < min then return 2 end
     if act > max then return 4 end
     return 0
  else
    if min then   -- we only have min
      if act < min then return 2 end
      return 0
    else          -- we only have max
      if act > min then return 4 end
      return 0
    end
  end
end

-- get the main result string (bottom right pane)
M.get_tool_result_string = function(channel, fmt)
  return M.format(channel, fmt.results)
end

-- Get the tool specific footer string
M.get_footer_string = function(channel, fmt)
	local limits = gui_lua_support.CfgValues
	if channel.tool ~= limits.Tool then
		return 'invalid tool'
	end
  return M.format(channel, fmt.footer)
end

-- Get the tool specific program name
M.get_prg_string = function(channel, fmt)
  return M.format(channel, fmt.prg)
end

-- Registration helper
M.register_tool = function(module)
  -- Compatibility for older OGS versions:
  if not base_lua_tool.default_init then
    module.channels = {}  	        -- initialize the channel structure
    -- create a new tool instance, ini_params are the instance params
    -- as defined in station.ini for the tool channel
    module.registration = function(tool, ini_params)
        XTRACE(16, string.format('%s: tool[%d]: registering tool', module.type, tool))
        local ret = base_lua_tool.registration(module, tool, ini_params)
        if ret ~= 'OK' then
            return ret
        end
        local channel = module.channels[tool]
        return module.init(channel)
    end
  end
  lua_known_tool_types.add_type(module)
end

----------------------------------------------------------------------------
M.split = function(pString, pPattern)
  local Table = {}  -- NOTE: use {n = 0} in Lua-5.0
  local fpat = "(.-)" .. pPattern
  local last_end = 1
  local s, e, cap = pString:find(fpat, 1)
  while s do
     if s ~= 1 or cap ~= "" then
    table.insert(Table,cap)
     end
     last_end = e+1
     s, e, cap = pString:find(fpat, last_end)
  end
  if last_end <= #pString then
     cap = pString:sub(last_end)
     table.insert(Table, cap)
  end
  return Table
end

----------------------------------------------------------------------------
M.interp = function(s, tab)
  return (s:gsub('%%%((%a%w*)%)([-0-9%.]*[cdeEfgGiouxXsq])',
            function(k, fmt) return tab[k] and ("%"..fmt):format(tab[k]) or
                '%('..k..')'..fmt end))
end
--getmetatable("").__mod = interp
--print( "%(key)s is %(val)7.2f%" % {key = "concentration", val = 56.2795} )
-- outputs "concentration is   56.28%"

local data = {key = "concentration", val = 56.2795}
local sret = M.interp("%(key)s is %(val)7.2f%", data)

--print(sret)

return M
