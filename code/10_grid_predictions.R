# 10_grid_predictions.R -- Sentinel-2 crop vigor and out-of-sample targeting maps
# A causal forest restricted to features that exist on a national grid
# (Sentinel-2 crop vigor, cropland share, iSDA soils, travel time, long-run
# CHIRPS rainfall and its variability, ERA5-Land maximum temperature; gee/gee_national_grid.py,
# which lists the Earth Engine datasets; tiles in data/raw/satellite/grid)
# predicts the maize return to a fertilizer voucher (kg) for every 1 km
# cropland cell of Malawi, outside the surveyed enumeration areas.
# Honest check: cross-fitted by EA (5 folds), the satellite-only ranking
# selects the actual number of recipients per round and is valued with the
# doubly robust scores of the survey forest (09_causal_forest_rules).
# Maps: 300 dpi, overview with zoom boxes (A: Lilongwe-Kasungu plain,
# B: Shire Highlands) and the zooms.
# Usage: Rscript code/10_grid_predictions.R [package root]
# Output: output/results/fig_s2_vigour.png/.pdf, fig_returns_map.png/.pdf,
#         grid_targeting.csv (value of satellite-only targeting),
#         district_returns.csv; data/derived/grid/predicted_returns.tif

suppressPackageStartupMessages({
  library(haven); library(grf); library(terra); library(sf); library(ggplot2)
  library(patchwork); library(ggrepel)
})
set.seed(20171105)
root <- commandArgs(trailingOnly = TRUE)[1]
# folder with the licensed survey data and the district boundaries
restricted <- commandArgs(trailingOnly = TRUE)[2]
if (is.na(restricted)) restricted <- file.path(root, "data", "raw")
if (is.na(root)) root <- "."
ext <- file.path(root, "output", "results")
der <- file.path(root, "data", "derived")
feats <- c("s2_peak", "crop_share", "soc", "ntot", "ph", "clay", "sand", "travel_min",
           "rain_lr", "rain_cv", "tmax_lr")
BANDS <- c("s2_peak", "s2_peak24", "s2_anom24", "crop_share", "soc", "ntot", "ph", "clay", "sand",
           "travel_min", "rain_lr", "rain_cv", "tmax_lr")

# --------------------------------------------------------------------------
# 1. grid
# --------------------------------------------------------------------------
tl <- list.files(file.path(root, "data", "raw", "satellite", "grid"), "^tile_[0-9]+\\.tif$", full.names = TRUE)
g <- merge(sprc(lapply(tl, rast)))
names(g) <- BANDS
g <- classify(g, cbind(-Inf, NA))
gd <- as.data.frame(g, xy = TRUE, na.rm = FALSE)
gd <- gd[!is.na(gd$crop_share), ]
gd$x <- round(gd$x, 3); gd$y <- round(gd$y, 3)   # exact 0.01-degree cell centres

# --------------------------------------------------------------------------
# 2. households: grid features at their locations
# --------------------------------------------------------------------------
fill <- function(df, vars) {
  X <- df[, vars, drop = FALSE]
  for (v in vars) if (anyNA(X[[v]])) X[[v]][is.na(X[[v]])] <- median(X[[v]], na.rm = TRUE)
  as.matrix(X)
}
# grid features at the household locations: mean of the cells within 5 km
pts0 <- read.csv(file.path(der, "ext_points.csv"))
pts0 <- pts0[complete.cases(pts0), ]
pb <- st_transform(st_buffer(st_transform(st_as_sf(pts0, coords = c("lon", "lat"), crs = 4326), 32736), 5000), 4326)
pf <- exactextractr::exact_extract(g, pb, "mean", progress = FALSE)
names(pf) <- sub("^mean\\.", "", names(pf))
pf$pid <- pts0$pid
write.csv(pf, file.path(der, "ext_points_grid_features.csv"), row.names = FALSE)
xw <- as.data.frame(zap_labels(read_dta(file.path(der, "ext_point_xwalk.dta"))))
d <- as.data.frame(zap_labels(read_dta(file.path(der, "all_waves_panel_sat.dta"))))
d <- d[d$grows_maize == 1, setdiff(names(d), BANDS)]
if (!"pid" %in% names(d)) d <- merge(d, xw[, c("wave", "hhkey", "pid")], by = c("wave", "hhkey"), all.x = TRUE)
d <- merge(d, pf[, c("pid", BANDS)], by = "pid", all.x = TRUE)
ra <- read.csv(file.path(der, "rule_assignment.csv"), colClasses = c(hhkey = "character"))
d <- merge(d, ra[, c("wave", "hhkey", "tau_dr")], by = c("wave", "hhkey"), all.x = TRUE)
d$Y <- d$maize_kg
d$W <- as.numeric(d$vou_fert == 1)
for (w in c(2013, 2016, 2019, 2024)) d[[paste0("w", w)]] <- as.numeric(d$wave == w)
waves <- c("w2013", "w2016", "w2019", "w2024")
X <- fill(d, c(feats, waves))
ea <- as.integer(factor(d$ea_id))
cat(sprintf("%d maize-grower observations, %d with grid features\n", nrow(d), sum(!is.na(d$s2_peak))))

