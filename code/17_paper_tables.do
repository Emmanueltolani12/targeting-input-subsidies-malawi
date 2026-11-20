*==============================================================================
* 17_paper_tables.do -- tables and numbers of the paper (output/paper)
* Writes output/paper/tables/t*.tex (LaTeX tables, numbered as in the paper)
* and output/paper/numbers.tex (one \newcommand per number used in the text),
* all read from the result files of steps 06-16, so that text and tables
* cannot drift apart. The tables use the layout commands in
* code/ado/jtmacros.tex.
*==============================================================================

global EXT "$ROOT/output/results"
global PAP "$ROOT/output/paper"
capture mkdir "$PAP"
capture mkdir "$PAP/tables"
do "$CODE/ado/report_helpers.do"
* jt also writes Word tables: a scratch document that is never saved
capture putdocx clear
putdocx begin

capture program drop tabopen
program define tabopen
	capture file close tex
	file open tex using "$PAP/tables/t`1'.tex", write replace
end
capture program drop tabclose
program define tabclose
	file close tex
end
capture file close nm
file open nm using "$PAP/numbers.tex", write replace
file write nm "% numbers used in the text, written by code/17_paper_tables.do" _n
capture program drop nmac
program define nmac
	* nmac <name> <value> [format]: \newcommand{\name}{formatted value}
	args name v f
	* a missing r() result leaves the value empty and shifts the format
	if substr(`"`v'"', 1, 1) == "%" | `"`v'"' == "" {
		local f `"`v'"'
		local v = .
		di as error "nmac: no value for \\`name'"
	}
	if "`f'" == "" local f "%9.0fc"
	local s = strtrim(string(`v', "`f'"))
	* negative numbers with a proper minus sign
	if substr("`s'", 1, 1) == "-" local s = "\$-\$" + substr("`s'", 2, .)
	file write nm "\newcommand{\\`name'}{`s'}" _n
end
capture program drop nmacs
program define nmacs
	* nmacs <name> "<text>"
	args name s
	file write nm "\newcommand{\\`name'}{`s'}" _n
end
capture program drop sstar
program define sstar
	* sstar <newvar> <b> <se>
	args nv b s
	gen str14 `nv' = cond(missing(`b'), "", strtrim(string(`b', "%6.3f")) + cond(abs(`b' / `s') >= 2.576, "***", ///
		cond(abs(`b' / `s') >= 1.960, "**", cond(abs(`b' / `s') >= 1.645, "*", ""))))
end
capture program drop pst
program define pst
	args nv p
	gen str4 `nv' = cond(missing(`p'), "", cond(`p' < 0.01, "***", cond(`p' < 0.05, "**", cond(`p' < 0.10, "*", ""))))
end
capture program drop mkse
program define mkse
	* standard error of the fiscal cost per kg: 5th-95th bootstrap percentile
	* range / 3.29 (the standard deviation of a ratio explodes in draws with a
	* maize gain near zero); missing when the 5th percentile of the maize gain
	* is below a tenth of its point estimate (cost per kg unbounded)
	quietly replace se_mk_per_kg = (mk_hi - mk_lo) / (2 * invnormal(0.95))
	quietly replace se_mk_per_kg = . if maize_lo < 0.1 * maize_t
end
local STARS " *** p<0.01, ** p<0.05, * p<0.10."
local BOOT "Bootstrap standard errors in parentheses (500 draws; enumeration areas resampled with all their rounds; demand elasticities drawn from their estimated joint distribution; frontier coefficients drawn (conventional model) or the correlated random-effects frontier re-estimated (joint model); rule scores held fixed)."
local MKSE "MK per kg: standard error from the 5th to 95th percentile range of the draws divided by 3.29."

*------------------------------------------------------------------------------
* Appendix Table A1. sample by round
*------------------------------------------------------------------------------
use "$DER/panel_efficiency.dta", clear
quietly count
nmac NPF `r(N)'
quietly tab uid
nmac NUnits `r(r)'
quietly tab uid if T >= 2
nmac NUnitsTwo `r(r)'
local i 0
foreach w in 2010 2013 2016 2019 2024 {
	local ++i
	local L : word `i' of A B C D E
	quietly count if wave == `w'
	nmac Nmz`L' `r(N)'
}
foreach k in mseed chitowe urea oseed {
	replace q_`k' = 0 if missing(q_`k')
}
gen double fert = chitowe_kg + urea_kg + otherfert_kg
gen byte usefert = fert > 0
gen byte rc = (q_mseed + q_chitowe + q_urea + q_oseed) > 0
gen double qf = q_chitowe + q_urea if rc
* mean subsidized fertilizer kg of a recipient, all rounds (for maize per kg)
quietly summarize qf if qf > 0 & !missing(qf)
global QFREC = r(mean)
nmac QfRec `r(mean)' "%4.0f"
gen double pvc = pv_chitowe
replace pvc = 300 if wave == 2024
gen double mtot = m_total / 1000
gen byte dry = spi12 < -1 if !missing(spi12)
preserve
use "$DER/all_waves_panel_sat.dta", clear
quietly count if wave == 2024 & grows_maize & missing(evi_max)
nmac NnoCoord `r(N)'
restore
local vars maize_kg area_maize fert usefert rc qf p_chitowe pvc mtot spi12 dry hot30
collapse (mean) `vars' (count) n = maize_kg, by(wave)
foreach v in usefert rc dry {
	replace `v' = 100 * `v'
}
xpose, clear varname
rename _varname v
drop if v == "wave"
gen str70 lab = ""
gen ord = .
local i 0
foreach x in "maize_kg Maize harvest (kg)" "area_maize Maize area (ha)" "fert Inorganic fertilizer used (kg)" ///
	"usefert Uses inorganic fertilizer (%)" "rc Received coupons or AIP inputs (%)" ///
	"qf Subsidized fertilizer received, recipients (kg)" "p_chitowe Commercial basal fertilizer price (MK/kg)" ///
	"pvc Farmer price of subsidized fertilizer (MK/kg)" "mtot Total expenditure (MK thousand)" ///
	"spi12 12-month SPI of the season" "dry Drought season, SPI below -1 (%)" "hot30 Days above 30 C" "n Households" {
	local ++i
	gettoken a b : x
	replace lab = strtrim("`b'") if v == "`a'"
	replace ord = `i' if v == "`a'"
}
keep if !missing(ord)
sort ord
gen str8 kind = "row"
forvalues j = 1/5 {
	gen str12 c`j' = strtrim(string(v`j', "%9.1fc"))
	replace c`j' = strtrim(string(v`j', "%9.0fc")) if inlist(v, "maize_kg", "fert", "p_chitowe", "pvc", "mtot", "n", "qf")
	replace c`j' = strtrim(string(v`j', "%9.2f")) if inlist(v, "area_maize", "spi12")
}
keep lab kind c1-c5
tabopen A1
jt "A1" "Maize Growers by Survey Round" ":1|Survey round (rainy season ending in):5" "|2010|2013|2016|2019|2024" "Means over households that grew maize with a positive harvest. Subsidized fertilizer: coupon (2010-2019) or AIP (2024) kilograms of basal fertilizer and urea among recipients. Farmer price: redemption price per kg from the survey; 2024: AIP price of MK 15,000 per 50 kg bag from program documents. Prices and expenditure in current kwacha. SPI: 12-month standardized precipitation index (CHIRPS). 2015/16 and 2023/24 were El Nino droughts."
tabclose

