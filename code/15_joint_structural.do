*==============================================================================
* 15_joint_structural.do -- structural model with the demand system and the
* frontier identified jointly, compared with realised returns
* (1) runs 14_structural_allrounds with global SIM_MODEL "joint": quota elasticities of the
*     instrumented demand system evaluated with the quota valued at market
*     prices, all elasticities used, converted into displaced commercial
*     kilograms within input groups at their evaluation point and bounded by
*     the household's purchases without the programme (SIM_CONV elastic),
*     and output elasticities of the correlated random-effects panel
*     translog (the control-function translog is estimated as a test only);
*     joint bootstrap (EA resampling; frontier re-estimated in every draw;
*     demand elasticities drawn from their covariance)
* (2) compares the maize gain per package of each allocation rule under the
*     conventional model (14_structural_allrounds) and the joint model with the realised return per
*     voucher of the same rule (doubly robust scores of the causal forest,
*     09_causal_forest_rules): levels, rank correlation across rules, ratio
* Output: $EXT/structural_allrounds_joint.csv, aip_levers_joint.csv,
*         cf_frontier.csv, structural_vs_realised.csv
*==============================================================================

global EXT "$ROOT/output/results"
* global SIM_SKIP 1 only redoes the comparison (the joint model's results exist)
global SIM_MODEL "joint"
if "$SIM_SKIP" != "1" do "$CODE/14_structural_allrounds.do"
global SIM_MODEL "conventional"

*------------------------------------------------------------------------------
* structural predictions against realised returns
*------------------------------------------------------------------------------
import delimited using "$EXT/policy_values.csv", clear varnames(1)
gen str12 rule_k = ""
replace rule_k = "actual" if rule == "Actual allocation"
replace rule_k = "random" if rule == "Random"
replace rule_k = "poor"   if rule == "Poorest first"
replace rule_k = "effpr"  if rule == "Persistent efficiency first (predicted)"
replace rule_k = "cate"   if rule == "Highest predicted returns"
replace rule_k = "tree"   if rule == "Policy tree (depth 2)"
keep if rule_k != ""
* realised: average effect on the treated for the actual allocation, mean
* doubly robust score of the selected households for the other rules
gen double se_real = cond(rule_k == "actual", se, se_boot)
keep rule_k kg_per_voucher se_real
rename (kg_per_voucher rule_k) (kg_real rule)
tempfile real
save `real'
foreach m in conv joint {
	local f = cond("`m'" == "conv", "structural_allrounds.csv", "structural_allrounds_joint.csv")
	import delimited using "$EXT/`f'", clear varnames(1)
	keep if spec == "iv"
	keep rule kg_per_package se_kg_per_package d_pct se_d_pct p_d
	rename (kg_per_package se_kg_per_package d_pct se_d_pct p_d) (kg_`m' se_`m' d_`m' sed_`m' pd_`m')
	merge 1:1 rule using `real', nogen
	save `real', replace
}
use `real', clear
gen int ord = cond(rule == "actual", 1, cond(rule == "random", 2, cond(rule == "poor", 3, cond(rule == "effpr", 4, cond(rule == "cate", 5, 6)))))
sort ord
foreach m in conv joint {
	gen double ratio_`m' = kg_`m' / kg_real
	quietly spearman kg_`m' kg_real
	gen double rho_`m' = r(rho)
}
list rule kg_real se_real kg_conv se_conv kg_joint se_joint ratio_conv ratio_joint rho_conv rho_joint, noobs clean
export delimited using "$EXT/structural_vs_realised.csv", replace
