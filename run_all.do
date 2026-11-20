*==============================================================================
* run_all.do -- replication package for
*   "Targeting Input Subsidies with Satellites and Machine Learning:
*    Evidence from Malawi"
*
* Runs every step from the raw data to the tables, figures and numbers of the
* paper (output/paper/tables, output/paper/numbers.tex, output/results).
*
* Usage: start Stata 18, cd to the package root (the folder that holds this
* file), adjust the settings below if needed, then:   do run_all.do
* Steps can be skipped with e.g.  global SKIP_13 1  before running.
* See README.md for the data, the software and the run time of each step.
*==============================================================================
version 18
clear all
set more off
set varabbrev off
set maxvar 10000

*------------------------------------------------------------------------------
* settings
*------------------------------------------------------------------------------
* folder with the licensed data that the package cannot redistribute (World
* Bank IHPS files, IHS conversion factors, household panel identifiers, GADM
* boundaries); default: data/raw of the package (see README, Data availability)
if "$RESTRICTED" == "" global RESTRICTED "`c(pwd)'/data/raw"
* R 4.5 (Rscript)
if "$RSCRIPT" == "" {
	global RSCRIPT "C:/Program Files/R/R-4.5.2/bin/Rscript.exe"
	capture confirm file "`: env LOCALAPPDATA'/Programs/R/R-4.5.2/bin/Rscript.exe"
	if !_rc global RSCRIPT "`: env LOCALAPPDATA'/Programs/R/R-4.5.2/bin/Rscript.exe"
}
* bootstrap draws of the structural simulations (paper: 500)
if "$SIM_BOOT" == "" global SIM_BOOT 500

*------------------------------------------------------------------------------
* paths
*------------------------------------------------------------------------------
global ROOT "`c(pwd)'"
capture confirm file "$ROOT/run_all.do"
if _rc {
	di as error "Run this file from the package root (the folder with run_all.do, code/ and data/)."
	exit 601
}
global CODE "$ROOT/code"
global DER  "$ROOT/data/derived"
global EXT  "$ROOT/output/results"
global LOG  "$ROOT/output/logs"
global TAB  "$ROOT/output/results"
global FIG  "$ROOT/output/results"
global RAW  "$RESTRICTED/ihps"
global CONV "$RESTRICTED/conversion"
global MAPS "$RESTRICTED/maps"
foreach d in "$ROOT/data/derived" "$ROOT/output" "$EXT" "$LOG" "$ROOT/output/paper" "$ROOT/output/paper/tables" {
	capture mkdir "`d'"
}
adopath ++ "$CODE/ado"

* survey rounds: 2010 and 2013 from the IHPS 2010-2013 short-term panel,
* 2016, 2019 and 2024 from the long-term panel
global WAVES "2010 2013 2016 2019 2024"
global DIR2010 "$RESTRICTED/ihps"
global DIR2013 "$RESTRICTED/ihps"
global DIR2016 "$RESTRICTED/ihps_long"
global DIR2019 "$RESTRICTED/ihps_long"
global DIR2024 "$RESTRICTED/ihps_long"
global KEY2010 "case_id"
global KEY2013 "y2_hhid"
global KEY2016 "y3_hhid"
global KEY2019 "y4_hhid"
global KEY2024 "y5_hhid"
global GEO2010 "HouseholdGeovariables_IHS3_Rerelease_10"
global GEO2013 "HouseholdGeovariables_IHPS_13"
global GEO2016 "HouseholdGeovariablesIHPSY3"
global GEO2019 "householdgeovariables_y4"
global GEO2024 ""
global COM2010 "COM_CK_10"
global COM2013 "COM_MOD_K_13"
global COM2016 ""
global COM2019 "com_ck_19"
global COM2024 "com_ck_24"
* rainfall shock of the frontier: 12-month SPI from CHIRPS
global SPI_SOURCE "chirps"
set seed 20171105
set sortseed 20171105

