*==============================================================================
* 06_panel_frontier.do -- persistent and transient efficiency
* Four-component stochastic frontier for maize on all five IHPS rounds
* (Colombi et al. 2014; Kumbhakar, Lien and Hardaker 2014, KLH), estimated
* with the KLH multi-step estimator:
*   ln y_it = b0 + f(x_it) + d_t + mu_i - eta_i + v_it - u_it
*   step 1  random-effects regression of the translog frontier (seven
*           inputs, centred logs, round effects): household effect a_i
*           (BLUP) and time-varying residual e_it
*   step 2  half-normal frontier on e_it: transient inefficiency u_it, whose
*           variance depends on the season's rainfall and heat shocks
*   step 3  half-normal frontier on a_i (one row per household): persistent
*           inefficiency eta_i, whose variance depends on household traits
*   efficiency: TE_p = exp(-E[eta|a]), TE_t = exp(-E[u|e]) (JLMS),
*               overall TE = TE_p x TE_t
* Household units follow the IHPS links: each round's household carries its
* predecessor's id; the continuing household (2013: original household;
* 2016-2024: split index 1 in data/raw/links/MWI_panel_ids.dta) keeps the
* unit, split-offs start a new one. MWI_panel_ids.dta holds these links; it
* was built from the tracking identifiers of the long-term panel releases
* (https://microdata.worldbank.org/index.php/catalog/2939, https://microdata.worldbank.org/index.php/catalog/3819).
* Inputs: $DER/all_waves_panel_sat.dta (05_merge_satellite)
* Output: $DER/panel_efficiency.dta; $EXT/panel_frontier_*.csv
*==============================================================================

global EXT "$ROOT/output/results"
capture mkdir "$EXT"

*------------------------------------------------------------------------------
* 1. household units across rounds
*------------------------------------------------------------------------------
use "$RESTRICTED/links/MWI_panel_ids.dta", clear
tempfile idx
local first 1
forvalues k = 3/5 {
	preserve
	keep if wave == `k'
	gen str12 hhkey = y`k'_hhid
	gen byte main = y`k'_index == 1
	gen int wave_y = cond(`k' == 3, 2016, cond(`k' == 4, 2019, 2024))
	keep hhkey wave_y main
	if !`first' append using `idx'
	save `idx', replace
	local first 0
	restore
}
use `idx', clear
rename wave_y wave
* first record of duplicated ids in file order (deterministic)
sort wave hhkey, stable
by wave hhkey: keep if _n == 1
save `idx', replace

use "$DER/all_waves_panel_sat.dta", clear
merge 1:1 wave hhkey using `idx', keep(master match) nogen
replace main = original == 1 if wave == 2013
replace main = 1 if wave == 2010
gen str12 prev = ""
replace prev = case_id if wave == 2013
replace prev = y2_hhid if wave == 2016
replace prev = y3_hhid if wave == 2019
replace prev = y4_hhid if wave == 2024
gen str24 unit = "2010-" + hhkey if wave == 2010
local waves 2010 2013 2016 2019 2024
forvalues j = 2/5 {
	local w : word `j' of `waves'
	local w0 : word `=`j'-1' of `waves'
	preserve
	keep if wave == `w0'
	keep hhkey unit
	rename (hhkey unit) (prev unit_prev)
	tempfile pu
	save `pu'
	restore
	merge m:1 prev using `pu', keep(master match) nogen
	* one continuing household per predecessor (first by id if several)
	gen byte cont = wave == `w' & main == 1 & unit_prev != ""
	bysort wave prev cont (hhkey): replace cont = 0 if cont & _n > 1
	replace unit = unit_prev if cont
	replace unit = "`w'-" + hhkey if wave == `w' & unit == ""
	drop unit_prev cont
}
egen long uid = group(unit)
label var uid "Household unit across rounds (continuing household keeps the unit)"

keep if grows_maize
bysort uid: gen int T = _N
label var T "Rounds in which the unit grew maize"
di as txt "maize-grower observations: " _N
tab T if wave == 2024
quietly duplicates report uid wave
assert r(unique_value) == r(N)

