# ==============================================================================
# 11_satellite_targeting.R -- value of satellite information for targeting
# For three sets of features that a program could hold at registration,
#   survey     household and plot traits a register can verify (as 09_causal_forest_rules)
#   satellite  features available for every location without a survey:
#              iSDAsoil soils, travel time, cropland share, Sentinel-2 crop
#              vigor (2018/19-2022/23 mean of the seasonal NDVI peak),
#              long-run rainfall, its variability and temperature
#   both       survey and satellite features
# a causal forest is fitted on four folds of enumeration areas (the folds of
# 09_causal_forest_rules) and predicts the return to a fertilizer voucher on the fifth. Each
# rule serves, in every round and fold, as many households as actually
# received a voucher, ranked by the predicted return. Rules are valued with the
# doubly robust scores of 09_causal_forest_rules (mean score of the households served) and
# compared, with an enumeration-area bootstrap (500 draws), with random
# selection, the actual allocation reproduced from verifiable traits, poorest
# first and each other. Targeting operating characteristics: the gain over the
# average return among the top q of households ranked by each feature set,
# and its integral over q (AUTOC; Yadlowsky et al. 2025).
# Inputs: data/derived/all_waves_panel_sat.dta, panel_efficiency.dta,
#         ext_points_grid_features.csv (10_grid_predictions), rule_assignment.csv (09_causal_forest_rules)
# Output: output/results/satellite_targeting.csv, satellite_toc.csv,
#         fig_toc.png/.pdf
# ==============================================================================
suppressMessages({
  library(haven); library(grf); library(ggplot2)
})
set.seed(20171105)
root <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(root)) root <- "."
ext <- file.path(root, "output", "results")
der <- file.path(root, "data", "derived")

# data and folds exactly as in 09_causal_forest_rules
d <- as.data.frame(zap_labels(read_dta(file.path(der, "all_waves_panel_sat.dta"))))
d <- d[d$grows_maize == 1, ]
pe <- as.data.frame(zap_labels(read_dta(file.path(der, "panel_efficiency.dta"))))
d <- merge(d, pe[, c("wave", "hhkey", "te_p", "te_o", "uid", "T")], by = c("wave", "hhkey"), all.x = TRUE)
d$Y <- d$maize_kg
d$W <- as.numeric(d$vou_fert == 1)
for (w in c(2013, 2016, 2019, 2024)) d[[paste0("w", w)]] <- as.numeric(d$wave == w)
ea <- as.integer(factor(d$ea_id))
u <- unique(ea); fold <- sample(rep(1:5, length.out = length(u)))[match(ea, u)]

# doubly robust scores and reference rules of 09_causal_forest_rules
ra <- read.csv(file.path(der, "rule_assignment.csv"), colClasses = c(hhkey = "character"))
m <- match(paste(d$wave, d$hhkey), paste(ra$wave, ra$hhkey))
stopifnot(!anyNA(m))
tau <- ra$tau_dr[m]
ref <- data.frame(random = ra$r_random[m], actual_pred = ra$r_actual_pred[m], poor = ra$r_poor[m])

# satellite features at the household locations (5 km means of the 1 km grid)
gf <- read.csv(file.path(der, "ext_points_grid_features.csv"))
mg <- match(d$pid, gf$pid)
for (v in c("s2_peak", "rain_lr", "rain_cv", "tmax_lr")) d[[paste0("g_", v)]] <- gf[[v]][mg]

verif <- c("head_female", "head_age", "hhsize", "educ_15_60", "wealth", "landowner", "area_cult",
           "soil_fair", "soil_poor", "soil_mixed", "soil_clay", "aez_warm_subhumid", "aez_cool_semiarid",
           "aez_cool_subhumid", "temperature", "dist_agmrkt", "dist_admarc")
static_sat <- c("soc", "ntot", "ph", "clay", "sand", "travel_min", "crop_share")
grid <- c("g_s2_peak", "g_rain_lr", "g_rain_cv", "g_tmax_lr")
waves <- c("w2013", "w2016", "w2019", "w2024")
sets <- list(survey = c(verif, waves), satellite = c(static_sat, grid, waves),
             both = c(verif, static_sat, grid, waves))
fill <- function(df, vars) {
  X <- df[, vars, drop = FALSE]
  for (v in vars) if (anyNA(X[[v]])) X[[v]][is.na(X[[v]])] <- median(X[[v]], na.rm = TRUE)
  as.matrix(X)
}
cat(sprintf("%d maize-grower observations; %d with Sentinel-2 vigor at the location\n",
            nrow(d), sum(!is.na(d$g_s2_peak))))

# cross-fitted predicted returns and rules
budget <- tapply(d$W, d$wave, sum)
pick_top <- function(score, idx, k) {
  if (k <= 0) return(integer(0))
  idx[order(-score[idx])][seq_len(min(k, length(idx)))]
}
pred <- matrix(NA_real_, nrow(d), length(sets), dimnames = list(NULL, names(sets)))
sel <- matrix(0L, nrow(d), length(sets), dimnames = list(NULL, names(sets)))
for (s in names(sets)) {
  X <- fill(d, sets[[s]])
  for (k in 1:5) {
    tr <- which(fold != k); te <- which(fold == k)
    cfk <- causal_forest(X[tr, ], d$Y[tr], d$W[tr], clusters = ea[tr], num.trees = 1000, seed = 40 + k)
    pred[te, s] <- predict(cfk, X[te, ])$predictions
    for (w in names(budget)) {
      idx <- te[d$wave[te] == as.numeric(w)]
      kk <- round(budget[w] * length(idx) / sum(d$wave == as.numeric(w)))
      sel[pick_top(pred[, s], idx, kk), s] <- 1L
    }
  }
  cat(sprintf("%s done\n", s))
}
allsel <- cbind(sel, as.matrix(ref))
lab <- c(survey = "Survey traits", satellite = "Satellite features only", both = "Survey and satellite",
         random = "Random", actual_pred = "Actual allocation, as predicted from traits", poor = "Poorest first")

