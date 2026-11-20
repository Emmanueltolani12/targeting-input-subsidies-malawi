# 09_causal_forest_rules.R -- heterogeneous returns and implementable allocation rules
# Causal forest (grf; Athey, Tibshirani and Wager 2019) for the effect of a
# fertilizer voucher (FISP coupon 2010-2019, AIP fertilizer 2024) on maize
# output of maize growers 2010-2024, clustered by enumeration area, and policy
# trees (policytree; Athey and Wager 2021) on characteristics that a village
# committee or the e-AIP register can verify before the season.
# Rules are compared at the actual budget: in every round as many households
# are selected as actually received a voucher. Honest evaluation: rules are
# learned on four EA folds (fold-specific forests) and evaluated on the fifth
# with the doubly robust (AIPW) scores of the full forest.
# Usage: Rscript code/09_causal_forest_rules.R [package root]   (R 4.5 with grf, policytree)
# Inputs: data/derived/all_waves_panel_sat.dta, panel_efficiency.dta (06_panel_frontier)
# Output: output/results/grf_summary.csv, grf_blp.csv, policy_values.csv,
#         policy_tree.txt, data/derived/rule_assignment.csv (for 14_structural_allrounds.do)

suppressPackageStartupMessages({
  library(haven); library(grf); library(policytree); library(ranger)
})
set.seed(20171105)
root <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(root)) root <- "."
ext <- file.path(root, "output", "results")
der <- file.path(root, "data", "derived")

d <- as.data.frame(zap_labels(read_dta(file.path(der, "all_waves_panel_sat.dta"))))
d <- d[d$grows_maize == 1, ]
pe <- as.data.frame(zap_labels(read_dta(file.path(der, "panel_efficiency.dta"))))
d <- merge(d, pe[, c("wave", "hhkey", "te_p", "te_o", "uid", "T")], by = c("wave", "hhkey"), all.x = TRUE)
d$Y <- d$maize_kg
d$lnyield <- log(d$maize_kg / d$area_maize)
d$W <- as.numeric(d$vou_fert == 1)
for (w in c(2013, 2016, 2019, 2024)) d[[paste0("w", w)]] <- as.numeric(d$wave == w)

# verifiable before the season (no inputs, output or current-season weather)
verif <- c("head_female", "head_age", "hhsize", "educ_15_60", "wealth", "landowner", "area_cult",
           "soil_fair", "soil_poor", "soil_mixed", "soil_clay", "aez_warm_subhumid", "aez_cool_semiarid",
           "aez_cool_subhumid", "temperature", "dist_agmrkt", "dist_admarc")
static_sat <- c("soc", "ntot", "ph", "clay", "sand", "travel_min", "crop_share")
waves <- c("w2013", "w2016", "w2019", "w2024")
# short list for the policy tree (interpretable splits)
tree_vars <- c("area_cult", "wealth", "educ_15_60", "head_female", "hhsize", "soc", "travel_min", "soil_poor")

fill <- function(df, vars) {
  X <- df[, vars, drop = FALSE]
  for (v in vars) if (anyNA(X[[v]])) X[[v]][is.na(X[[v]])] <- median(X[[v]], na.rm = TRUE)
  as.matrix(X)
}
X <- fill(d, c(verif, static_sat, waves))
Xt <- fill(d, tree_vars)
ea <- as.integer(factor(d$ea_id))
u <- unique(ea); fold <- sample(rep(1:5, length.out = length(u)))[match(ea, u)]

# --------------------------------------------------------------------------
# 1. full-sample causal forest: average effects, calibration, projection
# --------------------------------------------------------------------------
cf <- causal_forest(X, d$Y, d$W, clusters = ea, num.trees = 2000, seed = 11)
ate <- average_treatment_effect(cf)
att <- average_treatment_effect(cf, target.sample = "treated")
cal <- test_calibration(cf)
cf_l <- causal_forest(X, d$lnyield, d$W, clusters = ea, num.trees = 2000, seed = 12)
ate_l <- average_treatment_effect(cf_l)
summ <- data.frame(
  estimate = c("ATE maize output (kg)", "ATT maize output (kg)", "ATE ln yield",
               "Calibration: mean forest prediction", "Calibration: differential forest prediction"),
  value = c(ate[1], att[1], ate_l[1], cal[1, 1], cal[2, 1]),
  se = c(ate[2], att[2], ate_l[2], cal[1, 2], cal[2, 2]), n = nrow(d))