*------------------------------------------------------------------------------
* Table 3. panel frontier
*------------------------------------------------------------------------------
use "$DER/panel_efficiency.dta", clear
quietly summarize u_p
local vp = r(Var)
quietly summarize u_t
local vt = r(Var)
local vshare = 100 * `vp' / (`vp' + `vt')
nmac VshareP `vshare' "%4.1f"
* share of the household effect in the step-1 random-effects residual
* (persistent heterogeneity and inefficiency together): JLMS predictions from
* shrunken household effects understate the persistent share, this bounds it
preserve
import delimited using "$EXT/panel_frontier_estimates.csv", clear varnames(1) stringcols(_all)
destring estimate, replace force
quietly summarize estimate if strtrim(term) == "step1:sigma_u"
local su_ = r(mean)
quietly summarize estimate if strtrim(term) == "step1:sigma_e"
local se_ = r(mean)
nmac HhShare `=100 * `su_'^2 / (`su_'^2 + `se_'^2)' "%4.1f"
restore
foreach x in p t o {
	quietly summarize te_`x'
	local te`x' = r(mean)
	local L = cond("`x'" == "p", "P", cond("`x'" == "t", "T", "O"))
	nmac TE`L' `r(mean)' "%4.2f"
}
import delimited using "$EXT/panel_frontier_stability.csv", clear varnames(1)
nmac RhoTEo `=rank_corr_overall[1]' "%4.2f"
nmac RhoTEt `=rank_corr_transient[1]' "%4.2f"
nmac StayQ `=100 * same_quintile_next_round[1]' "%4.0f"
import delimited using "$EXT/panel_frontier_estimates.csv", clear varnames(1) stringcols(_all)
destring estimate se, replace force
foreach x in "spi_dry12 Dry" "hot30_10 Hot" "spi_shock Wet" {
	gettoken a b : x
	local b = strtrim("`b'")
	quietly summarize estimate if term == "transient_lnsig2u:`a'"
	nmac Tr`b' `r(mean)' "%5.3f"
	quietly summarize se if term == "transient_lnsig2u:`a'"
	nmac Tr`b'SE `r(mean)' "%5.3f"
}
quietly summarize estimate if term == "frontier:returns_to_scale"
nmac RTS `r(mean)' "%4.2f"
foreach x in "c_chit Chit" "c_urea Urea" "c_seed Seed" "c_area Area" {
	gettoken a b : x
	local b = strtrim("`b'")
	quietly summarize estimate if term == "frontier:`a'"
	nmac Fr`b' `r(mean)' "%4.2f"
}
gen str70 lab = ""
gen ord = .
local i 0
foreach x in "frontier:c_seed Maize seed" "frontier:c_org Organic fertilizer" "frontier:c_chit Basal fertilizer" ///
	"frontier:c_urea Urea" "frontier:c_othf Other fertilizer" "frontier:c_lab Labor" "frontier:c_area Area" ///
	"frontier:returns_to_scale Returns to scale" ///
	"transient_lnsig2u:spi_shock Wet season (SPI above 1.5)" "transient_lnsig2u:spi_dry12 Drought (SPI below -1)" ///
	"transient_lnsig2u:hot30_10 Days above 30 C (tens)" "transient_lnsig2u:_cons Constant" ///
	"persistent_lnsig2u:m_head_female Female head" "persistent_lnsig2u:m_educ10 Schooling (tens of years)" ///
	"persistent_lnsig2u:m_landowner Owned land share" "persistent_lnsig2u:m_wealth Asset index" ///
	"persistent_lnsig2u:m_soil_poor Poor soil" "persistent_lnsig2u:_cons Constant" {
	local ++i
	gettoken a b : x
	replace lab = strtrim("`b'") if term == "`a'"
	replace ord = `i' if term == "`a'"
}
keep if !missing(ord)
sort ord
gen str8 kind = "row"
gen str14 c1 = strtrim(string(estimate, "%9.3f")) + cond(missing(se), "", cond(abs(estimate / se) >= 2.576, "***", cond(abs(estimate / se) >= 1.960, "**", cond(abs(estimate / se) >= 1.645, "*", ""))))
expand 2 if !missing(se), gen(dup)
sort ord dup
replace kind = "se" if dup
replace lab = "" if dup
replace c1 = "(" + strtrim(string(se, "%9.3f")) + ")" if dup
replace ord = ord + 0.2 if dup
keep lab kind c1 ord
panelrow 1 "Frontier: output elasticities at the sample mean (step 1)"
panelrow 9 "Transient inefficiency: log variance (step 2)"
panelrow 13 "Persistent inefficiency: log variance, household means (step 3)"
local n = _N + 1
set obs `=_N + 5'
replace kind = "panel" in `n'
replace lab = "Efficiency" in `n'
replace ord = 50 in `n'
local j 0
foreach x in "Persistent efficiency, mean|`=strtrim(string(`tep', "%4.2f"))'" "Transient efficiency, mean|`=strtrim(string(`tet', "%4.2f"))'" ///
	"Overall efficiency, mean|`=strtrim(string(`teo', "%4.2f"))'" "Persistent share of inefficiency variance (%)|`=strtrim(string(`vshare', "%4.1f"))'" {
	local ++j
	gettoken a b : x, parse("|")
	local b = subinstr("`b'", "|", "", 1)
	replace lab = "`a'" in `=`n' + `j''
	replace c1 = "`b'" in `=`n' + `j''
	replace kind = "row" in `=`n' + `j''
	replace ord = 50 + `j' in `=`n' + `j''
}
sort ord
drop ord
tabopen 3
jt "3" "Four-Component Stochastic Frontier for Maize, 2010-2024" "" "|Estimate" "Multi-step estimator of Kumbhakar, Lien and Hardaker (2014). Step 1: random-effects translog frontier with round effects and site conditions, standard errors clustered by household unit; inputs in centered logs of (x + 1). Steps 2 and 3: half-normal frontiers with heteroskedastic inefficiency; step 3 uses households observed in at least two rounds. Standard errors in parentheses.`STARS'"
tabclose

*------------------------------------------------------------------------------
* Appendix Table A2. subsidies by persistent-efficiency quintile
*------------------------------------------------------------------------------
import delimited using "$EXT/panel_frontier_targeting.csv", clear varnames(1)
keep if basis == "persistent"
preserve
keep if inlist(quintile, 4, 5)
collapse (sum) share_subsidy, by(wave)
quietly summarize share_subsidy
nmac TopShareLo `=100 * r(min)' "%3.0f"
nmac TopShareHi `=100 * r(max)' "%3.0f"
restore
gen str40 lab = cond(missing(quintile), "Observed once (no score)", "Quintile " + string(quintile) + cond(quintile == 1, " (least efficient)", cond(quintile == 5, " (most efficient)", "")))
gen int ord = cond(missing(quintile), 6, quintile)
gen str10 s = strtrim(string(share_subsidy, "%5.3f"))
keep wave ord lab s
reshape wide s, i(ord lab) j(wave)
sort ord
gen str8 kind = "row"
rename (s2010 s2013 s2016 s2019 s2024) (c1 c2 c3 c4 c5)
keep lab kind c1-c5
tabopen A2
jt "A2" "Share of Subsidies Received by Persistent-Efficiency Quintile" ":1|Survey round:5" "Persistent efficiency|2010|2013|2016|2019|2024" "Share of all FISP coupons (2010-2019) or of AIP recipient households (2024) among maize growers. Quintiles of persistent efficiency (Table 3) within each round; households observed in only one round have no persistent score."
tabclose

