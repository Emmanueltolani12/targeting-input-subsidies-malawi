*! labvar 1.0  -- first variable whose label matches a regular expression
*  usage:  labvar <localname> "<regex>" [varlist]
*  case-insensitive; sets local <localname> in the caller ("" if none).
program define labvar
	version 18
	gettoken out 0 : 0
	gettoken rx 0 : 0
	if `"`0'"' == "" local 0 "_all"
	local found ""
	foreach v of varlist `0' {
		if "`found'" == "" {
			local l : variable label `v'
			if ustrregexm(lower(`"`l'"'), lower(`"`rx'"')) local found `v'
		}
	}
	c_local `out' `found'
end
