# 07b_yield_prediction_figures.R -- figures of the machine-learning benchmarks (07_yield_prediction.R)
# Drawn at the size they are printed (16 cm text width), so the type is 8-9 pt
# on the page. Reads the csv files written by 07_yield_prediction.R.
# Usage: Rscript code/07b_yield_prediction_figures.R [package root]
# Output: output/results/fig_ml_benchmark.png/.pdf, fig_cate.png/.pdf

suppressPackageStartupMessages({
  library(ggplot2); library(patchwork)
})
root <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(root)) root <- "."
ext <- file.path(root, "output", "results")

MODELS <- c("OLS", "LASSO", "Random forest", "Gradient boosting", "Neural network")
INK <- "#0b0b0b"; INK2 <- "#52514e"; GRID <- "#e4e3df"
pal1 <- c("Survey" = "#2a78d6", "Satellite" = "#eb6834", "Survey + satellite" = "#1baf7a")
pal2 <- c("Observable" = "#2a78d6", "Observable + satellite" = "#1baf7a")

theme_note <- function() {
  theme_minimal(base_size = 9, base_family = "sans") +
    theme(panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(colour = GRID, linewidth = 0.3),
          axis.text = element_text(colour = INK2, size = 8), axis.title = element_text(colour = INK, size = 8.5),
          legend.position = "bottom", legend.text = element_text(colour = INK, size = 8),
          legend.margin = margin(0, 0, 0, 0), legend.box.spacing = unit(2, "pt"), legend.key.width = unit(8, "pt"), legend.spacing.x = unit(2, "pt"),
          plot.title = element_text(face = "bold", size = 9, colour = INK, hjust = 0),
          plot.title.position = "plot", plot.margin = margin(4, 8, 4, 4))
}

save_both <- function(g, name, w, h) {
  ggsave(file.path(ext, paste0(name, ".png")), g, width = w, height = h, dpi = 300, bg = "white")
  ggsave(file.path(ext, paste0(name, ".pdf")), g, width = w, height = h, device = cairo_pdf, bg = "white")
}

# --------------------------------------------------------------------------
# Figure 1: yield prediction (R2) and identification of efficient farmers (AUC)
# --------------------------------------------------------------------------
r1 <- read.csv(file.path(ext, "ml_benchmark.csv"))
r1$model <- factor(r1$model, levels = rev(MODELS))
r1$features <- factor(r1$features, levels = names(pal1))
g1 <- ggplot(r1, aes(x = r2, y = model)) +
  geom_point(aes(fill = features), size = 2.4, shape = 21, colour = "white", stroke = 0.5) +
  scale_fill_manual(values = pal1, name = NULL, guide = guide_legend(nrow = 1)) +
  scale_x_continuous(limits = c(0.1, 0.42), breaks = seq(0.1, 0.4, 0.1)) +
  labs(x = expression("Out-of-sample " * R^2), y = NULL, title = "A. ln maize yield, 2010-2024") +
  theme_note()

r2 <- read.csv(file.path(ext, "targeting_benchmark.csv"))
r2$model[r2$model == "OLS"] <- "Logit"
r2$model[r2$model == "LASSO"] <- "LASSO logit"
r2$model <- factor(r2$model, levels = rev(c("Logit", "LASSO logit", MODELS[3:5])))
r2$features <- factor(r2$features, levels = names(pal2))
g2 <- ggplot(r2, aes(x = auc, y = model)) +
  geom_point(aes(fill = features), size = 2.4, shape = 21, colour = "white", stroke = 0.5) +
  scale_fill_manual(values = pal2, name = NULL, guide = guide_legend(nrow = 1)) +
  scale_x_continuous(limits = c(0.74, 0.79), breaks = seq(0.74, 0.79, 0.01)) +
  labs(x = "AUC", y = NULL, title = "B. Two most efficient quintiles of the round, 2010-2024") +
  theme_note()
save_both(g1 + g2 + plot_layout(widths = c(1, 1)), "fig_ml_benchmark", 6.3, 2.9)

# --------------------------------------------------------------------------
# Figure 2: distribution of predicted returns (R-learner)
# --------------------------------------------------------------------------
hh <- read.csv(file.path(ext, "cate_hh.csv"))
dml <- read.csv(file.path(ext, "dml_results.csv"))
theta <- dml$effect_ln_yield[grepl("^DML", dml$estimate)]
lo <- quantile(hh$tau, 0.005); hi <- quantile(hh$tau, 0.995)
cut <- sum(hh$tau < lo | hh$tau > hi)
g3 <- ggplot(subset(hh, tau >= lo & tau <= hi), aes(x = tau)) +
  geom_histogram(bins = 45, fill = "#2a78d6", colour = "white", linewidth = 0.25) +
  geom_vline(xintercept = 0, colour = INK2, linewidth = 0.3) +
  geom_vline(xintercept = theta, colour = INK, linewidth = 0.45, linetype = "dashed") +
  annotate("text", x = theta, y = Inf, label = sprintf("  DML average %.3f", theta), hjust = 0, vjust = 1.3,
           size = 2.9, colour = INK) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.13))) +
  labs(x = "Predicted effect of a fertilizer voucher on ln maize yield", y = "Households") +
  theme_note() + theme(panel.grid.major.y = element_line(colour = GRID, linewidth = 0.3),
                       panel.grid.major.x = element_blank())
save_both(g3, "fig_cate", 6.3, 2.6)
cat(sprintf("figures written; %d of %d households outside the 0.5-99.5 percentile range not drawn\n", cut, nrow(hh)))