*------------------------------------------------------------------------------
* Appendix Table A4. allocation arrangements and leakage
*------------------------------------------------------------------------------
import delimited using "$EXT/leakage_by_round.csv", clear varnames(1)
local i 0
foreach w in 2010 2013 2016 2019 {
	local ++i
	local L : word `i' of A B C D
	nmac Leak`L' `=100 * any_leak[`i']' "%3.0f"
	nmac NotRed`L' `=100 * not_red[`i']' "%3.0f"
	if `i' > 1 nmac Side`L' `=100 * side_pay[`i']' "%3.0f"
}
import delimited using "$EXT/arrangements_by_round.csv", clear varnames(1)
nmac ForumB `=100 * m_forum_alloc[1]' "%3.0f"
nmac ForumD `=100 * m_forum_alloc[3]' "%3.0f"
nmac PolB `=100 * inv_pol[1]' "%3.0f"
nmac PolD `=100 * inv_pol[3]' "%3.0f"
nmac HeadB `=100 * imp_head[1]' "%3.0f"
nmac HeadD `=100 * imp_head[3]' "%3.0f"
xpose, clear varname
rename _varname v
gen str70 lab = ""
gen ord = .
local i 0
foreach x in "m_forum_alloc Allocation in an open forum" "m_forum_dist Distribution in an open forum" ///
	"m_redistrib Coupons redistributed in the village" "m_supplement Supplementary allocations" ///
	"imp_head Village head important" "imp_vdc Development committee important" ///
	"imp_ext Extension staff important" "imp_ta Traditional authority important" "inv_pol Local politicians involved" {
	local ++i
	gettoken a b : x
	replace lab = strtrim("`b'") if v == "`a'"
	replace ord = `i' if v == "`a'"
}
keep if !missing(ord)
gen str8 c1 = ""
gen str8 c2 = strtrim(string(v1, "%5.2f"))
gen str8 c3 = strtrim(string(v2, "%5.2f"))
gen str8 c4 = strtrim(string(v3, "%5.2f"))
keep lab ord c1-c4
tempfile arrt
save `arrt'
import delimited using "$EXT/leakage_by_round.csv", clear varnames(1)
xpose, clear varname
rename _varname v
gen str70 lab = ""
gen ord = .
local i 20
foreach x in "paid_get Paid someone to get a coupon" "side_pay Side payment at redemption" "sold Sold a coupon" ///
	"gave Gave a coupon away" "lost Lost a coupon" "any_leak Any of the above" "not_red Did not redeem all coupons" ///
	"wait_day Waited a day or more at the depot" "n Recipient households (N)" {
	local ++i
	gettoken a b : x
	replace lab = strtrim("`b'") if v == "`a'"
	replace ord = `i' if v == "`a'"
}
keep if !missing(ord)
forvalues j = 1/4 {
	gen str8 c`j' = cond(missing(v`j'), "", strtrim(string(v`j', "%5.2f")))
	replace c`j' = strtrim(string(v`j', "%9.0fc")) if lab == "Recipient households (N)"
}
keep lab ord c1-c4
append using `arrt'
sort ord
gen str8 kind = "row"
panelrow 1 "A. Allocation in the village (households' reports, fertilizer coupons)"
panelrow 21 "B. Leakage among recipient households"
drop ord
tabopen A4
jt "A4" "Coupon Allocation Arrangements and Leakage, 2010-2019" ":1|Survey round:4" "|2010|2013|2016|2019" "Shares of households. Panel A: questions asked from 2013. Panel B: side payments and waiting time were not asked in 2010; sale, gift and loss refer to coupons not redeemed."
tabclose

*------------------------------------------------------------------------------
* Appendix Table A5. receipt and leakage by arrangement
*------------------------------------------------------------------------------
import delimited using "$EXT/allocation_regressions.csv", clear varnames(1)
foreach x in "PoorRc receipt poor" "LandRc receipt ln_land" "PolRc receipt z_ea_inv_pol" "PolEff receipt effXz_ea_inv_pol" ///
	"ForumPoor receipt poorXz_ea_m_forum_alloc" "LeakPol any_leak z_ea_inv_pol" "NotRedPoor not_red poor" "WaitPol wait_day z_ea_inv_pol" {
	gettoken k t : x
	gettoken m v : t
	local v = strtrim("`v'")
	quietly summarize estimate if model == "`m'" & term == "`v'"
	nmac `k' `=100 * r(mean)' "%4.1f"
	nmac `k'Abs `=abs(100 * r(mean))' "%4.1f"
	quietly summarize se if model == "`m'" & term == "`v'"
	nmac `k'SE `=100 * r(mean)' "%4.1f"
}
gen str40 lab = ""
gen ord = .
local i 0
foreach x in "poor Poorest tertile" "eff_top Two most persistently efficient quintiles" "ln_land Log land cultivated" ///
	"z_ea_m_forum_alloc Open-forum allocation (EA, s.d.)" "z_ea_imp_head Headman important (EA, s.d.)" ///
	"z_ea_inv_pol Politicians involved (EA, s.d.)" "poorXz_ea_m_forum_alloc Poorest x open forum" ///
	"poorXz_ea_inv_pol Poorest x politicians" "effXz_ea_m_forum_alloc Efficient x open forum" ///
	"effXz_ea_inv_pol Efficient x politicians" "mean_outcome Mean of outcome" {
	local ++i
	gettoken a b : x
	replace lab = strtrim("`b'") if term == "`a'"
	replace ord = `i' if term == "`a'"
}
keep if !missing(ord)
gen str12 b = strtrim(string(estimate, "%6.3f")) + cond(missing(se), "", cond(abs(estimate / se) >= 2.576, "***", cond(abs(estimate / se) >= 1.960, "**", cond(abs(estimate / se) >= 1.645, "*", ""))))
gen str12 s = cond(missing(se), "", "(" + strtrim(string(se, "%6.3f")) + ")")
gen byte mm = cond(model == "receipt", 1, cond(model == "any_leak", 2, cond(model == "not_red", 3, 4)))
quietly summarize n if model == "receipt"
local nrec : di %9.0fc r(mean)
quietly summarize n if model == "any_leak"
local nlk : di %9.0fc r(mean)
keep ord lab mm b s
reshape wide b s, i(ord lab) j(mm)
expand 2, gen(dup)
sort ord dup
gen str8 kind = cond(dup, "se", "row")
forvalues j = 1/4 {
	gen str12 c`j' = cond(dup, s`j', b`j')
	replace c`j' = "" if missing(c`j')
}
drop if dup & c1 == "" & c2 == "" & c3 == "" & c4 == ""
replace lab = "" if dup
keep lab kind c1-c4
tabopen A5
jt "A5" "Coupon Receipt and Leakage by Allocation Arrangement, 2013-2019" ":1|All households:1|Recipients:3" "|Receipt|Any leakage|Not redeemed|Waited 1+ day" "Linear probability models with district-by-round effects; standard errors clustered by enumeration area in parentheses. Arrangements: means of the other households' reports in the enumeration area (EA by district cells), standardized. Maize growers observed in at least two rounds (with a persistent-efficiency score). N = `=strtrim("`nrec'")' (receipt) and `=strtrim("`nlk'")' (recipients); controls for female head, schooling and household size.`STARS'"
tabclose

