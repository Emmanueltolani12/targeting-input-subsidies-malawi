*==============================================================================
* 14_structural_allrounds.do -- structural simulation on all rounds, and
* the AIP's own levers in 2024
* Two models (global SIM_MODEL):
*   conventional  the structural model in the form of Asfaw et al. (2017): food expenditure elasticity of
*          the all-round first-stage QUAIDS; quota elasticities of the
*          all-round second stage significant at 10%, applied to the quota
*          valued at the redemption price; household output elasticities of
*          the panel translog (06_panel_frontier). Specifications exog and iv (quota
*          control functions); AIP levers with iv.
*   joint  demand responses and technology estimated consistently: quota
*          elasticities of the instrumented
*          second stage evaluated with the quota valued at market prices (all
*          estimates, no pre-test), converted into displaced commercial
*          kilograms at the elasticities' evaluation point (bounded by the
*          household's purchases without the programme, which add back the
*          purchases its own quotas displaced; SIM_CONV elastic), and
*          household output elasticities of a correlated random-effects panel
*          translog (Mundlak means of the inputs within the household unit),
*          which removes persistent farmer heterogeneity correlated with input
*          use. A control-function translog with the programme instruments
*          (Amsler, Prokhorov and Schmidt 2016) is estimated as a test; its first
*          stages are weak, so it is not used in the simulation. Called by 15_joint_structural.
* (A) allocation rules of 09_causal_forest_rules in every round 2010-2024, standard package
* (B) AIP 2024: farmer price per bag (x0.5, x1, x1.5, x2; fertiliser bags
*     bought respond with the own-price elasticity of commercial fertiliser,
*     capped at the package), number of beneficiaries (x1, x1.5, x2),
*     registration rules (actual AIP recipients; all e-AIP registered
*     households; poorest first; highest predicted returns; random), and a
*     budget-neutral price rise.
* Fiscal costs in kwacha of the 2023/24 season (World Bank annual CPI of each
* season's planting year).
* AIP farmer price: data/raw/programme/programme_prices.csv (season 2023/24),
* else global AIP_PRICE (MK per 50 kg bag).
* Bootstrap (global SIM_BOOT draws, default 500; 0 = point estimates only).
* Each draw resamples enumeration areas with replacement (all rounds of an EA
* together) and draws the demand elasticities from their joint asymptotic
* normal distribution (delta-method covariance, 13_demand_system) and the food
* expenditure elasticity; the household output elasticities come from
*   paper: a draw of the panel translog coefficients from their cluster-robust
*          covariance (06_panel_frontier);
*   joint: the correlated random-effects frontier re-estimated on the
*          resampled data.
* The rule scores of 09_causal_forest_rules (and in the conventional model the 10% selection of the
* quota elasticities) are held at their full-sample values.
* Inputs: $DER/panel_efficiency.dta, stage1_all.dta, stage2_quota_all.dta,
*         stage2_all_elast_cov_*.mmat, panel_frontier_step1.ster,
*         demand_iv_instruments.dta (joint), rule_assignment.csv;
*         ihps_long/ag_mod_e1_24.dta (e-AIP); data/raw/prices (CPI, World Bank WDI via
*         DBnomics, https://db.nomics.world/WB/WDI/A-FP.CPI.TOTL-MWI)
* Output: $EXT/structural_allrounds[_joint].csv, aip_levers[_joint].csv,
*         $EXT/cf_frontier.csv (joint); $DER/sim13_draws[_joint].dta
*==============================================================================

global EXT "$ROOT/output/results"
if "$SIM_BOOT" == "" global SIM_BOOT 500
if "$SIM_MODEL" == "" global SIM_MODEL "conventional"
local joint = "$SIM_MODEL" == "joint"
local sfx = cond(`joint', "_joint", "")
if `joint' {
	global SIM_VALUE "market"
	global SIM_SPECS "iv"
	* quota elasticities converted into displaced commercial kilograms at
	* their evaluation point (sim_allrounds_programs.do, SIM_CONV elastic)
	global SIM_CONV "elastic"
}
else {
	global SIM_VALUE "redemption"
	global SIM_SPECS "exog iv"
	global SIM_CONV "value"
}
global SIM_AIP_SPEC "iv"
local s1_ $SIM_SPECS
local s2_ $SIM_AIP_SPEC
local allspecs : list s1_ | s2_
di as txt "model: $SIM_MODEL (conversion $SIM_CONV, quota valued at $SIM_VALUE prices), specifications: `allspecs'"
if "$SIM_CONV" == "elastic" {
	* evaluation point of the elasticities: means of the demand sample (13_demand_system)
	use "$DER/demand_iv_sample.dta", clear
	foreach g in mseed chitowe urea othfert oseed {
		quietly summarize com_kg`g'
		global XC_`g' = r(mean)
	}
	foreach k in mseed chitowe urea oseed {
		quietly summarize q_`k'
		global QS_`k' = r(mean)
	}
	di as txt "mean commercial kg: seed $XC_mseed, basal $XC_chitowe, urea $XC_urea, other fertiliser $XC_othfert, other seed $XC_oseed"
	di as txt "mean quota kg: seed $QS_mseed, basal $QS_chitowe, urea $QS_urea, other seed $QS_oseed"
}
* tie-breaking of sorts as in a fresh run of the master's settings
set sortseed 20171105
do "$CODE/ado/qd_lib.do"
do "$CODE/ado/sim_helpers.do"
do "$CODE/ado/sim_allrounds_programs.do"

*------------------------------------------------------------------------------
* AIP farmer price per kg of fertiliser (2023/24)
*------------------------------------------------------------------------------
local aipbag = .
capture confirm file "$ROOT/data/raw/programme/programme_prices.csv"
if !_rc {
	import delimited using "$ROOT/data/raw/programme/programme_prices.csv", clear varnames(1) stringcols(_all)
	destring farmer_price_mwk, replace force
	keep if programme == "AIP" & season == "2023/24" & !missing(farmer_price_mwk)
	keep if strpos(lower(input), "fert") | strpos(lower(input), "npk") | strpos(lower(input), "urea")
	quietly summarize farmer_price_mwk
	if r(N) > 0 local aipbag = r(mean)
}
if missing(`aipbag') & "$AIP_PRICE" != "" local aipbag = $AIP_PRICE
if missing(`aipbag') {
	di as error "AIP farmer price for 2023/24 not found: set global AIP_PRICE (MK per 50 kg bag)"
	exit 459
}
local aipkg = `aipbag' / 50
di as txt "AIP farmer price: MK " %9.0fc `aipbag' " per 50 kg bag (MK " %6.1f `aipkg' " per kg)"

*------------------------------------------------------------------------------
* CPI deflator to kwacha of the 2023/24 season (World Bank annual CPI of each
* season's planting year; the IMF monthly series starts in 2010)
import delimited using "$ROOT/data/raw/prices/mwi_cpi_annual_wdi.csv", clear varnames(nonames) rowrange(2) stringcols(_all)
rename (v1 v2) (year cpi)
destring year cpi, replace force
keep if inlist(year, 2009, 2012, 2015, 2018, 2023)
gen int wave = year + 1
quietly summarize cpi if wave == 2024
gen double cdefl = r(mean) / cpi
list wave cpi cdefl, noobs clean
keep wave cdefl
tempfile cdefl
save `cdefl'

*------------------------------------------------------------------------------
* elasticities: point estimates and covariance files
* layout of the elasticity vector of qd_elast: eta (5), e_ij (25, row-wise),
* z_ik (20, row-wise); goods and quotas in estimation order
*------------------------------------------------------------------------------
use "$DER/stage1_all.dta", clear
keep if point == "total" & group == "Food & beverage"
local eta0 = eta[1]
local seeta = se_eta[1]
global ETA_FOOD = `eta0'
local gn mseed chitowe urea othfert oseed
local qn mseed urea chitowe oseed
global TL_X c_seed c_org c_chit c_urea c_othf c_lab c_area
use "$DER/stage2_quota_all.dta", clear
foreach spec of local allspecs {
	quietly count if spec == "`spec'"
	if r(N) == 0 {
		di as error "specification `spec' not in stage2_quota_all.dta: run 13_demand_system first"
		exit 459
	}
	forvalues i = 1/`=_N' {
		if spec[`i'] != "`spec'" | inlist(quota[`i'], "eta", "own_price") continue
		* pre-test of the conventional model (10%); the joint model uses all estimates
		global S`spec'_`=good[`i']'_`=quota[`i']' = cond(`joint', 1, abs(z[`i'] / se[`i']) >= 1.645)
		global R`spec'_`=good[`i']'_`=quota[`i']' = z[`i']
	}
	local v = cond(`joint', "_mkt", "")
	capture confirm file "$DER/stage2_all_elast_cov_`spec'`v'.mmat"
	if _rc {
		di as error "stage2_all_elast_cov_`spec'`v'.mmat not found: run 13_demand_system first"
		exit 601
	}
	mata: G_`spec' = qd_read_matrix(st_global("DER") + "/stage2_all_elast_cov_`spec'`v'.mmat")
	mata: g0_`spec' = G_`spec'[1, .]
	mata: C_`spec' = G_`spec'[2::rows(G_`spec'), .]
	mata: st_matrix("g0_`spec'", g0_`spec')
	forvalues ii = 1/5 {
		local g : word `ii' of `gn'
		forvalues kk = 1/4 {
			local q : word `kk' of `qn'
			local c = 30 + (`ii' - 1) * 4 + `kk'
			* the redemption-price file reproduces stage2_quota_all.dta
			if !`joint' & reldif(el(g0_`spec', 1, `c'), ${R`spec'_`g'_`q'}) > 1e-6 {
				di as error "elasticity file does not match stage2_quota_all (`spec', `g', `q')"
				exit 9
			}
			global Z`spec'_`g'_`q' = ${S`spec'_`g'_`q'} * el(g0_`spec', 1, `c')
		}
	}
}
global EPS_FERT = (el(g0_$SIM_AIP_SPEC, 1, 12) + el(g0_$SIM_AIP_SPEC, 1, 18)) / 2
local eps0 = $EPS_FERT
di as txt "own-price elasticity of commercial fertiliser ($SIM_AIP_SPEC, mean of chitowe and urea): " %6.3f $EPS_FERT

