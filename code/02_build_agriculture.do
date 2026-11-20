*==============================================================================
* 02_build_agriculture.do
* Rainy-season agriculture variables for every IHPS wave in $WAVES with the
* same definitions; question numbering that changed between rounds is mapped
* explicitly below (plot keys, harvest, fertiliser, labour, tenure, purchase
* and coupon modules).
*   plots: area, soil type/quality, erosion control, tenure, inputs, labour
*   crops: maize harvest (kg), maize seed, modern varieties, Shannon index of
*          crop areas, value of crop production (income)
*   commercial purchases (F, H): maize seed, chitowe/NPK, urea, other
*          fertilisers, other seeds (kg, MK); pesticides and manure (MK)
*   input subsidies (E): FISP coupons 2010-2019, Affordable Inputs Programme
*          (AIP) inputs 2024 -- receipt, number, kg, redemption cost
*   livestock sales (R1)
* Output: $DER/ag_<wave>.dta, key = $KEY<wave>
* Data (World Bank Microdata Library, free registration; not redistributed):
*   2010, 2013  IHPS 2010-2013 short-term panel, https://microdata.worldbank.org/index.php/catalog/2248
*   2016        IHPS 2010-2013-2016 long-term panel, https://microdata.worldbank.org/index.php/catalog/2939
*   2019        IHPS 2010-2013-2016-2019 long-term panel, https://microdata.worldbank.org/index.php/catalog/3819
*   2024        IHPS 2024 (long-term panel and sample refresh), https://microdata.worldbank.org/index.php/catalog/8520
*   unit conversion factors (2020), distributed with the 2019 panel above
*               (https://microdata.worldbank.org/index.php/catalog/3819) and IHS5 (https://microdata.worldbank.org/index.php/catalog/3818)
*==============================================================================

* crop conversion factors (region x crop x unit x condition -> kg)
use "$CONV/ihs_seasonalcropconversion_factor_2020.dta", clear
keep region crop_code unit_code condition conversion
drop if missing(conversion) | conversion <= 0
collapse (mean) conversion, by(region crop_code unit_code condition)
save "$DER/tmp_ccf.dta", replace
collapse (median) conv_cu = conversion, by(crop_code unit_code)
save "$DER/tmp_ccf2.dta", replace

capture program drop mkplot
program define mkplot
	* builds string plot key "plot" from one id or garden + plot ids
	args a b
	foreach v in `a' `b' {
		capture confirm string variable `v'
		if _rc tostring `v', gen(`v'_s) force
		else gen `v'_s = `v'
		replace `v'_s = upper(strtrim(`v'_s))
	}
	if "`b'" == "" gen plot = `a'_s
	else gen plot = `a'_s + "_" + `b'_s
	drop `a'_s
	if "`b'" != "" drop `b'_s
end

capture program drop txtlab
program define txtlab
	* upper-case text of a (labelled numeric or string) variable
	args v out
	capture confirm variable `v', exact
	if _rc | "`v'" == "" {
		gen `out' = ""
		exit
	}
	capture confirm string variable `v'
	if !_rc gen `out' = upper(strtrim(`v'))
	else {
		capture decode `v', gen(`out')
		if _rc gen `out' = string(`v')
		replace `out' = upper(`out')
	}
end

