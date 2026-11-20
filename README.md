# Replication package: Targeting Input Subsidies with Satellites and Machine Learning: Evidence from Malawi

Emmanuel Tolani, Technical University of Munich

## Overview

Repository: https://github.com/Emmanueltolani12/targeting-input-subsidies-malawi

The code in this package builds every table, figure and in-text number of the paper from the raw data. A single Stata master file, `run_all.do`, runs steps 00-17 in order (12 Stata do-files and 7 R scripts). It writes:

- the paper's tables to `output/paper/tables` and its numbers to `output/paper/numbers.tex`;
- intermediate results and figures to `output/results`;
- a log for every step to `output/logs`;

The `output` folders are empty in the repository; running `run_all.do` fills them.

On a laptop (Intel i7, 32 GB RAM) a full run takes about five and a half hours, or about two and a half hours with the four demand specifications of step 13 run in parallel, most of it in step 13 (demand system, four specifications of 40-70 minutes each) and steps 14-15 (bootstrap of the structural models).

## Data availability and provenance

### Statement about rights

- [x] I certify that the author of the manuscript has legitimate access to and permission to use the data used in this manuscript.
- [ ] I certify that the author has documented permission to redistribute the data. Partly: only the open data in `data/raw/prices`, `data/raw/programme` and `data/raw/satellite` are redistributed. The licensed files must be obtained from their providers (below).

### Summary of availability

- [ ] All data **are** publicly available.
- [x] Some data **cannot be made** publicly available by the author but are available to any researcher from the provider.
- [ ] **No data can be made** publicly available.

### Data sources

