*==============================================================================
* 04_export_coordinates.do -- survey locations for the satellite covariates
* One point per household-round with the survey's displaced coordinates
* (EA level in 2010, household level 2013-2019); 2024 has no geovariable file,
* so the household's 2019 location is used (else 2016, else its EA mean).
* Output: data/derived/ext_points.csv (pid, lat, lon: unique points)
*         data/derived/ext_point_xwalk.dta (wave, hhkey, pid)
* Data: displaced coordinates in the IHPS geovariable files (https://microdata.worldbank.org/index.php/catalog/2248,
* https://microdata.worldbank.org/index.php/catalog/2939, https://microdata.worldbank.org/index.php/catalog/3819).
* Run through run_all.do, which sets the globals.
*==============================================================================

tempfile g
use "$RAW/HouseholdGeovariables_IHS3_Rerelease_10.dta", clear
gen str12 hhkey = case_id
gen double lat = lat_modified
gen double lon = lon_modified
gen int wave = 2010
keep wave hhkey lat lon
save `g'
use "$RAW/HouseholdGeovariables_IHPS_13.dta", clear
gen str12 hhkey = y2_hhid
gen double lat = LAT_DD_MOD
gen double lon = LON_DD_MOD
gen int wave = 2013
keep wave hhkey lat lon
append using `g'
save `g', replace
use "${DIR2016}/HouseholdGeovariablesIHPSY3.dta", clear
gen str12 hhkey = y3_hhid
gen double lat = lat_modified
gen double lon = lon_modified
gen int wave = 2016
keep wave hhkey lat lon
append using `g'
save `g', replace
use "${DIR2019}/householdgeovariables_y4.dta", clear
gen str12 hhkey = y4_hhid
gen double lat = lat_mod
gen double lon = lon_mod
gen int wave = 2019
keep wave hhkey lat lon
append using `g'
save `g', replace

* households of every round, with links to earlier rounds
use "$DER/all_waves_panel.dta", clear
keep wave hhkey y3_hhid y4_hhid ea_id
merge 1:1 wave hhkey using `g', keep(master match) nogen
* 2024: location of the same household in 2019, else 2016
preserve
use `g', clear
keep if wave == 2019
rename (hhkey lat lon) (y4_hhid lat19 lon19)
drop wave
tempfile l19
save `l19'
use `g', clear
keep if wave == 2016
rename (hhkey lat lon) (y3_hhid lat16 lon16)
drop wave
tempfile l16
save `l16'
restore
merge m:1 y4_hhid using `l19', keep(master match) nogen
merge m:1 y3_hhid using `l16', keep(master match) nogen
replace lat = lat19 if wave == 2024 & missing(lat)
replace lon = lon19 if wave == 2024 & missing(lon)
replace lat = lat16 if wave == 2024 & missing(lat)
replace lon = lon16 if wave == 2024 & missing(lon)
* remaining gaps: EA mean of the same round, else of all rounds
bysort wave ea_id: egen double mlat = mean(lat)
bysort wave ea_id: egen double mlon = mean(lon)
replace lat = mlat if missing(lat)
replace lon = mlon if missing(lon)
bysort ea_id: egen double alat = mean(lat)
bysort ea_id: egen double alon = mean(lon)
replace lat = alat if missing(lat)
replace lon = alon if missing(lon)
gen byte loc_carried = wave == 2024
drop lat19 lon19 lat16 lon16 mlat mlon alat alon
tab wave, summarize(lat)
count if missing(lat)

* unique points (coordinates rounded to 1e-5 degrees)
gen double rlat = round(lat, 0.00001)
gen double rlon = round(lon, 0.00001)
egen long pid = group(rlat rlon) if !missing(rlat, rlon)
preserve
keep pid rlat rlon
drop if missing(pid)
duplicates drop pid, force
rename (rlat rlon) (lat lon)
format lat lon %12.5f
export delimited using "$DER/ext_points.csv", replace datafmt
di as res "unique points: " _N
restore
keep wave hhkey pid lat lon loc_carried
save "$DER/ext_point_xwalk.dta", replace