*------------------------------------------------------------------------------
* 2. step 1: random-effects translog frontier
*------------------------------------------------------------------------------
local inp seed org chit urea othf lab area
foreach x of local inp {
	quietly summarize ln_`x'
	gen double c_`x' = ln_`x' - r(mean)
}
local cd c_seed c_org c_chit c_urea c_othf c_lab c_area
local tl `cd'
local k : word count `cd'
forvalues i = 1/`k' {
	local xi : word `i' of `cd'
	gen double sq_`i' = 0.5 * `xi'^2
	local tl `tl' sq_`i'
	forvalues j = `=`i'+1'/`k' {
		local xj : word `j' of `cd'
		gen double ix_`i'_`j' = `xi' * `xj'
		local tl `tl' ix_`i'_`j'
	}
}
* site conditions shift the frontier, so that the household effect is not
* land quality: agro-ecological zone, soil type and quality, temperature
local site aez_warm_subhumid aez_cool_semiarid aez_cool_subhumid soil_fair soil_poor ///
	soil_mixed soil_clay temperature
* households without coordinates (51 new EAs in 2024) take the mean of their
* district in the round, else of the district, else the sample mean
sort wave hhkey
foreach v of local site {
	bysort wave district: egen double m1_ = mean(`v')
	bysort district: egen double m2_ = mean(`v')
	quietly summarize `v'
	replace `v' = cond(!missing(m1_), m1_, cond(!missing(m2_), m2_, r(mean))) if missing(`v')
	drop m1_ m2_
}
xtset uid wave
xtreg lny `tl' `site' i.wave, re vce(cluster uid)
estimates store step1
* saved for parametric draws of the output elasticities (14_structural_allrounds bootstrap)
estimates save "$DER/panel_frontier_step1.ster", replace
matrix b1 = e(b)
local sig_u = e(sigma_u)
local sig_e = e(sigma_e)
predict double a_i, u
predict double e_it, e
* household output elasticities of the translog at its own inputs (inputs
* in ln(x + 1), centred), for the structural simulation on all rounds
forvalues i = 1/`k' {
	local xi : word `i' of `cd'
	gen double el_`xi' = _b[`xi'] + _b[sq_`i'] * `xi'
	forvalues j = 1/`k' {
		if `j' == `i' continue
		local a = min(`i', `j')
		local b = max(`i', `j')
		local xj : word `j' of `cd'
		replace el_`xi' = el_`xi' + _b[ix_`a'_`b'] * `xj'
	}
	label var el_`xi' "Translog output elasticity of `xi' (panel frontier, step 1)"
}
* first-order elasticities at the sample mean and returns to scale
local rts 0
foreach x of local cd {
	local rts = `rts' + _b[`x']
}
di as txt "returns to scale at the mean: " %5.3f `rts'

*------------------------------------------------------------------------------
* 3. step 2: transient inefficiency (season shocks shift its variance)
*------------------------------------------------------------------------------
gen byte spi_dry12 = spi12 < -1 if !missing(spi12)
label var spi_dry12 "Drought (12-month SPI < -1)"
* season shocks of households without coordinates: mean of the district in
* the same round (the same season's weather), else the round mean
foreach v in spi_shock spi_dry12 hot30 {
	bysort wave district: egen double m1_ = mean(`v')
	bysort wave: egen double m2_ = mean(`v')
	replace `v' = cond(!missing(m1_), m1_, m2_) if missing(`v')
	drop m1_ m2_
}
gen double hot30_10 = hot30 / 10
capture noisily frontier e_it, distribution(hnormal) uhet(spi_shock spi_dry12 hot30_10)
local tr_het = _rc == 0 & e(converged) == 1
if !`tr_het' {
	di as error "transient model with shocks did not converge: homoskedastic model"
	frontier e_it, distribution(hnormal)
}
estimates store step2
predict double u_t, u
gen double te_t = exp(-u_t)
label var te_t "Transient technical efficiency (KLH step 2, JLMS)"

*------------------------------------------------------------------------------
* 4. step 3: persistent inefficiency (one row per household unit)
*------------------------------------------------------------------------------
preserve
foreach v in head_female educ_15_60 landowner wealth soil_poor {
	bysort uid: egen double m_`v' = mean(`v')
	quietly summarize m_`v'
	replace m_`v' = r(mean) if missing(m_`v')
}
gen double m_educ10 = m_educ_15_60 / 10
bysort uid: keep if _n == 1
* the household effect is informative only for units observed at least twice
keep if T >= 2
capture noisily frontier a_i, distribution(hnormal) uhet(m_head_female m_educ10 m_landowner m_wealth m_soil_poor)
local pe_het = _rc == 0 & e(converged) == 1
if !`pe_het' {
	di as error "persistent model with household traits did not converge: homoskedastic model"
	frontier a_i, distribution(hnormal)
}
estimates store step3
predict double u_p, u
gen double te_p = exp(-u_p)
label var te_p "Persistent technical efficiency (KLH step 3, JLMS)"
keep uid u_p te_p
tempfile pers
save `pers'
restore
merge m:1 uid using `pers', nogen
gen double te_o = te_p * te_t
label var te_o "Overall technical efficiency (persistent x transient)"

*------------------------------------------------------------------------------
* 5. targets: efficiency quintiles by round; who received subsidies
*------------------------------------------------------------------------------
gen byte recip = ncoup_total > 0 & ncoup_total < .
label var recip "Received FISP coupons (2010-2019) or AIP inputs (2024)"
* quintiles among households with a score (persistent and overall scores
* exist for units observed in at least two rounds)
foreach s in p o t {
	bysort wave: egen long n_`s' = count(te_`s')
	bysort wave (te_`s'): gen byte q_`s' = ceil(5 * _n / n_`s') if !missing(te_`s')
	drop n_`s'
}
label var q_p "Quintile of persistent efficiency within the round"
label var q_o "Quintile of overall efficiency within the round"
label var q_t "Quintile of transient efficiency within the round"