# values and bootstrap differences
mean_sel <- function(w) colSums(allsel * w * tau) / colSums(allsel * w)
base <- mean_sel(rep(1, nrow(d)))
B <- 500
ue <- unique(ea)
bs <- matrix(NA_real_, B, ncol(allsel), dimnames = list(NULL, colnames(allsel)))
# targeting operating characteristic on the pooled cross-fitted ranking
qs <- seq(0.05, 1, by = 0.05)
toc <- function(score, w) {
  o <- order(-score)
  g <- tau[o]; ww <- w[o]
  cw <- cumsum(ww); n <- sum(ww); avg <- sum(g * ww) / n
  sapply(qs, function(q) { k <- cw <= q * n; sum(g[k] * ww[k]) / sum(ww[k]) - avg })
}
toc0 <- sapply(names(sets), function(s) toc(pred[, s], rep(1, nrow(d))))
tocb <- array(NA_real_, c(B, length(qs), length(sets)))
for (b in 1:B) {
  draw <- table(factor(sample(ue, length(ue), replace = TRUE), levels = ue))
  w <- as.numeric(draw[match(ea, ue)])
  bs[b, ] <- mean_sel(w)
  for (j in seq_along(sets)) tocb[b, , j] <- toc(pred[, j], w)
}
res <- data.frame(rule = names(base), label = lab[names(base)], kg_per_voucher = base,
                  se = apply(bs, 2, sd), n_selected = colSums(allsel),
                  share_poorest_tertile = colSums(allsel * (d$wealth_t == 1), na.rm = TRUE) / colSums(allsel),
                  row.names = NULL)
for (r in c("random", "actual_pred", "survey")) {
  dd <- bs - bs[, r]
  res[[paste0("diff_", r)]] <- base - base[r]
  res[[paste0("se_diff_", r)]] <- apply(dd, 2, sd)
  res[[paste0("lo_", r)]] <- apply(dd, 2, quantile, 0.025)
  res[[paste0("hi_", r)]] <- apply(dd, 2, quantile, 0.975)
  res[[paste0("p_", r)]] <- apply(dd, 2, function(x) min(1, 2 * min(mean(x <= 0), mean(x >= 0))))
}
# AUTOC (mean of the targeting operating characteristic over q)
autoc <- colMeans(toc0)
autoc_se <- apply(apply(tocb, c(1, 3), mean), 2, sd)
res$autoc <- c(autoc, NA, NA, NA)[match(res$rule, c(names(sets), "random", "actual_pred", "poor"))]
res$se_autoc <- c(autoc_se, NA, NA, NA)[match(res$rule, c(names(sets), "random", "actual_pred", "poor"))]
# correlation of the predicted returns across feature sets
res$corr_with_both <- c(cor(pred[, "survey"], pred[, "both"]), cor(pred[, "satellite"], pred[, "both"]), 1, NA, NA, NA)
write.csv(res, file.path(ext, "satellite_targeting.csv"), row.names = FALSE)
print(res[, c("rule", "kg_per_voucher", "se", "diff_random", "se_diff_random", "diff_survey", "se_diff_survey", "autoc", "se_autoc")])

tocd <- do.call(rbind, lapply(seq_along(sets), function(j) data.frame(
  set = lab[names(sets)[j]], q = qs, toc = toc0[, j],
  lo = apply(tocb[, , j], 2, quantile, 0.025), hi = apply(tocb[, , j], 2, quantile, 0.975))))
write.csv(tocd, file.path(ext, "satellite_toc.csv"), row.names = FALSE)

# figure: targeting operating characteristic by feature set
pal <- c("Survey traits" = "#0072B2", "Satellite features only" = "#E69F00", "Survey and satellite" = "#009E73")
tocd$set <- factor(tocd$set, levels = names(pal))
p <- ggplot(tocd, aes(q * 100, toc, colour = set, fill = set)) +
  geom_hline(yintercept = 0, colour = "grey55", linewidth = 0.4) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.12, colour = NA) +
  geom_line(linewidth = 0.8) +
  scale_colour_manual(values = pal, name = NULL) + scale_fill_manual(values = pal, name = NULL) +
  labs(x = "Share of households served, ranked by predicted return (%)",
       y = "Gain over the average return (kg maize per voucher)") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top", panel.grid.minor = element_blank(),
        panel.grid.major = element_line(colour = "grey90", linewidth = 0.3))
ggsave(file.path(ext, "fig_toc.png"), p, width = 6.5, height = 4, dpi = 300, bg = "white")
ggsave(file.path(ext, "fig_toc.pdf"), p, width = 6.5, height = 4)
cat("done\n")
