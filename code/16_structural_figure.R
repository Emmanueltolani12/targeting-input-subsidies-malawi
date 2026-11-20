# ==============================================================================
# 16_structural_figure.R -- realized returns of each allocation rule
# against the predictions of the conventional and the joint structural model
# (kg of maize per voucher or package, 95% bootstrap intervals)
# Input:  output/results/structural_vs_realised.csv (15_joint_structural)
# Output: output/results/fig_structural.png/.pdf
# ==============================================================================
suppressMessages(library(ggplot2))
root <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(root)) root <- "."
ext <- file.path(root, "output", "results")
d <- read.csv(file.path(ext, "structural_vs_realised.csv"))
lab <- c(actual = "Actual allocation", random = "Random", poor = "Poorest first",
         effpr = "Persistent efficiency (predicted)", cate = "Highest predicted returns", tree = "Policy tree")
d$rule_lab <- factor(lab[d$rule], levels = rev(lab))
long <- rbind(
  data.frame(rule = d$rule_lab, model = "Realized (doubly robust)", kg = d$kg_real, se = d$se_real),
  data.frame(rule = d$rule_lab, model = "Conventional structural model", kg = d$kg_conv, se = d$se_conv),
  data.frame(rule = d$rule_lab, model = "Joint structural model", kg = d$kg_joint, se = d$se_joint))
long$model <- factor(long$model, levels = c("Realized (doubly robust)", "Conventional structural model", "Joint structural model"))
pal <- c("Realized (doubly robust)" = "#0072B2", "Conventional structural model" = "#D55E00", "Joint structural model" = "#E69F00")
p <- ggplot(long, aes(kg, rule, colour = model)) +
  geom_vline(xintercept = 0, colour = "grey55", linewidth = 0.4) +
  geom_errorbarh(aes(xmin = kg - 1.96 * se, xmax = kg + 1.96 * se), height = 0, linewidth = 0.6,
                 position = position_dodge(width = 0.6)) +
  geom_point(size = 2.4, position = position_dodge(width = 0.6)) +
  scale_colour_manual(values = pal, name = NULL) +
  labs(x = "Maize gain per voucher or package (kg)", y = NULL) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top", panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(colour = "grey90", linewidth = 0.3))
ggsave(file.path(ext, "fig_structural.png"), p, width = 6.5, height = 4, dpi = 300, bg = "white")
ggsave(file.path(ext, "fig_structural.pdf"), p, width = 6.5, height = 4)
cat("done\n")
