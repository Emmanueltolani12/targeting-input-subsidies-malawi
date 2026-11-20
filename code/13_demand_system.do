*==============================================================================
* 13_demand_system.do -- quota and price effects in the demand system, all
* rounds
* Both stages of the two-stage QUAIDS on maize growers of all five rounds
* (2010-2024). Voucher quotas (coupon or AIP kilograms) and commercial
* fertiliser prices are treated as endogenous; control functions (first-stage
* residuals) enter the share equations as translating variables, as the
* expenditure residual does.
* Excluded instruments for the quotas (allocation decided above the village):
*   iv_<k>  leave-EA-out district coverage: mean kilograms of coupon type k
*           received by households in the other enumeration areas of the same
*           district and round (EA x district cells, so households that moved
*           take the value of their current district)
*   off_cov official fertiliser beneficiaries per farm family of the district
*           (data/raw/programme): Logistics Unit 2009/10, 2012/13, 2015/16;
*           for 2018/19, for which no district figures are public, the latest
*           official season (2016/17); Ombudsman 2024 report for AIP 2023/24
*   dl_d    delivery timing: mean months after 1 October of the season in
*           which households in the other EAs of the district obtained their
*           coupons (2010-2019) or redeemed AIP inputs (2024)
* Excluded instruments for the prices of commercial chitowe (NPK) and urea:
*   zp_npk, zp_urea  world DAP and urea prices (World Bank Pink Sheet, US$
*           per tonne) converted at the MWK/US$ rate (IMF), mean of the
*           planting months September-December, in logs, interacted with the
*           household's remoteness (log distance to the nearest agricultural
*           market, centred); remoteness itself enters the share equations.
*           World prices pass through less where transport is a larger share
*           of the farm-gate price; round effects absorb the common component.
* Price data (data/raw/prices):
*   World Bank Commodity Price Data (Pink Sheet), monthly,
*     https://www.worldbank.org/en/research/commodity-markets
*   IMF exchange rate MWK per US$, monthly (via DBnomics),
*     https://db.nomics.world/IMF/IFS/M.MW.ENDA_XDC_USD_RATE
* District allocations: data/raw/programme (sources and pages in
*   data/raw/programme/README.md and sources.csv)
* Specifications: exog (quotas exogenous), iv (quota control functions), iv_cov
*   (leave-EA-out coverage only), iv_price (quota and price control
*   functions). All on one sample (households with every instrument).
* Diagnostics: per-equation F and Sanderson-Windmeijer conditional F of the
*   excluded instruments (cluster-robust), partial R2 on the same sample,
*   Hansen J of a linear IV model of commercial fertiliser shares.
* Parallel runs: global S2_PART = all (default: everything in sequence) |
*   prep (instruments, first stages, sample) | <spec> (one second stage) |
*   combine (tables). Each second stage takes 40-70 minutes (50-70 FGNLS iterations).
* Inputs: $DER/all_waves_panel.dta, all_waves_panel_sat.dta; IHPS coupon
*   modules (AG E); data/raw/programme; data/raw/prices
* Output: $EXT/demand_iv_first_stage.csv, demand_iv_quota.csv,
*   demand_iv_quota_mkt.csv, demand_iv_eta.csv, demand_iv_diagnostics.csv;
*   $DER/stage1_all.dta, stage2_quota_all.dta, demand_iv_sample.dta,
*   stage2_all_elast_cov_<spec>.mmat (redemption-price valuation),
*   stage2_all_elast_cov_<spec>_mkt.mmat (quota valued at market prices),
*   demand_iv_instruments.dta (household instruments, all maize growers)
*==============================================================================

global EXT "$ROOT/output/results"
do "$CODE/ado/qd_lib.do"
set sortseed 20171105
if "$S2_PART" == "" global S2_PART "all"
if "$S2_SPECS" == "" global S2_SPECS "exog iv iv_cov iv_price"
local part "$S2_PART"
local Zd ln_hhsize head_female head_age10 educ10 y2013 y2016 y2019 y2024 reg2 reg3
local Zq qz_mseed qz_urea qz_chitowe qz_oseed
local IVq iv_mseed iv_urea iv_chitowe iv_oseed off_cov dl_d
local IVp zp_npk zp_urea

