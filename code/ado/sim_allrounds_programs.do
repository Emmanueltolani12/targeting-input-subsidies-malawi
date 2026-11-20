*==============================================================================
* sim_allrounds_programs.do -- programs of the structural simulation on
* all rounds (14_structural_allrounds and 15_joint_structural). Data in memory: maize growers 2010-2024 with
* quotas q_*, market prices p_*, redemption prices pv_*, inputs, household
* output elasticities el_c_*, rule scores, m_total, wealth_t, deflator cdefl
* (2024 kwacha per kwacha of the round).
* Globals read:
*   Z<spec>_<good>_<quota>  quota elasticities (0 if not used)
*   ETA_FOOD                food expenditure elasticity
*   EPS_FERT                own-price elasticity of commercial fertiliser
*   SIM_VALUE               "redemption" (Asfaw et al. 2017: displaced spending =
*                           quota valued at the farmer's redemption price x
*                           elasticity) or "market" (quota valued at market
*                           prices)
*   SIM_SPECS               specifications of part (A), e.g. "exog iv"
*   SIM_AIP_SPEC            specification of part (B), the AIP levers
*   SIM_CONV                conversion of the quota elasticities into
*                           displaced purchases:
*                           "" or "value" (the convention of Asfaw et al.
*                           2017: displaced spending = elasticity x value of
*                           the quota, SIM_VALUE; no-programme input use =
*                           observed use minus coupon kg)
*                           "elastic" (average marginal effect at the
*                           evaluation point of the elasticities: displaced
*                           commercial kg of good g = sum_k zeta_gk x XC_g /
*                           QS_k x package kg of k, where XC_g is the mean
*                           commercial kg of g and QS_k the mean quota kg of k
*                           in the demand sample (globals XC_<g>, QS_<k>);
*                           displacement cannot exceed the household's
*                           commercial purchases without the programme; the
*                           purchases and input use without the programme add
*                           back the change caused by the household's own
*                           quotas)
*==============================================================================

capture program drop sim13_build
program define sim13_build
	* elasticities, no-subsidy inputs, standard package and rule scores
	gen double elx_mseed   = max(el_c_seed, 0)
	gen double elx_chitowe = max(el_c_chit, 0)
	gen double elx_urea    = max(el_c_urea, 0)
	gen double elx_othfert = max(el_c_othf, 0)
	gen double xns_mseed   = max(maize_seed_kg - q_mseed, 0)
	gen double xns_chitowe = max(chitowe_kg - q_chitowe, 0)
	gen double xns_urea    = max(urea_kg - q_urea, 0)
	gen double xns_othfert = otherfert_kg
	* commercial kg bought (SIM_CONV elastic); not com_*, which sim13_run drops
	foreach g in mseed chitowe urea othfert oseed {
		capture drop ckg_`g'
		gen double ckg_`g' = cond(missing(com_kg`g'), 0, com_kg`g')
	}
	capture drop recip
	gen byte recip = (q_mseed + q_chitowe + q_urea + q_oseed) > 0
	foreach k in mseed chitowe urea oseed {
		bysort wave: egen double qbar_`k' = mean(cond(recip, q_`k', .))
		replace qbar_`k' = 0 if missing(qbar_`k')
		bysort wave: egen double pbar_`k' = mean(p_`k')
		bysort wave: egen double pvbar_`k' = mean(pv_`k')
	}
	bysort wave: egen double nrec = total(recip)
	gen double u = runiform()
	gen double s_actual = 2 * recip + u
	gen double s_eaip   = 2 * eaip + u
	gen double s_random = u
	gen double s_poor   = -wealth + 1e-6 * u
	gen double s_cate   = cate + 1e-6 * u
	gen double s_effpr  = eff_pred + 1e-6 * u
	gen double s_tree   = 2 * r_tree + u
end

