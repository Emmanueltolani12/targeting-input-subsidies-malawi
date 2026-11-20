*! pickvar 1.0  -- first existing variable among candidate names
*  usage:  pickvar <localname> : cand1 cand2 ...
*  sets local <localname> in the caller to the first candidate that exists
*  in the data (exact name match), or to "" if none exists.
program define pickvar
	version 18
	gettoken out 0 : 0
	gettoken colon 0 : 0
	if "`colon'" != ":" {
		di as error "pickvar syntax: pickvar name : candidates"
		exit 198
	}
	local found ""
	foreach c of local 0 {
		if "`found'" == "" {
			capture confirm variable `c', exact
			if !_rc local found `c'
		}
	}
	c_local `out' `found'
end