if inlist("`part'", "all", "prep") {
*------------------------------------------------------------------------------
* 1a. leave-EA-out district-round coverage (all households)
*------------------------------------------------------------------------------
use "$DER/all_waves_panel.dta", clear
keep wave hhkey district ea_id q_mseed q_chitowe q_urea q_oseed
foreach k in mseed chitowe urea oseed {
	replace q_`k' = 0 if missing(q_`k')
	bysort wave district: egen double T_`k' = total(q_`k')
	bysort wave district ea_id: egen double E_`k' = total(q_`k')
}
bysort wave district: gen double N_d = _N
bysort wave district ea_id: gen double N_e = _N
foreach k in mseed chitowe urea oseed {
	gen double iv_`k' = (T_`k' - E_`k') / (N_d - N_e) / 10
}
tempfile hhloc
preserve
keep wave hhkey district ea_id
save `hhloc'
restore
bysort wave district ea_id: keep if _n == 1
keep wave district ea_id iv_*
tempfile ivs
save `ivs'

*------------------------------------------------------------------------------
* 1b. delivery timing: months after 1 October of the season start
*------------------------------------------------------------------------------
tempfile dl
local first 1
foreach x in "2010 ihps/AG_MOD_E_10 case_id ag_e05a ag_e05b" "2013 ihps/AG_MOD_E2_13 y2_hhid ag_e05a ag_e05b" ///
	"2016 ihps_long/ag_mod_e2_16 y3_hhid ag_e05a ag_e05b" "2019 ihps_long/ag_mod_e2_19 y4_hhid ag_e05a ag_e05b" ///
	"2024 ihps_long/ag_mod_e2_24 y5_hhid ag_e08_1a ag_e08_1b" {
	tokenize `x'
	use "$RESTRICTED/`2'.dta", clear
	gen str12 hhkey = `3'
	gen double delay = (`5' - (`1' - 1)) * 12 + `4' - 10
	keep if inrange(delay, -4, 9)
	collapse (mean) delay, by(hhkey)
	gen int wave = `1'
	if !`first' append using `dl'
	save `dl', replace
	local first 0
}
use `hhloc', clear
merge 1:1 wave hhkey using `dl', keep(master match) nogen
bysort wave district: egen double Td = total(delay)
bysort wave district: egen double Nd = count(delay)
bysort wave district ea_id: egen double Te = total(delay)
bysort wave district ea_id: egen double Ne = count(delay)
gen double dl_d = (Td - Te) / (Nd - Ne) if Nd > Ne
tabstat delay dl_d, by(wave) statistics(mean sd n) format(%5.2f)
bysort wave district ea_id: keep if _n == 1
keep wave district ea_id dl_d
merge 1:1 wave district ea_id using `ivs', nogen
save `ivs', replace

*------------------------------------------------------------------------------
* 1c. official district fertiliser coverage (beneficiaries per farm family).
* 2009/10 and 2012/13: beneficiaries / farm families; 2015/16: fertiliser
* coupons / 2; 2018/19: 2016/17 beneficiaries (latest official season; no
* district figures are public for 2017/18-2019/20); 2023/24: AIP fertiliser
* beneficiaries; denominator: farm families of the season, else 2012/13.
* Split districts (Mzimba N/S, Lilongwe E/W, Dowa E/W) are summed.
*------------------------------------------------------------------------------
import delimited using "$ROOT/data/raw/programme/fisp_aip_district_allocations.csv", clear varnames(1) stringcols(_all) bindquote(strict)
destring value, replace force
keep if inlist(season, "2009/10", "2012/13", "2015/16", "2016/17", "2018/19", "2023/24") & !missing(value)
keep if inlist(measure, "beneficiaries", "farm_families", "fertiliser_coupons", "beneficiaries_fertiliser")
keep if !(season == "2015/16" & measure != "fertiliser_coupons")
keep if !(season == "2016/17" & measure != "beneficiaries")
keep if !(season == "2023/24" & measure != "beneficiaries_fertiliser")
gen str30 dname = lower(district)
foreach sfx in " north" " south" " east" " west" {
	replace dname = subinstr(dname, "`sfx'", "", .)
}
replace dname = subinstr(dname, " ", "", .)
drop if strpos(dname, "add") | strpos(dname, "region") | strpos(dname, "total")
collapse (sum) value, by(season dname measure)
reshape wide value, i(season dname) j(measure) string
gen double ff1213 = valuefarm_families if season == "2012/13"
bysort dname (ff1213): replace ff1213 = ff1213[1]
gen double ff = cond(!missing(valuefarm_families), valuefarm_families, ff1213)
foreach v in valuebeneficiaries_fertiliser valuefertiliser_coupons valuebeneficiaries {
	capture confirm variable `v'
	if _rc gen double `v' = .
}
gen double benef = cond(inlist(season, "2009/10", "2012/13", "2016/17", "2018/19"), valuebeneficiaries, ///
	cond(season == "2015/16", valuefertiliser_coupons / 2, valuebeneficiaries_fertiliser))