*------------------------------------------------------------------------------
* data: maize growers 2010-2024
*------------------------------------------------------------------------------
import delimited using "$DER/rule_assignment.csv", clear varnames(1) stringcols(2 3)
keep wave hhkey cate eff_pred r_tree tau_dr
tempfile ra
save `ra'
use "$RESTRICTED/ihps_long/ag_mod_e1_24.dta", clear
gen str12 hhkey = y5_hhid
gen byte eaip = ag_e01_1 == 1
gen int wave = 2024
keep wave hhkey eaip
tempfile ea
save `ea'

use "$DER/panel_efficiency.dta", clear
sort wave hhkey
merge 1:1 wave hhkey using `ra', keep(master match) nogen
merge 1:1 wave hhkey using `ea', keep(master match) nogen
merge m:1 wave using `cdefl', keep(master match) nogen
if `joint' {
	merge 1:1 wave hhkey using "$DER/demand_iv_instruments.dta", keep(master match) ///
		keepusing(iv_mseed iv_urea iv_chitowe iv_oseed off_cov dl_d) nogen
}
sort wave hhkey
replace eaip = 0 if missing(eaip)
foreach v in cate eff_pred {
	bysort wave: egen double m_`v' = mean(`v')
	replace `v' = m_`v' if missing(`v')
	drop m_`v'
}
replace r_tree = 0 if missing(r_tree)
foreach k in mseed chitowe urea oseed {
	replace q_`k' = 0 if missing(q_`k')
}
* 2024 redemption prices: AIP fertiliser price; seed at the same subsidy rate
replace pv_chitowe = `aipkg' if wave == 2024
replace pv_urea    = `aipkg' if wave == 2024
quietly summarize p_chitowe if wave == 2024
local rate24 = `aipkg' / r(mean)
replace pv_mseed = p_mseed * `rate24' if wave == 2024
replace pv_oseed = p_oseed * `rate24' if wave == 2024
sort wave hhkey
tempfile base
save `base'

