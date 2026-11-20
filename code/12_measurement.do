*==============================================================================
* 12_measurement.do -- transient inefficiency and crop vigor from space
* The IHPS has no crop cuts in any round and the plot coordinates are not
* public, so the objective benchmark is crop vigour seen from space at the
* household location (5 km around the displaced coordinates): MODIS EVI on
* cropland in every round (seasonal maximum and its anomaly) and the
* Sentinel-2 anomaly of 2023/24, together with rainfall and heat shocks.
*   (1) transient inefficiency (06_panel_frontier) = EA-season component + within-EA part
*   (2) the EA-season component is regressed on satellite vigour and weather:
*       the share explained is confirmed as real production shortfall
*   (3) the within-EA part cannot be verified from space at this resolution;
*       it bounds measurement error plus idiosyncratic shocks
*   (4) the same for self-reported ln yield
* Inputs: $DER/panel_efficiency.dta, all_waves_panel_sat.dta,
*         ext_points_grid_features.csv (10_grid_predictions)
* Output: $EXT/measurement.csv
*==============================================================================

global EXT "$ROOT/output/results"
import delimited using "$DER/ext_points_grid_features.csv", clear varnames(1)
keep pid s2_anom24 s2_peak
destring s2_anom24 s2_peak, replace force
rename (s2_anom24 s2_peak) (g_s2_anom24 g_s2_peak)
tempfile s2
save `s2'

use "$DER/panel_efficiency.dta", clear
keep uid wave hhkey ea_id district u_t te_t te_o T maize_kg area_maize evi_max evi_anom spi12 hot30 pid
merge m:1 pid using `s2', keep(master match) nogen
gen double lnyield = ln(maize_kg / area_maize)
gen double s2_anom = g_s2_anom24 if wave == 2024
* EA-season: EA x district x round (households that moved are not grouped
* with the village they left)
egen long ear = group(ea_id district wave)
foreach v in evi_anom evi_max spi12 hot30 s2_anom {
	bysort ear: egen double ea_`v' = mean(`v')
}
gen double hot10 = hot30 / 10
bysort ear: egen double ea_hot10 = mean(hot10)

tempname m
postfile `m' str40 outcome str60 stat double value using "$DER/measurement.dta", replace
foreach y in u_t lnyield {
	quietly summarize `y'
	local vt = r(Var)
	bysort ear: egen double ea_`y' = mean(`y')
	gen double w_`y' = `y' - ea_`y'
	quietly summarize ea_`y'
	local vb = r(Var)
	quietly summarize w_`y'
	local vw = r(Var)
	post `m' ("`y'") ("share of variance between EA-seasons") (`vb' / `vt')
	post `m' ("`y'") ("share of variance within EA-seasons") (`vw' / `vt')
	* EA-season level: satellite vigour and weather (one row per EA-season)
	preserve
	bysort ear: keep if _n == 1
	* both R2 on the EA-seasons with satellite and weather measures
	keep if !missing(ea_evi_anom, ea_spi12, ea_hot10, ea_`y')
	quietly regress ea_`y' ea_evi_anom ea_spi12 ea_hot10 i.wave
	local r2_all = e(r2)
	quietly regress ea_`y' i.wave
	local r2_w = e(r2)
	quietly regress ea_`y' ea_evi_anom ea_spi12 ea_hot10 i.wave, vce(cluster ea_id)
	post `m' ("`y'") ("EA-seasons") (e(N))
	post `m' ("`y'") ("R2 of satellite and weather beyond round effects") ((`r2_all' - `r2_w') / (1 - `r2_w'))
	foreach v in ea_evi_anom ea_spi12 ea_hot10 {
		post `m' ("`y'") ("coef `v'") (_b[`v'])
		post `m' ("`y'") ("se `v'") (_se[`v'])
	}
	* 2024: Sentinel-2 anomaly
	quietly regress ea_`y' ea_s2_anom if wave == 2024, robust
	post `m' ("`y'") ("2024: coef Sentinel-2 anomaly") (_b[ea_s2_anom])
	post `m' ("`y'") ("2024: se Sentinel-2 anomaly") (_se[ea_s2_anom])
	post `m' ("`y'") ("2024: R2 Sentinel-2 anomaly") (e(r2))
	quietly corr ea_`y' ea_evi_max
	post `m' ("`y'") ("corr with EVI maximum (EA-seasons)") (r(rho))
	restore
	* household level: within-EA variation of the satellite measures is small
	quietly summarize evi_anom
	local ve = r(Var)
	quietly summarize ea_evi_anom
	post `m' ("`y'") ("share of EVI anomaly variance between EA-seasons") (r(Var) / `ve')
	* share of total variance confirmed by satellites and weather: between
	* share times the variance share of the EA-season means that vigour and
	* weather explain beyond round effects (gain in R2, not the partial R2,
	* which would also count the variance absorbed by the round effects)
	post `m' ("`y'") ("R2 of round effects") (`r2_w')
	post `m' ("`y'") ("share of total variance confirmed from space") ((`vb' / `vt') * (`r2_all' - `r2_w'))
	drop ea_`y' w_`y'
}
postclose `m'
use "$DER/measurement.dta", clear
export delimited using "$EXT/measurement.csv", replace
list, noobs clean