gen double cov = benef / ff
* 2018/19 news figures (six districts) as a check of the 2016/17 proxy
preserve
keep if inlist(season, "2016/17", "2018/19")
keep season dname cov
replace season = cond(season == "2016/17", "a", "b")
reshape wide cov, i(dname) j(season) string
quietly count if !missing(cova, covb)
if r(N) >= 3 {
	quietly corr cova covb
	di as txt "2018/19 news coverage vs 2016/17 official coverage: corr = " %5.2f r(rho) " (" r(N) " districts)"
	global OFF1819_RHO = r(rho)
	global OFF1819_N = r(N)
}
restore
drop if season == "2018/19"
gen int wave = cond(season == "2016/17", 2019, real(substr(season, 1, 4)) + 1)
rename cov off_cov
keep wave dname off_cov
tempfile offd
save `offd'

*------------------------------------------------------------------------------
* 1d. world fertiliser prices in kwacha (planting months Sep-Dec)
*------------------------------------------------------------------------------
import delimited using "$ROOT/data/raw/prices/mwi_mwk_usd_monthly_imf.csv", clear varnames(nonames) rowrange(2) stringcols(_all)
rename (v1 v2) (period er)
destring er, replace force
tempfile er
save `er'
import delimited using "$ROOT/data/raw/prices/wb_fertiliser_prices_monthly.csv", clear varnames(1) stringcols(1)
merge 1:1 period using `er', keep(match) nogen
gen int year = real(substr(period, 1, 4))
gen int month = real(substr(period, 6, 2))
keep if inrange(month, 9, 12) & inlist(year, 2009, 2012, 2015, 2018, 2023)
gen double mwk_urea = urea * er
gen double mwk_dap = dap * er
collapse (mean) mwk_urea mwk_dap urea dap er, by(year)
gen int wave = year + 1
gen double lpw_urea = ln(mwk_urea)
gen double lpw_dap = ln(mwk_dap)
list wave urea dap er mwk_urea mwk_dap, noobs clean
keep wave lpw_urea lpw_dap mwk_urea mwk_dap
tempfile pw
save `pw'