# honest value of satellite-only targeting
u <- unique(ea); fold <- sample(rep(1:5, length.out = length(u)))[match(ea, u)]
cate <- rep(NA_real_, nrow(d))
for (k in 1:5) {
  tr <- fold != k
  m <- causal_forest(X[tr, ], d$Y[tr], d$W[tr], clusters = ea[tr], num.trees = 1000, seed = 40 + k)
  cate[!tr] <- predict(m, X[!tr, ])$predictions
}
sel <- rep(FALSE, nrow(d)); selr <- rep(FALSE, nrow(d))
for (w in unique(d$wave)) {
  idx <- which(d$wave == w)
  k <- sum(d$W[idx])
  sel[idx[order(-cate[idx])][seq_len(k)]] <- TRUE
  selr[sample(idx, k)] <- TRUE
}
ok <- !is.na(d$tau_dr)
val <- data.frame(rule = c("Satellite-only predicted returns", "Random"),
                  kg_per_voucher = c(mean(d$tau_dr[sel & ok]), mean(d$tau_dr[selr & ok])),
                  se = c(sd(d$tau_dr[sel & ok]) / sqrt(sum(sel & ok)), sd(d$tau_dr[selr & ok]) / sqrt(sum(selr & ok))),
                  n = c(sum(sel), sum(selr)),
                  share_poorest_tertile = c(mean(d$wealth_t[sel] == 1, na.rm = TRUE), mean(d$wealth_t[selr] == 1, na.rm = TRUE)))
write.csv(val, file.path(ext, "grid_targeting.csv"), row.names = FALSE)
print(val)

# full forest and grid prediction (2024 conditions)
cf <- causal_forest(X, d$Y, d$W, clusters = ea, num.trees = 2000, seed = 50)
gp <- gd[gd$crop_share >= 0.10 & complete.cases(gd[, feats]), ]
Xg <- cbind(as.matrix(gp[, feats]), w2013 = 0, w2016 = 0, w2019 = 0, w2024 = 1)
gp$ret <- predict(cf, Xg)$predictions
rr <- rast(gp[, c("x", "y", "ret")], type = "xyz", crs = "EPSG:4326")
dir.create(file.path(der, "grid"), showWarnings = FALSE, recursive = TRUE)
writeRaster(rr, file.path(der, "grid", "predicted_returns.tif"), overwrite = TRUE)