capture program drop simz
program define simz
	* simz <name> <score> <households x> <package x> <farmer price x> <z spec>
	* The farmer price multiplier applies to fertiliser (chitowe, urea); bags
	* bought respond with EPS_FERT and cannot exceed the package.
	args nm sc nmult pmult pricem spec
	tempvar rk
	bysort wave (`sc'): gen long `rk' = _N - _n + 1
	local resp = min(1, `pricem'^($EPS_FERT))
	local elastic = "$SIM_CONV" == "elastic"
	gen byte sel_`nm' = `rk' <= round(nrec * `nmult')
	gen double pay_`nm' = 0
	gen double com_`nm' = 0
	gen double cost_`nm' = 0
	foreach k in mseed chitowe urea oseed {
		local fert = inlist("`k'", "chitowe", "urea")
		local pm = cond(`fert', `pricem', 1)
		local rs = cond(`fert', `resp', 1)
		gen double qn_`k' = sel_`nm' * qbar_`k' * `pmult' * `rs'
		replace pay_`nm' = pay_`nm' + qn_`k' * pv_`k' * `pm'
		replace cost_`nm' = cost_`nm' + qn_`k' * (pbar_`k' - `pm' * pvbar_`k') * cdefl
	}
	if `elastic' {
		* purchases and use without the programme (sim_x0), then the change in
		* commercial kg of each good, bounded below by the purchases without
		* the programme
		sim_x0 `spec'
		foreach g in mseed chitowe urea othfert oseed {
			gen double dxc_`g' = 0
			foreach k in mseed chitowe urea oseed {
				* within input groups only (sim_samegroup)
				sim_samegroup `g' `k'
				if !r(same) continue
				local zz = cond("${Z`spec'_`g'_`k'}" == "", 0, ${Z`spec'_`g'_`k'})
				replace dxc_`g' = dxc_`g' + `zz' * ${XC_`g'} / ${QS_`k'} * qn_`k'
			}
		}
		* at most one kilogram displaced per coupon kilogram (sim_cap), and no
		* more than the household would have bought
		sim_cap dxc_ qn_
		foreach g in mseed chitowe urea othfert oseed {
			replace dxc_`g' = max(dxc_`g', -xc0_`g')
			replace com_`nm' = com_`nm' + p_`g' * dxc_`g'
		}
	}
	else {
		foreach k in mseed chitowe urea oseed {
			local fert = inlist("`k'", "chitowe", "urea")
			local pm = cond(`fert', `pricem', 1)
			* value of the quota on which crowding-out acts
			local val = cond("$SIM_VALUE" == "market", "p_`k'", "pv_`k' * `pm'")
			foreach i in mseed chitowe urea othfert oseed {
				local zz = cond("${Z`spec'_`i'_`k'}" == "", 0, ${Z`spec'_`i'_`k'})
				replace com_`nm' = com_`nm' + qn_`k' * `val' * `zz'
			}
		}
	}
	gen double dfood_`nm' = 100 * $ETA_FOOD * (-(pay_`nm' + com_`nm')) / m_total
	gen double dlny_`nm' = 0
	foreach x in mseed chitowe urea othfert {
		gen double dx = 0
		capture replace dx = dx + qn_`x'
		if `elastic' {
			replace dx = dx + dxc_`x'
			replace dlny_`nm' = dlny_`nm' + elx_`x' * (ln(max(x0_`x' + dx, 0) + 1) - ln(x0_`x' + 1))
		}
		else {
			foreach k in mseed chitowe urea oseed {
				local fert = inlist("`k'", "chitowe", "urea")
				local pm = cond(`fert', `pricem', 1)
				local val = cond("$SIM_VALUE" == "market", "p_`k'", "pv_`k' * `pm'")
				local zz = cond("${Z`spec'_`x'_`k'}" == "", 0, ${Z`spec'_`x'_`k'})
				replace dx = dx + qn_`k' * `val' * `zz' / p_`x'
			}
			replace dlny_`nm' = dlny_`nm' + elx_`x' * (ln(max(xns_`x' + dx, 0) + 1) - ln(xns_`x' + 1))
		}
		drop dx
	}
	drop qn_*
	capture drop dxc_* xc0_* x0_*
end

capture program drop sim_samegroup
program define sim_samegroup, rclass
	* sim_samegroup <good> <quota>: 1 if the quota and the commercial good are
	* in the same input group (fertiliser quotas on basal fertiliser, urea and
	* other fertiliser; seed quotas on maize seed and other seed). The seed
	* quotas are small (sample means 0.6 and 0.1 kg), so their cross effects on
	* fertiliser purchases, scaled to a package, are not credible (tens of kg
	* per kg of seed) and are left out of the elastic conversion.
	args g k
	local fg = inlist("`g'", "chitowe", "urea", "othfert")
	local fk = inlist("`k'", "chitowe", "urea")
	return scalar same = (`fg' == `fk')
end

capture program drop sim_cap
program define sim_cap
	* sim_cap <change prefix> <quota prefix>: within each input group the
	* commercial kilograms displaced (negative changes) cannot exceed the
	* coupon kilograms of the group: a ration is substituted for purchases at
	* most one for one. Larger implied displacement is scaled down in
	* proportion across the goods of the group.
	args d q
	foreach grp in F S {
		local goods = cond("`grp'" == "F", "chitowe urea othfert", "mseed oseed")
		local quot = cond("`grp'" == "F", "chitowe urea", "mseed oseed")
		tempvar dn qq sc
		quietly gen double `dn' = 0
		foreach g of local goods {
			quietly replace `dn' = `dn' - min(`d'`g', 0)
		}
		quietly gen double `qq' = 0
		foreach k of local quot {
			quietly replace `qq' = `qq' + cond(missing(`q'`k'), 0, `q'`k')
		}
		quietly gen double `sc' = cond(`dn' > `qq', `qq' / `dn', 1)
		foreach g of local goods {
			quietly replace `d'`g' = cond(`d'`g' < 0, `d'`g' * `sc', `d'`g')
		}
		drop `dn' `qq' `sc'
	}
end

capture program drop sim_x0
program define sim_x0
	* sim_x0 <spec>: commercial purchases xc0_<g> and input use x0_<x> without
	* the programme (SIM_CONV elastic). The household's own quotas changed its
	* commercial purchases by dact = sum_k zeta_gk x XC_g / QS_k x q_k (kg);
	* without the programme it would have bought com_kg<g> - dact (at least
	* zero), and used its observed input minus coupon kg minus that change.
	args spec
	capture drop xc0_* x0_* da_*
	foreach g in mseed chitowe urea othfert oseed {
		gen double da_`g' = 0
		foreach k in mseed chitowe urea oseed {
			sim_samegroup `g' `k'
			if !r(same) continue
			local zz = cond("${Z`spec'_`g'_`k'}" == "", 0, ${Z`spec'_`g'_`k'})
			replace da_`g' = da_`g' + `zz' * ${XC_`g'} / ${QS_`k'} * q_`k'
		}
	}
	* the same one-for-one cap for the household's own quotas
	sim_cap da_ q_
	foreach g in mseed chitowe urea othfert oseed {
		tempvar dact
		gen double `dact' = da_`g'
		gen double xc0_`g' = max(ckg_`g' - `dact', 0)
		* the change in purchases the household actually made
		replace `dact' = ckg_`g' - xc0_`g'
		if "`g'" != "oseed" {
			local tot = cond("`g'" == "mseed", "maize_seed_kg", cond("`g'" == "othfert", "otherfert_kg", "`g'_kg"))
			local qq = cond("`g'" == "othfert", "0", "q_`g'")
			gen double x0_`g' = max(cond(missing(`tot'), 0, `tot') - `qq' - `dact', 0)
		}
		drop `dact'
	}
	drop da_*
end

capture program drop sim13_run
program define sim13_run
	* sim13_run <postfile> <draw>: (A) rules on all rounds, (B) AIP levers 2024
	args pf d
	quietly {
		foreach spec of global SIM_SPECS {
			foreach r in actual random poor effpr cate tree {
				simz `r'_`spec' s_`r' 1 1 1 `spec'
			}
		}
		* no-subsidy maize output of each specification: actual output net of
		* the actual programme effect under that specification
		capture drop maize_ns
		gen double maize_ns = .
		foreach spec of global SIM_SPECS {
			replace maize_ns = maize_kg / exp(dlny_actual_`spec')
			foreach r in actual random poor effpr cate tree {
				sim_collect `pf' `d' A `r' `spec' `r'_`spec' ""
			}
		}
		* (B) AIP levers, 2024
		local sp $SIM_AIP_SPEC
		keep if wave == 2024
		drop sel_* pay_* com_* cost_* dfood_* dlny_*
		count if recip
		global N_REC = r(N)
		count if eaip
		global N_EAIP = r(N)
		local m_eaip = $N_EAIP / $N_REC
		* budget-neutral price rise: fiscal cost per package at x1 and x2
		local sub1 = 0
		local sub2 = 0
		foreach k in mseed chitowe urea oseed {
			local fert = inlist("`k'", "chitowe", "urea")
			summarize qbar_`k', meanonly
			local qb = r(mean)
			summarize pbar_`k', meanonly
			local pb = r(mean)
			summarize pvbar_`k', meanonly
			local pvb = r(mean)
			local sub1 = `sub1' + `qb' * (`pb' - `pvb')
			if `fert' local sub2 = `sub2' + `qb' * min(1, 2^($EPS_FERT)) * (`pb' - 2 * `pvb')
			else local sub2 = `sub2' + `qb' * (`pb' - `pvb')
		}
		local m_bn = `sub1' / `sub2'
		global M_BN = `m_bn'
		*     name        score     households  package price  spec
		simz  base        s_actual  1           1       1      `sp'
		simz  price05     s_actual  1           1       0.5    `sp'
		simz  price15     s_actual  1           1       1.5    `sp'
		simz  price20     s_actual  1           1       2      `sp'
		simz  price20bn   s_actual  `m_bn'      1       2      `sp'
		simz  benef15     s_actual  1.5         1       1      `sp'
		simz  benef20     s_actual  2           1       1      `sp'
		simz  reg_eaip    s_eaip    `m_eaip'    1       1      `sp'
		simz  reg_poor    s_poor    1           1       1      `sp'
		simz  reg_cate    s_cate    1           1       1      `sp'
		simz  reg_random  s_random  1           1       1      `sp'
		simz  reg_effpr   s_effpr   1           1       1      `sp'
		replace maize_ns = maize_kg / exp(dlny_base)
		foreach x in "base AIP 2023/24 as implemented (actual recipients)" "price05 Farmer price x0.5" ///
			"price15 Farmer price x1.5" "price20 Farmer price x2" "price20bn Farmer price x2, savings fund more beneficiaries" ///
			"benef15 Beneficiaries x1.5" "benef20 Beneficiaries x2" "reg_eaip All e-AIP registered households served" ///
			"reg_poor Registration: poorest first" "reg_cate Registration: highest predicted returns" ///
			"reg_effpr Registration: predicted persistent efficiency" "reg_random Registration: random" {
			gettoken nm lab : x
			local lab = strtrim(`"`lab'"')
			sim_collect `pf' `d' B `nm' `sp' `nm' "`lab'"
		}
	}
end