write.csv(summ, file.path(ext, "grf_summary.csv"), row.names = FALSE)
print(summ)
blp_vars <- c("wealth", "area_cult", "head_female", "educ_15_60", "hhsize", "soc", "travel_min", "soil_poor")
blp <- best_linear_projection(cf, X[, blp_vars])
blp <- data.frame(term = rownames(blp), estimate = blp[, 1], se = blp[, 2], row.names = NULL)
write.csv(blp, file.path(ext, "grf_blp.csv"), row.names = FALSE)
print(blp)
vi <- variable_importance(cf)
vi <- data.frame(variable = colnames(X), importance = as.numeric(vi))
write.csv(vi[order(-vi$importance), ], file.path(ext, "grf_importance.csv"), row.names = FALSE)

# doubly robust scores (out-of-bag) for evaluation: tau_i = Gamma1 - Gamma0
G <- double_robust_scores(cf)
tau_dr <- G[, 2] - G[, 1]

# --------------------------------------------------------------------------
# 2. cross-fitted rules
# --------------------------------------------------------------------------
budget <- tapply(d$W, d$wave, sum)
pick_top <- function(score, idx_round, k) {
  # select k households with the highest score among idx_round
  if (k <= 0) return(integer(0))
  idx_round[order(-score[idx_round])][seq_len(min(k, length(idx_round)))]
}
rules <- c("Actual allocation", "Actual allocation, as predicted from traits", "Random", "Poorest first",
           "Smallest farms first", "Persistent efficiency first (predicted)", "Highest predicted returns",
           "Policy tree (depth 2)")
what <- cf$W.hat     # out-of-bag probability of receiving a voucher
assign <- matrix(0L, nrow(d), length(rules), dimnames = list(NULL, rules))
assign[, "Actual allocation"] <- d$W
cate_cf <- rep(NA_real_, nrow(d))
eff_pred <- rep(NA_real_, nrow(d))
tree_txt <- character(0)
for (k in 1:5) {
  tr <- which(fold != k); te <- which(fold == k)
  cfk <- causal_forest(X[tr, ], d$Y[tr], d$W[tr], clusters = ea[tr], num.trees = 1000, seed = 20 + k)
  cate_cf[te] <- predict(cfk, X[te, ])$predictions
  # implementable efficiency: persistent efficiency (06_panel_frontier) predicted from verifiable traits
  ok <- tr[!is.na(d$te_p[tr])]
  rfe <- ranger(x = X[ok, ], y = d$te_p[ok], num.trees = 500, min.node.size = 20, seed = 30 + k)
  eff_pred[te] <- predict(rfe, X[te, , drop = FALSE])$predictions
  # policy tree on the training folds' doubly robust scores, with a cost per
  # voucher that makes the tree treat about the budget share
  Gk <- double_robust_scores(cfk)
  share <- mean(d$W[tr])
  best <- NULL
  for (c0 in quantile(Gk[, 2] - Gk[, 1], probs = seq(0.30, 0.80, by = 0.10))) {
    Gc <- cbind(Gk[, 1], Gk[, 2] - c0)
    pt <- policy_tree(Xt[tr, ], Gc, depth = 2, min.node.size = 50, split.step = 20)
    sh <- mean(predict(pt, Xt[tr, ]) == 2)
    if (is.null(best) || abs(sh - share) < abs(best$sh - share)) best <- list(pt = pt, sh = sh, c0 = c0)
  }
  elig <- predict(best$pt, Xt[te, ]) == 2
  tree_txt <- c(tree_txt, sprintf("== fold %d (cost %.1f kg, treated share in training %.2f)", k, best$c0, best$sh),
                capture.output(print(best$pt)))
  # fill the budget of each round within the test fold
  for (w in names(budget)) {
    idx <- te[d$wave[te] == as.numeric(w)]
    kk <- round(budget[w] * length(idx) / sum(d$wave == as.numeric(w)))
    rnd <- runif(length(d$Y))
    assign[pick_top(rnd, idx, kk), "Random"] <- 1L
    assign[pick_top(what + 1e-6 * rnd, idx, kk), "Actual allocation, as predicted from traits"] <- 1L
    assign[pick_top(-d$wealth, idx, kk), "Poorest first"] <- 1L
    assign[pick_top(-d$area_cult + 1e-6 * rnd, idx, kk), "Smallest farms first"] <- 1L
    assign[pick_top(eff_pred, idx, kk), "Persistent efficiency first (predicted)"] <- 1L
    assign[pick_top(cate_cf, idx, kk), "Highest predicted returns"] <- 1L
    # policy tree: eligible households first (lottery within), then the rest by lottery
    tsc <- rnd + 2 * as.numeric(seq_along(d$Y) %in% te[elig])
    assign[pick_top(tsc, idx, kk), "Policy tree (depth 2)"] <- 1L
  }
  cat(sprintf("fold %d done\n", k))
}
writeLines(tree_txt, file.path(ext, "policy_tree_folds.txt"))

