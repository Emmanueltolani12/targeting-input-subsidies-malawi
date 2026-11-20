*==============================================================================
* 05_merge_satellite.do -- satellite covariates
* Adds the Earth Engine covariates (gee/gee_household_points.py) to every
* household-round of all_waves_panel.dta. The sources of each covariate are
* listed in code/gee/gee_household_points.py and README.md.
* Output: data/derived/all_waves_panel_sat.dta
*==============================================================================

import delimited using "$ROOT/data/raw/satellite/ext_satellite_points.csv", clear varnames(1)
rename spi spi_chirps
tempfile sat
save `sat'

use "$DER/all_waves_panel.dta", clear
merge 1:1 wave hhkey using "$DER/ext_point_xwalk.dta", keepusing(pid loc_carried) keep(master match) nogen
merge m:1 pid wave using `sat', keep(master match) nogen

label var rain_season "Rainy-season rainfall Nov-Apr (mm, CHIRPS)"
label var rain_days   "Rainy days > 1 mm Nov-Apr (CHIRPS)"
label var spi_chirps  "SPI of the season total (gamma, 1981/82-2023/24)"
label var tmax        "Mean daily maximum temperature Dec-Mar (deg C, ERA5-Land)"
label var hot30       "Days with maximum temperature > 30 C, Dec-Mar"
label var gdd         "Growing degree days Nov-Apr (base 10, cap 30)"
label var evi_max     "Seasonal maximum EVI, cropland (MODIS)"
label var evi_mean    "Seasonal mean EVI Dec-Apr, cropland"
label var evi_anom    "Seasonal maximum EVI minus 2001-2024 mean"
label var soc         "Soil organic carbon 0-20 cm (g/kg, iSDAsoil)"
label var ntot        "Soil total nitrogen 0-20 cm (g/kg)"
label var ph          "Soil pH 0-20 cm"
label var clay        "Clay content 0-20 cm (%)"
label var sand        "Sand content 0-20 cm (%)"
label var travel_min  "Travel time to nearest city (minutes, 2015)"
label var crop_share  "Cropland share within 5 km (WorldCover 2021)"
label var loc_carried "Location carried over from an earlier round"
gen byte spi_dry = spi_chirps < -1 if !missing(spi_chirps)
gen byte spi_wet = spi_chirps > 1.5 if !missing(spi_chirps)
label var spi_dry "Drought season (SPI < -1)"
label var spi_wet "Positive rainfall shock (SPI > 1.5), as in the paper"

compress
* fixed row order (the R steps assign cross-validation folds by order of
* appearance)
sort wave hhkey
save "$DER/all_waves_panel_sat.dta", replace
tabstat rain_season spi_chirps spi_wet tmax hot30 gdd evi_max evi_anom soc ph clay travel_min crop_share, ///
	by(wave) statistics(mean) format(%9.2f) columns(statistics) longstub
* the survey's own rainfall anomaly against the CHIRPS SPI (both reference seasons)
pwcorr spi_chirps spi spi_shock spi_wet if inlist(wave, 2010, 2013), obs