*------------------------------------------------------------------------------
* Appendix Table A3. first stages
*------------------------------------------------------------------------------
import delimited using "$EXT/demand_iv_first_stage.csv", clear varnames(1)
quietly summarize f if spec == "iv"
nmac FfMin `r(min)' "%4.0f"
nmac FfMax `r(max)' "%4.0f"
quietly summarize f_sw if spec == "iv"
nmac FswMin `r(min)' "%3.1f"
nmac FswMax `r(max)' "%3.1f"
quietly summarize partialr2 if spec == "iv"
nmac PrLo `=100 * r(min)' "%3.1f"
nmac PrHi `=100 * r(max)' "%3.1f"
gen double t3 = abs(b3 / se3)
quietly summarize t3 if spec == "iv"
nmac TdMax `r(max)' "%3.1f"
quietly summarize f if spec == "iv_price" & substr(endog, 1, 2) == "p_"
nmac FpMax `r(max)' "%3.1f"
quietly summarize f_sw if spec == "iv_price" & substr(endog, 1, 2) == "p_"
nmac FpswMax `r(max)' "%3.1f"
quietly summarize f_sw if spec == "iv_cov"
nmac FswcMin `r(min)' "%4.1f"
nmac FswcMax `r(max)' "%4.1f"
quietly summarize f if spec == "iv_cov"
nmac FcMin `r(min)' "%4.0f"
nmac FcMax `r(max)' "%4.0f"
quietly summarize n if spec == "iv"
nmac NDem `r(mean)'
local ndem : di %9.0fc r(mean)
import delimited using "$EXT/demand_iv_diagnostics.csv", clear varnames(1)
quietly summarize value if stat == "corr_off1819_news"
nmac RhoOffNews `r(mean)' "%4.2f"
quietly summarize value if stat == "hansen_p" & outcome == "s_chitowe"
nmac HjC `r(mean)' "%4.2f"
quietly summarize value if stat == "hansen_p" & outcome == "s_urea"
nmac HjU `r(mean)' "%4.2f"
import delimited using "$EXT/demand_iv_first_stage.csv", clear varnames(1)
keep if spec == "iv" | (spec == "iv_price" & substr(endog, 1, 2) == "p_")
gen str40 lab = ""
replace lab = "Basal fertilizer coupons" if endog == "chitowe"
replace lab = "Urea coupons" if endog == "urea"
replace lab = "Maize seed coupons" if endog == "mseed"
replace lab = "Other seed (flexi) coupons" if endog == "oseed"
replace lab = "Basal fertilizer" if endog == "p_chitowe"
replace lab = "Urea" if endog == "p_urea"
gen int ord = cond(endog == "chitowe", 1, cond(endog == "urea", 2, cond(endog == "mseed", 3, cond(endog == "oseed", 4, cond(endog == "p_chitowe", 5, 6)))))
sort ord
sstar c1 b1 se1
sstar c2 b2 se2
sstar c3 b3 se3
forvalues j = 1/3 {
	gen str14 e`j' = "(" + strtrim(string(se`j', "%6.3f")) + ")"
}
gen str14 c4 = strtrim(string(f, "%6.1f"))
gen str14 c5 = strtrim(string(f_sw, "%6.1f"))
gen str14 c6 = strtrim(string(partialr2, "%5.3f"))
expand 2, gen(dup)
replace ord = ord + 0.25 if dup
sort ord
gen str8 kind = cond(dup, "se", "row")
replace lab = "" if dup
forvalues j = 1/3 {
	replace c`j' = e`j' if dup
}
foreach v in c4 c5 c6 {
	replace `v' = "" if dup
}
keep ord lab kind c1-c6
panelrow 1 "A. Voucher quotas (10 kg)"
panelrow 5 "B. Log price of commercial fertilizer"
drop ord
tabopen A3
jt "A3" "First Stage: Voucher Quotas and Commercial Fertilizer Prices on Program Instruments" "" "|Own instrument|Official coverage|Delivery timing|F|Conditional F|Partial R²" "Panel A: coupon or AIP kilograms received; own instrument: mean kilograms of the same coupon type received in the other enumeration areas of the district in that round (all four types included). Official coverage: fertilizer beneficiaries per farm family of the district (Logistics Unit reports 2009/10, 2012/13, 2015/16; 2016/17 allocation for 2018/19; Ombudsman report for AIP 2023/24). Delivery timing: mean months after 1 October in which households in the other enumeration areas obtained coupons (2024: redeemed AIP inputs). Panel B: own instrument: log world DAP (basal) or urea price in kwacha, September-December, times log distance to the nearest agricultural market (centered); quota instruments included. F: excluded instruments; conditional F: Sanderson and Windmeijer (2016). Round and region effects, demographics, other log prices and log income included; standard errors clustered by enumeration area. N = `=strtrim("`ndem'")'.`STARS'"
tabclose

*------------------------------------------------------------------------------
* Table 5. elasticities of commercial input spending
*------------------------------------------------------------------------------
import delimited using "$EXT/demand_iv_quota.csv", clear varnames(1)
foreach k in chitowe urea {
	local K = cond("`k'" == "chitowe", "Chit", "Urea")
	foreach sp in exog iv iv_price {
		local S = cond("`sp'" == "exog", "Ex", cond("`sp'" == "iv", "Iv", "Ivp"))
		quietly summarize z if spec == "`sp'" & quota == "`k'" & good == "`k'"
		nmac Z`S'`K' `r(mean)' "%5.2f"
		quietly summarize se if spec == "`sp'" & quota == "`k'" & good == "`k'"
		nmac Z`S'`K'SE `r(mean)' "%4.2f"
	}
}
quietly summarize z if spec == "iv" & quota == "own_price" & inlist(good, "chitowe", "urea")
nmac EpsIv `r(mean)' "%5.2f"
quietly summarize z if spec == "iv_price" & quota == "own_price" & inlist(good, "chitowe", "urea")
nmac EpsIvp `r(mean)' "%5.2f"
gen str12 col = spec
tempfile qa
save `qa'
import delimited using "$EXT/demand_iv_quota_mkt.csv", clear varnames(1)
keep if spec == "iv"
foreach k in chitowe urea {
	local K = cond("`k'" == "chitowe", "Chit", "Urea")
	quietly summarize z if quota == "`k'" & good == "`k'"
	nmac ZMk`K' `r(mean)' "%5.2f"
	quietly summarize se if quota == "`k'" & good == "`k'"
	nmac ZMk`K'SE `r(mean)' "%4.2f"
}
gen str12 col = "mkt"
append using `qa'
keep if (inlist(quota, "chitowe", "urea", "mseed") & (good == quota | (quota == "urea" & good == "chitowe") | (quota == "chitowe" & good == "urea"))) ///
	| (quota == "own_price" & inlist(good, "chitowe", "urea") & col != "mkt")
* rows: coupon type, then the commercial input whose spending responds
gen str60 lab = ""
replace lab = "Basal coupons: basal fertilizer" if quota == "chitowe" & good == "chitowe"
replace lab = "Urea coupons: urea" if quota == "urea" & good == "urea"
replace lab = "Maize seed coupons: maize seed" if quota == "mseed" & good == "mseed"
replace lab = "Urea coupons: basal fertilizer" if quota == "urea" & good == "chitowe"
replace lab = "Basal coupons: urea" if quota == "chitowe" & good == "urea"
replace lab = "Basal fertilizer" if quota == "own_price" & good == "chitowe"
replace lab = "Urea" if quota == "own_price" & good == "urea"
gen int ord = cond(lab == "Basal coupons: basal fertilizer", 1, cond(lab == "Urea coupons: urea", 2, ///
	cond(lab == "Maize seed coupons: maize seed", 3, cond(lab == "Urea coupons: basal fertilizer", 4, ///
	cond(lab == "Basal coupons: urea", 5, cond(lab == "Basal fertilizer", 7, 8))))))
gen byte cc = cond(col == "exog", 1, cond(col == "iv", 2, cond(col == "iv_cov", 3, cond(col == "iv_price", 4, 5))))
sstar b z se
gen str14 s = cond(missing(se), "", "(" + strtrim(string(se, "%6.3f")) + ")")
keep ord lab cc b s
reshape wide b s, i(ord lab) j(cc)
expand 2, gen(dup)
sort ord dup
gen str8 kind = cond(dup, "se", "row")
forvalues j = 1/5 {
	capture confirm variable b`j'
	if _rc {
		gen str14 b`j' = ""
		gen str14 s`j' = ""
	}
	gen str14 c`j' = cond(dup, s`j', b`j')
	replace c`j' = "" if missing(c`j')
}
replace lab = "" if dup
keep ord lab kind c1-c5
panelrow 1 "A. Quota elasticities (coupon type: commercial input)"
panelrow 7 "B. Own-price elasticities of commercial spending"
drop ord
tabopen 5
jt "5" "Elasticities of Commercial Input Spending, 2010-2024" ":1|Transfer valued at the redemption price:4|Market value:1" "|Exogenous|Instrumented|Coverage only|Quotas and prices|Instrumented" "Censored quota-constrained QUAIDS of commercial spending on five inputs, evaluated at the sample means (equation \eqref{eq:zeta}). Exogenous: quotas treated as exogenous. Instrumented: control functions for the four quotas (Appendix Table A3, panel A instruments). Coverage only: other-EA coverage as the only instruments. Quotas and prices: control functions also for the prices of basal fertilizer and urea (panel B), with remoteness in the share equations. Market value: instrumented model with the income effect of the transfer valued at market prices. Standard errors (delta method, clustered by enumeration area) in parentheses.`STARS'"
tabclose
import delimited using "$EXT/demand_iv_eta.csv", clear varnames(1)
quietly summarize eta if group == "Food & beverage" & point == "total"
nmac EtaFood `r(mean)' "%4.2f"

*------------------------------------------------------------------------------
* Table 1. realized returns of allocation rules
*------------------------------------------------------------------------------
import delimited using "$EXT/grf_summary.csv", clear varnames(1)
nmac ATE `=value[1]' "%4.0f"
nmac ATEse `=se[1]' "%3.0f"
nmac ATT `=value[2]' "%4.0f"
nmac ATTse `=se[2]' "%3.0f"
nmac MzPerKg `=value[2] / $QFREC' "%4.1f"
nmac ATElnY `=value[3]' "%4.2f"
nmac CalD `=value[5]' "%4.2f"
nmac CalDse `=se[5]' "%4.2f"
import delimited using "$EXT/policy_differences.csv", clear varnames(1)
foreach x in "Poor Poorest first" "Cate Highest predicted returns" "Eff Persistent efficiency first (predicted)" "Tree Policy tree (depth 2)" "Small Smallest farms first" "Rnd Random" {
	gettoken k r : x
	local r = strtrim("`r'")
	quietly summarize difference if rule == "`r'" & reference == "Actual allocation, as predicted from traits"
	nmac D`k' `r(mean)' "%4.0f"
	nmac D`k'Abs `=abs(r(mean))' "%4.0f"
	quietly summarize se if rule == "`r'" & reference == "Actual allocation, as predicted from traits"
	nmac D`k'SE `r(mean)' "%3.0f"
	quietly summarize difference if rule == "`r'" & reference == "Random"
	nmac R`k' `r(mean)' "%4.0f"
	quietly summarize lo if rule == "`r'" & reference == "Random"
	nmac R`k'Lo `r(mean)' "%4.0f"
	quietly summarize hi if rule == "`r'" & reference == "Random"
	nmac R`k'Hi `r(mean)' "%4.0f"
}
import delimited using "$EXT/policy_values.csv", clear varnames(1)
foreach x in "Act Actual allocation" "ActP Actual allocation, as predicted from traits" "Rnd Random" "Poor Poorest first" "Small Smallest farms first" "Eff Persistent efficiency first (predicted)" "Cate Highest predicted returns" "Tree Policy tree (depth 2)" {
	gettoken k r : x
	local r = strtrim("`r'")
	quietly summarize kg_per_voucher if rule == "`r'"
	nmac V`k' `r(mean)' "%4.0f"
}
quietly summarize n_selected if rule == "Actual allocation"
nmac NGrf `r(mean)'
tempfile pv
save `pv'
import delimited using "$EXT/policy_differences.csv", clear varnames(1)
keep if reference == "Actual allocation, as predicted from traits"
keep rule difference se
rename (difference se) (dif dif_se)
merge 1:1 rule using `pv', nogen
gen ord = cond(rule == "Actual allocation", 1, cond(rule == "Actual allocation, as predicted from traits", 2, ///
	cond(rule == "Random", 3, cond(rule == "Poorest first", 4, cond(rule == "Smallest farms first", 5, ///
	cond(rule == "Persistent efficiency first (predicted)", 6, cond(rule == "Highest predicted returns", 7, 8)))))))
sort ord
gen str60 lab = rule
gen str8 kind = "row"
gen double se_k = cond(rule == "Actual allocation", se, se_boot)
gen str12 c1 = strtrim(string(kg_per_voucher, "%5.0f")) + cond(abs(kg_per_voucher / se_k) >= 2.576, "***", cond(abs(kg_per_voucher / se_k) >= 1.960, "**", cond(abs(kg_per_voucher / se_k) >= 1.645, "*", "")))
gen str12 c2 = cond(ord <= 2, "", strtrim(string(dif, "%5.0f")) + cond(abs(dif / dif_se) >= 2.576, "***", cond(abs(dif / dif_se) >= 1.960, "**", cond(abs(dif / dif_se) >= 1.645, "*", ""))))
gen str12 c3 = strtrim(string(share_poorest_tertile, "%4.2f"))
gen str12 c4 = strtrim(string(mean_land_ha, "%4.2f"))
gen str12 c5 = strtrim(string(share_also_actual, "%4.2f"))
expand 2, gen(dup)
sort ord dup
replace kind = "se" if dup
replace lab = "" if dup
replace c1 = "(" + strtrim(string(se_k, "%4.0f")) + ")" if dup
replace c2 = cond(ord <= 2, "", "(" + strtrim(string(dif_se, "%4.0f")) + ")") if dup
foreach v in c3 c4 c5 {
	replace `v' = "" if dup
}
keep lab kind c1-c5
tabopen 1
jt "1" "Realized Maize Return to a Voucher under Alternative Allocation Rules, 2010-2024" "" "Rule|kg per voucher|Difference|Poorest tertile|Land (ha)|Also recipient" "kg per voucher: mean doubly robust score of the selected households (actual allocation: average effect on the treated), causal forest; standard errors from 500 enumeration-area bootstrap draws in parentheses. Difference: against the actual allocation reproduced from verifiable traits. Rules select the actual number of recipients in each round and are cross-fitted over five folds of enumeration areas. Persistent efficiency predicted by a random forest from verifiable traits; predicted returns from fold-specific causal forests. Poorest tertile: share of the selected households in the poorest wealth tertile of the round; Land: their mean land area; Also recipient: share that actually received a voucher. Stars: kg per voucher against zero, difference against the actual allocation.`STARS'"
tabclose