# full-sample policy tree (reported rule)
share <- mean(d$W)
best <- NULL
for (c0 in quantile(tau_dr, probs = seq(0.30, 0.80, by = 0.10))) {
  pt <- policy_tree(Xt, cbind(G[, 1], G[, 2] - c0), depth = 2, min.node.size = 50, split.step = 20)
  sh <- mean(predict(pt, Xt) == 2)
  if (is.null(best) || abs(sh - share) < abs(best$sh - share)) best <- list(pt = pt, sh = sh, c0 = c0)
}
writeLines(c(sprintf("Policy tree, all rounds (cost per voucher %.1f kg; share eligible %.2f; budget share %.2f)",
                     best$c0, best$sh, share), capture.output(print(best$pt))), file.path(ext, "policy_tree.txt"))

# --------------------------------------------------------------------------
# 3. value of each rule (kg of maize per voucher and per household)
# --------------------------------------------------------------------------
val <- lapply(rules, function(r) {
  s <- assign[, r] == 1
  if (r == "Actual allocation") {
    g <- att[1]; g_se <- att[2]
  } else {
    g <- mean(tau_dr[s]); g_se <- sd(tau_dr[s]) / sqrt(sum(s))
  }
  data.frame(rule = r, kg_per_voucher = g, se = g_se, n_selected = sum(s),
             share_poorest_tertile = mean(d$wealth_t[s] == 1, na.rm = TRUE),
             share_female_head = mean(d$head_female[s], na.rm = TRUE),
             mean_land_ha = mean(d$area_cult[s], na.rm = TRUE),
             mean_persistent_te = mean(d$te_p[s], na.rm = TRUE),
             share_also_actual = mean(d$W[s]))
})
val <- do.call(rbind, val)
val$gain_vs_actual <- val$kg_per_voucher - val$kg_per_voucher[val$rule == "Actual allocation"]

# paired differences with an EA cluster bootstrap (500 draws): every rule
# against the actual allocation as predicted from traits and against random
sel <- assign[, rules[-1]] == 1
mean_sel <- function(w) colSums(sel * w * tau_dr) / colSums(sel * w)
base <- mean_sel(rep(1, nrow(d)))
B <- 500
bs <- matrix(NA_real_, B, ncol(sel), dimnames = list(NULL, colnames(sel)))
ue <- unique(ea)
for (b in 1:B) {
  draw <- table(factor(sample(ue, length(ue), replace = TRUE), levels = ue))
  bs[b, ] <- mean_sel(as.numeric(draw[match(ea, ue)]))
}
dif <- function(ref) {
  dd <- bs - bs[, ref]
  data.frame(rule = colnames(sel), reference = ref, difference = base - base[ref],
             se = apply(dd, 2, sd), lo = apply(dd, 2, quantile, 0.025), hi = apply(dd, 2, quantile, 0.975))
}
pdif <- rbind(dif("Actual allocation, as predicted from traits"), dif("Random"))
write.csv(pdif, file.path(ext, "policy_differences.csv"), row.names = FALSE)
print(pdif)
val$se_boot <- c(att[2], apply(bs, 2, sd))
write.csv(val, file.path(ext, "policy_values.csv"), row.names = FALSE)
print(val)

# household assignments for the structural simulation (14_structural_allrounds.do)
out <- data.frame(wave = d$wave, hhkey = d$hhkey, case_id = d$case_id, tau_dr = tau_dr, cate = cate_cf,
                  eff_pred = eff_pred, what = what, assign)
names(out) <- c("wave", "hhkey", "case_id", "tau_dr", "cate", "eff_pred", "what",
                "r_actual", "r_actual_pred", "r_random", "r_poor", "r_small", "r_eff", "r_cate", "r_tree")
write.csv(out, file.path(der, "rule_assignment.csv"), row.names = FALSE)
cat("done\n")