*------------------------------------------------------------------------------
* 2. estimation sample: maize growers, all rounds, with every instrument
*------------------------------------------------------------------------------
use "$DER/all_waves_panel_sat.dta", clear
keep if grows_maize
merge m:1 wave district ea_id using `ivs', keep(master match) nogen
district_names
gen str30 dname = lower(subinstr(NAME_1, " ", "", .))
merge m:1 wave dname using `offd', keep(master match) nogen
merge m:1 wave using `pw', keep(master match) nogen
tab wave, summarize(off_cov)
* districts without another EA with coupon recipients: round mean timing
bysort wave: egen double m_dl = mean(dl_d)
gen byte dl_imp = missing(dl_d)
replace dl_d = m_dl if missing(dl_d)
tab wave dl_imp
foreach w in 2013 2016 2019 2024 {
	gen byte y`w' = wave == `w'
}
gen byte reg2 = region == 2
gen byte reg3 = region == 3
gen double ln_hhsize = ln(hhsize)
gen double head_age10 = head_age / 10
gen double educ10 = educ_15_60 / 10
egen long hid = group(wave hhkey)
foreach k in mseed chitowe urea oseed {
	replace q_`k' = 0 if missing(q_`k')
	gen double qz_`k' = q_`k' / 10
}
quietly summarize dist_agmrkt
gen double rem = ln(1 + dist_agmrkt)
quietly summarize rem
replace rem = rem - r(mean)
gen double zp_npk = lpw_dap * rem
gen double zp_urea = lpw_urea * rem
foreach v of varlist iv_* off_cov dl_d zp_npk zp_urea {
	quietly drop if missing(`v')
}
* household-level instruments (control-function test of the joint model, 14_structural_allrounds)
preserve
keep wave hhkey district ea_id iv_mseed iv_urea iv_chitowe iv_oseed off_cov dl_d dl_imp rem zp_npk zp_urea
save "$DER/demand_iv_instruments.dta", replace
restore

*------------------------------------------------------------------------------
* 3. first-stage QUAIDS (five budget groups, module-based in every round)
*------------------------------------------------------------------------------
preserve
foreach g in A B C D E {
	quietly summarize lnP_`g'
	gen double lp_`g' = lnP_`g' - r(mean)
}
gen double lnm = ln(m_total)
keep if !missing(lnm, w_A, w_B, w_C, w_D, w_E, ln_income) & m_total > 0
regress lnm ln_income `Zd' lp_*, vce(cluster ea_id)
predict double vhat, resid
quietly summarize lnm
global QD_a0 = r(mean)
global QD_n 5
global QD_neq 4
global QD_Q : word count `Zd'
global QD_cf 1
global QD_cens 0
global QD_free 0
local K = 3 * 4 + 10 + 4 * $QD_Q + 4
matrix b0 = J(1, `K', 0)
local i 0
foreach g in A B C D {
	local ++i
	quietly summarize w_`g'
	matrix b0[1, `i'] = r(mean)
}
nlsur qd @ w_A w_B w_C w_D lp_A lp_B lp_C lp_D lp_E lnm `Zd' vhat, ///
	nparameters(`K') nequations(4) ifgnls initial(b0) vce(cluster ea_id)
matrix bq = e(b)
matrix Vq = e(V)
local N1 = e(N)
tempname t1
postfile `t1' str45 group str8 point double(eta se_eta own se_own N) using "$DER/stage1_all.dta", replace
local names `" "Food & beverage" "Housing and furnishing" "Clothes, transport, education and health" "Miscellaneous" "Agricultural inputs" "'
foreach pt in total 2010 2013 2016 2019 2024 {
	local cond = cond("`pt'" == "total", "1", "wave == `pt'")
	foreach g in A B C D E {
		quietly summarize lp_`g' if `cond'
		local m_`g' = r(mean)
	}
	quietly summarize lnm if `cond'
	local mm = r(mean)
	local zs ""
	foreach z of local Zd {
		quietly summarize `z' if `cond'
		local zs "`zs' `=r(mean)'"
	}
	mata: R = qd_elast_dm(st_matrix("bq"), st_matrix("Vq"), 5, 4, $QD_Q, 1, 0, $QD_a0, ///
		(`m_A', `m_B', `m_C', `m_D', `m_E'), `mm', strtoreal(tokens("`zs'")), J(1,5,1), J(1,5,0), ///
		0, J(1,0,0), J(1,0,0), J(1,0,0), 1)
	mata: st_matrix("R", R)
	forvalues i = 1/5 {
		local io = 5 + (`i' - 1) * 5 + `i'
		post `t1' ("`: word `i' of `names''") ("`pt'") (R[1, `i']) (R[2, `i']) (R[1, `io']) (R[2, `io']) (`N1')
	}
}
postclose `t1'
restore

*------------------------------------------------------------------------------
* 4. censoring probits (all rounds) and second-stage sample
*------------------------------------------------------------------------------
gen byte wealth1 = wealth_t == 1
local X head_female head_age hhsize educ_15_60 dist_agmrkt sp_farm wealth1 wealth2 soil_fair soil_poor ///
	y2013 y2016 y2019 y2024
foreach g in mseed chitowe urea othfert oseed {
	quietly probit buy_`g' `X' vou_mseed vou_chitowe vou_urea vou_oseed dist_admarc, vce(cluster district)
	predict double xb_`g', xb
	gen double cdf_`g' = normal(xb_`g')
	gen double pdf_`g' = normalden(xb_`g')
	drop xb_`g'
}
keep if M > 0 & !missing(M)
foreach g in mseed chitowe urea othfert oseed {
	gen double lp_`g' = ln(p_`g')
	quietly summarize lp_`g'
	replace lp_`g' = lp_`g' - r(mean)
}
gen double lnM = ln(M)
foreach v of varlist s_mseed s_chitowe s_urea s_othfert s_oseed lp_* cdf_* pdf_* ln_income `Zd' {
	quietly drop if missing(`v')
}

*------------------------------------------------------------------------------
* first stages and diagnostics
*------------------------------------------------------------------------------
local EXq `Zd' lp_mseed lp_chitowe lp_urea lp_othfert lp_oseed ln_income
local EXp `Zd' rem lp_mseed lp_othfert lp_oseed ln_income
tempname fs
postfile `fs' str10 endog str8 spec double(b1 se1 b2 se2 b3 se3 F F_sw partialR2 N) using "$DER/demand_iv_fs.dta", replace
* (a) quotas, quota instruments (spec iv); (b) coverage only (iv_cov);
* (c) quotas and prices with all instruments (iv_price)
foreach set in iv iv_cov iv_price {
	if "`set'" == "iv" {
		local IV `IVq'
		local EX `EXq'
		local EN `Zq'
	}
	else if "`set'" == "iv_cov" {
		local IV iv_mseed iv_urea iv_chitowe iv_oseed
		local EX `EXq'
		local EN `Zq'
	}
	else {
		local IV `IVq' `IVp'
		local EX `EXp'
		local EN `Zq' lp_chitowe lp_urea
	}
	local nI : word count `IV'
	local nE : word count `EN'
	foreach x of local EN {
		local k = cond(substr("`x'", 1, 3) == "qz_", substr("`x'", 4, .), "p_" + substr("`x'", 4, .))
		quietly regress `x' `IV' `EX', vce(cluster ea_id)
		local N = e(N)
		local i1 = cond(substr("`x'", 1, 3) == "qz_", "iv_" + substr("`x'", 4, .), cond("`x'" == "lp_chitowe", "zp_npk", "zp_urea"))
		local b1 = _b[`i1']
		local s1 = _se[`i1']
		local b2 = .
		local s2 = .
		local b3 = .
		local s3 = .
		capture local b2 = _b[off_cov]
		capture local s2 = _se[off_cov]
		capture local b3 = _b[dl_d]
		capture local s3 = _se[dl_d]
		quietly test `IV'
		local F = r(F)
		tempvar es
		gen byte `es' = e(sample)
		predict double v_`set'_`k', resid
		quietly regress `x' `EX' if `es'
		local r0 = e(r2)
		quietly regress `x' `IV' `EX' if `es'
		local pr2 = (e(r2) - `r0') / (1 - `r0')
		* Sanderson-Windmeijer conditional F: the other endogenous variables
		* instrumented, residual regressed on the instruments
		local Fsw = `F'
		if `nE' > 1 {
			local oth : list EN - x
			capture {
				ivregress 2sls `x' `EX' (`oth' = `IV') if `es'
				tempvar ew
				predict double `ew' if `es', resid
				regress `ew' `IV' `EX' if `es', vce(cluster ea_id)
				test `IV'
				local Fsw = r(F) * `nI' / (`nI' - `nE' + 1)
			}
			if _rc local Fsw = .
		}
		post `fs' ("`k'") ("`set'") (`b1') (`s1') (`b2') (`s2') (`b3') (`s3') (`F') (`Fsw') (`pr2') (`N')
	}
}
postclose `fs'
tempname dg
postfile `dg' str24 stat str10 outcome double value using "$DER/demand_iv_diag.dta", replace
if "$OFF1819_RHO" != "" {
	post `dg' ("corr_off1819_news") ("") ($OFF1819_RHO)
	post `dg' ("n_off1819_news") ("") ($OFF1819_N)
}
quietly count if dl_imp
post `dg' ("delivery_imputed") ("") (r(N))
postclose `dg'
* temporary variables of the first-stage loop are not saved
capture drop __0*
save "$DER/demand_iv_sample.dta", replace
}