*------------------------------------------------------------------------------
* helpers: R steps (through a batch file, so that paths with
* spaces survive Windows' command line); the step fails if its key output is
* missing afterwards or its log reports an error
*------------------------------------------------------------------------------
capture program drop run_ext
program define run_ext
	* run_ext R <script> <output that must exist afterwards> [extra argument]
	args kind script check extra
	* Windows paths with backslashes; Rscript is quoted
	local root = subinstr("$ROOT", "/", "\", .)
	local scr = subinstr("$CODE/`script'", "/", "\", .)
	local lg = subinstr("$LOG/`script'.log", "/", "\", .)
	local bat = subinstr("$LOG/_run_`script'.bat", "/", "\", .)
	local exe = `"""' + subinstr("$RSCRIPT", "/", "\", .) + `"""'
	local ex = subinstr(`"`extra'"', "/", "\", .)
	tempname fh
	file open `fh' using "`bat'", write replace text
	file write `fh' "@echo off" _n "cd /d " `"""' "`root'" `"""' _n
	file write `fh' `"`exe' ""' "`scr'" `"" ""' "`root'" `"""'
	if `"`extra'"' != "" file write `fh' `" ""' `"`ex'"' `"""'
	file write `fh' " > " `"""' "`lg'" `"""' " 2>&1" _n
	file close `fh'
	di as txt "running `script' ($S_TIME)"
	capture erase "`check'"
	shell "`bat'"
	capture confirm file "`check'"
	if _rc {
		di as error "`script' did not write `check': see $LOG/`script'.log"
		exit 601
	}
	* a script that stops with an error after writing its check file fails too
	tempname lf
	file open `lf' using "$LOG/`script'.log", read text
	file read `lf' line
	while r(eof) == 0 {
		if strpos(`"`macval(line)'"', "Execution halted") | strpos(`"`macval(line)'"', "Traceback") | ///
			substr(`"`macval(line)'"', 1, 6) == "Error:" | substr(`"`macval(line)'"', 1, 7) == "failed:" {
			file close `lf'
			di as error "`script' stopped with an error: see $LOG/`script'.log"
			exit 601
		}
		file read `lf' line
	}
	file close `lf'
end

capture program drop run_do
program define run_do
	* run_do <do-file without extension>
	args f
	di as txt _n "{hline 78}" _n "`f'  ($S_TIME)" _n "{hline 78}"
	capture log close step
	* LOGSFX: suffix for parallel runs of one step (e.g. "_iv" with S2_PART iv)
	log using "$LOG/`f'$LOGSFX.log", replace text name(step)
	do "$CODE/`f'.do"
	log close step
end

*------------------------------------------------------------------------------
* steps
*------------------------------------------------------------------------------
* district boundaries for the maps (once): GADM 4.1 level 1 -> shapefile
capture confirm file "$RESTRICTED/maps/mwi_districts.shp"
if _rc & "$SKIP_00" != "1" run_ext R 00_prepare_district_map.R "$RESTRICTED/maps/mwi_districts.shp" "$RESTRICTED/maps"

* data: household and agriculture variables of every round, the panel, the
* satellite features at the survey locations (extracts of code/gee shipped in
* data/raw/satellite), and the four-component panel frontier
foreach f in 01_build_household 02_build_agriculture 03_build_panel 04_export_coordinates 05_merge_satellite 06_panel_frontier {
	if "${SKIP_`=substr("`f'", 1, 2)'}" != "1" run_do `f'
}
* yield prediction and the efficiency check (machine learning)
if "$SKIP_07" != "1" {
	run_ext R 07_yield_prediction.R "$EXT/targeting_benchmark.csv"
	run_ext R 07b_yield_prediction_figures.R "$EXT/fig_ml_benchmark.pdf"
}
* delivery, causal forest and allocation rules, satellite targeting,
* measurement
if "$SKIP_08" != "1" run_do 08_allocation_leakage
if "$SKIP_09" != "1" run_ext R 09_causal_forest_rules.R "$DER/rule_assignment.csv"
if "$SKIP_10" != "1" run_ext R 10_grid_predictions.R "$EXT/fig_returns_map.pdf" "$RESTRICTED"
if "$SKIP_11" != "1" run_ext R 11_satellite_targeting.R "$EXT/satellite_toc.csv"
if "$SKIP_12" != "1" run_do 12_measurement
* demand system (four specifications; see README for running them in
* parallel) and the structural models
if "$SKIP_13" != "1" run_do 13_demand_system
if "$SKIP_14" != "1" {
	global SIM_MODEL "conventional"
	run_do 14_structural_allrounds
}
if "$SKIP_15" != "1" run_do 15_joint_structural
if "$SKIP_16" != "1" run_ext R 16_structural_figure.R "$EXT/fig_structural.pdf"
* tables and numbers of the paper
if "$SKIP_17" != "1" run_do 17_paper_tables
di as res _n "done ($S_TIME): tables and numbers in output/paper, figures and results in output/results"