*------------------------------------------------------------------------------
* control-function panel translog (joint model)
*------------------------------------------------------------------------------
capture program drop cf_frontier
program define cf_frontier, rclass
	* cf_frontier <unit id>: first stages of the variable inputs on the
	* programme instruments, residuals in the random-effects translog
	* (step 1 of the panel frontier); replaces el_c_* with its elasticities
	args unit
	local IV iv_mseed iv_urea iv_chitowe iv_oseed off_cov dl_d
	local site aez_warm_subhumid aez_cool_semiarid aez_cool_subhumid soil_fair soil_poor ///
		soil_mixed soil_clay temperature
	local tl
	local k : word count $TL_X
	forvalues i = 1/`k' {
		local tl `tl' `: word `i' of $TL_X' sq_`i'
		forvalues j = `=`i'+1'/`k' {
			local tl `tl' ix_`i'_`j'
		}
	}
	capture drop cfr_*
	local fmin = .
	foreach x in c_seed c_chit c_urea c_othf {
		quietly regress `x' `IV' c_org c_lab c_area `site' i.wave, vce(cluster ea_id)
		quietly test `IV'
		local fmin = min(`fmin', r(F))
		return scalar F_`x' = r(F)
		quietly predict double cfr_`x', resid
	}
	quietly xtset `unit' wave
	quietly xtreg lny `tl' `site' i.wave cfr_*, re vce(cluster `unit')
	quietly test cfr_c_seed cfr_c_chit cfr_c_urea cfr_c_othf
	return scalar p_exog = r(p)
	return scalar chi2_exog = r(chi2)
	return scalar F_min = `fmin'
	return scalar N = e(N)
	foreach x in c_seed c_chit c_urea c_othf {
		return scalar rho_`x' = _b[cfr_`x']
		return scalar se_rho_`x' = _se[cfr_`x']
	}
	matrix bcf_ = e(b)
	tl_elast bcf_ 1 ""