foreach w of global WAVES {
	local s = substr("`w'", 3, 2)
	local D "${DIR`w'}"
	local k "${KEY`w'}"
	local new = `w' >= 2016
	di as txt _n "================ agriculture build: wave `w' ================"
	use "$DER/tmp_ids_`w'.dta", clear
	keep `k' region ea_id district
	tempfile reg
	save `reg'

	*--------------------------------------------------------------------------
	* A. Plot areas (module C)
	*--------------------------------------------------------------------------
	use "`D'/ag_mod_c_`s'.dta", clear
	if `new' mkplot gardenid plotid
	else mkplot ag_c00
	gen double area_gps = ag_c04c * 0.404686 if ag_c04c > 0
	gen double f = cond(ag_c04b == 1, 0.404686, cond(ag_c04b == 2, 1, cond(ag_c04b == 3, 0.0001, .)))
	gen double area_est = ag_c04a * f if ag_c04a > 0
	gen double area_ha = cond(!missing(area_gps), area_gps, area_est)
	keep `k' plot area_ha
	drop if plot == "" | plot == "."
	duplicates drop `k' plot, force
	tempfile area
	save `area'

	*--------------------------------------------------------------------------
	* B. Crops on plots (module G)
	*--------------------------------------------------------------------------
	use "`D'/ag_mod_g_`s'.dta", clear
	if `w' == 2010 {
		mkplot ag_g0b
		gen crop_code = ag_g0d
	}
	else if `w' == 2013 {
		mkplot ag_g00
		gen crop_code = ag_g0b
	}
	else mkplot gardenid plotid
	drop if missing(crop_code) | plot == ""
	merge m:1 `k' using `reg', keep(match) nogen
	merge m:1 `k' plot using `area', keep(master match) nogen
	* harvest (2016+: G13 = completed harvest; earlier rounds: G09); expected
	* harvest (G08) if the harvest was not completed
	if `new' {
		gen double q = ag_g13a
		gen ucode = ag_g13b
		gen cond = ag_g13c
		capture confirm variable ag_g09a, exact
		if !_rc {
			replace ucode = ag_g09b if missing(q) | q == 0
			replace cond  = ag_g09c if missing(q) | q == 0
			replace q     = ag_g09a if missing(q) | q == 0
		}
	}
	else {
		gen double q = ag_g09a
		gen ucode = ag_g09b
		gen cond = ag_g09c
	}
	replace ucode = ag_g08b if missing(q) | q == 0
	replace cond  = ag_g08c if missing(q) | q == 0
	replace q     = ag_g08a if missing(q) | q == 0
	gen unit_code = string(ucode)
	gen condition = cond
	merge m:1 region crop_code unit_code condition using "$DER/tmp_ccf.dta", keep(master match) nogen
	merge m:1 crop_code unit_code using "$DER/tmp_ccf2.dta", keep(master match) nogen
	replace conversion = conv_cu if missing(conversion)
	replace conversion = 1  if missing(conversion) & ucode == 1
	replace conversion = 50 if missing(conversion) & ucode == 2
	replace conversion = 90 if missing(conversion) & ucode == 3
	gen double harv_kg = q * conversion
	kgunit ag_g04b, gen(fs) type(seed)
	gen double seed_kg = ag_g04a * fs
	gen double frac = 1 if ag_g02 == 1
	replace frac = 0.125 if ag_g03 == 1 & ag_g02 != 1
	replace frac = 0.25  if ag_g03 == 2 & ag_g02 != 1
	replace frac = 0.5   if ag_g03 == 3 & ag_g02 != 1
	replace frac = 0.75  if ag_g03 == 4 & ag_g02 != 1
	replace frac = 0.875 if ag_g03 == 5 & ag_g02 != 1
	replace frac = 0.5   if missing(frac)
	gen double crop_area = area_ha * frac
	gen byte maize = inrange(crop_code, 1, 4)
	gen byte mv_row = inlist(crop_code, 2, 3)
	keep `k' plot crop_code region district ea_id harv_kg seed_kg crop_area maize mv_row
	save "$DER/tmp_crops_`w'.dta", replace

	preserve
	keep if maize
	collapse (sum) maize_kg = harv_kg maize_seed_kg = seed_kg (max) mv = mv_row, by(`k' plot)
	gen byte maize_plot = 1
	tempfile mplots
	save `mplots'
	restore

	preserve
	collapse (sum) crop_area, by(`k' crop_code)
	bysort `k': egen double tot = total(crop_area)
	gen double sh = crop_area / tot
	gen double sl = -sh * ln(sh) if sh > 0
	collapse (sum) shannon = sl (count) n_crops = crop_area, by(`k')
	tempfile shan
	save `shan'
	restore

	* crop prices: median unit value of sales (module I)
	use "`D'/ag_mod_i_`s'.dta", clear
	merge m:1 `k' using `reg', keep(match) nogen
	if `new' == 0 gen crop_code = ag_i0b
	gen unit_code = string(ag_i02b)
	gen condition = ag_i02c
	merge m:1 region crop_code unit_code condition using "$DER/tmp_ccf.dta", keep(master match) nogen
	merge m:1 crop_code unit_code using "$DER/tmp_ccf2.dta", keep(master match) nogen
	replace conversion = conv_cu if missing(conversion)
	replace conversion = 1 if missing(conversion) & ag_i02b == 1
	gen double uv = ag_i03 / (ag_i02a * conversion) if ag_i02a > 0 & ag_i03 > 0
	tempfile cp_d cp_r cp_n
	preserve
	collapse (median) pm_district = uv (count) n_district = uv, by(crop_code district)
	save `cp_d'
	restore
	preserve
	collapse (median) pm_region = uv (count) n_region = uv, by(crop_code region)
	save `cp_r'
	restore
	collapse (median) pm_nat = uv, by(crop_code)
	save `cp_n'
	use "$DER/tmp_crops_`w'.dta", clear
	merge m:1 crop_code district using `cp_d', keep(master match) nogen
	merge m:1 crop_code region using `cp_r', keep(master match) nogen
	merge m:1 crop_code using `cp_n', keep(master match) nogen
	gen double pcrop = pm_district if n_district >= 3
	replace pcrop = pm_region if missing(pcrop) & n_region >= 3
	replace pcrop = pm_nat if missing(pcrop)
	gen double crop_value = harv_kg * pcrop
	gen double pmaize_ = pcrop if maize
	collapse (sum) inc_crop = crop_value (mean) p_maize = pmaize_, by(`k')
	tempfile cval
	save `cval'

	*--------------------------------------------------------------------------
	* C. Tenure (2010/2013: plot module D; 2016+: garden roster B2)
	*--------------------------------------------------------------------------
	if `new' {
		use "`D'/ag_mod_b2_`s'.dta", clear
		* "How did your household acquire this garden?" (unlabelled in 2019)
		pickvar acq : ag_b203
		if "`acq'" == "" {
			di as error "wave `w': tenure question not found in ag_mod_b2"
			gen tenure_s = ""
		}
		else txtlab `acq' tenure_s
		noisily tab tenure_s, m
		* soil type / quality are asked at garden level in some rounds
		labvar stv "soil type"
		labvar sqv "soil quality"
		txtlab "`stv'" st_b2
		txtlab "`sqv'" sq_b2
		capture confirm string variable gardenid
		if _rc tostring gardenid, replace force
		replace gardenid = upper(strtrim(gardenid))
		keep `k' gardenid tenure_s st_b2 sq_b2
		duplicates drop `k' gardenid, force
		tempfile tenure
		save `tenure'
	}

	*--------------------------------------------------------------------------
	* D. Plot details and inputs (module D)
	*--------------------------------------------------------------------------
	use "`D'/ag_mod_d_`s'.dta", clear
	if `new' {
		mkplot gardenid plotid
		capture confirm string variable gardenid
		if _rc tostring gardenid, replace force
		replace gardenid = upper(strtrim(gardenid))
		merge m:1 `k' gardenid using `tenure', keep(master match) nogen
		* fertiliser: 1st application a/b/c/d, 2nd application g/h/i/j
		local f1 "ag_d39a ag_d39b ag_d39c ag_d39d"
		local f2 "ag_d39g ag_d39h ag_d39i ag_d39j"
	}
	else {
		mkplot ag_d00
		txtlab ag_d03 tenure_s
		* fertiliser: 1st type a, qty b, unit c, kg d; 2nd type f, qty g, unit h, kg i
		local f1 "ag_d39a ag_d39b ag_d39c ag_d39d"
		local f2 "ag_d39f ag_d39g ag_d39h ag_d39i"
	}
	drop if plot == ""
	duplicates drop `k' plot, force
	merge 1:1 `k' plot using `area', keep(master match) nogen
	merge 1:1 `k' plot using `mplots', keep(master match) nogen
	replace maize_plot = 0 if missing(maize_plot)
	* organic fertiliser (kg)
	gen double fo = cond(ag_d37b == 2, 1, cond(ag_d37b == 10, 10.75, cond(ag_d37b == 11, 80, cond(ag_d37b == 12, 800, .))))
	gen double organic_kg = cond(ag_d36 == 1, ag_d37a * fo, 0)
	replace organic_kg = 0 if missing(organic_kg)
	* inorganic fertiliser by type (kg)
	foreach t in chitowe urea otherfert {
		gen double `t'_kg = 0
	}
	foreach j in 1 2 {
		local ty : word 1 of `f`j''
		local qq : word 2 of `f`j''
		local uu : word 3 of `f`j''
		local kk : word 4 of `f`j''
		txtlab `ty' tyl`j'
		kgunit `uu', gen(fk`j') type(fert)
		gen double kg`j' = `kk'
		replace kg`j' = `qq' * fk`j' if missing(kg`j') | kg`j' == 0
		gen tcat`j' = cond(ustrregexm(tyl`j', "CHITOWE|23:21|NPK"), 1, cond(strpos(tyl`j', "UREA"), 2, cond(tyl`j' != "" & tyl`j' != ".", 3, .)))
		replace chitowe_kg   = chitowe_kg   + kg`j' if tcat`j' == 1 & kg`j' < .
		replace urea_kg      = urea_kg      + kg`j' if tcat`j' == 2 & kg`j' < .
		replace otherfert_kg = otherfert_kg + kg`j' if tcat`j' == 3 & kg`j' < .
	}
	* labour (person-days): household members, hired, exchange
	gen double lab_fam = 0
	foreach b in 42 43 44 {
		if `new' {
			forvalues i = 1/13 {
				capture replace lab_fam = lab_fam + ag_d`b'b`i' * ag_d`b'c`i' if ag_d`b'b`i' < . & ag_d`b'c`i' < .
			}
		}
		else {
			foreach p in "b c" "f g" "j k" "n o" {
				local wk : word 1 of `p'
				local dy : word 2 of `p'
				capture replace lab_fam = lab_fam + ag_d`b'`wk' * ag_d`b'`dy' if ag_d`b'`wk' < . & ag_d`b'`dy' < .
			}
		}
	}
	gen double lab_hired = 0
	if `new' local hv ag_d46a1 ag_d46a2 ag_d46a3 ag_d47a1 ag_d47a2 ag_d47a3 ag_d48a1 ag_d48a2 ag_d48a3
	else     local hv ag_d47a ag_d47c ag_d47e ag_d48a ag_d48c ag_d48e
	foreach v of local hv {
		capture replace lab_hired = lab_hired + `v' if `v' < .
	}
	gen double lab_exch = 0
	foreach v in ag_d52a ag_d52b ag_d52c ag_d54a ag_d54b ag_d54c {
		capture replace lab_exch = lab_exch + `v' if `v' < .
	}
	gen double labour = lab_fam + lab_hired + lab_exch
	* plot attributes (classified by answer text: codes differ across rounds)
	gen byte owned = ustrregexm(tenure_s, "GRANTED|INHERIT|BRIDE|PURCHASED|LEASEHOLD|CUSTOMARY|ALLOCATED") if tenure_s != "" & tenure_s != "."
	replace owned = 0 if ustrregexm(tenure_s, "RENT|TENANT|BORROW|WITHOUT PERMISSION|W/O PERMISSION|SHARECROP")
	* unlabelled codes (same code list as 2010): 1-6 owned, 7-10 rented/borrowed
	replace owned = inrange(real(tenure_s), 1, 6) if !missing(real(tenure_s)) & real(tenure_s) <= 10
	txtlab ag_d25a ec1
	txtlab ag_d25b ec2
	gen byte erosion_ctrl = (ec1 != "" & ec1 != "." & !strpos(ec1, "NO ")) | (ec2 != "" & ec2 != "." & !strpos(ec2, "NO "))
	txtlab ag_d21 st_s
	txtlab ag_d22 sq_s
	if `new' {
		replace st_s = st_b2 if inlist(st_s, "", ".")
		replace sq_s = sq_b2 if inlist(sq_s, "", ".")
	}
	gen soiltype = cond(strpos(st_s, "BETWEEN") | strpos(st_s, "MIX") | strpos(st_s, "LOAM"), 2, cond(strpos(st_s, "CLAY"), 3, cond(strpos(st_s, "SAND"), 1, .)))
	gen soilqual = cond(strpos(sq_s, "GOOD"), 1, cond(strpos(sq_s, "FAIR"), 2, cond(strpos(sq_s, "POOR"), 3, .)))
	* cultivated plots: plots with crops in module G
	gen byte cult = maize_plot == 1
	merge 1:m `k' plot using "$DER/tmp_crops_`w'.dta", keepusing(`k') keep(master match)
	replace cult = 1 if _merge == 3
	drop _merge
	duplicates drop `k' plot, force
	keep if cult == 1
	replace area_ha = . if area_ha <= 0
	gen double aw = area_ha
	bysort `k': egen double aw_mean = mean(area_ha)
	replace aw = aw_mean if missing(aw)
	replace aw = 1 if missing(aw)
	foreach c in 1 2 3 {
		gen double st`c' = aw * (soiltype == `c')
		gen double sq`c' = aw * (soilqual == `c')
	}
	gen double own_a = aw * owned
	gen double aw_own = aw if !missing(owned)
	foreach v in area_ha organic_kg chitowe_kg urea_kg otherfert_kg labour {
		gen double m_`v' = `v' * maize_plot
	}
	collapse (sum) area_cult = area_ha area_maize = m_area_ha ///
		organic_kg = m_organic_kg chitowe_kg = m_chitowe_kg urea_kg = m_urea_kg ///
		otherfert_kg = m_otherfert_kg labour = m_labour ///
		maize_kg maize_seed_kg st1 st2 st3 sq1 sq2 sq3 own_a aw_own ///
		(max) mv antierosion = erosion_ctrl (count) n_plots = aw, by(`k')
	gen double landowner = own_a / aw_own
	egen double stmax = rowmax(st1 st2 st3)
	gen soil_type = cond(st1 == stmax & stmax > 0, 1, cond(st2 == stmax & stmax > 0, 2, cond(st3 == stmax & stmax > 0, 3, .)))
	egen double sqmax = rowmax(sq1 sq2 sq3)
	gen soil_quality = cond(sq1 == sqmax & sqmax > 0, 1, cond(sq2 == sqmax & sqmax > 0, 2, cond(sq3 == sqmax & sqmax > 0, 3, .)))
	label define soiltype 1 "Sandy" 2 "Mixed" 3 "Clay", replace
	label define soilqual 1 "Good" 2 "Fair" 3 "Poor", replace
	label values soil_type soiltype
	label values soil_quality soilqual
	drop st1-st3 sq1-sq3 stmax sqmax own_a aw_own
	merge 1:1 `k' using `shan', keep(master match) nogen
	merge 1:1 `k' using `cval', keep(master match) nogen
	tempfile plots
	save `plots'

	*--------------------------------------------------------------------------
	* E. Commercial purchases: fertiliser (module F) and seed (module H)
	*    2010-2019: up to three sources (16/26/36, values 19/29);
	*    2024: one total (07a/b, value 10)
	*--------------------------------------------------------------------------
	tempfile fpur
	foreach mod in f h {
		use "`D'/ag_mod_`mod'_`s'.dta", clear
		if "`mod'" == "f" {
			if `w' == 2013 {
				txtlab ag_f0d lab
				replace lab = "ORGANIC" if lab == "" & strpos(upper(ag_f00b), "ORGANIC")
			}
			else txtlab ag_f0c lab
			local kt fert
		}
		else {
			if `w' == 2010      txtlab ag_h0b lab
			else if `w' == 2013 txtlab ag_h0c lab
			else                txtlab crop_code lab
			local kt seed
		}
		local i 0
		foreach src in 16 26 36 07 {
			capture confirm numeric variable ag_`mod'`src'a ag_`mod'`src'b, exact
			if !_rc {
				local ++i
				kgunit ag_`mod'`src'b, gen(u`i') type(`kt')
				gen double q`i' = ag_`mod'`src'a * u`i'
			}
		}
		gen double v1 = .
		gen double v2 = .
		foreach vv in 19 10 {
			capture confirm numeric variable ag_`mod'`vv', exact
			if !_rc replace v1 = ag_`mod'`vv' if missing(v1)
		}
		capture confirm numeric variable ag_`mod'29, exact
		if !_rc replace v2 = ag_`mod'29
		forvalues j = 1/3 {
			capture confirm variable q`j'
			if _rc gen double q`j' = .
		}
		gen double uv1 = v1 / q1 if q1 > 0 & v1 > 0
		gen double v3 = q3 * uv1 if q3 > 0
		egen double com_kg  = rowtotal(q1 q2 q3) if ag_`mod'04 == 1
		egen double com_val = rowtotal(v1 v2 v3) if ag_`mod'04 == 1
		replace com_kg = 0 if missing(com_kg)
		replace com_val = 0 if missing(com_val)
		gen str9 good = ""
		if "`mod'" == "f" {
			replace good = "othfert" if ustrregexm(lab, "DAP|CAN|COMPOUND|SUPER|FERTILI|AMMON|SULPHATE|NITRATE|POTASH")
			replace good = "chitowe" if ustrregexm(lab, "CHITOWE|23:21|NPK")
			replace good = "urea"    if strpos(lab, "UREA")
			replace good = "chem"    if ustrregexm(lab, "INSECT|HERBIC|FUNGIC|FUMIG|PESTIC|CHEMICAL")
			replace good = "orgbuy"  if ustrregexm(lab, "ORGANIC|MANURE")
		}
		else {
			replace good = "oseed" if lab != "" & lab != "."
			replace good = "mseed" if strpos(lab, "MAIZE")
		}
		drop if good == ""
		collapse (sum) com_kg com_val, by(`k' good)
		if "`mod'" == "h" append using `fpur'
		save `fpur', replace
	}
	reshape wide com_kg com_val, i(`k') j(good) string
	foreach g in mseed oseed chitowe urea othfert chem orgbuy {
		foreach x in kg val {
			capture confirm variable com_`x'`g'
			if _rc gen double com_`x'`g' = 0
		}
	}
	foreach v of varlist com_* {
		replace `v' = 0 if missing(`v')
	}
	tempfile purch
	save `purch'

	*--------------------------------------------------------------------------
	* F. Input subsidy: FISP coupons (2010-2019) / AIP inputs (2024)
	*    v_chitowe = basal fertiliser (chitowe/NPK; DAP/CAN/D-compound pooled)
	*    v_urea = urea; v_mseed = maize seed; v_oseed = flexi/legume/other seed
	*--------------------------------------------------------------------------
	if `w' == 2010 {
		use "`D'/ag_mod_e_`s'.dta", clear
		txtlab ag_e0d tlab
		gen ncoup = ag_e01
		gen nred = ag_e06
		gen bribe = 0
	}
	else if `w' < 2024 {
		use "`D'/ag_mod_e1_`s'.dta", clear
		txtlab ag_e0c tlab
		gen ncoup = ag_e0d
		keep `k' tlab ncoup
		drop if tlab == "" | tlab == "."
		tempfile e1
		save `e1'
		use "`D'/ag_mod_e2_`s'.dta", clear
		txtlab ag_e01_1 tlab
		if `w' == 2013 gen nred = ag_e05_1 == 1
		else gen nred = ag_e06 == 1
		gen ncoup = 0
		gen bribe = ag_e15_1
		append using `e1'
	}
	else {
		* AIP 2024: one row per input obtained (no coupon; national ID)
		use "`D'/ag_mod_e2_`s'.dta", clear
		txtlab input_id tlab
		gen ncoup = 1
		gen nred = 1
		gen bribe = ag_e15_1
		capture drop ag_e15
		gen ag_e15 = .
	}
	gen str9 vk = ""
	replace vk = "v_oseed"   if ustrregexm(tlab, "FLEXI|LEGUME|BEAN|GROUNDNUT|SOYA|PIGEON|RICE|SORGHUM|OTHER INPUT")
	replace vk = "v_chitowe" if ustrregexm(tlab, "CHITOWE|23:21|NPK|DAP|^CAN|COMPOUND|OTHER FERT")
	replace vk = "v_urea"    if strpos(tlab, "UREA")
	replace vk = "v_mseed"   if strpos(tlab, "MAIZE")
	noisily tab tlab vk, m
	drop if vk == ""
	foreach v in ag_e08a ag_e08b ag_e15 {
		capture confirm variable `v', exact
		if _rc gen `v' = .
	}
	kgunit ag_e08b, gen(fu) type(fert)
	gen double kg = ag_e08a * fu
	replace kg = . if kg <= 0
	* plausibility: standard packs 50 kg fertiliser, ~5 kg maize seed, ~3 kg
	* legume seed per coupon; more than 3 packs per redeemed coupon is a unit
	* error -> reported number as kg if plausible, else one pack per coupon
	gen double pack = cond(inlist(vk, "v_chitowe", "v_urea"), 50, cond(vk == "v_mseed", 5, 3))
	replace nred = 1 if missing(nred) & kg > 0 & kg < .
	replace kg = ag_e08a if kg / max(nred, 1) > 3 * pack & kg < . & ag_e08a > 0 & ag_e08a <= 3 * pack * max(nred, 1)
	replace kg = max(nred, 1) * pack if kg / max(nred, 1) > 3 * pack & kg < .
	gen double kgpc = kg / max(nred, 1) if nred > 0
	bysort vk: egen double med_kgpc = median(kgpc)
	replace kg = nred * med_kgpc if missing(kg) & nred > 0 & !missing(nred)
	replace kg = 0 if missing(kg)
	gen double cost = ag_e15
	replace cost = 0 if missing(cost)
	replace bribe = 0 if missing(bribe)
	replace ncoup = 0 if missing(ncoup)
	replace nred = 0 if missing(nred)
	collapse (sum) ncoup nred kg cost bribe, by(`k' vk)
	reshape wide ncoup nred kg cost bribe, i(`k') j(vk) string
	foreach g in chitowe urea mseed oseed {
		foreach x in ncoup nred kg cost bribe {
			capture confirm variable `x'v_`g'
			if _rc gen double `x'v_`g' = 0
			replace `x'v_`g' = 0 if missing(`x'v_`g')
		}
	}
	tempfile coup
	save `coup'

	*--------------------------------------------------------------------------
	* G. Livestock sales (module R1)
	*--------------------------------------------------------------------------
	use "`D'/ag_mod_r1_`s'.dta", clear
	collapse (sum) inc_livestock = ag_r17, by(`k')
	tempfile lsale
	save `lsale'

	*--------------------------------------------------------------------------
	* H. Assemble
	*--------------------------------------------------------------------------
	use `reg', clear
	merge 1:1 `k' using `plots', nogen
	merge 1:1 `k' using `purch', nogen
	merge 1:1 `k' using `coup', nogen
	merge 1:1 `k' using `lsale', nogen
	foreach v of varlist com_* ncoupv_* nredv_* kgv_* costv_* bribev_* inc_livestock {
		replace `v' = 0 if missing(`v')
	}
	gen int wave = `w'
	gen byte aip = `w' == 2024
	compress
	save "$DER/ag_`w'.dta", replace
	di as res "wave `w': " _N " households"
	summarize maize_kg area_maize maize_seed_kg organic_kg chitowe_kg urea_kg ///
		otherfert_kg labour landowner antierosion mv shannon soil_type soil_quality ///
		com_kg* com_val* ncoupv_* kgv_* costv_*
}
