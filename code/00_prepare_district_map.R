# 00_prepare_district_map.R
# Converts the GADM 4.1 Malawi district boundaries (terra PackedSpatVector,
# data/raw/maps/gadm41_MWI_1_pk.rds) into a shapefile that Stata's
# -spshape2dta- can read: data/raw/maps/mwi_districts.shp
# Data: GADM 4.1, Malawi level 1, https://gadm.org/download_country.html
# (also geodata::gadm("MWI", level = 1)); licensed, not redistributed
# Run once from the package root:  Rscript code/00_prepare_district_map.R
library(terra)
library(sf)
# folder with the GADM file (argument 1, default data/raw/maps)
maps <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(maps)) maps <- file.path("data", "raw", "maps")
x <- terra::unwrap(readRDS(file.path(maps, "gadm41_MWI_1_pk.rds")))
s <- sf::st_as_sf(x)[, c("GID_1", "NAME_1")]
s$NAME_1 <- as.character(s$NAME_1)
sf::st_write(s, file.path(maps, "mwi_districts.shp"), delete_layer = TRUE, quiet = TRUE)
cat("written:", nrow(s), "districts\n")