*------------------------------------------------------------------------------
* Table 2. value of satellite information for targeting
*------------------------------------------------------------------------------
import delimited using "$EXT/satellite_targeting.csv", clear varnames(1)
destring autoc se_autoc corr_with_both, replace force
foreach x in "Sv survey" "St satellite" "Bo both" "Po poor" {
	gettoken k r : x
	local r = strtrim("`r'")
	quietly summarize kg_per_voucher if rule == "`r'"
	nmac VS`k' `r(mean)' "%4.0f"
	quietly summarize se if rule == "`r'"
	nmac VS`k'SE `r(mean)' "%3.0f"
	foreach c in random actual_pred survey {
		local C = cond("`c'" == "random", "Rnd", cond("`c'" == "actual_pred", "Act", "Sv"))
		quietly summarize diff_`c' if rule == "`r'"
		nmac DS`k'`C' `r(mean)' "%4.0f"
		nmac DS`k'`C'Abs `=abs(r(mean))' "%4.0f"
		quietly summarize se_diff_`c' if rule == "`r'"
		nmac DS`k'`C'SE `r(mean)' "%3.0f"
	}
	quietly summarize autoc if rule == "`r'"
	nmac AUTOC`k' `r(mean)' "%4.0f"
	quietly summarize se_autoc if rule == "`r'"
	nmac AUTOC`k'SE `r(mean)' "%3.0f"
}
preserve
import delimited using "$EXT/satellite_toc.csv", clear varnames(1)
keep if abs(q - 0.10) < 1e-6
quietly summarize toc if set == "Satellite features only"
nmac TOCStTen `r(mean)' "%4.0f"
quietly summarize lo if set == "Satellite features only"
nmac TOCStTenLo `r(mean)' "%4.0f"
quietly summarize hi if set == "Satellite features only"
nmac TOCStTenHi `r(mean)' "%4.0f"
quietly summarize toc if set == "Survey traits"
nmac TOCSvTen `r(mean)' "%4.0f"
nmac TOCSvTenAbs `=abs(r(mean))' "%4.0f"
restore
quietly summarize corr_with_both if rule == "satellite"
nmac CorrSatBoth `r(mean)' "%4.2f"
import delimited using "$EXT/grid_targeting.csv", clear varnames(1)
nmac VGrid `=kg_per_voucher[1]' "%4.0f"
nmac VGridSE `=se[1]' "%3.0f"
nmac VGridRnd `=kg_per_voucher[2]' "%4.0f"
import delimited using "$EXT/district_returns.csv", clear varnames(1)
quietly summarize pred_return
nmac DistLo `r(min)' "%4.0f"
nmac DistHi `r(max)' "%4.0f"
quietly corr pred_return coverage_2024
nmac RhoDistCov `r(rho)' "%4.2f"
import delimited using "$EXT/ml_benchmark.csv", clear varnames(1)
quietly summarize r2 if features == "Survey" & model == "OLS"
nmac RtwoOLS `r(mean)' "%4.2f"
quietly summarize r2 if features == "Survey" & model == "Gradient boosting"
nmac RtwoGBs `r(mean)' "%4.2f"
quietly summarize r2 if features == "Survey + satellite" & model == "Gradient boosting"
nmac RtwoGBb `r(mean)' "%4.2f"
quietly summarize r2 if features == "Satellite" & model == "Gradient boosting"
nmac RtwoGBsat `r(mean)' "%4.2f"
import delimited using "$EXT/targeting_benchmark.csv", clear varnames(1)
quietly summarize auc
nmac AUClo `r(min)' "%4.2f"
nmac AUChi `r(max)' "%4.2f"
import delimited using "$EXT/satellite_targeting.csv", clear varnames(1)
destring autoc se_autoc corr_with_both, replace force
gen int ord = cond(rule == "survey", 1, cond(rule == "satellite", 2, cond(rule == "both", 3, cond(rule == "actual_pred", 4, cond(rule == "poor", 5, 6)))))
sort ord
gen str60 lab = label
replace lab = "Survey traits" if rule == "survey"
replace lab = "Satellite features only" if rule == "satellite"
replace lab = "Survey traits and satellite features" if rule == "both"
gen str8 kind = "row"
pst s1 p_random
pst s2 p_actual_pred
gen str12 c1 = strtrim(string(kg_per_voucher, "%5.0f"))
gen str12 c2 = cond(rule == "random", "", strtrim(string(diff_random, "%5.0f")) + s1)
gen str12 c3 = cond(rule == "actual_pred", "", strtrim(string(diff_actual_pred, "%5.0f")) + s2)
gen str12 c4 = cond(missing(autoc), "", strtrim(string(autoc, "%5.0f")))
gen str12 c5 = strtrim(string(share_poorest_tertile, "%4.2f"))
gen str12 e1 = "(" + strtrim(string(se, "%5.0f")) + ")"
gen str12 e2 = cond(rule == "random", "", "(" + strtrim(string(se_diff_random, "%5.0f")) + ")")
gen str12 e3 = cond(rule == "actual_pred", "", "(" + strtrim(string(se_diff_actual_pred, "%5.0f")) + ")")
gen str12 e4 = cond(missing(se_autoc), "", "(" + strtrim(string(se_autoc, "%5.0f")) + ")")
expand 2, gen(dup)
replace ord = ord + 0.25 if dup
sort ord
replace kind = "se" if dup
replace lab = "" if dup
forvalues j = 1/4 {
	replace c`j' = e`j' if dup
}
replace c5 = "" if dup
keep ord lab kind c1-c5
panelrow 1 "Rules ranked by predicted returns, features used"
panelrow 4 "Reference rules"
drop ord
tabopen 2
jt "2" "Value of Satellite Information for Targeting Fertilizer Vouchers, 2010-2024" "" "|kg per voucher|vs random|vs actual|AUTOC|Poorest tertile" "Each rule serves, in every round, as many households as actually received a voucher. Predicted returns: causal forests fitted on four folds of enumeration areas and predicting on the fifth, with the three feature sets of the method; satellite features: soils (iSDAsoil), travel time, cropland share, mean Sentinel-2 crop vigor 2018/19-2022/23, long-run rainfall, its variability and temperature, available for every location. Values: mean doubly robust score of the households served (equation \eqref{eq:aipw}). vs actual: against the actual allocation reproduced from verifiable traits. AUTOC: area under the targeting operating characteristic (equation \eqref{eq:toc}), kg per voucher. The survey-and-satellite rule adds Sentinel-2 vigor and long-run climate to the features of the predicted-returns rule of Table 1. Standard errors from 500 enumeration-area bootstrap draws in parentheses; stars: two-sided bootstrap test of the difference.`STARS'"
tabclose

