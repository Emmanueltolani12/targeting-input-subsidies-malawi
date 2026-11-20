*==============================================================================
* 01_build_household.do
* Household-level variables for every IHPS wave in $WAVES (2010-2024), with
* the same definitions in each wave:
*   identifiers and panel links, head sex/age, schooling of members 15-60,
*   wealth items (durables, dwelling), non-farm income components,
*   expenditure groups A-D (module-based, all waves; official NSO aggregate
*   categories where released: 2010, 2013), food price index inputs
*   (Lewbel 1989) and non-food group price indices (community prices).
* Output: $DER/hh_<wave>.dta, key = wave-specific household id ($KEY<wave>)
* Data (World Bank Microdata Library, free registration; not redistributed):
*   2010, 2013  IHPS 2010-2013 short-term panel, https://microdata.worldbank.org/index.php/catalog/2248
*   2016        IHPS 2010-2013-2016 long-term panel, https://microdata.worldbank.org/index.php/catalog/2939
*   2019        IHPS 2010-2013-2016-2019 long-term panel, https://microdata.worldbank.org/index.php/catalog/3819
*   2024        IHPS 2024 (long-term panel and sample refresh), https://microdata.worldbank.org/index.php/catalog/8520
*   unit conversion factors (2020), distributed with the 2019 panel above
*               (https://microdata.worldbank.org/index.php/catalog/3819) and IHS5 (https://microdata.worldbank.org/index.php/catalog/3818)
*==============================================================================

* 2010 consumption aggregate is in 2013 prices; MK 37,002 (IHS3 poverty line,
* 2010/11 prices) = MK 85,852 in 2013 prices.
global F2010 = 85852/37002

* food conversion factors (region x item x unit -> kg)
use "$CONV/ihs_foodconversion_factor_2020.dta", clear
keep region item_code unit_code factor
drop if unit_code == "23" | missing(factor) | factor <= 0
replace unit_code = upper(strtrim(unit_code))
collapse (mean) factor, by(region item_code unit_code)
save "$DER/tmp_fcf.dta", replace
gen unit_base = ustrregexs(0) if ustrregexm(unit_code, "^[0-9]+")
collapse (median) factor_b = factor, by(region item_code unit_base)
save "$DER/tmp_fcf_base.dta", replace

foreach w of global WAVES {
	local s = substr("`w'", 3, 2)
	local D "${DIR`w'}"
	local k "${KEY`w'}"
	di as txt _n "================ household build: wave `w' ================"

	*--------------------------------------------------------------------------
	* 1. Identifiers and panel links
	*--------------------------------------------------------------------------
	use "`D'/hh_mod_a_filt_`s'.dta", clear
	if `w' == 2010 rename hh_a01 district
	foreach v in case_id y2_hhid y3_hhid y4_hhid ea_id district {
		capture confirm variable `v', exact
		if _rc gen `v' = ""
	}
	capture confirm string variable district
	if !_rc destring district, replace force
	gen byte original = 1
	if `w' == 2013 replace original = hh_a05 == 1
	capture confirm variable dist_to_IHS3location, exact
	if _rc gen dist_to_IHS3location = .
	pickvar wv : panelweight_`w' panelweight hh_wgt
	gen double wgt = `wv'
	local kv `k' case_id y2_hhid y3_hhid y4_hhid ea_id district original wgt dist_to_IHS3location
	local kv : list uniq kv
	keep `kv'
	duplicates drop `k', force
	gen int wave = `w'
	gen region = floor(district / 100)
	save "$DER/tmp_ids_`w'.dta", replace

	*--------------------------------------------------------------------------
	* 2. Roster: head sex/age; schooling of members aged 15-60
	*--------------------------------------------------------------------------
	use "`D'/hh_mod_b_`s'.dta", clear
	pickvar pidv : PID id_code hh_b01
	pickvar ordv : hh_b01 id_code
	capture confirm variable hhmember, exact
	if !_rc noisily tab hhmember if hh_b04 == 1, m
	gen byte is_head = hh_b04 == 1
	gen byte cur = 1
	capture confirm variable hhmember, exact
	if !_rc replace cur = hhmember == 1 | missing(hhmember)
	preserve
	keep if is_head
	gsort `k' -cur `ordv'
	by `k': keep if _n == 1
	gen byte head_female = hh_b03 == 2 if !missing(hh_b03)
	gen head_age = hh_b05a
	keep `k' head_female head_age
	save "$DER/tmp_head_`w'.dta", replace
	restore
	keep if cur
	keep `k' `pidv' hh_b05a
	rename `pidv' pid_
	capture tostring pid_, replace
	duplicates drop `k' pid_, force
	tempfile age
	save `age'
	use "`D'/hh_mod_c_`s'.dta", clear
	pickvar pidc : `pidv' PID id_code hh_c01
	rename `pidc' pid_
	capture tostring pid_, replace
	keep `k' pid_ hh_c06 hh_c08
	duplicates drop `k' pid_, force
	merge 1:1 `k' pid_ using `age', keep(match) nogen
	keep if inrange(hh_b05a, 15, 60)
	* grades: std1-8 = 1-8, form1-6 = 9-14, university 1-5 = 15-19,
	* teacher college 1-4 = 13-16; never attended / nursery = 0
	gen grade = 0 if hh_c06 == 2 | hh_c08 == 0
	replace grade = hh_c08 if inrange(hh_c08, 1, 19)
	replace grade = 12 + (hh_c08 - 19) if inrange(hh_c08, 20, 23)
	collapse (mean) educ_15_60 = grade, by(`k')
	save "$DER/tmp_educ_`w'.dta", replace

	*--------------------------------------------------------------------------
	* 3. Wealth items: durable assets (module L) and dwelling (module F)
	*--------------------------------------------------------------------------
	use "`D'/hh_mod_l_`s'.dta", clear
	keep `k' hh_l01 hh_l02
	gen byte own = hh_l01 == 1
	drop hh_l01
	drop if missing(hh_l02)
	collapse (max) own, by(`k' hh_l02)
	reshape wide own, i(`k') j(hh_l02)
	tempfile assets
	save `assets'
	use "`D'/hh_mod_f_`s'.dta", clear
	foreach v in hh_f07 hh_f08 hh_f09 hh_f36 hh_f41 {
		capture confirm numeric variable `v', exact
		if !_rc {
			decode `v', gen(`v'_s)
			replace `v'_s = upper(`v'_s)
		}
		else gen `v'_s = ""
	}
	foreach v in hh_f19 hh_f34 hh_f10 {
		capture confirm variable `v', exact
		if _rc gen `v' = .
	}
	gen byte wall_brick  = strpos(hh_f07_s, "BURNT") > 0 | strpos(hh_f07_s, "CONCRETE") > 0
	gen byte roof_iron   = strpos(hh_f08_s, "IRON") > 0 | strpos(hh_f08_s, "TILE") > 0 | strpos(hh_f08_s, "CONCRETE") > 0
	gen byte floor_cem   = strpos(hh_f09_s, "CEMENT") > 0 | strpos(hh_f09_s, "TILE") > 0
	gen byte water_impr  = strpos(hh_f36_s, "PIPED") > 0 | strpos(hh_f36_s, "BOREHOLE") > 0 | strpos(hh_f36_s, "PROTECTED") > 0
	gen byte toilet_impr = strpos(hh_f41_s, "FLUSH") > 0 | strpos(hh_f41_s, "VIP") > 0 | strpos(hh_f41_s, "SLAB") > 0
	gen byte electricity = hh_f19 == 1
	gen byte cellphone   = hh_f34 > 0 & !missing(hh_f34)
	* rent paid or imputed (annual MK), for the housing expenditure group
	gen double rent_year = 0
	foreach p in "hh_f04a hh_f04b" "hh_f03a hh_f03b" {
		local a : word 1 of `p'
		local u : word 2 of `p'
		capture confirm numeric variable `a' `u', exact
		if !_rc {
			decode `u', gen(u_s)
			replace u_s = upper(u_s)
			gen double per = cond(strpos(u_s, "DAY"), 365, cond(strpos(u_s, "WEEK"), 52, cond(strpos(u_s, "MONTH"), 12, cond(strpos(u_s, "YEAR"), 1, .))))
			replace rent_year = `a' * per if rent_year == 0 & `a' > 0 & `a' < . & per < .
			drop u_s per
		}
	}
	keep `k' wall_brick roof_iron floor_cem water_impr toilet_impr electricity cellphone rent_year
	merge 1:1 `k' using `assets', nogen
	save "$DER/tmp_wealth_`w'.dta", replace

	*--------------------------------------------------------------------------
	* 4. Non-farm income components (annual, nominal MK)
	*--------------------------------------------------------------------------
	use "`D'/hh_mod_e_`s'.dta", clear
	foreach v in hh_e22 hh_e23 hh_e25 hh_e26a hh_e26b hh_e56 hh_e57 hh_e58 hh_e59 {
		capture confirm numeric variable `v', exact
		if _rc {
			capture drop `v'
			gen `v' = .
		}
	}
	replace hh_e26a = 1 if missing(hh_e26a) | hh_e26a == 0
	capture decode hh_e26b, gen(unit_s)
	if _rc gen unit_s = ""
	replace unit_s = upper(unit_s)
	gen double pay_unit = hh_e25 / hh_e26a
	gen double inc_wage = pay_unit * hh_e22                 if strpos(unit_s, "MONTH") | hh_e26b == 5
	replace    inc_wage = pay_unit * hh_e23 * hh_e22        if strpos(unit_s, "WEEK")  | (hh_e26b == 4 & unit_s == "")
	replace    inc_wage = pay_unit * 5 * hh_e23 * hh_e22    if strpos(unit_s, "DAY")   | (hh_e26b == 3 & unit_s == "")
	gen double inc_ganyu = hh_e56 * hh_e57 * hh_e58 * hh_e59
	collapse (sum) inc_wage inc_ganyu, by(`k')
	tempfile e
	save `e'

	use "`D'/hh_mod_n2_`s'.dta", clear
	gen months_op = 0
	foreach v of varlist hh_n25* {
		capture confirm numeric variable `v'
		if !_rc replace months_op = months_op + inrange(`v', 1, 3)
	}
	replace months_op = 12 if months_op == 0
	replace months_op = min(months_op, 12)
	capture confirm variable hh_n40, exact
	if _rc gen hh_n40 = .
	gen double inc_ent = max(hh_n40, 0) * months_op
	collapse (sum) inc_ent, by(`k')
	tempfile n
	save `n'

	use "`D'/hh_mod_p_`s'.dta", clear
	collapse (sum) inc_other = hh_p02, by(`k')
	tempfile p
	save `p'
	use "`D'/hh_mod_o_`s'.dta", clear
	capture confirm variable hh_o14, exact
	if _rc gen hh_o14 = .
	collapse (sum) inc_remit = hh_o14, by(`k')
	tempfile o
	save `o'
	use "`D'/hh_mod_r_`s'.dta", clear
	capture confirm variable hh_r02a, exact
	if _rc gen hh_r02a = .
	collapse (sum) inc_snet = hh_r02a, by(`k')
	merge 1:1 `k' using `o', nogen
	merge 1:1 `k' using `p', nogen
	merge 1:1 `k' using `n', nogen
	merge 1:1 `k' using `e', nogen
	foreach v in inc_wage inc_ganyu inc_ent inc_other inc_remit inc_snet {
		replace `v' = 0 if missing(`v')
	}
	save "$DER/tmp_income_`w'.dta", replace

	*--------------------------------------------------------------------------
	* 5. Food: purchase unit values, Lewbel food price index, food expenditure
	*    unit value = MK spent / kg purchased; EA median per item (>= 3 obs),
	*    district, region and national fall-backs; prices relative to the
	*    2010 national median of each item. Food consumption (all sources) is
	*    valued at the local price; weekly -> annual (x 52).
	*--------------------------------------------------------------------------
	use "`D'/hh_mod_g1_`s'.dta", clear
	keep if hh_g01 == 1
	rename hh_g02 item_code
	merge m:1 `k' using "$DER/tmp_ids_`w'.dta", keepusing(ea_id district region) keep(match) nogen
	foreach x in 3 4 {
		* unit code as string; from 2016 a size sub-code (A/B/C) is separate
		capture confirm string variable hh_g0`x'b
		if !_rc gen u`x' = upper(strtrim(hh_g0`x'b))
		else gen u`x' = string(hh_g0`x'b)
		capture confirm variable hh_g0`x'c, exact
		if !_rc {
			capture confirm string variable hh_g0`x'c
			if !_rc replace u`x' = u`x' + upper(strtrim(hh_g0`x'c)) if !inlist(strtrim(hh_g0`x'c), "", ".")
			else {
				capture decode hh_g0`x'c, gen(sz`x')
				if !_rc {
					replace sz`x' = upper(substr(strtrim(sz`x'), 1, 1)) if inlist(upper(substr(strtrim(sz`x'), 1, 1)), "A", "B", "C")
					replace sz`x' = "" if !inlist(sz`x', "A", "B", "C")
					replace u`x' = u`x' + sz`x'
				}
			}
		}
		gen unit_code = u`x'
		merge m:1 region item_code unit_code using "$DER/tmp_fcf.dta", keep(master match) nogen
		gen unit_base = ustrregexs(0) if ustrregexm(unit_code, "^[0-9]+")
		merge m:1 region item_code unit_base using "$DER/tmp_fcf_base.dta", keep(master match) nogen
		replace factor = factor_b if missing(factor)
		replace factor = 1 if missing(factor) & unit_code == "1"
		rename factor f`x'
		drop unit_code unit_base factor_b
	}
	gen double kg_con = hh_g03a * f3
	gen double kg_pur = hh_g04a * f4
	gen double uv = hh_g05 / kg_pur if kg_pur > 0 & hh_g05 > 0
	bysort item_code: egen double med_i = median(uv)
	replace uv = . if uv < med_i / 10 | uv > med_i * 10
	foreach lev in ea_id district region {
		bysort item_code `lev': egen double m_`lev' = median(uv)
		bysort item_code `lev': egen n_`lev' = count(uv)
	}
	gen double p_item = m_ea_id if n_ea_id >= 3
	replace p_item = m_district if missing(p_item) & n_district >= 3
	replace p_item = m_region   if missing(p_item) & n_region >= 3
	replace p_item = med_i      if missing(p_item)
	if `w' == 2010 {
		preserve
		collapse (median) p0 = uv, by(item_code)
		save "$DER/tmp_foodbase_2010.dta", replace
		restore
	}
	merge m:1 item_code using "$DER/tmp_foodbase_2010.dta", keep(master match) nogen
	* weekly value: purchases at reported spending, other sources at local price
	gen double kg_oth = max(kg_con - cond(missing(kg_pur), 0, kg_pur), 0) if kg_con < .
	gen double val_week = cond(hh_g05 > 0 & hh_g05 < ., hh_g05, 0) + cond(kg_oth < . & p_item < ., kg_oth * p_item, 0)
	preserve
	collapse (sum) food_week = val_week, by(`k')
	gen double expmod_A = 52 * food_week
	keep `k' expmod_A
	tempfile foodexp
	save `foodexp'
	restore
	gen double lnp_rel = ln(p_item / p0)
	gen double val = kg_con * p_item
	keep if val > 0 & !missing(val, lnp_rel)
	bysort `k': egen double tot = total(val)
	gen double wf = val / tot
	gen double s1 = wf * lnp_rel
	gen double s2 = -wf * ln(wf)
	collapse (sum) lewbel_A1 = s1 lewbel_A2 = s2 (count) nfood = wf, by(`k')
	merge 1:1 `k' using `foodexp', nogen
	save "$DER/tmp_food_`w'.dta", replace

	*--------------------------------------------------------------------------
	* 6. Non-food expenditure groups from the household modules (annual MK)
	*    I1 (7 days, x52), I2 (1 month, x12), J (3 months, x4), K/K1 (12 months)
	*    items classified by their label; plus education (module C), health
	*    (module D) and rent (module F). Transfers/ceremonies/loans excluded.
	*--------------------------------------------------------------------------
	tempfile nf
	local first 1
	foreach m in i1 i2 j k k1 {
		capture confirm file "`D'/hh_mod_`m'_`s'.dta"
		if _rc continue
		use "`D'/hh_mod_`m'_`s'.dta", clear
		local item : word `=cond("`m'"=="i1",1,cond("`m'"=="i2",2,cond("`m'"=="j",3,4)))' of hh_i02 hh_i05 hh_j02 hh_k02
		local amt  : word `=cond("`m'"=="i1",1,cond("`m'"=="i2",2,cond("`m'"=="j",3,4)))' of hh_i03 hh_i06 hh_j03 hh_k03
		capture confirm numeric variable `item' `amt', exact
		if _rc {
			di as error "wave `w' module `m': `item'/`amt' not found -- skipped"
			continue
		}
		local mult = cond("`m'"=="i1", 52, cond("`m'"=="i2", 12, cond("`m'"=="j", 4, 1)))
		decode `item', gen(lab)
		replace lab = upper(lab)
		gen double amt = `amt' * `mult' if `amt' > 0 & `amt' < .
		gen str1 grp = "D"
		replace grp = "B" if ustrregexm(lab, "RENT|PARAFFIN|KEROSENE|CHARCOAL|FIREWOOD|ELECTRIC|WATER|CANDLE|MATCH|BULB|DWELLING|HOUSE|MORTAR|BED|MATTRESS|BLANKET|SHEET|\bMAT|FURNITURE|CARPET|RUG|CURTAIN|PLATE|CUP|POT|PAN|BUCKET|UTENSIL|LAMP|LANTERN|BROOM|MOSQUITO|NET|COOKING|BASIN|TABLE|CHAIR|SERVANT|LINEN|TOWEL|KITCHEN|STOVE|GAS|FUEL")
		replace grp = "C" if ustrregexm(lab, "CLOTH|SHOE|SANDAL|BOOT|UNIFORM|CHITENJE|SHIRT|TROUSER|DRESS|SKIRT|UNDERWEAR|SOCKS|BLOUSE|SWEATER|JACKET|COAT|TAILOR|TRANSPORT|BUS|MINIBUS|TAXI|FARE|PETROL|DIESEL|MOTOR|BICYCLE|SCHOOL|TUITION|BOOK|MEDIC|DRUG|HOSPITAL|CLINIC|HEALTH|DOCTOR|TRAVEL")
		replace grp = "A" if ustrregexm(lab, "MILLING|GRINDING")
		replace grp = "X" if ustrregexm(lab, "MORTGAGE|LOAN|FUNERAL|WEDDING|MARRIAGE|BRIDE|LOBOLA|DOWRY|TAX|CEREMON|DONATION|INITIATION|LAND|LIVESTOCK|INSURANCE|LOTTERY|GAMBL")
		keep if amt < . & grp != "X"
		collapse (sum) amt, by(`k' grp)
		if !`first' append using `nf'
		save `nf', replace
		local first 0
	}
	collapse (sum) amt, by(`k' grp)
	reshape wide amt, i(`k') j(grp) string
	foreach g in A B C D {
		capture confirm variable amt`g'
		if _rc gen amt`g' = 0
		replace amt`g' = 0 if missing(amt`g')
	}
	tempfile nonfood
	save `nonfood'
	* education
	use "`D'/hh_mod_c_`s'.dta", clear
	labvar edtot "total" hh_c22*
	* 2019+ questionnaires: hh_c22l is the total (labels are empty in 2024)
	if "`edtot'" == "" & `w' >= 2016 pickvar edtot : hh_c22l
	if "`edtot'" == "" {
		egen double ed_ = rowtotal(hh_c22*)
	}
	else gen double ed_ = `edtot'
	collapse (sum) educ_exp = ed_, by(`k')
	tempfile edu
	save `edu'
	* health
	use "`D'/hh_mod_d_`s'.dta", clear
	foreach v in hh_d10 hh_d11 hh_d12 hh_d14 hh_d15 hh_d16 hh_d19 {
		capture confirm numeric variable `v', exact
		if _rc {
			capture drop `v'
			gen `v' = 0
		}
		replace `v' = 0 if missing(`v') | `v' < 0
	}
	gen double hl_ = 13 * (hh_d10 + hh_d11 + hh_d12) + hh_d14 + hh_d15 + hh_d16 + hh_d19
	collapse (sum) health_exp = hl_, by(`k')
	merge 1:1 `k' using `edu', nogen
	merge 1:1 `k' using `nonfood', nogen
	merge 1:1 `k' using "$DER/tmp_wealth_`w'.dta", keepusing(rent_year) nogen
	merge 1:1 `k' using `foodexp', nogen
	foreach v in educ_exp health_exp amtA amtB amtC amtD rent_year expmod_A {
		replace `v' = 0 if missing(`v')
	}
	replace expmod_A = expmod_A + amtA
	gen double expmod_B = amtB + rent_year
	gen double expmod_C = amtC + educ_exp + health_exp
	gen double expmod_D = amtD
	keep `k' expmod_A expmod_B expmod_C expmod_D educ_exp health_exp
	save "$DER/tmp_consmod_`w'.dta", replace

	*--------------------------------------------------------------------------
	* 7. Official NSO consumption aggregate categories (2010, 2013 only)
	*    A = food/bev + alcohol/tobacco + restaurants; B = housing/utilities +
	*    furnishings; C = clothing + health + transport + education;
	*    D = communication + recreation + miscellaneous. Real 2013 prices are
	*    converted back to nominal survey-round prices.
	*--------------------------------------------------------------------------
	if inlist(`w', 2010, 2013) {
		local rr = cond(`w' == 2010, 1, 2)
		use "$RAW/Round `rr' (`w') Consumption Aggregate.dta", clear
		foreach c in 01 02 03 04 05 06 07 08 09 10 11 12 {
			capture confirm variable rexp_cat`c'
			if _rc gen rexp_cat`c' = 0
			replace rexp_cat`c' = 0 if missing(rexp_cat`c')
		}
		local F = cond(`w' == 2010, $F2010, 1)
		gen double defl = (price_indexL / 100) / `F'
		gen double expoff_A = (rexp_cat01 + rexp_cat02 + rexp_cat11) * defl
		gen double expoff_B = (rexp_cat04 + rexp_cat05) * defl
		gen double expoff_C = (rexp_cat03 + rexp_cat06 + rexp_cat07 + rexp_cat10) * defl
		gen double expoff_D = (rexp_cat08 + rexp_cat09 + rexp_cat12) * defl
		gen double rexpagg_nom = rexpagg * defl
		keep `k' expoff_* rexpagg rexpagg_nom hhsize adulteq price_indexL defl
		save "$DER/tmp_consoff_`w'.dta", replace
	}

	*--------------------------------------------------------------------------
	* 8. Non-food group price indices from the community price questionnaire
	*    B: firewood, charcoal, paraffin, foam mattress, mosquito net
	*    C: aspirin, fansidar, chitenje cloth, trousers, bicycle
	*    D: bar soap, toothbrush, toothpaste, washing powder, vaseline,
	*       soft drink, beer, cigarettes, battery, watch
	*    Equal-weight geometric index of EA prices relative to the round's
	*    national median (EA -> district -> region -> national): the spatial
	*    component only. Unit codes are not comparable across rounds, so the
	*    round's price level is anchored to the food price index in 03.
	*--------------------------------------------------------------------------
	if "${COM`w'}" != "" {
		use "`D'/${COM`w'}.dta", clear
		* item names (codes differ between rounds, so items are matched by name)
		capture confirm string variable com_ck00a
		if !_rc gen lab = lower(com_ck00b)
		else decode com_ck00a, gen(lab)
		replace lab = lower(lab)
		* price, number of units, unit (2010/2013: com_ck00b1-b3; 2019+: ckb-ckd)
		pickvar pr : com_ck00b1 ckb
		pickvar nu : com_ck00b2 ckc
		pickvar un : com_ck00b3 ckd
		capture confirm string variable `nu'
		if !_rc gen double nunits = real(`nu')
		else gen double nunits = `nu'
		gen double price = `pr' / cond(nunits > 0 & !missing(nunits), nunits, 1)
		gen unit = `un'
		gen str12 item = ""
		replace item = "firewood"   if strpos(lab, "firewood")
		replace item = "charcoal"   if strpos(lab, "charcoal")
		replace item = "paraffin"   if strpos(lab, "paraffin")
		replace item = "mattress"   if strpos(lab, "mattress")
		replace item = "mosqnet"    if strpos(lab, "mosquito")
		replace item = "aspirin"    if strpos(lab, "aspirin") | strpos(lab, "panadol")
		replace item = "fansidar"   if strpos(lab, "fansidar")
		replace item = "chitenje"   if strpos(lab, "chitenje")
		replace item = "trousers"   if strpos(lab, "trouser")
		replace item = "bicycle"    if strpos(lab, "bicycle")
		replace item = "barsoap"    if strpos(lab, "bar soap")
		replace item = "toothbrush" if strpos(lab, "toothbrush")
		replace item = "toothpaste" if strpos(lab, "toothpaste")
		replace item = "washsoap"   if strpos(lab, "clothes soap") | strpos(lab, "omo")
		replace item = "vaseline"   if strpos(lab, "vaseline")
		replace item = "softdrink"  if strpos(lab, "coca") | strpos(lab, "fanta")
		replace item = "beer"       if strpos(lab, "beer") | strpos(lab, "carlsberg")
		replace item = "cigarettes" if strpos(lab, "cigarette")
		replace item = "battery"    if strpos(lab, "battery")
		replace item = "watch"      if strpos(lab, "watch")
		gen int wave = `w'
		keep ea_id item price unit wave
		keep if price > 0 & !missing(price) & item != ""
		gen str1 grp = "D"
		replace grp = "B" if inlist(item, "firewood", "charcoal", "paraffin", "mattress", "mosqnet")
		replace grp = "C" if inlist(item, "aspirin", "fansidar", "chitenje", "trousers", "bicycle")
		bysort item unit: gen nu_ = _N
		* modal unit; ties broken by the unit code, not by the sort order
		bysort item (nu_ unit): gen modal = unit[_N]
		keep if unit == modal
		* spatial relative price within the round (unit codes are not
		* comparable across rounds; the round's price level is added in 03)
		bysort item: egen double p0 = median(price)
		gen double lnp_rel = ln(price / p0)
		collapse (mean) lnp_rel, by(ea_id item grp)
		tempfile com
		save `com'
		use "$DER/tmp_ids_`w'.dta", clear
		keep `k' ea_id district region
		tempfile hhl
		save `hhl'
		use `com', clear
		keep item grp
		duplicates drop
		cross using `hhl'
		merge m:1 ea_id item using `com', keep(master match) keepusing(lnp_rel) nogen
		foreach lev in district region {
			bysort item `lev': egen double m_`lev' = mean(lnp_rel)
		}
		bysort item: egen double m_nat = mean(lnp_rel)
		replace lnp_rel = m_district if missing(lnp_rel)
		replace lnp_rel = m_region   if missing(lnp_rel)
		replace lnp_rel = m_nat      if missing(lnp_rel)
		collapse (mean) lnp_rel, by(`k' grp)
		reshape wide lnp_rel, i(`k') j(grp) string
		rename lnp_rel* lnP_*
		save "$DER/tmp_nonfoodprice_`w'.dta", replace
	}

	*--------------------------------------------------------------------------
	* 9. Assemble
	*--------------------------------------------------------------------------
	use "$DER/tmp_ids_`w'.dta", clear
	foreach f in head educ wealth income food consmod consoff nonfoodprice {
		capture confirm file "$DER/tmp_`f'_`w'.dta"
		if !_rc merge 1:1 `k' using "$DER/tmp_`f'_`w'.dta", keep(master match) nogen
	}
	replace educ_15_60 = 0 if missing(educ_15_60)
	foreach g in B C D {
		capture confirm variable lnP_`g'
		if _rc gen double lnP_`g' = .
	}
	compress
	save "$DER/hh_`w'.dta", replace
	di as res "wave `w': " _N " households"
	summarize head_female head_age educ_15_60 expmod_* lewbel_A1 lnP_B lnP_C lnP_D inc_*
}
