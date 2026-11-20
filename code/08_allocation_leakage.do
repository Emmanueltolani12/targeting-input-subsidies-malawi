*==============================================================================
* 08_allocation_leakage.do -- allocation arrangements and leakage
* How coupons were allocated in the village and how much leaked, 2010-2019,
* and whether targeting and leakage differ by allocation arrangement.
*   coupon modules (AG E 2010; E2 2013-2019): paid anyone to get the coupon,
*     side payments (bribes) at redemption (2013-2019), coupon sold, given
*     away, lost or stolen, not redeemed, waited a day or more at the depot
*     (2013-2019)
*   village arrangements reported by households (AG E4/E5 2013; E3/E4 2016,
*     2019): open-forum allocation, open-forum distribution, redistribution
*     after the forum, later supplementary allocation (fertiliser coupons);
*     who was involved and important: extension staff, VDC, village headman,
*     traditional authority, local politicians
*   EA arrangement = leave-one-out mean of the other households' reports
* Inputs: raw coupon modules; $DER/all_waves_panel_sat.dta;
*         $DER/panel_efficiency.dta (06_panel_frontier)
* Output: $DER/allocation_leakage.dta; $EXT/leakage_by_round.csv,
*         $EXT/arrangements_by_round.csv, $EXT/allocation_regressions.csv
*==============================================================================

global EXT "$ROOT/output/results"
local L "$RESTRICTED/ihps_long"
local S "$RESTRICTED/ihps"

