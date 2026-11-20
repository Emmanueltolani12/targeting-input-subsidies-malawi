*==============================================================================
* 03_build_panel.do
* all_waves_panel.dta: every household in every IHPS wave (2010-2024)
*     with the same variable definitions in each wave
* Data: household and agriculture files of steps 01-02; IHPS geovariable
* files (https://microdata.worldbank.org/index.php/catalog/2248,
* https://microdata.worldbank.org/index.php/catalog/2939, https://microdata.worldbank.org/index.php/catalog/3819);
* CHIRPS rainfall (https://www.chc.ucsb.edu/data/chirps) via Earth Engine
*==============================================================================

*------------------------------------------------------------------------------
* 1. Stack all waves
*------------------------------------------------------------------------------
tempfile stack
local first 1
foreach w of global WAVES {
	local k "${KEY`w'}"
	use "$DER/hh_`w'.dta", clear
	merge 1:1 `k' using "$DER/ag_`w'.dta", nogen keep(master match)
	gen str12 hhkey = `k'
	foreach v in y2_hhid y3_hhid y4_hhid y5_hhid {
		capture confirm variable `v', exact
		if _rc gen str8 `v' = ""
	}
	if !`first' append using `stack'
	save `stack', replace
	local first 0
}
use `stack', clear
label var hhkey "Household id of the wave (case_id 2010, y2..y5_hhid 2013-2024)"
label var wave "Survey round (agricultural season ends in this year)"
gen byte year2013 = wave == 2013

*------------------------------------------------------------------------------
* 2. Geovariables (EA level, survey geovariable files)
*    reference rainy season: 2009/10, 2012/13, 2015/16, 2018/19 (2024: none)
*------------------------------------------------------------------------------
tempfile geo
local first 1
foreach w in 2010 2013 2016 2019 {
	local k "${KEY`w'}"
	use "${DIR`w'}/${GEO`w'}.dta", clear
	pickvar adm : dist_admarc
	pickvar agm : dist_agmrkt
	pickvar tmp : af_bio_1
	pickvar aez : ssa_aez09
	pickvar avg : anntot_avg
	local y0 = `w' - 1
	labvar ref "starting july `y0'" h20*
	if `w' == 2010 labvar ref "starting july 2009" h20*
	* naming convention of the later files: h<end year>_tot
	if "`ref'" == "" & `w' > 2010 pickvar ref : h`w'_tot
	foreach v in adm agm tmp avg ref {
		if "``v''" == "" local `v' "."
	}
	gen double g_admarc = `adm'
	gen double g_agmrkt = `agm'
	gen double g_temp   = `tmp' / 10
	if "`aez'" != "" {
		decode `aez', gen(g_aez)
		replace g_aez = lower(g_aez)
	}
	else gen g_aez = ""
	gen double g_rainavg = `avg'
	gen double g_rainref = `ref'
	di as txt "wave `w': reference-season rainfall variable = `ref'"
	gen int wave = `w'
	gen str12 hhkey = `k'
	keep hhkey wave g_*
	if !`first' append using `geo'
	save `geo', replace
	local first 0
}
use `stack', clear
gen byte year2013 = wave == 2013
merge 1:1 hhkey wave using `geo', keep(master match) nogen
* 2024: no geovariable file -> EA-level values of the same household in 2019
preserve
keep if wave == 2019
keep hhkey g_admarc g_agmrkt g_temp g_aez g_rainavg
rename hhkey y4_hhid
rename g_* c19_*
tempfile g19
save `g19'
restore
merge m:1 y4_hhid using `g19', keep(master match) nogen
foreach v in admarc agmrkt temp aez rainavg {
	replace g_`v' = c19_`v' if wave == 2024 & missing(g_`v')
}
drop c19_*
* distance to the agricultural market is first released in 2013: use the
* household's 2013 value in 2010 (same baseline location)
preserve
keep if wave == 2013
* split-off households share the 2010 case_id: take the original household
* (lowest 2013 id), so that the result does not depend on the sort order
keep case_id y2_hhid g_agmrkt
bysort case_id (y2_hhid): keep if _n == 1
drop y2_hhid
rename g_agmrkt agm13
tempfile agm
save `agm'
restore
merge m:1 case_id using `agm', keep(master match) nogen
replace g_agmrkt = agm13 if wave == 2010 & missing(g_agmrkt)
drop agm13

rename (g_admarc g_agmrkt g_temp) (dist_admarc dist_agmrkt temperature)
gen aez_s = g_aez
gen byte aez_warm_semiarid = strpos(aez_s, "warm/semiarid") > 0
gen byte aez_warm_subhumid = strpos(aez_s, "warm/subhumid") > 0
gen byte aez_cool_semiarid = strpos(aez_s, "cool/semiarid") > 0
gen byte aez_cool_subhumid = strpos(aez_s, "cool/subhumid") > 0

* rainfall shock. Paper: 12-month SPI, positive shock if SPI > 1.5.
* (a) default ($SPI_SOURCE "chirps"): 12-month SPI of the July-June reference
*     year at the household location from CHIRPS daily rainfall (gamma fit on
*     1981/82-2023/24), extracted once by code/gee/gee_chirps_spi12.py and stored
*     in data/raw/satellite/chirps_spi12_households.csv
* (b) $SPI_SOURCE "survey": anomaly of the survey geovariables' reference-season
*     total relative to the EA long-run mean, standardised by the district
*     dispersion of these anomalies (no 2024 value: no geovariable file)
gen double rr = g_rainref / g_rainavg - 1
bysort district: egen double cv_rain = sd(rr)
gen double spi_survey = rr / cv_rain
gen byte spi_shock_survey = spi_survey > 1.5 if !missing(spi_survey)
label var spi_survey "Standardised reference-season rainfall anomaly (survey geovariables)"
label var spi_shock_survey "Positive rainfall shock (survey anomaly > 1.5)"
preserve
import delimited using "$ROOT/data/raw/satellite/chirps_spi12_households.csv", ///
	clear varnames(1) stringcols(2)
keep wave hhkey rain12 spi12
tempfile c12
save `c12'
restore
merge 1:1 wave hhkey using `c12', keep(master match) nogen
label var rain12 "Rainfall July-June of the reference year (mm, CHIRPS)"
label var spi12  "12-month SPI of the reference year (CHIRPS, gamma)"
if "$SPI_SOURCE" == "survey" {
	gen double spi = spi_survey
	gen byte spi_shock = spi_shock_survey
	label var spi "Rainfall anomaly used in the models (survey geovariables)"
	label var spi_shock "Positive rainfall shock (survey anomaly > 1.5)"
}
else {
	gen double spi = spi12
	gen byte spi_shock = spi12 > 1.5 if !missing(spi12)
	label var spi "Rainfall anomaly used in the models (12-month SPI, CHIRPS)"
	label var spi_shock "Positive rainfall shock (12-month SPI > 1.5)"
}
di as txt "rainfall shock source: " cond("$SPI_SOURCE" == "survey", "survey anomaly", "CHIRPS 12-month SPI")
tab wave spi_shock, row nofreq

* 2024 soil type/quality not asked: carry forward the 2019 value of the household
preserve
keep if wave == 2019
keep hhkey soil_type soil_quality
rename hhkey y4_hhid
rename (soil_type soil_quality) (st19 sq19)
tempfile soil19
save `soil19'
restore
merge m:1 y4_hhid using `soil19', keep(master match) nogen
gen byte soil_carried = wave == 2024 & missing(soil_type) & !missing(st19)
replace soil_type = st19 if wave == 2024 & missing(soil_type)
replace soil_quality = sq19 if wave == 2024 & missing(soil_quality)
drop st19 sq19

*------------------------------------------------------------------------------
* 3. Input prices (MK/kg), by wave: commercial unit values and voucher
*    redemption prices; missing -> EA (>=3) -> district -> region -> national
*------------------------------------------------------------------------------
local goods mseed chitowe urea othfert oseed
foreach g of local goods {
	gen double p_`g' = com_val`g' / com_kg`g' if com_kg`g' > 0 & com_val`g' > 0
	bysort wave: egen double med = median(p_`g')
	replace p_`g' = . if p_`g' < med / 10 | p_`g' > med * 10
	drop med
	gen byte buy_`g' = com_kg`g' > 0 & com_val`g' > 0
}
foreach g in mseed chitowe urea oseed {
	gen double pv_`g' = costv_`g' / kgv_`g' if kgv_`g' > 0 & costv_`g' > 0
	bysort wave: egen double med = median(pv_`g')
	replace pv_`g' = . if pv_`g' < med / 10 | pv_`g' > med * 10
	drop med
}
foreach v in p_mseed p_chitowe p_urea p_othfert p_oseed pv_mseed pv_chitowe pv_urea pv_oseed {
	gen double `v'_obs = `v'
	foreach lev in ea_id district region {
		bysort wave `lev': egen double m_`lev' = median(`v'_obs)
		bysort wave `lev': egen n_`lev' = count(`v'_obs)
	}
	bysort wave: egen double m_nat = median(`v'_obs)
	replace `v' = m_ea_id    if missing(`v') & n_ea_id >= 3
	replace `v' = m_district if missing(`v') & n_district >= 3
	replace `v' = m_region   if missing(`v') & n_region >= 3
	replace `v' = m_nat      if missing(`v')
	drop m_ea_id n_ea_id m_district n_district m_region n_region m_nat
}

*------------------------------------------------------------------------------
* 4. Expenditures, budget shares, quotas
*------------------------------------------------------------------------------
egen double exp_com = rowtotal(com_valmseed com_valchitowe com_valurea com_valothfert com_valoseed)
egen double exp_vou = rowtotal(costv_mseed costv_chitowe costv_urea costv_oseed)
gen double exp_E = exp_com + exp_vou + com_valchem + com_valorgbuy
foreach g in A B C D {
	gen double exp_`g' = expmod_`g'
}
gen double m_total = exp_A + exp_B + exp_C + exp_D + exp_E
foreach g in A B C D E {
	gen double w_`g' = exp_`g' / m_total
}
gen double M = exp_com
foreach g of local goods {
	gen double s_`g' = cond(M > 0, com_val`g' / M, 0)
}
foreach g in mseed chitowe urea oseed {
	gen double q_`g' = kgv_`g'
	gen double pq_`g' = pv_`g' * q_`g'
	gen byte vou_`g' = ncoupv_`g' > 0
}
gen byte vou_fert = vou_chitowe | vou_urea
egen double ncoup_total = rowtotal(ncoupv_mseed ncoupv_chitowe ncoupv_urea ncoupv_oseed)

*------------------------------------------------------------------------------
* 5. Group price indices (logs; base = 2010 national medians)
*------------------------------------------------------------------------------
gen double lnP_A = lewbel_A1 + lewbel_A2
foreach lev in ea_id district {
	bysort wave `lev': egen double m = mean(lnP_A)
	replace lnP_A = m if missing(lnP_A)
	drop m
}
* non-food: spatial index within the wave + the wave's food price level
bysort wave: egen double anchor = mean(lewbel_A1)
foreach g in B C D {
	replace lnP_`g' = 0 if missing(lnP_`g')
	replace lnP_`g' = lnP_`g' + anchor
}
drop anchor
* agricultural inputs: Lewbel index over the five input prices
foreach g of local goods {
	quietly summarize p_`g' if wave == 2010, detail
	gen double p0_`g' = r(p50)
	bysort wave: egen double sbar_`g' = mean(s_`g') if M > 0
	bysort wave (sbar_`g'): replace sbar_`g' = sbar_`g'[1]
	gen double sw_`g' = cond(M > 0, s_`g', sbar_`g')
}
gen double lnP_E = 0
foreach g of local goods {
	replace lnP_E = lnP_E + sw_`g' * ln(p_`g' / p0_`g')
	replace lnP_E = lnP_E - sw_`g' * ln(sw_`g') if sw_`g' > 0
}
foreach g in A B C D E {
	gen double P_`g' = 100 * exp(lnP_`g')
}

*------------------------------------------------------------------------------
* 6. Income and farm specialisation
*------------------------------------------------------------------------------
foreach v in inc_crop inc_livestock inc_wage inc_ganyu inc_ent inc_other inc_remit inc_snet {
	replace `v' = 0 if missing(`v')
}
gen double inc_total = inc_crop + inc_livestock + inc_wage + inc_ganyu + inc_ent + inc_other + inc_remit + inc_snet
gen double farm_share = (inc_crop + inc_livestock) / inc_total if inc_total > 0
gen byte sp_farm = farm_share > 0.75 if !missing(farm_share)
replace sp_farm = 1 if missing(sp_farm)
gen double ln_income = ln(inc_total + 1)

*------------------------------------------------------------------------------
* 7. Regressors, production-function variables, maize-grower flag
*------------------------------------------------------------------------------
foreach v in antierosion mv {
	replace `v' = 0 if missing(`v')
}
gen double S = shannon
gen double S2 = shannon^2
gen byte soil_good  = soil_quality == 1
gen byte soil_fair  = soil_quality == 2
gen byte soil_poor  = soil_quality == 3
gen byte soil_sandy = soil_type == 1
gen byte soil_mixed = soil_type == 2
gen byte soil_clay  = soil_type == 3
replace spi_shock = 0 if missing(spi_shock) & !missing(spi)
gen byte grows_maize = maize_kg > 0 & maize_kg < . & area_maize > 0 & area_maize < .
label var grows_maize "Grew maize with positive harvest and area (rainy season)"
label var aip "Input subsidy is the Affordable Inputs Programme (2024)"
label var soil_carried "Soil type/quality carried forward from 2019"

* wealth items common to all waves (asset codes asked in every round)
ds own*
foreach v in `r(varlist)' {
	quietly count if missing(`v')
	bysort wave: egen byte has_ = max(!missing(`v'))
	quietly summarize has_
	if r(min) == 0 drop `v'
	else replace `v' = 0 if missing(`v')
	drop has_
}
compress
save "$DER/all_waves_panel_raw.dta", replace

*------------------------------------------------------------------------------
* 8. Variables shared by both outputs (applied separately to each sample):
*    top-coding, wealth index, missing-value fill, logs
*------------------------------------------------------------------------------
capture program drop finish_sample
program define finish_sample
	* 8a. top-code continuous agricultural quantities at the wave's 99th pct
	foreach v in maize_kg area_maize maize_seed_kg organic_kg chitowe_kg urea_kg ///
		otherfert_kg labour com_kgmseed com_kgchitowe com_kgurea com_kgothfert ///
		com_kgoseed com_valmseed com_valchitowe com_valurea com_valothfert ///
		com_valoseed com_valchem com_valorgbuy kgv_mseed kgv_chitowe kgv_urea kgv_oseed {
		quietly levelsof wave, local(ws)
		foreach r of local ws {
			quietly summarize `v' if wave == `r' & `v' > 0, detail
			if r(N) > 0 quietly replace `v' = r(p99) if wave == `r' & `v' > r(p99) & `v' < .
		}
	}
	quietly levelsof wave, local(ws)
	foreach r of local ws {
		quietly summarize area_maize if wave == `r', detail
		quietly replace area_maize = r(p1) if wave == `r' & area_maize < r(p1)
	}
	* 8b. wealth index: first principal component of assets and dwelling
	ds own*
	local assets `r(varlist)'
	foreach v of local assets {
		quietly summarize `v'
		if r(mean) < 0.005 | r(mean) > 0.995 drop `v'
	}
	ds own*
	local assets `r(varlist)'
	local dwell wall_brick roof_iron floor_cem water_impr toilet_impr electricity cellphone
	foreach v of local dwell {
		replace `v' = 0 if missing(`v')
	}
	pca `assets' `dwell', components(1)
	predict double wealth, score
	xtile wealth_t = wealth, nq(3)
	gen byte wealth2 = wealth_t == 2
	gen byte wealth3 = wealth_t == 3
	label define wealth_t 1 "Wealth: 1 (poorest)" 2 "Wealth: 2 (medium)" 3 "Wealth: 3 (richest)", replace
	label values wealth_t wealth_t
	* 8c. missing values of regressors: sample median (documented in README)
	foreach v in head_female head_age landowner shannon dist_agmrkt dist_admarc temperature hhsize {
		capture confirm variable `v'
		if !_rc {
			quietly summarize `v', detail
			replace `v' = r(p50) if missing(`v')
		}
	}
	replace S = shannon if missing(S)
	replace S2 = S^2
	replace soil_quality = 2 if missing(soil_quality)
	replace soil_type = 2 if missing(soil_type)
	replace soil_good = soil_quality == 1
	replace soil_fair = soil_quality == 2
	replace soil_poor = soil_quality == 3
	replace soil_sandy = soil_type == 1
	replace soil_mixed = soil_type == 2
	replace soil_clay = soil_type == 3
	* 8d. production function in logs (zero inputs as ln(x+1))
	gen double lny      = ln(maize_kg)
	gen double ln_seed  = ln(maize_seed_kg + 1)
	gen double ln_org   = ln(organic_kg + 1)
	gen double ln_chit  = ln(chitowe_kg + 1)
	gen double ln_urea  = ln(urea_kg + 1)
	gen double ln_othf  = ln(otherfert_kg + 1)
	gen double ln_lab   = ln(labour + 1)
	gen double ln_area  = ln(area_maize)
	* labels
	label var maize_kg      "Maize production (kg)"
	label var maize_seed_kg "Maize seeds utilized (kg)"
	label var organic_kg    "Organic fertilizer utilized (kg)"
	label var urea_kg       "Urea utilized (kg)"
	label var chitowe_kg    "Chitowe utilized (kg)"
	label var otherfert_kg  "Other fertilizers utilized (kg)"
	label var labour        "Labour utilized (person-days)"
	label var area_maize    "Area cultivated with maize (ha)"
	label var head_female   "HH female headed (dummy)"
	label var head_age      "Age of HH head (years)"
	label var educ_15_60    "Avg. completed grade of members aged 15-60"
	label var wealth        "Wealth index (first principal component)"
	label var landowner     "Share of cultivated area owned"
	label var dist_agmrkt   "Distance from main agricultural market (km)"
	label var dist_admarc   "Distance from nearest ADMARC outlet (km)"
	label var sp_farm       "Receives >75% of income from farming"
	label var antierosion   "Applied anti-erosion measures"
	label var mv            "Uses modern maize varieties (OPV/hybrid)"
	label var S             "Shannon index of crop areas"
	label var temperature   "Annual mean temperature at EA (deg C)"
end

*------------------------------------------------------------------------------
* 9. Output 1: all households, all waves
*------------------------------------------------------------------------------
use "$DER/all_waves_panel_raw.dta", clear
capture confirm variable hhsize
if _rc gen hhsize = .
finish_sample
order wave hhkey case_id y2_hhid y3_hhid y4_hhid ea_id district region
sort wave hhkey
compress
save "$DER/all_waves_panel.dta", replace
di as res "all_waves_panel: " _N " household-wave observations"
tab wave grows_maize
tabstat maize_kg area_maize maize_seed_kg chitowe_kg urea_kg labour w_A w_B w_C w_D w_E ///
	vou_chitowe vou_urea vou_mseed vou_oseed p_chitowe p_urea pv_chitowe spi_shock, ///
	by(wave) statistics(mean) format(%9.3f) columns(statistics) longstub
