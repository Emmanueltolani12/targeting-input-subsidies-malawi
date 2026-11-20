# 07_yield_prediction.R -- out-of-sample prediction of maize yields from survey and satellite features
# Data: data/derived/all_waves_panel_sat.dta (IHPS 2010-2024 + Earth Engine
# covariates) and panel_efficiency.dta (four-component panel frontier, 06_panel_frontier;
# run that step first). All cross-validation is grouped by enumeration area
# (5 folds).
#  T1 maize yield prediction (ln kg/ha, maize growers 2010-2024): survey vs
#     satellite vs both; OLS, LASSO, random forest, gradient boosting, MLP
#  T2 implementable targeting (2010-2024): predict the two most efficient
#     quintiles of overall efficiency within the round (panel frontier) from
#     variables officials can observe (no inputs or output) with and without
#     satellite data; AUC, precision
#  T3 heterogeneous returns to fertilizer vouchers (FISP coupons / AIP):
#     double machine learning (partially linear, random-forest nuisance) and
#     an R-learner CATE; targeting on predicted returns vs actual recipients.
#     Selection on observables -- exploratory.
# Usage: Rscript code/07_yield_prediction.R [package root]   (R 4.5.2 with torch)
# Output: output/results/ml_benchmark.csv, targeting_benchmark.csv,
#         dml_results.csv, cate_groups.csv, cate_hh.csv (figures: 07b_yield_prediction_figures.R)

Sys.setenv(TORCH_HOME = file.path(Sys.getenv("LOCALAPPDATA"), "R", "torch_home"))
suppressPackageStartupMessages({
  library(haven); library(glmnet); library(ranger); library(xgboost); library(torch)
})
set.seed(20171105)
torch_manual_seed(20171105)
root <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(root)) root <- "."
out_dir <- file.path(root, "output", "results")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

d <- as.data.frame(zap_labels(read_dta(file.path(root, "data", "derived", "all_waves_panel_sat.dta"))))
d <- d[d$grows_maize == 1, ]
d$lnyield <- log(d$maize_kg / d$area_maize)
for (w in c(2013, 2016, 2019, 2024)) d[[paste0("w", w)]] <- as.numeric(d$wave == w)

# --------------------------------------------------------------------------
# feature sets
# --------------------------------------------------------------------------
observable <- c("head_female", "head_age", "hhsize", "educ_15_60", "wealth", "landowner",
                "dist_agmrkt", "dist_admarc", "antierosion", "mv", "S", "soil_fair", "soil_poor",
                "soil_mixed", "soil_clay", "temperature", "aez_warm_subhumid", "aez_cool_semiarid",
                "aez_cool_subhumid", "area_maize", "sp_farm")
inputs <- c("ln_seed", "ln_org", "ln_chit", "ln_urea", "ln_othf", "ln_lab", "ln_area")
satellite <- c("rain_season", "rain_days", "spi_chirps", "tmax", "hot30", "gdd", "evi_max", "evi_mean",
               "evi_anom", "soc", "ntot", "ph", "clay", "sand", "travel_min", "crop_share")
waves <- c("w2013", "w2016", "w2019", "w2024")

