*==============================================================================
* sim_helpers.do -- shared programs of the structural simulations and their
* bootstrap (14_structural_allrounds). Needs qd_lib.do (Mata qd_mvn_draw).
*   tl_elast      household output elasticities of a translog from a
*                 coefficient matrix (point estimates or a draw)
*   sim_draw_b    one draw of a coefficient vector from N(b, V)
*   sim_collect   totals of one simulated rule, posted to a postfile
*   sim_summarise bootstrap standard errors, 90% percentile intervals and the
*                 change against the reference rule, from the posted draws
*==============================================================================

capture program drop tl_elast
program define tl_elast
	* tl_elast <b matrix> <factor of the squared terms> <equation prefix>
	* el_x = b_x + f b_sq_x c_x + sum_j b_ix_xj c_j for x in $TL_X (centred
	* ln(x + 1)); f = 1 when sq = 0.5 c^2 (06_panel_frontier), 2 when sq = c^2 (05_sfa)
	* (coefficients are read into scalars first: matrix functions inside
	* -replace- are evaluated for every observation and are very slow)
	args bm f pref
	local k : word count $TL_X
	forvalues i = 1/`k' {
		local xi : word `i' of $TL_X
		scalar tl_b_ = el(`bm', 1, colnumb(`bm', "`pref'`xi'"))
		scalar tl_s_ = el(`bm', 1, colnumb(`bm', "`pref'sq_`i'"))
		if missing(tl_b_, tl_s_) {
			di as error "tl_elast: coefficient of `xi' not found in `bm'"
			exit 111
		}
		quietly replace el_`xi' = tl_b_ + `f' * tl_s_ * `xi'
		forvalues j = 1/`k' {
			if `j' == `i' continue
			local a = min(`i', `j')
			local c = max(`i', `j')
			local xj : word `j' of $TL_X
			scalar tl_x_ = el(`bm', 1, colnumb(`bm', "`pref'ix_`a'_`c'"))
			if missing(tl_x_) {
				di as error "tl_elast: coefficient ix_`a'_`c' not found in `bm'"
				exit 111
			}
			quietly replace el_`xi' = el_`xi' + tl_x_ * `xj'
		}
	}
	scalar drop tl_b_ tl_s_ tl_x_
end

capture program drop sim_draw_b
program define sim_draw_b
	* sim_draw_b <b matrix> <V matrix> <output matrix>
	args bm vm out
	mata: st_matrix("`out'", qd_mvn_draw(st_matrix("`bm'"), st_matrix("`vm'")))
	matrix colnames `out' = `: colfullnames `bm''
end

capture program drop sim_collect
program define sim_collect
	* sim_collect <postfile> <draw> <part> <rule key> <spec> <variable stem> "<label>"
	* households served, maize gain (t), kg per household served, mean % change
	* in food spending (all, poorest tertile), fiscal cost (MK m), MK per kg
	args pf d part key spec nm lab
	quietly {
		count if sel_`nm'
		local nh = r(N)
		gen double g_ = maize_ns * (exp(dlny_`nm') - 1)
		summarize g_, meanonly
		local mt = r(sum) / 1000
		summarize dfood_`nm', meanonly
		local fp = r(mean)
		summarize dfood_`nm' if wealth_t == 1, meanonly
		local fpp = r(mean)
		summarize cost_`nm', meanonly
		local cm = r(sum) / 1e6
		drop g_
	}
	post `pf' (`d') ("`part'") ("`key'") ("`spec'") (`"`lab'"') (`nh') (`mt') (`mt' * 1000 / `nh') ///
		(`fp') (`fpp') (`cm') (`cm' * 1e6 / max(`mt' * 1000, 1))
end

capture program drop sim_summarise
program define sim_summarise
	* in memory: the posted draws (draw 0 = point estimates) with seq (row
	* within a draw), refgrp and isref (reference row of the group: change in
	* maize is measured against it), bestgrp (rows compared for the largest
	* maize gain; 0 = not compared). Leaves the point estimates with
	* se_* (standard deviation over the draws), maize_lo, maize_hi, mk_lo,
	* mk_hi, d_lo, d_hi (5th and 95th percentiles), d_pct (% change in maize against the reference), its
	* standard error, interval and two-sided bootstrap p-value p_d, p_best
	* (share of draws in which the row has the largest maize gain of its
	* group) and reps (number of draws).
	quietly {
		gen double mref_ = maize_t if isref
		bysort draw refgrp (mref_): replace mref_ = mref_[1]
		gen double d_pct = 100 * (maize_t / mref_ - 1)
		bysort draw bestgrp: egen double mmax_ = max(maize_t)
		gen double best_ = cond(bestgrp > 0, reldif(maize_t, mmax_) < 1e-9, .)
		gen double dle_ = d_pct <= 0 if !missing(d_pct)
		gen double dge_ = d_pct >= 0 if !missing(d_pct)
		count if draw > 0
		local nb = r(N)
		if `nb' > 0 {
			preserve
			keep if draw > 0
			collapse (sd) se_maize_t = maize_t se_kg_per_hh = kg_per_hh se_food_pct = food_pct ///
				se_food_pct_poor = food_pct_poor se_cost_mk = cost_mk se_mk_per_kg = mk_per_kg ///
				se_d_pct = d_pct (p5) maize_lo = maize_t mk_lo = mk_per_kg d_lo = d_pct ///
				(p95) maize_hi = maize_t mk_hi = mk_per_kg d_hi = d_pct ///
				(mean) p_best = best_ dle_ dge_ (count) reps = maize_t, by(seq)
			gen double p_d = min(1, 2 * min(dle_, dge_))
			drop dle_ dge_
			tempfile s_
			save `s_'
			restore
		}
		keep if draw == 0
		drop mref_ mmax_ best_ dle_ dge_
		if `nb' > 0 {
			merge 1:1 seq using `s_', nogen
			foreach v in se_d_pct d_lo d_hi p_d {
				replace `v' = . if isref
			}
		}
		else {
			foreach v in se_maize_t se_kg_per_hh se_food_pct se_food_pct_poor se_cost_mk se_mk_per_kg ///
				se_d_pct maize_lo mk_lo d_lo maize_hi mk_hi d_hi p_best reps p_d {
				gen double `v' = .
			}
		}
		sort seq
	}
end