end

capture program drop cre_frontier
program define cre_frontier, rclass
	* cre_frontier <unit id>: correlated random-effects translog (Mundlak
	* means of the seven inputs within the household unit), step 1 of the panel
	* frontier; replaces el_c_* with its elasticities
	args unit
	local site aez_warm_subhumid aez_cool_semiarid aez_cool_subhumid soil_fair soil_poor ///
		soil_mixed soil_clay temperature
	local tl
	local mn
	local k : word count $TL_X
	capture drop mn_*
	forvalues i = 1/`k' {
		local xi : word `i' of $TL_X
		local tl `tl' `xi' sq_`i'
		forvalues j = `=`i'+1'/`k' {
			local tl `tl' ix_`i'_`j'
		}
		quietly bysort `unit': egen double mn_`xi' = mean(`xi')
		local mn `mn' mn_`xi'
	}
	quietly xtset `unit' wave
	quietly xtreg lny `tl' `site' i.wave `mn', re vce(cluster `unit')
	quietly test `mn'
	return scalar chi2_m = r(chi2)
	return scalar p_m = r(p)
	return scalar N = e(N)
	matrix bcre_ = e(b)
	tl_elast bcre_ 1 ""
end
*------------------------------------------------------------------------------
* point estimates (draw 0) and bootstrap draws
*------------------------------------------------------------------------------
tempname pf
postfile `pf' int draw str1 part str12 rule str6 spec str60 lever ///
	double(households maize_t kg_per_hh food_pct food_pct_poor cost_mk mk_per_kg) ///
	using "$DER/sim13_draws`sfx'.dta", replace