# --------------------------------------------------------------------------
# 3. district summary: predicted return (cropland-weighted) vs coverage
# --------------------------------------------------------------------------
districts <- st_read(file.path(restricted, "maps", "mwi_districts.shp"), quiet = TRUE)
pts <- st_as_sf(gp, coords = c("x", "y"), crs = 4326)
pts <- st_join(pts, districts["NAME_1"])
pdf_ <- st_drop_geometry(pts)
pdf_$ret_w <- pdf_$ret * pdf_$crop_share
dr <- aggregate(cbind(ret_w, crop_share) ~ NAME_1, data = pdf_, FUN = sum)
dr$pred_return <- dr$ret_w / dr$crop_share
# IHPS district codes -> GADM names (cities merged into their district; as code/ado/district_names.ado)
codes <- c(`101` = "Chitipa", `102` = "Karonga", `103` = "Nkhata Bay", `104` = "Rumphi", `105` = "Mzimba",
           `106` = "Likoma", `107` = "Mzimba", `201` = "Kasungu", `202` = "Nkhotakota", `203` = "Ntchisi",
           `204` = "Dowa", `205` = "Salima", `206` = "Lilongwe", `207` = "Mchinji", `208` = "Dedza",
           `209` = "Ntcheu", `210` = "Lilongwe", `301` = "Mangochi", `302` = "Machinga", `303` = "Zomba",
           `304` = "Chiradzulu", `305` = "Blantyre", `306` = "Mwanza", `307` = "Thyolo", `308` = "Mulanje",
           `309` = "Phalombe", `310` = "Chikwawa", `311` = "Nsanje", `312` = "Balaka", `313` = "Neno",
           `314` = "Zomba", `315` = "Blantyre")
cov <- d[d$wave %in% c(2019, 2024), c("wave", "district", "W")]
cov$NAME_1 <- codes[as.character(cov$district)]
cv <- aggregate(W ~ NAME_1 + wave, data = cov, FUN = mean)
cv <- reshape(cv, idvar = "NAME_1", timevar = "wave", direction = "wide")
names(cv) <- sub("^W\\.", "coverage_", names(cv))
dr <- merge(dr, cv, by = "NAME_1", all.x = TRUE)
write.csv(dr[, c("NAME_1", "pred_return", grep("^coverage_", names(dr), value = TRUE))],
          file.path(ext, "district_returns.csv"), row.names = FALSE)

# --------------------------------------------------------------------------
# 4. maps
# --------------------------------------------------------------------------
ink <- "#0b0b0b"; ink2 <- "#52514e"; bg <- "#f0efec"
zA <- c(33.30, 34.30, -13.90, -12.80)   # Lilongwe-Kasungu plain
zB <- c(34.80, 35.80, -16.30, -15.25)   # Shire Highlands
box <- function(z, lab) list(
  annotate("rect", xmin = z[1], xmax = z[2], ymin = z[3], ymax = z[4], fill = NA, colour = ink, linewidth = 0.4),
  annotate("text", x = z[1] - 0.06, y = z[4], label = lab, hjust = 1, vjust = 1, size = 3, fontface = "bold", colour = ink))
theme_m <- theme_void(base_size = 9) +
  theme(plot.title = element_text(face = "bold", size = 9, colour = ink, hjust = 0),
        legend.position = "bottom", legend.title = element_text(size = 8, colour = ink),
        legend.text = element_text(size = 7, colour = ink2), legend.key.height = unit(5, "pt"),
        legend.key.width = unit(22, "pt"), plot.margin = margin(3, 3, 3, 3))
base_map <- function(df, var, scale, title, zoom = NULL, boxes = TRUE) {
  p <- ggplot() + geom_sf(data = districts, fill = bg, colour = NA) +
    geom_tile(data = df, aes(x = x, y = y, fill = .data[[var]]), width = 0.01, height = 0.01) +
    geom_sf(data = districts, fill = NA, colour = "white", linewidth = 0.2) + scale + labs(title = title) + theme_m
  if (is.null(zoom)) {
    p <- p + coord_sf(expand = FALSE)
    if (boxes) p <- p + box(zA, "A") + box(zB, "B")
  } else {
    p <- p + coord_sf(xlim = zoom[1:2], ylim = zoom[3:4], expand = FALSE) + theme(legend.position = "none")
  }
  p
}
greens <- c("#eef4e8", "#c3dfb4", "#86bf73", "#3f8f3a", "#14532d")
vg <- gd[gd$crop_share >= 0.10 & !is.na(gd$s2_peak), ]
lim_v <- quantile(vg$s2_peak, c(0.01, 0.99))
sc_v <- scale_fill_gradientn(colours = greens, limits = lim_v, oob = scales::squish, name = "Peak NDVI", guide = guide_colourbar(title.position = "top", title.hjust = 0.5),
                             labels = scales::label_number(accuracy = 0.01), breaks = scales::breaks_pretty(4))