sort wave hhkey
save "$DER/panel_efficiency.dta", replace

*------------------------------------------------------------------------------
* 6. tables (csv): estimates, efficiency by round, targeting by quintile
*------------------------------------------------------------------------------
* (a) variance components and determinants
tempname fh
file open `fh' using "$EXT/panel_frontier_estimates.csv", write replace
file write `fh' "term,estimate,se" _n
estimates restore step1
foreach x of local cd {
	file write `fh' "frontier:`x'," %9.4f (_b[`x']) "," %9.4f (_se[`x']) _n
}
file write `fh' "frontier:returns_to_scale," %9.4f (`rts') "," _n
file write `fh' "step1:sigma_u," %9.4f (`sig_u') "," _n "step1:sigma_e," %9.4f (`sig_e') "," _n
file write `fh' "step1:N," (e(N)) "," _n "step1:units," (e(N_g)) "," _n
estimates restore step2
foreach v in spi_shock spi_dry12 hot30_10 _cons {
	capture file write `fh' "transient_lnsig2u:`v'," %9.4f (_b[lnsig2u:`v']) "," %9.4f (_se[lnsig2u:`v']) _n
}
capture file write `fh' "transient:sigma_v," %9.4f (e(sigma_v)) "," _n
estimates restore step3
foreach v in m_head_female m_educ10 m_landowner m_wealth m_soil_poor _cons {
	capture file write `fh' "persistent_lnsig2u:`v'," %9.4f (_b[lnsig2u:`v']) "," %9.4f (_se[lnsig2u:`v']) _n
}
capture file write `fh' "persistent:sigma_v," %9.4f (e(sigma_v)) "," _n
file write `fh' "persistent:units," (e(N)) "," _n
file write `fh' "model:transient_heteroskedastic,`tr_het'," _n "model:persistent_heteroskedastic,`pe_het'," _n
file close `fh'

* (b) mean efficiency by round
preserve
collapse (mean) te_p te_t te_o recip spi_shock spi_dry12 (count) n = te_o, by(wave)
export delimited using "$EXT/panel_frontier_te_by_round.csv", replace
restore

* (c) share of subsidy recipients and of coupons by efficiency quintile and round
preserve
gen double coup = cond(wave == 2024, recip, ncoup_total)
foreach s in p o {
	bysort wave: egen double tot_`s' = total(coup)
	bysort wave q_`s': egen double sh_`s' = total(coup)
	replace sh_`s' = sh_`s' / tot_`s'
	bysort wave q_`s': egen double rr_`s' = mean(recip)
}
keep wave q_p sh_p rr_p
bysort wave q_p: keep if _n == 1
rename (q_p sh_p rr_p) (quintile share_subsidy recipient_rate)
gen str10 basis = "persistent"
tempfile qp
save `qp'
restore
preserve
gen double coup = cond(wave == 2024, recip, ncoup_total)
bysort wave: egen double tot_o = total(coup)
bysort wave q_o: egen double sh_o = total(coup)
replace sh_o = sh_o / tot_o
bysort wave q_o: egen double rr_o = mean(recip)
keep wave q_o sh_o rr_o
bysort wave q_o: keep if _n == 1
rename (q_o sh_o rr_o) (quintile share_subsidy recipient_rate)
gen str10 basis = "overall"
append using `qp'
order basis wave quintile
sort basis wave quintile
export delimited using "$EXT/panel_frontier_targeting.csv", replace
restore

* (d) stability of the ranking: same unit in consecutive rounds
preserve
keep uid wave te_o te_t q_o
xtset uid wave, delta(1)
sort uid wave
by uid: gen double te_o_prev = te_o[_n-1]
by uid: gen double te_t_prev = te_t[_n-1]
by uid: gen byte q_o_prev = q_o[_n-1]
quietly spearman te_o te_o_prev
local rho_o = r(rho)
quietly spearman te_t te_t_prev
local rho_t = r(rho)
quietly count if q_o == q_o_prev & !missing(q_o_prev)
local stay = r(N)
quietly count if !missing(q_o_prev)
local stay = `stay' / r(N)
clear
set obs 1
gen double rank_corr_overall = `rho_o'
gen double rank_corr_transient = `rho_t'
gen double same_quintile_next_round = `stay'
export delimited using "$EXT/panel_frontier_stability.csv", replace
restore

* variance shares of the two inefficiency components
quietly summarize u_p
local vp = r(Var)
quietly summarize u_t
local vt = r(Var)
di as txt "share of inefficiency variance that is persistent: " %5.3f `vp' / (`vp' + `vt')
tabstat te_p te_t te_o, by(wave) statistics(mean sd) format(%5.3f)