*------------------------------------------------------------------------------
* Table 6. structural evaluation of rules, conventional model
*------------------------------------------------------------------------------
* why the conventional model favors actual recipients
use "$DER/panel_efficiency.dta", clear
foreach k in mseed chitowe urea oseed {
	replace q_`k' = 0 if missing(q_`k')
}
gen byte rc_ = (q_mseed + q_chitowe + q_urea + q_oseed) > 0
gen byte nof_ = max(chitowe_kg - q_chitowe, 0) + max(urea_kg - q_urea, 0) == 0
gen double elf_ = max(el_c_chit, 0) + max(el_c_urea, 0)
quietly summarize nof_ if rc_ == 1
nmac NoOwnRec `=100 * r(mean)' "%3.0f"
quietly summarize nof_ if rc_ == 0
nmac NoOwnOth `=100 * r(mean)' "%3.0f"
quietly summarize elf_ if rc_ == 1
nmac ElfRec `r(mean)' "%4.2f"
quietly summarize elf_ if rc_ == 0
nmac ElfOth `r(mean)' "%4.2f"
quietly summarize elf_ if wealth_t == 1
nmac ElfPoor `r(mean)' "%4.2f"
import delimited using "$EXT/structural_allrounds.csv", clear varnames(1)
mkse
foreach sp in exog iv {
	local S = cond("`sp'" == "exog", "Ex", "Iv")
	quietly summarize maize_t if rule == "actual" & spec == "`sp'"
	nmac SA`S' `r(mean)' "%9.0fc"
	quietly summarize se_maize_t if rule == "actual" & spec == "`sp'"
	nmac SA`S'SE `r(mean)' "%9.0fc"
	quietly summarize kg_per_package if rule == "actual" & spec == "`sp'"
	nmac SAkg`S' `r(mean)' "%4.0f"
	quietly summarize se_kg_per_package if rule == "actual" & spec == "`sp'"
	nmac SAkg`S'SE `r(mean)' "%3.0f"
	quietly summarize p_best if rule == "actual" & spec == "`sp'"
	nmac SAbest`S' `=100 * r(mean)' "%3.0f"
	quietly summarize mk_per_kg if rule == "actual" & spec == "`sp'"
	nmac SAmk`S' `r(mean)' "%4.0f"
	quietly summarize se_mk_per_kg if rule == "actual" & spec == "`sp'"
	nmac SAmk`S'SE `r(mean)' "%3.0f"
	quietly summarize food_pct_poor if rule == "actual" & spec == "`sp'"
	nmac SAfp`S' `=abs(r(mean))' "%4.2f"
	foreach x in "Rnd random" "Poor poor" "Eff effpr" "Cate cate" "Tree tree" {
		gettoken k r : x
		local r = strtrim("`r'")
		quietly summarize d_pct if rule == "`r'" & spec == "`sp'"
		nmac SA`S'`k' `r(mean)' "%4.0f"
		nmac SA`S'`k'Abs `=abs(r(mean))' "%4.0f"
		quietly summarize se_d_pct if rule == "`r'" & spec == "`sp'"
		nmac SA`S'`k'SE `r(mean)' "%3.0f"
	}
}
quietly summarize households if rule == "actual" & spec == "iv"
nmac NSA `r(mean)'
local nsa : di %9.0fc r(mean)
gen int ord = cond(rule == "actual", 1, cond(rule == "random", 2, cond(rule == "poor", 3, cond(rule == "effpr", 4, cond(rule == "cate", 5, 6)))))
pst st p_d
gen str12 m_ = strtrim(string(maize_t, "%9.0fc"))
gen str12 ms_ = "(" + strtrim(string(se_maize_t, "%9.0fc")) + ")"
gen str12 d_ = cond(rule == "actual", "", strtrim(string(d_pct, "%5.0f")) + st)
gen str12 ds_ = cond(rule == "actual", "", "(" + strtrim(string(se_d_pct, "%5.0f")) + ")")
gen str12 k_ = strtrim(string(mk_per_kg, "%5.0f"))
gen str12 ks_ = cond(missing(se_mk_per_kg), "(–)", "(" + strtrim(string(se_mk_per_kg, "%5.0f")) + ")")
gen str12 f_ = strtrim(string(cond(abs(food_pct_poor) < 0.005, 0, food_pct_poor), "%6.2f"))
gen str12 fs_ = "(" + strtrim(string(se_food_pct_poor, "%6.2f")) + ")"
keep ord rule spec m_ ms_ d_ ds_ k_ ks_ f_ fs_
* the two quota specifications as stacked panels (eight columns side by side
* do not fit the page)
replace ord = ord + 10 if spec == "iv"
sort ord
gen str60 lab = ""
replace lab = "Actual recipients" if rule == "actual"
replace lab = "Random" if rule == "random"
replace lab = "Poorest first" if rule == "poor"
replace lab = "Persistent efficiency first (predicted)" if rule == "effpr"
replace lab = "Highest predicted returns" if rule == "cate"
replace lab = "Policy tree" if rule == "tree"
expand 2, gen(dup)
sort ord dup
gen str8 kind = cond(dup, "se", "row")
local j 0
foreach v in m d k f {
	local ++j
	gen str12 c`j' = cond(dup, `v's_, `v'_)
}
replace lab = "" if dup
keep ord lab kind c1-c4
panelrow 1 "A. Quotas treated as exogenous"
panelrow 11 "B. Instrumented quotas"
drop ord
tabopen 6
jt "6" "Structural Evaluation of Allocation Rules, Conventional Model, 2010-2024" "" "|Maize gain (t)|Change (%)|MK per kg|Food, poorest (%)" "Conventional model: food expenditure elasticity of the upper-stage QUAIDS; quota elasticities significant at 10% (Table 5) applied to the quota valued at the redemption price; household output elasticities of the panel translog (Table 3). Panel A treats the quotas as exogenous, panel B instruments them (Appendix Table A3). Every rule serves `=strtrim("`nsa'")' household-rounds (the actual number of recipients in each round) with the round's standard package. Maize gain: against no subsidy in the sample. Change: change in the maize gain against the actual allocation. MK per kg: fiscal cost (market minus farmer price, kwacha of 2023/24) per extra kg of maize. Food: mean change in food spending, poorest wealth tertile. `BOOT' `MKSE' Stars: change against the actual allocation, two-sided bootstrap test.`STARS'"
tabclose

