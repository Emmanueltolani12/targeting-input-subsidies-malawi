* report_helpers.do -- journal-table and text helpers used by
* 17_paper_tables.do (needs an open file handle 'tex' and an active putdocx
* document)
capture program drop texs
program define texs
	* LaTeX-escape a string into local `2' of the caller
	args s out
	local t `"`s'"'
	local t = subinstr(`"`t'"', "&", "\&", .)
	local t = subinstr(`"`t'"', "%", "\%", .)
	local t = subinstr(`"`t'"', "_", "\_", .)
	local t = subinstr(`"`t'"', "#", "\#", .)
	* number ranges (2010-2024) get an en-dash
	local d = char(36)
	local t = ustrregexra(`"`t'"', "([0-9])-([0-9])", "`d'1--`d'2")
	local t = subinstr(`"`t'"', ">", "\textgreater{}", .)
	local t = subinstr(`"`t'"', "<", "\textless{}", .)
	c_local `out' `"`t'"'
end

capture program drop jt
program define jt
	args num title groups heads note
	* a header string starting with | leaves the label column empty
	if substr(`"`heads'"', 1, 1) == "|" local heads `"_`heads'"'
	quietly ds c*
	local cols `r(varlist)'
	local K : word count `cols'
	local nc = `K' + 1
	local spec "l"
	forvalues j = 1/`K' {
		local spec "`spec'c"
	}
	local ng 0
	if `"`groups'"' != "" local ng 1
	local nh = 1 + `ng'
	local nr = `nh' + _N

	*---------------- LaTeX ----------------
	texs `"`title'"' tt
	file write tex "\begin{table}[htbp]" _n "\centering\footnotesize" _n ///
		"\jtcaption{\textbf{Table `num'}\\ `tt'}" _n ///
		"\begin{jttab}{`spec'}" _n "\toprule" _n
	if `ng' {
		local line ""
		local cm ""
		local pos 1
		tokenize `"`groups'"', parse("|")
		local i 1
		while `"``i''"' != "" {
			if `"``i''"' != "|" {
				gettoken gtxt gspan : `i', parse(":")
				if `"`gtxt'"' == ":" {
					local gtxt ""
					local gspan `"``i''"'
				}
				local gspan = subinstr(`"`gspan'"', ":", "", .)
				texs `"`gtxt'"' gt
				if `pos' > 1 local line "`line' & "
				if "`gt'" == "" {
					local line "`line'"
					forvalues z = 2/`gspan' {
						local line "`line' & "
					}
				}
				else {
					local line "`line'\multicolumn{`gspan'}{c}{`gt'}"
					local cm "`cm'\cmidrule(lr){`pos'-`=`pos'+`gspan'-1'}"
				}
				local pos = `pos' + `gspan'
			}
			local ++i
		}
		file write tex "`line' \\" _n "`cm'" _n
	}
	local line ""
	tokenize `"`heads'"', parse("|")
	local i 1
	local j 0
	while `"``i''"' != "" {
		if `"``i''"' != "|" {
			local ++j
			texs `"``i''"' h
			if `"``i''"' == "_" local h ""
			if `j' == 1 local line "`h'"
			else local line "`line' & `h'"
		}
		local ++i
	}
	file write tex "`line' \\" _n "\midrule" _n
	forvalues r = 1/`=_N' {
		local k = kind[`r']
		texs `"`=lab[`r']'"' L
		if "`k'" == "panel" {
			if `r' > 1 file write tex "\addlinespace" _n
			file write tex "\multicolumn{`nc'}{l}{\textit{`L'}} \\" _n
			continue
		}
		if "`k'" == "row" & "`L'" != "" local line "\quad `L'"
		else local line ""
		foreach v of local cols {
			texs `"`=`v'[`r']'"' x
			local line "`line' & `x'"
		}
		file write tex "`line' \\" _n
	}
	file write tex "\bottomrule" _n "\end{jttab}" _n
	if `"`note'"' != "" {
		texs `"`note'"' nn
		file write tex "\jtnotes{`nn'}" _n
	}
	file write tex "\end{table}" _n _n

	*---------------- Word ----------------
	putdocx paragraph, spacing(before, 12pt)
	putdocx text ("Table `num'"), bold font("Times New Roman", 10)
	putdocx paragraph, spacing(after, 4pt)
	putdocx text ("`title'"), font("Times New Roman", 10)
	putdocx table tb = (`nr', `nc'), border(all, nil) layout(autofitwindow)
	local fnt `"font("Times New Roman", 9)"'
	if `ng' {
		local pos 1
		tokenize `"`groups'"', parse("|")
		local i 1
		while `"``i''"' != "" {
			if `"``i''"' != "|" {
				gettoken gtxt gspan : `i', parse(":")
				if `"`gtxt'"' == ":" {
					local gtxt ""
					local gspan `"``i''"'
				}
				local gspan = subinstr(`"`gspan'"', ":", "", .)
				if `"`gtxt'"' != "" {
					putdocx table tb(1, `pos') = ("`gtxt'"), `fnt' halign(center)
					putdocx table tb(1, `pos'), border(bottom, single, black, 0.5pt)
					if `gspan' > 1 putdocx table tb(1, `pos'), colspan(`gspan')
					local pos = `pos' + 1
				}
				else local pos = `pos' + `gspan'
			}
			local ++i
		}
	}
	tokenize `"`heads'"', parse("|")
	local i 1
	local j 0
	while `"``i''"' != "" {
		if `"``i''"' != "|" {
			local ++j
			local hh `"``i''"'
			if `"`hh'"' == "_" local hh ""
			putdocx table tb(`nh', `j') = ("`hh'"), `fnt' halign(`=cond(`j' == 1, "left", "center")')
		}
		local ++i
	}
	putdocx table tb(1, .), border(top, single, black, 1pt)
	putdocx table tb(`nh', .), border(bottom, single, black, 0.5pt)
	forvalues r = 1/`=_N' {
		local rr = `r' + `nh'
		local k = kind[`r']
		local L = lab[`r']
		if "`k'" == "panel" {
			putdocx table tb(`rr', 1) = ("`L'"), `fnt' italic
			putdocx table tb(`rr', 1), colspan(`nc')
			continue
		}
		local ind = cond("`k'" == "row" & "`L'" != "", "   ", "")
		putdocx table tb(`rr', 1) = ("`ind'`L'"), `fnt'
		local j 1
		foreach v of local cols {
			local ++j
			local x = `v'[`r']
			putdocx table tb(`rr', `j') = ("`x'"), `fnt' halign(center)
		}
	}
	putdocx table tb(`nr', .), border(bottom, single, black, 1pt)
	if `"`note'"' != "" {
		putdocx paragraph, spacing(after, 10pt)
		putdocx text ("Notes: "), italic font("Times New Roman", 8)
		putdocx text ("`note'"), font("Times New Roman", 8)
	}
end

* helpers to build table rows
capture program drop f3
program define f3
	* f3 <newvar> <numvar> [digits]: formatted number, "" if missing
	args nv v d
	if "`d'" == "" local d 3
	gen str20 `nv' = strtrim(string(`v', "%12.`d'f"))
	replace `nv' = strtrim(string(`v', "%12.1f")) if abs(`v') >= 100 & !missing(`v')
	replace `nv' = strtrim(string(`v', "%12.0fc")) if abs(`v') >= 1000 & !missing(`v')
	replace `nv' = "" if missing(`v')
end
capture program drop separ
program define separ
	* separ <newvar> <numvar>: standard error in parentheses
	args nv v
	gen str20 `nv' = "(" + strtrim(string(`v', "%12.3f")) + ")"
	replace `nv' = "" if missing(`v')
end
capture program drop stars
program define stars
	* stars <strvar> <estimate> <se>: append significance stars
	args sv b s
	tempvar z
	gen double `z' = abs(`b' / `s')
	replace `sv' = `sv' + cond(`z' >= 2.576, "***", cond(`z' >= 1.960, "**", cond(`z' >= 1.645, "*", ""))) if !missing(`z')
end
capture program drop panelrow
program define panelrow
	* insert a panel heading before observation `1'
	args at text
	local n = _N + 1
	set obs `n'
	replace lab = "`text'" in `n'
	replace kind = "panel" in `n'
	replace ord = `at' - 0.5 in `n'
	sort ord, stable
end

capture program drop rpar
program define rpar
	* rpar "<text>" [1|2]: paragraph or heading in both documents
	args txt lvl
	local bs = char(92)
	texs `"`txt'"' t2
	if "`lvl'" != "" {
		putdocx paragraph, style(Heading`lvl')
		putdocx text ("`txt'")
		local cmd = cond("`lvl'" == "1", "section", "subsection")
		file write tex "`bs'`cmd'{`t2'}" _n
	}
	else {
		putdocx paragraph
		putdocx text ("`txt'")
		file write tex "`t2'" _n _n
	}
end
capture program drop rbullet
program define rbullet
	args txt
	texs `"`txt'"' t2
	* Word: bullet character and hanging indent (putdocx has no bullet numbering)
	putdocx paragraph, indent(left, 0.6cm) indent(hanging, 0.4cm) spacing(after, 3pt)
	putdocx text ("•" + char(9) + "`txt'")
	file write tex "\begin{itemize}\item `t2'\end{itemize}" _n
end
capture program drop texlists
program define texlists
	* join the one-item itemize blocks written by rbullet into one list
	args f
	tempfile t1 t2
	filefilter "`f'" `t1', from("\BSend{itemize}\W\BSbegin{itemize}") to("\W") replace
	filefilter `t1' `t2', from("\BSend{itemize}\U\BSbegin{itemize}") to("\U") replace
	copy `t2' "`f'", replace
end
capture program drop rfig
program define rfig
	args file num title width
	putdocx paragraph, spacing(before, 12pt)
	putdocx text ("Figure `num'. "), bold font("Times New Roman", 10)
	putdocx text ("`title'"), font("Times New Roman", 10)
	putdocx paragraph, halign(center)
	putdocx image "$FIG/`file'.png", width(`width'cm)
	texs `"`title'"' tt
	file write tex "\begin{figure}[tbp]\centering" _n ///
		"\includegraphics[width=\textwidth]{../figures/`file'.pdf}" _n ///
		"\caption*{\textbf{Figure `num'.} `tt'}" _n "\end{figure}" _n _n
end