*------------------------------------------------------------------------------
* 5. second-stage QUAIDS by specification
*------------------------------------------------------------------------------
capture program drop s2_fit
program define s2_fit
	* s2_fit <spec> <number of demographic variables> <Z list>
	args spec nzd
	macro shift 2
	local Z `*'
	regress lnM ln_income `Z' lp_*, vce(cluster ea_id)
	capture drop vhat
	predict double vhat, resid
	quietly summarize lnM
	global QD_a0 = r(mean)
	global QD_n 5
	global QD_neq 5
	global QD_Q : word count `Z'
	global QD_cf 1
	global QD_cens 1
	global QD_free 1
	local K = 3 * 5 + 10 + 5 * $QD_Q + 5 + 5
	matrix b0 = J(1, `K', 0)
	local i 0
	foreach g in mseed chitowe urea othfert oseed {
		local ++i
		quietly summarize s_`g'
		matrix b0[1, `i'] = r(mean)
	}
	nlsur qd @ s_mseed s_chitowe s_urea s_othfert s_oseed lp_mseed lp_chitowe lp_urea ///
		lp_othfert lp_oseed lnM `Z' vhat cdf_mseed cdf_chitowe cdf_urea cdf_othfert cdf_oseed ///
		pdf_mseed pdf_chitowe pdf_urea pdf_othfert pdf_oseed, ///
		nparameters(`K') nequations(5) ifgnls initial(b0) vce(cluster ea_id)
	matrix bq = e(b)
	matrix Vq = e(V)
	local NN = e(N)
	estimates save "$DER/stage2_all_est_`spec'.ster", replace
	* evaluation at the sample means
	local lp ""
	local cdf ""
	local pdf ""
	foreach g in mseed chitowe urea othfert oseed {
		quietly summarize lp_`g'
		local lp "`lp' `=r(mean)'"
		quietly summarize cdf_`g'
		local cdf "`cdf' `=r(mean)'"
		quietly summarize pdf_`g'
		local pdf "`pdf' `=r(mean)'"
	}
	quietly summarize lnM
	local mm = r(mean)
	quietly summarize M
	local Mb = r(mean)
	local zs ""
	foreach z of local Z {
		quietly summarize `z'
		local zs "`zs' `=r(mean)'"
	}
	* quota value at the redemption price (the paper) and at market prices
	local pq ""
	local pqm ""
	local qb ""
	foreach k in mseed urea chitowe oseed {
		tempvar x xm
		gen double `x' = pv_`k' * q_`k'
		gen double `xm' = p_`k' * q_`k'
		quietly summarize `x'
		local pq "`pq' `=r(mean)'"
		quietly summarize `xm'
		local pqm "`pqm' `=r(mean)'"
		quietly summarize qz_`k'
		local qb "`qb' `=r(mean)'"
		drop `x' `xm'
	}
	local qpos "(`nzd' + 1, `nzd' + 2, `nzd' + 3, `nzd' + 4)"
	mata: R = qd_elast_dm(st_matrix("bq"), st_matrix("Vq"), 5, 5, $QD_Q, 1, 1, $QD_a0, ///
		strtoreal(tokens("`lp'")), `mm', strtoreal(tokens("`zs'")), strtoreal(tokens("`cdf'")), ///
		strtoreal(tokens("`pdf'")), 4, `qpos', strtoreal(tokens("`qb'")), strtoreal(tokens("`pq'")), `Mb')
	mata: st_matrix("R", R)
	foreach v in "" "_mkt" {
		local pv = cond("`v'" == "", "`pq'", "`pqm'")
		mata: qd_save_matrix(st_global("DER") + "/stage2_all_elast_cov_`spec'`v'.mmat", ///
			qd_elast_cov(st_matrix("bq"), st_matrix("Vq"), 5, 5, $QD_Q, 1, 1, $QD_a0, ///
			strtoreal(tokens("`lp'")), `mm', strtoreal(tokens("`zs'")), strtoreal(tokens("`cdf'")), ///
			strtoreal(tokens("`pdf'")), 4, `qpos', strtoreal(tokens("`qb'")), strtoreal(tokens("`pv'")), `Mb'))
	}
	local names mseed chitowe urea othfert oseed
	local qnames mseed urea chitowe oseed
	tempname pf
	postfile `pf' str12 spec str10 quota str10 good double(z se N) using "$DER/stage2_quota_all_`spec'.dta", replace
	forvalues i = 1/5 {
		post `pf' ("`spec'") ("eta") ("`: word `i' of `names''") (R[1, `i']) (R[2, `i']) (`NN')
		forvalues k = 1/4 {
			local c = 30 + (`i' - 1) * 4 + `k'
			post `pf' ("`spec'") ("`: word `k' of `qnames''") ("`: word `i' of `names''") (R[1, `c']) (R[2, `c']) (`NN')
		}
		local io = 5 + (`i' - 1) * 5 + `i'
		post `pf' ("`spec'") ("own_price") ("`: word `i' of `names''") (R[1, `io']) (R[2, `io']) (`NN')
	}
	postclose `pf'
end

capture program drop s2_spec
program define s2_spec
	* s2_spec <spec>: the Z list of each specification
	args spec
	local Zd ln_hhsize head_female head_age10 educ10 y2013 y2016 y2019 y2024 reg2 reg3
	local Zq qz_mseed qz_urea qz_chitowe qz_oseed
	local nd : word count `Zd'
	if "`spec'" == "exog"     s2_fit exog `nd' `Zd' `Zq'
	if "`spec'" == "iv"       s2_fit iv `nd' `Zd' `Zq' v_iv_mseed v_iv_urea v_iv_chitowe v_iv_oseed
	if "`spec'" == "iv_cov"   s2_fit iv_cov `nd' `Zd' `Zq' v_iv_cov_mseed v_iv_cov_urea v_iv_cov_chitowe v_iv_cov_oseed
	if "`spec'" == "iv_price" s2_fit iv_price `=`nd' + 1' `Zd' rem `Zq' v_iv_price_mseed v_iv_price_urea ///
		v_iv_price_chitowe v_iv_price_oseed v_iv_price_p_chitowe v_iv_price_p_urea
end

if "`part'" == "all" {
	foreach spec of global S2_SPECS {
		di as txt "==== second stage: `spec'  $S_TIME"
		s2_spec `spec'
	}
}
else if !inlist("`part'", "prep", "combine") {
	use "$DER/demand_iv_sample.dta", clear
	di as txt "==== second stage: `part'  $S_TIME"
	s2_spec `part'
	di as txt "==== done: `part'  $S_TIME"
}

*------------------------------------------------------------------------------
* 6. tables
*------------------------------------------------------------------------------
if inlist("`part'", "all", "combine") {
	clear
	local first 1
	foreach spec of global S2_SPECS {
		capture confirm file "$DER/stage2_quota_all_`spec'.dta"
		if _rc {
			di as error "second stage `spec' missing"
			continue
		}
		if `first' use "$DER/stage2_quota_all_`spec'.dta", clear
		else append using "$DER/stage2_quota_all_`spec'.dta"
		local first 0
	}
	save "$DER/stage2_quota_all.dta", replace
	export delimited using "$EXT/demand_iv_quota.csv", replace
	list if inlist(quota, "chitowe", "urea", "mseed") & good == quota, noobs clean
	* elasticities with the quota valued at market prices
	local names mseed chitowe urea othfert oseed
	local qnames mseed urea chitowe oseed
	tempname pm
	postfile `pm' str12 spec str10 quota str10 good double(z se) using "$DER/stage2_quota_all_mkt.dta", replace
	foreach spec of global S2_SPECS {
		capture confirm file "$DER/stage2_all_elast_cov_`spec'_mkt.mmat"
		if _rc continue
		mata: G = qd_read_matrix(st_global("DER") + "/stage2_all_elast_cov_`spec'_mkt.mmat")
		mata: st_matrix("G0", G[1, .])
		mata: st_matrix("GS", sqrt(diagonal(G[2::rows(G), .]))')
		forvalues i = 1/5 {
			forvalues k = 1/4 {
				local c = 30 + (`i' - 1) * 4 + `k'
				post `pm' ("`spec'") ("`: word `k' of `qnames''") ("`: word `i' of `names''") (G0[1, `c']) (GS[1, `c'])
			}
		}
	}
	postclose `pm'
	use "$DER/stage2_quota_all_mkt.dta", clear
	export delimited using "$EXT/demand_iv_quota_mkt.csv", replace
	use "$DER/demand_iv_fs.dta", clear
	export delimited using "$EXT/demand_iv_first_stage.csv", replace
	list, noobs clean
	* overidentification: linear IV (two-step GMM, EA-clustered) of commercial
	* fertiliser shares on the quotas; Hansen J
	use "$DER/demand_iv_sample.dta", clear
	egen long eac_ = group(ea_id)
	tempname hj
	postfile `hj' str24 stat str10 outcome double value using "$DER/demand_iv_hansen.dta", replace
	foreach y in s_chitowe s_urea {
		capture noisily ivregress gmm `y' `Zd' lp_mseed lp_chitowe lp_urea lp_othfert lp_oseed ln_income ///
			(`Zq' = `IVq'), vce(cluster eac_)
		if !_rc {
			estat overid
			post `hj' ("hansen_j") ("`y'") (r(HansenJ))
			post `hj' ("hansen_p") ("`y'") (r(p_HansenJ))
		}
	}
	postclose `hj'
	use "$DER/demand_iv_diag.dta", clear
	append using "$DER/demand_iv_hansen.dta"
	export delimited using "$EXT/demand_iv_diagnostics.csv", replace
	list, noobs clean
	use "$DER/stage1_all.dta", clear
	export delimited using "$EXT/demand_iv_eta.csv", replace
}