prep <- function(df, vars) {
  X <- df[, vars, drop = FALSE]
  for (v in vars) {
    if (anyNA(X[[v]])) {
      X[[paste0(v, "_na")]] <- as.numeric(is.na(X[[v]]))
      X[[v]][is.na(X[[v]])] <- median(X[[v]], na.rm = TRUE)
    }
  }
  X <- X[, vapply(X, function(z) sd(z) > 0, logical(1)), drop = FALSE]
  as.matrix(X)
}
folds_by <- function(g, k = 5) {
  u <- unique(g)
  f <- sample(rep(seq_len(k), length.out = length(u)))
  f[match(g, u)]
}
r2 <- function(y, p) 1 - sum((y - p)^2) / sum((y - mean(y))^2)
auc <- function(y, p) {
  r <- rank(p); n1 <- sum(y == 1); n0 <- sum(y == 0)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

# --------------------------------------------------------------------------
# learners: fit on train, predict test (y numeric or 0/1)
# --------------------------------------------------------------------------
fit_ols <- function(X, y, Xt, binary) {
  df <- data.frame(y = y, X)
  m <- if (binary) glm(y ~ ., data = df, family = binomial()) else lm(y ~ ., data = df)
  as.numeric(predict(m, newdata = data.frame(Xt), type = "response"))
}
fit_lasso <- function(X, y, Xt, binary) {
  m <- cv.glmnet(X, y, family = if (binary) "binomial" else "gaussian", nfolds = 5)
  as.numeric(predict(m, Xt, s = "lambda.min", type = "response"))
}
fit_rf <- function(X, y, Xt, binary) {
  m <- ranger(x = X, y = if (binary) factor(y) else y, num.trees = 500, probability = binary,
              min.node.size = 10, seed = 1)
  p <- predict(m, Xt)$predictions
  if (binary) p[, "1"] else p
}
fit_xgb <- function(X, y, Xt, binary) {
  dtr <- xgb.DMatrix(X, label = y)
  m <- xgb.train(params = list(objective = if (binary) "binary:logistic" else "reg:squarederror",
                               eta = 0.05, max_depth = 4, subsample = 0.8, colsample_bytree = 0.8,
                               min_child_weight = 5, nthread = 4),
                 data = dtr, nrounds = 400, verbose = 0)
  predict(m, xgb.DMatrix(Xt))
}
fit_mlp <- function(X, y, Xt, binary) {
  mu <- colMeans(X); s <- apply(X, 2, sd); s[s == 0] <- 1
  xs <- torch_tensor(scale(X, mu, s), dtype = torch_float())
  xt <- torch_tensor(scale(Xt, mu, s), dtype = torch_float())
  ys <- torch_tensor(matrix(y, ncol = 1), dtype = torch_float())
  net <- nn_sequential(nn_linear(ncol(X), 64), nn_relu(), nn_dropout(0.2),
                       nn_linear(64, 32), nn_relu(), nn_dropout(0.2), nn_linear(32, 1))
  opt <- optim_adam(net$parameters, lr = 1e-3, weight_decay = 1e-4)
  lossf <- if (binary) nn_bce_with_logits_loss() else nn_mse_loss()
  n <- nrow(X); idx_val <- sample(n, floor(0.15 * n)); idx_tr <- setdiff(seq_len(n), idx_val)
  best <- Inf; best_state <- NULL; patience <- 0
  for (ep in 1:300) {
    net$train()
    for (b in split(sample(idx_tr), ceiling(seq_along(idx_tr) / 128))) {
      opt$zero_grad()
      l <- lossf(net(xs[b, ]), ys[b, ])
      l$backward(); opt$step()
    }
    net$eval()
    vl <- with_no_grad(lossf(net(xs[idx_val, ]), ys[idx_val, ])$item())
    if (vl < best - 1e-5) {
      best <- vl; patience <- 0
      best_state <- lapply(net$state_dict(), function(t) t$clone())
    } else if ((patience <- patience + 1) >= 20) break
  }
  net$load_state_dict(best_state); net$eval()
  p <- with_no_grad(as.numeric(net(xt)))
  if (binary) plogis(p) else p
}
LEARNERS <- list(OLS = fit_ols, LASSO = fit_lasso, `Random forest` = fit_rf,
                 `Gradient boosting` = fit_xgb, `Neural network` = fit_mlp)

cv_pred <- function(X, y, fold, learner, binary = FALSE) {
  p <- numeric(length(y))
  for (k in sort(unique(fold))) {
    tr <- fold != k
    p[!tr] <- learner(X[tr, , drop = FALSE], y[tr], X[!tr, , drop = FALSE], binary)
  }
  p
}

# --------------------------------------------------------------------------
# T1 yield prediction
# --------------------------------------------------------------------------
t1 <- d[is.finite(d$lnyield), ]
fold1 <- folds_by(t1$ea_id)
sets <- list(Survey = c(observable, inputs, waves), Satellite = c(satellite, waves),
             `Survey + satellite` = c(observable, inputs, satellite, waves))
res1 <- list()
for (sn in names(sets)) {
  X <- prep(t1, sets[[sn]])
  for (ln in names(LEARNERS)) {
    t0 <- Sys.time()
    p <- cv_pred(X, t1$lnyield, fold1, LEARNERS[[ln]])
    res1[[length(res1) + 1]] <- data.frame(task = "T1 ln maize yield", features = sn, model = ln,
                                           r2 = r2(t1$lnyield, p), n = nrow(X))
    cat(sprintf("T1 %-20s %-18s R2 = %.3f (%.0fs)\n", sn, ln, r2(t1$lnyield, p),
                as.numeric(Sys.time() - t0, units = "secs")))
  }
}
res1 <- do.call(rbind, res1)
write.csv(res1, file.path(out_dir, "ml_benchmark.csv"), row.names = FALSE)

# --------------------------------------------------------------------------
# T2 implementable targeting of efficient farmers (2010-2024): the two most
# efficient quintiles of overall efficiency within the round (panel frontier)
# --------------------------------------------------------------------------
pe <- as.data.frame(zap_labels(read_dta(file.path(root, "data", "derived", "panel_efficiency.dta"))))
t2 <- merge(pe[!is.na(pe$q_o), c("hhkey", "wave", "q_o")], d[, c("hhkey", "wave", "ea_id", observable, satellite, waves)],
            by = c("hhkey", "wave"))
t2$efficient <- as.numeric(t2$q_o >= 4)
fold2 <- folds_by(t2$ea_id)
sets2 <- list(Observable = c(observable, waves), `Observable + satellite` = c(observable, satellite, waves))
res2 <- list()
for (sn in names(sets2)) {
  X <- prep(t2, sets2[[sn]])
  for (ln in names(LEARNERS)) {
    p <- cv_pred(X, t2$efficient, fold2, LEARNERS[[ln]], binary = TRUE)
    top <- p >= quantile(p, 0.6)              # select 40% of households
    res2[[length(res2) + 1]] <- data.frame(task = "T2 efficient (top two quintiles)", features = sn,
                                           model = ln, auc = auc(t2$efficient, p),
                                           precision_at_40 = mean(t2$efficient[top]),
                                           base_rate = mean(t2$efficient), n = nrow(X))
    cat(sprintf("T2 %-24s %-18s AUC = %.3f, precision@40%% = %.3f\n", sn, ln,
                auc(t2$efficient, p), mean(t2$efficient[top])))
  }
}
res2 <- do.call(rbind, res2)
write.csv(res2, file.path(out_dir, "targeting_benchmark.csv"), row.names = FALSE)

# --------------------------------------------------------------------------
# T3 heterogeneous returns to fertilizer vouchers (DML + R-learner)
# --------------------------------------------------------------------------
t3 <- t1
t3$W <- as.numeric(t3$vou_fert == 1)
X3 <- prep(t3, c(observable, satellite, waves))
fold3 <- folds_by(t3$ea_id)
rf_reg <- function(X, y, Xt) predict(ranger(x = X, y = y, num.trees = 500, min.node.size = 20, seed = 2), Xt)$predictions
mhat <- ehat <- numeric(nrow(t3))
for (k in 1:5) {
  tr <- fold3 != k
  mhat[!tr] <- rf_reg(X3[tr, ], t3$lnyield[tr], X3[!tr, ])
  ehat[!tr] <- rf_reg(X3[tr, ], t3$W[tr], X3[!tr, ])
}
ehat <- pmin(pmax(ehat, 0.05), 0.95)
yt <- t3$lnyield - mhat
wt <- t3$W - ehat
theta <- sum(wt * yt) / sum(wt^2)
psi <- (yt - theta * wt) * wt / mean(wt^2)
se <- sqrt(var(psi) / nrow(t3))
naive <- coef(lm(lnyield ~ W, data = t3))[2]
dml <- data.frame(estimate = c("Naive difference", "DML (random forest, cross-fitted)"),
                  effect_ln_yield = c(naive, theta), se = c(NA, se), n = nrow(t3))
cat(sprintf("T3 DML effect of fertilizer voucher on ln yield: %.3f (se %.3f); naive %.3f\n", theta, se, naive))
write.csv(dml, file.path(out_dir, "dml_results.csv"), row.names = FALSE)

# R-learner: regress yt/wt on X with weights wt^2 (cross-fitted)
tau <- numeric(nrow(t3))
for (k in 1:5) {
  tr <- fold3 != k
  m <- ranger(x = X3[tr, ], y = (yt / wt)[tr], case.weights = (wt^2)[tr], num.trees = 1000,
              min.node.size = 50, seed = 3)
  tau[!tr] <- predict(m, X3[!tr, ])$predictions
}
t3$tau <- tau
grp <- function(name, g) {
  do.call(rbind, lapply(sort(unique(g[!is.na(g)])), function(v)
    data.frame(group = name, level = as.character(v), mean_cate = mean(tau[g == v], na.rm = TRUE),
               share_recipients = mean(t3$W[g == v], na.rm = TRUE), n = sum(g == v, na.rm = TRUE))))
}
cg <- rbind(grp("Wealth tertile", t3$wealth_t), grp("Survey round", t3$wave),
            grp("Agro-ecological zone", ifelse(t3$aez_warm_subhumid == 1, "warm sub-humid",
                ifelse(t3$aez_cool_semiarid == 1, "cool semi-arid",
                ifelse(t3$aez_cool_subhumid == 1, "cool sub-humid", "warm semi-arid")))))
# targeting comparison: same number of beneficiaries as actual recipients
nrec <- sum(t3$W)
sel <- order(-tau)[seq_len(nrec)]
cg <- rbind(cg, data.frame(group = "Targeting", level = c("Actual recipients", "Top predicted returns", "All maize growers"),
                           mean_cate = c(mean(tau[t3$W == 1]), mean(tau[sel]), mean(tau)),
                           share_recipients = c(1, mean(t3$W[sel]), mean(t3$W)), n = c(nrec, nrec, nrow(t3))))
write.csv(cg, file.path(out_dir, "cate_groups.csv"), row.names = FALSE)
print(cg)

# household-level predicted returns (figures: 07b_yield_prediction_figures.R)
write.csv(data.frame(wave = t3$wave, voucher = t3$W, tau = tau),
          file.path(out_dir, "cate_hh.csv"), row.names = FALSE)
cat("done\n")