| Data | Source and access | Included | Location |
|---|---|---|---|
| Integrated Household Panel Survey (IHPS) 2010-2013, short-term panel (2010 and 2013 rounds) | National Statistical Office of Malawi and World Bank LSMS, [World Bank Microdata Library, catalog 2248](https://microdata.worldbank.org/index.php/catalog/2248); free registration; the terms of use do not allow redistribution | No | `RESTRICTED/ihps` |
| IHPS 2010-2013-2016, long-term panel (2016 round) | [Microdata Library, catalog 2939](https://microdata.worldbank.org/index.php/catalog/2939); as above | No | `RESTRICTED/ihps_long` |
| IHPS 2010-2013-2016-2019, long-term panel (2019 round) | [Microdata Library, catalog 3819](https://microdata.worldbank.org/index.php/catalog/3819); as above | No | `RESTRICTED/ihps_long` |
| IHPS 2024, long-term panel and sample refresh (2024 round) | [Microdata Library, catalog 8520](https://microdata.worldbank.org/index.php/catalog/8520); as above | No | `RESTRICTED/ihps_long` |
| Food and crop unit conversion factors (2020) | distributed with the 2019 panel ([catalog 3819](https://microdata.worldbank.org/index.php/catalog/3819)) and the Fifth Integrated Household Survey ([catalog 3818](https://microdata.worldbank.org/index.php/catalog/3818)) | No | `RESTRICTED/conversion` |
| Household identifiers across rounds, including split-off households (`MWI_panel_ids.dta`) | built by the author from the tracking identifiers of the long-term panel releases (catalogs [2939](https://microdata.worldbank.org/index.php/catalog/2939) and [3819](https://microdata.worldbank.org/index.php/catalog/3819)); derived from the licensed files, so not redistributed | No | `RESTRICTED/links` |
| District boundaries, GADM 4.1, Malawi level 1 (`gadm41_MWI_1_pk.rds`) | [gadm.org](https://gadm.org/download_country.html) (in R: `geodata::gadm("MWI", level = 1)`); the license allows academic use but not redistribution | No | `RESTRICTED/maps` |
| District allocations of FISP coupons and AIP beneficiaries, program prices | compiled by the author from Ministry of Agriculture Logistics Unit reports and AIP reports; every value with its source, link and page in `data/raw/programme/README.md` and `sources.csv` | Yes | `data/raw/programme` |
| World fertilizer prices (DAP, urea), monthly | [World Bank Commodity Price Data (Pink Sheet)](https://www.worldbank.org/en/research/commodity-markets), file `CMO-Historical-Data-Monthly.xlsx`; CC BY 4.0 | Yes | `data/raw/prices` |
| Kwacha-dollar exchange rate, monthly | IMF International Financial Statistics, through [DBnomics](https://db.nomics.world/IMF/IFS/M.MW.ENDA_XDC_USD_RATE) | Yes | `data/raw/prices` |
| Consumer price index, monthly | IMF Consumer Price Index database, through [DBnomics](https://db.nomics.world/IMF/CPI/M.MW.PCPI_IX) | Yes | `data/raw/prices` |
| Consumer price index, annual | World Bank World Development Indicators, through [DBnomics](https://db.nomics.world/WB/WDI/A-FP.CPI.TOTL-MWI) ([indicator page](https://data.worldbank.org/indicator/FP.CPI.TOTL?locations=MW)); CC BY 4.0 | Yes | `data/raw/prices` |
| Satellite and weather features at the survey locations | extracted in Google Earth Engine with `code/gee/gee_household_points.py` and `code/gee/gee_chirps_spi12.py` (point identifiers only, no coordinates) from [CHIRPS](https://developers.google.com/earth-engine/datasets/catalog/UCSB-CHG_CHIRPS_DAILY), [ERA5-Land](https://developers.google.com/earth-engine/datasets/catalog/ECMWF_ERA5_LAND_DAILY_AGGR), [MODIS MOD13Q1](https://developers.google.com/earth-engine/datasets/catalog/MODIS_061_MOD13Q1), [iSDAsoil](https://developers.google.com/earth-engine/datasets/catalog/ISDASOIL_Africa_v1_carbon_organic), [travel time to cities](https://developers.google.com/earth-engine/datasets/catalog/Oxford_MAP_accessibility_to_cities_2015_v1_0) and [ESA WorldCover](https://developers.google.com/earth-engine/datasets/catalog/ESA_WorldCover_v200) | Yes | `data/raw/satellite` |
| National 1 km grid of satellite features (Sentinel-2 crop vigor 2018/19-2022/23 and its 2023/24 anomaly, soils, access, climate) | extracted with `code/gee/gee_national_grid.py` from [Sentinel-2 L2A](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S2_SR_HARMONIZED), [ERA5-Land monthly](https://developers.google.com/earth-engine/datasets/catalog/ECMWF_ERA5_LAND_MONTHLY_AGGR) and the datasets above | Yes | `data/raw/satellite/grid` |

`data/raw/RESTRICTED_FILES.txt` lists every licensed file the code reads, with its size. Place the files in the folders shown (default `data/raw/...`), or set `global RESTRICTED "<folder>"` before running `run_all.do`.

The Earth Engine scripts in `code/gee` need an Earth Engine account and the household coordinates of the licensed survey files. Their outputs are shipped in `data/raw/satellite`, so the master file does not run them.

## Computational requirements

### Software

- **Stata 18 (SE or MP).** No user-written packages are needed; the helpers are in `code/ado`.
- **R 4.5.2**, with these packages:
  - haven, ggplot2, patchwork, ggrepel, scales;
  - grf, policytree, ranger, glmnet, xgboost, torch (for deep learning in step 07);
  - terra, sf, exactextractr.
- **Python 3.11 or later** only for the Earth Engine scripts in `code/gee`, which `run_all.do` does not run: earthengine-api, pandas, scipy, numpy and requests.

Set the path to Rscript at the top of `run_all.do` (`global RSCRIPT`).

### Randomness

Seeds are set in `run_all.do` (Stata), in every R script that draws random numbers (07, 09, 10, 11) and in the bootstrap programs (14, 15).

### Hardware

Tested on Windows 11 with Stata/SE 18 and R 4.5.2. About 2 GB of disk space is needed for derived data.

## Instructions

1. Obtain the licensed files listed in `data/raw/RESTRICTED_FILES.txt` and put them in `data/raw/<folder>`, or point `global RESTRICTED` to the folder that holds them.
2. Start Stata 18 in the package root and run `do run_all.do`.
3. To skip a step, set `global SKIP_nn 1` before running, where `nn` is the step number. `global SIM_BOOT 0` skips the bootstrap of the structural models.
4. Step 13 estimates four specifications of the demand system, each taking 40-70 minutes. To run them in parallel:
   - run steps 00-12 with `global SKIP_13 1` … `global SKIP_17 1`;
   - run step 13 alone with `global S2_PART prep`;
   - run it in four Stata sessions at once with `global S2_PART exog`, `iv`, `iv_cov` and `iv_price`, and `global LOGSFX "_<part>"` so that each session keeps its own log;
   - run `global S2_PART combine`;
   - continue with steps 14-17.

## Steps

| Step | Program | What it does | Main outputs |
|---|---|---|---|
| 00 | `00_prepare_district_map.R` | GADM district boundaries to a shapefile (once) | `RESTRICTED/maps/mwi_districts.shp` |
| 01 | `01_build_household.do` | household variables of every round 2010-2024 | `data/derived/hh_<round>.dta` |
| 02 | `02_build_agriculture.do` | plots, inputs, harvest, purchases, coupons and AIP of every round | `ag_<round>.dta` |
| 03 | `03_build_panel.do` | all-round panel with the CHIRPS rainfall shock | `all_waves_panel.dta` |
| 04 | `04_export_coordinates.do` | point identifiers of the survey locations | `ext_points.csv`, `ext_point_xwalk.dta` |
| 05 | `05_merge_satellite.do` | satellite and weather features merged to the panel | `all_waves_panel_sat.dta` |
| 06 | `06_panel_frontier.do` | four-component panel frontier 2010-2024 | `panel_efficiency.dta`; Table 3, Appendix Table A2 |
| 07 | `07_yield_prediction.R`, `07b_yield_prediction_figures.R` | out-of-sample yield prediction and prediction of the most efficient households from verifiable traits and satellite features | `ml_benchmark.csv`, `targeting_benchmark.csv`; Appendix Figures A1, A2 |
| 08 | `08_allocation_leakage.do` | allocation arrangements, leakage, receipt regressions | Appendix Tables A4, A5 |
| 09 | `09_causal_forest_rules.R` | causal forest, doubly robust scores, allocation rules | `rule_assignment.csv`, `policy_values.csv`; Table 1 |
| 10 | `10_grid_predictions.R` | satellite-only forest on the national grid, maps | `ext_points_grid_features.csv`; Figure 2, Appendix Figure A3 |
| 11 | `11_satellite_targeting.R` | value of satellite information, targeting operating characteristic | Table 2, Figure 1 |
| 12 | `12_measurement.do` | transient inefficiency against crop vigor from space | Table 4 |
| 13 | `13_demand_system.do` | instruments, first stages, demand system on all rounds | Table 5, Appendix Table A3 |
| 14 | `14_structural_allrounds.do` | conventional structural model, AIP levers, bootstrap | Tables 6, 8 |
| 15 | `15_joint_structural.do` | joint structural model (runs step 14 with `SIM_MODEL joint`), comparison with realized returns | Tables 7, 8 |
| 16 | `16_structural_figure.R` | predicted and realized returns by rule | Figure 3 |
| 17 | `17_paper_tables.do` | all tables (LaTeX) and the numbers cited in the text | `output/paper/tables`, `numbers.tex` |

Shared programs in `code/ado`:

- `qd_lib.do`: QUAIDS estimation and elasticities with delta-method covariance;
- `sim_allrounds_programs.do` and `sim_helpers.do`: simulation and bootstrap;
- `report_helpers.do`: table writer;
- `jtmacros.tex`: LaTeX layout commands used by the tables in `output/paper/tables`;
- small helpers for units, district names and labels.

## List of tables, figures and programs

Each table and figure of the paper and its appendix, and the program that produces it:

| Exhibit | Program | Output |
|---|---|---|
| Table 1 | 09, 17 | `output/paper/tables/t1.tex` |
| Table 2 | 11, 17 | `t2.tex` |
| Table 3 | 06, 17 | `t3.tex` |
| Table 4 | 12, 17 | `t4.tex` |
| Table 5 | 13, 17 | `t5.tex` |
| Table 6 | 14, 17 | `t6.tex` |
| Table 7 | 15, 17 | `t7.tex` |
| Table 8 | 14, 15, 17 | `t8.tex` |
| Figure 1 | 11 | `output/results/fig_toc.pdf` |
| Figure 2 | 10 | `output/results/fig_returns_map.pdf` |
| Figure 3 | 16 | `output/results/fig_structural.pdf` |
| Appendix Table A1 | 17 | `tA1.tex` |
| Appendix Table A2 | 06, 17 | `tA2.tex` |
| Appendix Table A3 | 13, 17 | `tA3.tex` |
| Appendix Tables A4, A5 | 08, 17 | `tA4.tex`, `tA5.tex` |
| Appendix Figure A1 | 07b | `output/results/fig_ml_benchmark.pdf` |
| Appendix Figure A2 | 07b | `output/results/fig_cate.pdf` |
| Appendix Figure A3 | 10 | `output/results/fig_s2_vigour.pdf` |
| Numbers in the text | 17 | `output/paper/numbers.tex` |

## References for the data

- National Statistical Office of Malawi. Integrated Household Panel Survey 2010-2013 (Short-Term Panel, 204 EAs). World Bank Microdata Library, https://microdata.worldbank.org/index.php/catalog/2248.
- National Statistical Office of Malawi. Integrated Household Panel Survey 2010-2013-2016 (Long-Term Panel, 102 EAs). https://microdata.worldbank.org/index.php/catalog/2939.
- National Statistical Office of Malawi. Integrated Household Panel Survey 2010-2013-2016-2019 (Long-Term Panel, 102 EAs). https://microdata.worldbank.org/index.php/catalog/3819.
- National Statistical Office of Malawi. Integrated Household Panel Survey 2024 (Long-Term Panel and Sample Refresh, 51 EAs each). https://microdata.worldbank.org/index.php/catalog/8520.
- National Statistical Office of Malawi. Fifth Integrated Household Survey 2019-2020. https://microdata.worldbank.org/index.php/catalog/3818.
- Global Administrative Areas (2022). GADM database of global administrative areas, version 4.1. https://gadm.org.
- World Bank (2026). Commodity Price Data (The Pink Sheet), January 2026 release. https://www.worldbank.org/en/research/commodity-markets.
- International Monetary Fund. International Financial Statistics and Consumer Price Index databases, retrieved through DBnomics, https://db.nomics.world.
- World Bank. World Development Indicators. https://databank.worldbank.org/source/world-development-indicators.
- Funk, C. et al. (2015). The climate hazards infrared precipitation with stations (CHIRPS). Scientific Data 2: 150066. https://doi.org/10.1038/sdata.2015.66.
- Muñoz Sabater, J. et al. (2021). ERA5-Land. Earth System Science Data 13: 4349-4383. https://doi.org/10.5194/essd-13-4349-2021.
- Didan, K. (2021). MODIS/Terra Vegetation Indices 16-Day L3 Global 250m (MOD13Q1 v061). NASA EOSDIS LP DAAC. https://doi.org/10.5067/MODIS/MOD13Q1.061.
- Hengl, T. et al. (2021). African soil properties and nutrients mapped at 30 m spatial resolution (iSDAsoil). Scientific Reports 11: 6130. https://doi.org/10.1038/s41598-021-85639-y.
- Weiss, D. J. et al. (2018). A global map of travel time to cities. Nature 553: 333-336. https://doi.org/10.1038/nature25181.
- Zanaga, D. et al. (2022). ESA WorldCover 10 m 2021 v200. https://doi.org/10.5281/zenodo.7254221.
- Copernicus Sentinel-2 MSI Level-2A surface reflectance, European Space Agency. https://dataspace.copernicus.eu.