capture program drop yn
program define yn
	* yn <new> <old>: 1 = yes, 0 = no (numeric 1/2 or string YES/NO)
	args new old
	capture confirm numeric variable `old'
	if !_rc gen byte `new' = `old' == 1 if inlist(`old', 1, 2)
	else gen byte `new' = upper(strtrim(`old')) == "YES" if inlist(upper(strtrim(`old')), "YES", "NO")
end

*------------------------------------------------------------------------------
* 1. coupon-level leakage -> household-round
*------------------------------------------------------------------------------
tempfile leak
* 2010: one row per member and coupon type (counts)
use "`S'/AG_MOD_E_10.dta", clear
gen str12 hhkey = case_id
keep if !missing(ag_e0d)
gen double n_coup = ag_e01
yn paid_get ag_e03
gen double amt_get = ag_e04 if paid_get == 1
yn sold ag_e18
gen double amt_sold = ag_e20 if sold == 1
yn gave ag_e22
yn lost ag_e24
gen byte not_red = ag_e06 < ag_e01 if !missing(ag_e06, ag_e01)
gen byte side_pay = .
gen double amt_side = .
gen byte wait_day = .
gen int wave = 2010
keep wave hhkey n_coup paid_get amt_get sold amt_sold gave lost not_red side_pay amt_side wait_day
save `leak'

* 2013-2019: one row per coupon
foreach w in 2013 2016 2019 {
	if `w' == 2013 {
		use "`S'/AG_MOD_E2_13.dta", clear
		gen str12 hhkey = y2_hhid
		yn red ag_e05_1
	}
	else {
		local yy = substr("`w'", 3, 2)
		use "`L'/ag_mod_e2_`yy'.dta", clear
		local idv = cond(`w' == 2016, "y3_hhid", "y4_hhid")
		gen str12 hhkey = `idv'
		yn red ag_e06
	}
	keep if !missing(ag_e01_1)
	gen double n_coup = 1
	yn paid_get ag_e03
	gen double amt_get = ag_e04 if paid_get == 1
	gen double amt_side = ag_e15_1
	gen byte side_pay = ag_e15_1 > 0 if !missing(ag_e15_1)
	yn sold ag_e18
	gen double amt_sold = ag_e20 if sold == 1
	yn gave ag_e22
	yn lost ag_e24
	gen byte not_red = red == 0 if !missing(red)
	* waiting time at the depot: a day or more (unit days/weeks, or >= 8 hours)
	capture confirm numeric variable ag_e08_2b
	if !_rc decode ag_e08_2b, gen(wu)
	else gen wu = ag_e08_2b
	replace wu = upper(wu)
	gen byte wait_day = (strpos(wu, "DAY") | strpos(wu, "WEEK")) & ag_e08_2a > 0 if !missing(ag_e08_2a) & wu != ""
	replace wait_day = 1 if strpos(wu, "HOUR") & ag_e08_2a >= 8 & !missing(ag_e08_2a)
	gen int wave = `w'
	keep wave hhkey n_coup paid_get amt_get sold amt_sold gave lost not_red side_pay amt_side wait_day
	append using `leak'
	save `leak', replace
}
use `leak', clear
collapse (sum) n_coup amt_get amt_sold amt_side (max) paid_get sold gave lost not_red side_pay wait_day, by(wave hhkey)
egen byte any_leak = rowmax(paid_get side_pay sold gave lost)
label var any_leak "Paid to get a coupon, side payment, sold, gave away or lost a coupon"
label var not_red "At least one coupon not (fully) redeemed"
label var wait_day "Waited a day or more at the depot"
save `leak', replace

*------------------------------------------------------------------------------
* 2. village allocation arrangements (household reports)
*------------------------------------------------------------------------------
tempfile arr
* 2013 methods: one row per coupon type, fertiliser coupons = code 1
use "`S'/AG_MOD_E4_13.dta", clear
keep if ag_e29_00 == 1
gen str12 hhkey = y2_hhid
foreach m in a b c d {
	yn meth_`m' ag_e29`m'
}
keep hhkey meth_*
gen int wave = 2013
save `arr'
foreach w in 2016 2019 {
	local yy = substr("`w'", 3, 2)
	use "`L'/ag_mod_e3_`yy'.dta", clear
	local idv = cond(`w' == 2016, "y3_hhid", "y4_hhid")
		gen str12 hhkey = `idv'
	foreach m in a b c d {
		yn meth_`m' ag_e29`m'
	}
	keep hhkey meth_*
	gen int wave = `w'
	append using `arr'
	save `arr', replace
}
* decision makers: 2013 person codes 1-6, 2016/2019 roster ids 0-5 (same order)
tempfile who
foreach w in 2013 2016 2019 {
	if `w' == 2013 {
		use "`S'/AG_MOD_E5_13.dta", clear
		gen str12 hhkey = y2_hhid
		gen int pc = ag_e30_00
	}
	else {
		local yy = substr("`w'", 3, 2)
		use "`L'/ag_mod_e4_`yy'.dta", clear
		local idv = cond(`w' == 2016, "y3_hhid", "y4_hhid")
		gen str12 hhkey = `idv'
		local pcv = cond(`w' == 2016, "ag_30_00", "ag_e30")
		gen int pc = `pcv' + 1
	}
	keep if inrange(pc, 1, 5)
	egen byte imp = anymatch(ag_e30a ag_e30b ag_e30c ag_e30d), values(1)
	egen byte inv = anymatch(ag_e30a ag_e30b ag_e30c ag_e30d), values(1 2)
	keep hhkey pc imp inv
	reshape wide imp inv, i(hhkey) j(pc)
	gen int wave = `w'
	if `w' != 2013 append using `who'
	save `who', replace
}
use `arr', clear
merge 1:1 wave hhkey using `who', nogen
rename (meth_a meth_b meth_c meth_d) (m_forum_alloc m_forum_dist m_redistrib m_supplement)
rename (imp1 imp2 imp3 imp4 imp5) (imp_ext imp_vdc imp_head imp_ta imp_pol)
rename (inv1 inv2 inv3 inv4 inv5) (inv_ext inv_vdc inv_head inv_ta inv_pol)
save `arr', replace

*------------------------------------------------------------------------------
* 3. household-round file with outcomes, arrangements and household traits
*------------------------------------------------------------------------------
use "$DER/all_waves_panel_sat.dta", clear
keep if inlist(wave, 2010, 2013, 2016, 2019)
keep wave hhkey ea_id district wgt grows_maize ncoup_total wealth_t head_female head_age ///
	educ_15_60 area_cult hhsize landowner
merge 1:1 wave hhkey using `leak', keep(master match) gen(_ml)
merge 1:1 wave hhkey using `arr', keep(master match) nogen
merge 1:1 wave hhkey using "$DER/panel_efficiency.dta", keep(master match) keepusing(te_p q_p te_o q_o T) nogen
gen byte recip = ncoup_total > 0 & ncoup_total < .
* skip patterns: sale, gift and loss are asked only about coupons not (fully)
* redeemed, side payments and waiting only about redeemed coupons, so a
* skipped question means "no" for a recipient household; side payments and
* waiting time were not asked in 2010
foreach v in paid_get side_pay sold gave lost not_red wait_day {
	replace `v' = 0 if recip & missing(`v')
	replace `v' = . if !recip
}
foreach v in side_pay wait_day {
	replace `v' = . if wave == 2010
}
drop any_leak
egen byte any_leak = rowmax(paid_get side_pay sold gave lost) if recip
label var any_leak "Paid to get a coupon, side payment, sold, gave away or lost a coupon"
* leave-one-out EA means of the arrangement reports (EA x district cells:
* households that moved are grouped with their current district)
sort wave hhkey
foreach v of varlist m_* imp_* inv_* {
	bysort wave district ea_id: egen double t_`v' = total(`v')
	bysort wave district ea_id: egen double n_`v' = count(`v')
	gen double ea_`v' = (t_`v' - cond(missing(`v'), 0, `v')) / (n_`v' - !missing(`v'))
	drop t_`v' n_`v'
}
gen byte poor = wealth_t == 1 if !missing(wealth_t)
gen byte eff_top = inlist(q_p, 4, 5) if !missing(q_p)
gen double ln_land = ln(area_cult + 0.01)
label var poor "Poorest wealth tertile"
label var eff_top "Two most persistently efficient quintiles"
save "$DER/allocation_leakage.dta", replace

*------------------------------------------------------------------------------
* 4. tables
*------------------------------------------------------------------------------
* (a) leakage among recipient households, by round
preserve
keep if recip
collapse (mean) paid_get side_pay sold gave lost not_red wait_day any_leak ///
	(count) n = recip, by(wave)
export delimited using "$EXT/leakage_by_round.csv", replace
restore
* (b) arrangements reported, by round (share of households answering)
preserve
keep if inlist(wave, 2013, 2016, 2019)
collapse (mean) m_forum_alloc m_forum_dist m_redistrib m_supplement imp_ext imp_vdc ///
	imp_head imp_ta imp_pol inv_pol (count) n = m_forum_alloc, by(wave)
export delimited using "$EXT/arrangements_by_round.csv", replace
restore

* (c) targeting and leakage by arrangement: linear probability models with
*     district-by-round effects, standard errors clustered by EA
keep if inlist(wave, 2013, 2016, 2019) & grows_maize
egen long dr = group(district wave)
local A ea_m_forum_alloc ea_imp_head ea_inv_pol
foreach a of local A {
	quietly summarize `a'
	gen double z_`a' = (`a' - r(mean)) / r(sd)
}
local Az z_ea_m_forum_alloc z_ea_imp_head z_ea_inv_pol
foreach a of local Az {
	gen double poorX`a' = poor * `a'
	gen double effX`a' = eff_top * `a'
}
local X poor eff_top head_female ln_land educ_15_60 hhsize
tempname fh
file open `fh' using "$EXT/allocation_regressions.csv", write replace
file write `fh' "model,term,estimate,se,N" _n
* (1) receipt: who gets coupons, and does it change with the arrangement
areg recip `X' `Az' poorX* effX*, absorb(dr) vce(cluster ea_id)
foreach v in poor eff_top head_female ln_land `Az' poorXz_ea_m_forum_alloc poorXz_ea_imp_head ///
	poorXz_ea_inv_pol effXz_ea_m_forum_alloc effXz_ea_imp_head effXz_ea_inv_pol {
	file write `fh' "receipt,`v'," %9.4f (_b[`v']) "," %9.4f (_se[`v']) "," (e(N)) _n
}
* (2)-(4) leakage among recipients
foreach y in any_leak not_red wait_day {
	areg `y' `X' `Az', absorb(dr) vce(cluster ea_id)
	foreach v in poor eff_top `Az' {
		file write `fh' "`y',`v'," %9.4f (_b[`v']) "," %9.4f (_se[`v']) "," (e(N)) _n
	}
	quietly summarize `y' if e(sample)
	file write `fh' "`y',mean_outcome," %9.4f (r(mean)) ",," (e(N)) _n
}
file close `fh'
type "$EXT/allocation_regressions.csv"