a_lim <- max(abs(quantile(vg$s2_anom24, c(0.01, 0.99), na.rm = TRUE)))
sc_a <- scale_fill_gradient2(low = "#e34948", mid = "#f0efec", high = "#2a78d6", midpoint = 0,
                             limits = c(-a_lim, a_lim), oob = scales::squish, name = "Change in peak NDVI, 2023/24", guide = guide_colourbar(title.position = "top", title.hjust = 0.5),
                             labels = scales::label_number(accuracy = 0.01), breaks = c(-signif(0.8 * a_lim, 1), 0, signif(0.8 * a_lim, 1)))
p1 <- base_map(vg, "s2_peak", sc_v, "a. Crop vigor, 2019-2023")
p2 <- base_map(vg, "s2_anom24", sc_a, "b. 2023/24 (drought)", boxes = TRUE)
p3 <- base_map(vg, "s2_peak", sc_v, "A. Lilongwe-Kasungu plain", zoom = zA)
p4 <- base_map(vg, "s2_peak", sc_v, "B. Shire Highlands", zoom = zB)
f1 <- (p1 | p2 | (p3 / p4)) + plot_layout(widths = c(1, 1, 1.15))
ggsave(file.path(ext, "fig_s2_vigour.png"), f1, width = 6.3, height = 6.2, dpi = 300, bg = "white")
ggsave(file.path(ext, "fig_s2_vigour.pdf"), f1, width = 6.3, height = 6.2, device = cairo_pdf, bg = "white")

blues <- c("#e3eefb", "#a9cbf3", "#5598e7", "#1c5cab", "#0b2f5e")
lim_r <- quantile(gp$ret, c(0.01, 0.99))
sc_r <- scale_fill_gradientn(colours = blues, limits = lim_r, oob = scales::squish, name = "kg maize per voucher", guide = guide_colourbar(title.position = "top", title.hjust = 0.5),
                             breaks = scales::breaks_pretty(4))
q1 <- base_map(gp, "ret", sc_r, "a. Predicted return, 2024 conditions")
q2 <- base_map(gp, "ret", sc_r, "A. Lilongwe-Kasungu plain", zoom = zA)
q3 <- base_map(gp, "ret", sc_r, "B. Shire Highlands", zoom = zB)
dd <- dr[!is.na(dr$coverage_2024), ]
q4 <- ggplot(dd, aes(x = 100 * coverage_2024, y = pred_return)) +
  geom_point(size = 2, colour = "#2a78d6") +
  geom_text_repel(aes(label = NAME_1), size = 2.4, colour = ink2, min.segment.length = 0.2, seed = 1, max.overlaps = 30) +
  labs(x = "AIP recipients among maize growers, 2024 (%)", y = "Predicted return (kg per voucher)",
       title = "b. Districts") +
  theme_minimal(base_size = 8) +
  theme(plot.title = element_text(face = "bold", size = 9, colour = ink), panel.grid.minor = element_blank(),
        axis.text = element_text(colour = ink2), axis.title = element_text(colour = ink))
f2 <- (q1 | (q2 / q3) | q4) + plot_layout(widths = c(1, 0.9, 1.5))
ggsave(file.path(ext, "fig_returns_map.png"), f2, width = 6.3, height = 5.4, dpi = 300, bg = "white")
ggsave(file.path(ext, "fig_returns_map.pdf"), f2, width = 6.3, height = 5.4, device = cairo_pdf, bg = "white")
cat(sprintf("grid cells with cropland >= 10%%: %d; correlation of district return and 2024 coverage: %.2f\n",
            nrow(gp), cor(dd$pred_return, dd$coverage_2024, use = "complete.obs")))
cat("done\n")