*------------------------------------------------------------------------------
* Table 7. structural predictions against realized returns
*------------------------------------------------------------------------------
* crowding-out of the joint model: commercial kg displaced per coupon kg at
* the evaluation point of the instrumented elasticities (transfer at market
* value), zeta x mean commercial kg / mean quota kg (demand sample)
use "$DER/demand_iv_sample.dta", clear
foreach g in chitowe urea {
	quietly summarize com_kg`g'
	local xc_`g' = r(mean)
	quietly summarize q_`g'
	local qs_`g' = r(mean)
}
import delimited using "$EXT/demand_iv_quota_mkt.csv", clear varnames(1)
keep if spec == "iv"
foreach x in "UU urea urea" "UB urea chitowe" "BB chitowe chitowe" "BU chitowe urea" {
	tokenize `x'
	quietly summarize z if quota == "`2'" & good == "`3'"
	nmac Cv`1' `=abs(r(mean)) * `xc_`3'' / `qs_`2''' "%4.2f"
}
* commercial fertilizer purchases of recipients and other households, 2024
use "$DER/panel_efficiency.dta", clear
keep if wave == 2024
foreach k in mseed chitowe urea oseed {
	replace q_`k' = 0 if missing(q_`k')
}
gen byte rc_ = (q_mseed + q_chitowe + q_urea + q_oseed) > 0
gen byte cf_ = (cond(missing(com_kgchitowe), 0, com_kgchitowe) + cond(missing(com_kgurea), 0, com_kgurea)) > 0
quietly summarize cf_ if rc_ == 1
nmac ComRec `=100 * r(mean)' "%3.0f"
quietly summarize cf_ if rc_ == 0
nmac ComOth `=100 * r(mean)' "%3.0f"
import delimited using "$EXT/cf_frontier.csv", clear varnames(1)
quietly summarize estimate if term == "CF exogeneity test p"
nmac CFp `r(mean)' "%5.3f"
quietly summarize estimate if strpos(term, "CF first stage F")
nmac CFFmin `r(min)' "%3.1f"
nmac CFFmax `r(max)' "%3.1f"
quietly summarize estimate if term == "CRE Mundlak test chi2"
nmac CREchi `r(mean)' "%4.1f"
quietly summarize estimate if term == "CRE Mundlak test p"
nmac CREp `r(mean)' "%5.3f"
foreach x in "c_chit Chit" "c_urea Urea" "c_seed Seed" {
	gettoken a b : x
	local b = strtrim("`b'")
	quietly summarize estimate if term == "CRE mean elasticity: `a'"
	nmac ElCRE`b' `r(mean)' "%4.2f"
	quietly summarize estimate if term == "RE mean elasticity: `a'"
	nmac ElRE`b' `r(mean)' "%4.2f"
	quietly summarize estimate if term == "CF mean elasticity: `a'"
	nmac ElCF`b' `r(mean)' "%4.2f"
}
* joint model: difference to the actual allocation in kg per package, with its
* bootstrap standard error and two-sided p-value from the draws (percentages are
* not informative where the gain of the actual allocation is near zero)
use "$DER/sim13_draws_joint.dta", clear
keep if part == "A" & spec == "iv"
bysort draw: egen double a0_ = max(cond(rule == "actual", kg_per_hh, .))
gen double dk_ = kg_per_hh - a0_
gen double le_ = dk_ <= 0
gen double ge_ = dk_ >= 0
preserve
keep if draw == 0
keep rule dk_
rename dk_ dk
tempfile k0
save `k0'
restore
keep if draw > 0
collapse (sd) se_dk = dk_ (mean) le_ ge_, by(rule)
gen double p_dk = min(1, 2 * min(le_, ge_))
merge 1:1 rule using `k0', nogen
keep rule dk se_dk p_dk
tempfile dkj
save `dkj'
import delimited using "$EXT/structural_vs_realised.csv", clear varnames(1)
merge 1:1 rule using `dkj', nogen
nmac RhoPaper `=rho_conv[1]' "%4.2f"
nmac RhoJoint `=rho_joint[1]' "%4.2f"
foreach x in "Act actual" "Rnd random" "Poor poor" "Eff effpr" "Cate cate" "Tree tree" {
	gettoken k r : x
	local r = strtrim("`r'")
	quietly summarize kg_joint if rule == "`r'"
	nmac KJ`k' `r(mean)' "%4.0f"
	quietly summarize se_joint if rule == "`r'"
	nmac KJ`k'SE `r(mean)' "%3.0f"
	quietly summarize dk if rule == "`r'"
	nmac DJ`k' `r(mean)' "%4.0f"
	nmac DJ`k'Abs `=abs(r(mean))' "%4.0f"
	nmacs DJ`k'W `"`=cond(r(mean) < 0, "less", "more")'"'
	quietly summarize se_dk if rule == "`r'"
	nmac DJ`k'SE `r(mean)' "%3.0f"
	quietly summarize ratio_conv if rule == "`r'"
	nmac RatP`k' `r(mean)' "%3.1f"
	quietly summarize ratio_joint if rule == "`r'"
	nmac RatJ`k' `r(mean)' "%3.1f"
}
quietly summarize ratio_conv
nmac RatPLo `r(min)' "%3.1f"
nmac RatPHi `r(max)' "%3.1f"
quietly summarize ratio_joint
nmac RatJLo `r(min)' "%3.1f"
nmac RatJHi `r(max)' "%3.1f"
gen str60 lab = ""
replace lab = "Actual allocation" if rule == "actual"
replace lab = "Random" if rule == "random"
replace lab = "Poorest first" if rule == "poor"
replace lab = "Persistent efficiency first (predicted)" if rule == "effpr"
replace lab = "Highest predicted returns" if rule == "cate"
replace lab = "Policy tree" if rule == "tree"
sort ord
pst stj p_dk
gen str8 kind = "row"
gen str12 c1 = strtrim(string(kg_real, "%5.0f"))
gen str12 c2 = strtrim(string(kg_conv, "%5.0f"))
gen str12 c3 = strtrim(string(kg_joint, "%5.0f"))
gen str12 c4 = cond(rule == "actual", "", strtrim(string(dk, "%5.0f")) + stj)
gen str12 c5 = strtrim(string(ratio_conv, "%4.1f"))
gen str12 c6 = strtrim(string(ratio_joint, "%4.1f"))
gen str12 e1 = "(" + strtrim(string(se_real, "%5.0f")) + ")"
gen str12 e2 = "(" + strtrim(string(se_conv, "%5.0f")) + ")"
gen str12 e3 = "(" + strtrim(string(se_joint, "%5.0f")) + ")"
gen str12 e4 = cond(rule == "actual", "", "(" + strtrim(string(se_dk, "%5.0f")) + ")")
expand 2, gen(dup)
replace ord = ord + 0.25 if dup
sort ord
replace kind = "se" if dup
replace lab = "" if dup
forvalues j = 1/4 {
	replace c`j' = e`j' if dup
}
replace c5 = "" if dup
replace c6 = "" if dup
keep lab kind c1-c6
tabopen 7
jt "7" "Maize Gain per Voucher or Package: Realized Returns and Two Structural Models, 2010-2024" ":1|kg of maize:3|Joint model:1|Ratio to realized:2" "|Realized|Conventional|Joint|vs actual (kg)|Conventional|Joint" "Realized: mean doubly robust score of the households selected by each rule (actual allocation: average effect on the treated), Table 1. Conventional: Table 6, instrumented quotas. Joint: quota elasticities of the instrumented demand system with the transfer at market value, no pre-test, converted into displaced commercial kilograms within input groups, at most one per coupon kilogram and bounded by the household's purchases without the program (equation \eqref{eq:crowdjoint}); output elasticities of the correlated random-effects panel translog (Mundlak means of the inputs). vs actual: difference of the joint model's gain per package from that of the actual allocation, kg. `BOOT' Stars: difference against the actual allocation, two-sided bootstrap test.`STARS'"
tabclose

*------------------------------------------------------------------------------
* Table 8. AIP levers, conventional and joint model
*------------------------------------------------------------------------------
foreach m in conv joint {
	local f = cond("`m'" == "conv", "aip_levers.csv", "aip_levers_joint.csv")
	local M = cond("`m'" == "conv", "C", "J")
	* change in the maize gain against the AIP as implemented in metric tons, with
	* its bootstrap standard error and two-sided p-value, from the draws (the
	* percentage change is not informative where the gain itself is near zero)
	use "$DER/sim13_draws`=cond("`m'" == "joint", "_joint", "")'.dta", clear
	gen long obs_ = _n
	keep if part == "B"
	bysort draw (obs_): gen int row_ = _n
	bysort draw: egen double b0_ = max(cond(row_ == 1, maize_t, .))
	gen double dt_ = maize_t - b0_
	gen double le_ = dt_ <= 0
	gen double ge_ = dt_ >= 0
	preserve
	keep if draw == 0
	keep row_ dt_
	rename dt_ dt
	tempfile d0
	save `d0'
	restore
	keep if draw > 0
	collapse (sd) se_dt = dt_ (mean) le_ ge_, by(row_)
	gen double p_dt = min(1, 2 * min(le_, ge_))
	merge 1:1 row_ using `d0', nogen
	keep row_ dt se_dt p_dt
	tempfile dt_`m'
	save `dt_`m''
	import delimited using "$EXT/`f'", clear varnames(1)
mkse
	gen int row_ = _n
	merge 1:1 row_ using `dt_`m'', nogen
	replace dt = . if row_ == 1
	replace se_dt = . if row_ == 1
	replace p_dt = . if row_ == 1
	if "`m'" == "conv" {
		nmac EpsFert `=eps_fert[1]' "%4.2f"
		nmac NEaip `=eaip_registered[1]'
		nmac NAip `=aip_recipients[1]'
		nmac BagCut `=100 * (1 - min(1, 2^eps_fert[1]))' "%3.0f"
		nmac NbX `=households[5] / households[1]' "%3.1f"
	}
	local i 0
	foreach k in Base PHalf POneHalf PTwo PTwoBN BOneHalf BTwo Eaip RPoor RCate REff RRnd {
		local ++i
		nmac A`M'`k' `=maize_t[`i']' "%5.1f"
		nmac A`M'`k'SE `=se_maize_t[`i']' "%4.1f"
		nmac A`M'mk`k' `=mk_per_kg[`i']' "%5.0f"
		nmac A`M'fp`k' `=abs(food_pct_poor[`i'])' "%4.2f"
		if `i' > 1 {
			nmac A`M'dt`k' `=dt[`i']' "%5.1f"
			nmac A`M'dt`k'Abs `=abs(dt[`i'])' "%5.1f"
			nmacs A`M'dt`k'W `"`=cond(dt[`i'] < 0, "less", "more")'"'
			nmac A`M'dt`k'SE `=se_dt[`i']' "%4.1f"
			nmac A`M'd`k' `=d_pct[`i']' "%4.0f"
			nmac A`M'd`k'Abs `=abs(d_pct[`i'])' "%4.0f"
			nmacs A`M'd`k'W `"`=cond(d_pct[`i'] < 0, "less", "more")'"'
			nmac A`M'd`k'SE `=se_d_pct[`i']' "%3.0f"
		}
	}
	* the two models as stacked panels (side by side they do not fit the page)
	gen ord = _n + cond("`m'" == "joint", 20, 0)
	gen str70 lab = lever
	local i 0
	foreach l in "As implemented (actual recipients)" "Farmer price ×0.5" "Farmer price ×1.5" "Farmer price ×2" ///
		"Farmer price ×2, savings to more households" "Beneficiaries ×1.5" "Beneficiaries ×2" "Registered: all households" ///
		"Registered: poorest first" "Registered: highest predicted returns" "Registered: persistent efficiency first" "Registered: random" {
		local ++i
		replace lab = "`l'" in `i'
	}
	pst st p_dt
	gen str12 m_ = strtrim(string(maize_t, "%9.1f"))
	gen str12 ms_ = "(" + strtrim(string(se_maize_t, "%9.1f")) + ")"
	gen str12 d_ = cond(_n == 1, "", strtrim(string(cond(abs(dt) < 0.05, 0, dt), "%9.1f")) + st)
	gen str12 ds_ = cond(_n == 1, "", "(" + strtrim(string(se_dt, "%9.1f")) + ")")
	gen str12 k_ = strtrim(string(mk_per_kg, "%5.0f"))
	gen str12 ks_ = cond(missing(se_mk_per_kg), "(–)", "(" + strtrim(string(se_mk_per_kg, "%5.0f")) + ")")
	gen str12 f_ = strtrim(string(cond(abs(food_pct_poor) < 0.005, 0, food_pct_poor), "%6.2f"))
	gen str12 fs_ = "(" + strtrim(string(se_food_pct_poor, "%6.2f")) + ")"
	gen str12 h_ = strtrim(string(households, "%9.0fc"))
	keep ord lab h_ m_ ms_ d_ ds_ k_ ks_ f_ fs_
	tempfile a_`m'
	save `a_`m''
}
use `a_conv', clear
append using `a_joint'
expand 2, gen(dup)
replace ord = ord + 0.25 if dup
sort ord
gen str8 kind = cond(dup, "se", "row")
gen str12 c1 = cond(dup, "", h_)
local j 1
foreach v in m d k f {
	local ++j
	gen str12 c`j' = cond(dup, `v's_, `v'_)
}
replace lab = "" if dup
keep ord lab kind c1-c5
panelrow 1 "A. Conventional model"
panelrow 21 "B. Joint model"
drop ord
tabopen 8
jt "8" "Simulated Levers of the Affordable Inputs Program, 2024" "" "|Households|Maize gain (t)|Change (t)|MK per kg|Food, poorest (%)" "2024 maize growers in the sample; AIP farmer price MK 15,000 per 50 kg bag; package: mean AIP kilograms of recipients. Maize gain: against no AIP; Change: against the AIP as implemented; Food: mean change in food spending, poorest wealth tertile. Registered: the AIP's number of recipients chosen among the households registered on the electronic AIP system; all households: every registered household served. The price multiplier applies to fertilizer; bags bought respond with the own-price elasticity of commercial fertilizer, up to the package. Models and bootstrap standard errors in parentheses as in Tables 6 and 7. `MKSE' (–): not bounded, because the maize gain is near zero in some draws. Stars: change against the AIP as implemented, two-sided bootstrap test.`STARS'"
tabclose

*------------------------------------------------------------------------------
* Table 4. transient inefficiency and crop vigor from space
*------------------------------------------------------------------------------
import delimited using "$EXT/measurement.csv", clear varnames(1)
foreach y in u_t lnyield {
	local K = cond("`y'" == "u_t", "U", "Y")
	quietly summarize value if outcome == "`y'" & stat == "share of variance between EA-seasons"
	nmac MBet`K' `=100 * r(mean)' "%3.0f"
	nmac MWit`K' `=100 - 100 * r(mean)' "%3.0f"
	quietly summarize value if outcome == "`y'" & stat == "R2 of satellite and weather beyond round effects"
	nmac MRsq`K' `=100 * r(mean)' "%3.0f"
	quietly summarize value if outcome == "`y'" & stat == "share of total variance confirmed from space"
	nmac MConf`K' `=100 * r(mean)' "%3.0f"
}
gen str70 lab = ""
gen int ord = .
local i 0
foreach x in "share of variance between EA-seasons|Share of variance between EA-seasons" "share of variance within EA-seasons|Share of variance within EA-seasons" ///
	"R2 of satellite and weather beyond round effects|EA-seasons: R-squared of vigor and weather beyond round effects" ///
	"coef ea_evi_anom|EVI anomaly (EA-season mean)" "coef ea_spi12|12-month SPI" "coef ea_hot10|Days above 30 C (tens)" ///
	"2024: coef Sentinel-2 anomaly|2024: Sentinel-2 NDVI anomaly" "corr with EVI maximum (EA-seasons)|Correlation with EVI maximum (EA-seasons)" ///
	"share of total variance confirmed from space|Share of total variance confirmed from space" "EA-seasons|EA-seasons (N)" {
	local ++i
	gettoken a b : x, parse("|")
	local b = subinstr("`b'", "|", "", 1)
	replace lab = "`b'" if stat == "`a'"
	replace ord = `i' if stat == "`a'"
}
gen str40 sstat = subinstr(subinstr(stat, "coef ", "se ", 1), "2024: coef", "2024: se", 1)
tempfile mm
save `mm'
keep outcome stat value
rename (stat value) (sstat sev)
tempfile ses
save `ses'
use `mm', clear
merge m:1 outcome sstat using `ses', keep(master match) nogen
replace sev = . if sstat == stat
keep if !missing(ord)
gen str14 v = strtrim(string(value, "%6.3f"))
replace v = v + cond(abs(value / sev) >= 2.576, "***", cond(abs(value / sev) >= 1.960, "**", cond(abs(value / sev) >= 1.645, "*", ""))) if !missing(sev)
replace v = strtrim(string(value, "%9.0fc")) if lab == "EA-seasons (N)"
gen str14 s = cond(missing(sev), "", "(" + strtrim(string(sev, "%6.3f")) + ")")
gen byte cc = cond(outcome == "u_t", 1, 2)
keep ord lab cc v s
reshape wide v s, i(ord lab) j(cc)
expand 2, gen(dup)
sort ord dup
drop if dup & s1 == "" & s2 == ""
gen str8 kind = cond(dup, "se", "row")
gen str14 c1 = cond(dup, s1, v1)
gen str14 c2 = cond(dup, s2, v2)
replace lab = "" if dup
keep lab kind c1 c2
tabopen 4
jt "4" "Transient Inefficiency, Reported Yields and Crop Vigor from Space" "" "|Transient inefficiency|Log yield (reported)" "Maize growers 2010-2024. EA-seasons: enumeration area by district by round cells. EA-season means regressed on the mean MODIS EVI anomaly (5 km buffers, cropland), the 12-month SPI and hot days with round effects (standard errors clustered by enumeration area); 2024: Sentinel-2 anomaly alone. Share confirmed from space: between-EA-season share times the gain in R-squared of vigor and weather over round effects alone (R-squared beyond round effects: the same gain as a share of the variance the round effects leave).`STARS'"
tabclose

file close nm
putdocx clear
di as txt "paper tables and numbers written to $PAP"