use `base', clear
if `joint' {
	* frontier with and without control functions: elasticities at the mean
	foreach x of global TL_X {
		gen double ex_`x' = el_`x'
	}
	tempname cfp
	postfile `cfp' str40 term double(estimate se) using "$DER/cf_frontier.dta", replace
	* (a) control functions with the programme instruments: a test of input
	* exogeneity and of instrument strength
	cf_frontier uid
	foreach x in c_seed c_chit c_urea c_othf {
		post `cfp' ("CF first stage F: `x'") (r(F_`x')) (.)
		post `cfp' ("CF control function: `x'") (r(rho_`x')) (r(se_rho_`x'))
	}
	post `cfp' ("CF exogeneity test chi2") (r(chi2_exog)) (.)
	post `cfp' ("CF exogeneity test p") (r(p_exog)) (.)
	post `cfp' ("CF N") (r(N)) (.)
	foreach x in c_seed c_chit c_urea c_othf c_lab c_area {
		quietly summarize el_`x'
		post `cfp' ("CF mean elasticity: `x'") (r(mean)) (.)
	}
	* (b) correlated random effects: the technology of the joint model
	cre_frontier uid
	post `cfp' ("CRE Mundlak test chi2") (r(chi2_m)) (.)
	post `cfp' ("CRE Mundlak test p") (r(p_m)) (.)
	post `cfp' ("CRE N") (r(N)) (.)
	foreach x in c_seed c_chit c_urea c_othf c_lab c_area {
		quietly summarize el_`x'
		local m1 = r(mean)
		quietly summarize ex_`x'
		post `cfp' ("CRE mean elasticity: `x'") (`m1') (.)
		post `cfp' ("RE mean elasticity: `x'") (r(mean)) (.)
	}
	postclose `cfp'
	drop ex_*
	preserve
	use "$DER/cf_frontier.dta", clear
	export delimited using "$EXT/cf_frontier.csv", replace
	list, noobs clean
	restore
}
set seed 20171105
sim13_build
sim13_run `pf' 0
local n_rec0 = $N_REC
local n_eaip0 = $N_EAIP

if $SIM_BOOT > 0 {
	if !`joint' {
		estimates use "$DER/panel_frontier_step1.ster"
		matrix bF = e(b)
		matrix VF = e(V)
		* the household elasticities are reproduced from the saved coefficients
		use `base', clear
		foreach x of global TL_X {
			gen double chk_`x' = el_`x'
		}
		tl_elast bF 1 ""
		foreach x of global TL_X {
			gen double dd_ = reldif(el_`x', chk_`x')
			quietly summarize dd_
			if r(max) > 1e-6 | r(N) == 0 {
				di as error "translog elasticities of `x' not reproduced from panel_frontier_step1.ster (max reldif " r(max) ")"
				exit 9
			}
			drop dd_
		}
	}
	di as txt "bootstrap: $SIM_BOOT draws (EA resampling + parameter draws)  $S_TIME"
	set seed 20261120
	forvalues b = 1/$SIM_BOOT {
		use `base', clear
		bsample, cluster(ea_id) idcluster(eab_)
		global ETA_FOOD = `eta0' + `seeta' * rnormal()
		foreach spec of local allspecs {
			mata: st_matrix("gd_", qd_mvn_draw(g0_`spec', C_`spec'))
			forvalues ii = 1/5 {
				local g : word `ii' of `gn'
				forvalues kk = 1/4 {
					local q : word `kk' of `qn'
					global Z`spec'_`g'_`q' = ${S`spec'_`g'_`q'} * el(gd_, 1, 30 + (`ii' - 1) * 4 + `kk')
				}
			}
			if "`spec'" == "$SIM_AIP_SPEC" global EPS_FERT = (el(gd_, 1, 12) + el(gd_, 1, 18)) / 2
		}
		if `joint' {
			egen long uidb_ = group(uid eab_)
			quietly cre_frontier uidb_
		}
		else {
			sim_draw_b bF VF bd_
			tl_elast bd_ 1 ""
		}
		quietly sim13_build
		sim13_run `pf' `b'
		if mod(`b', 50) == 0 di as txt "  draw `b'  $S_TIME"
	}
}
postclose `pf'

*------------------------------------------------------------------------------
* point estimates with bootstrap standard errors
*------------------------------------------------------------------------------
use "$DER/sim13_draws`sfx'.dta", clear
gen long obs_ = _n
bysort draw (obs_): gen int seq = _n
drop obs_
egen byte refgrp = group(part spec)
gen byte isref = (part == "A" & rule == "actual") | (part == "B" & rule == "base")
gen byte bestgrp = cond(part == "A", refgrp, cond(inlist(rule, "base", "reg_poor", "reg_cate", "reg_effpr", "reg_random"), refgrp, 0))
sim_summarise
local se_cols se_maize_t se_kg_per_hh se_food_pct se_food_pct_poor se_cost_mk se_mk_per_kg ///
	maize_lo maize_hi mk_lo mk_hi d_pct se_d_pct d_lo d_hi p_d p_best reps
preserve
keep if part == "A"
rename (kg_per_hh se_kg_per_hh) (kg_per_package se_kg_per_package)
local se_a = subinstr("`se_cols'", "se_kg_per_hh", "se_kg_per_package", 1)
keep rule spec households maize_t kg_per_package food_pct food_pct_poor cost_mk mk_per_kg `se_a'
order rule spec households maize_t kg_per_package food_pct food_pct_poor cost_mk mk_per_kg `se_a'
export delimited using "$EXT/structural_allrounds`sfx'.csv", replace
list rule spec maize_t se_maize_t d_pct d_lo d_hi p_d p_best mk_per_kg se_mk_per_kg, noobs clean
restore
keep if part == "B"
gen double aip_price_bag = `aipbag'
gen double eps_fert = `eps0'
gen double eaip_registered = `n_eaip0'
gen double aip_recipients = `n_rec0'
keep lever households maize_t kg_per_hh food_pct food_pct_poor cost_mk mk_per_kg aip_price_bag eps_fert ///
	eaip_registered aip_recipients `se_cols'
order lever households maize_t kg_per_hh food_pct food_pct_poor cost_mk mk_per_kg aip_price_bag eps_fert ///
	eaip_registered aip_recipients `se_cols'
export delimited using "$EXT/aip_levers`sfx'.csv", replace
list lever maize_t se_maize_t d_pct d_lo d_hi p_d mk_per_kg mk_lo mk_hi, noobs clean
