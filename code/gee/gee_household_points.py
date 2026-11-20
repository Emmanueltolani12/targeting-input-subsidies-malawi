"""gee/gee_household_points.py -- satellite covariates for IHPS household locations.

Earth Engine (project "emmanueltolani"). For every point in
data/derived/ext_points.csv (survey-displaced household/EA coordinates, 5 km
buffer to cover the displacement) and every survey season (rainy season
November of year t-1 to April of year t; t = 2010, 2013, 2016, 2019, 2024):

  rain_*      CHIRPS daily: season total (mm), rainy days (> 1 mm), and the
              Standardised Precipitation Index of the season total (gamma fit
              on the 1981/82-2023/24 season totals of the point)
  tmax, hot30, gdd   ERA5-Land daily: mean daily maximum temperature Dec-Mar
              (deg C), days with maximum > 30 deg C Dec-Mar, growing degree
              days Nov-Apr (base 10, cap 30)
  evi_max, evi_mean  MODIS MOD13Q1 v061 EVI on cropland pixels (ESA WorldCover
              2021 class 40): seasonal maximum and mean Dec-Apr; evi_anom =
              evi_max minus the point's 2001-2024 mean of seasonal maxima
  static      iSDAsoil 0-20 cm (organic carbon g/kg, total N g/kg, pH, clay %,
              sand %), travel time to cities (minutes, MAP 2015), cropland
              share of the buffer

Data (Earth Engine catalog):
  CHIRPS daily       https://developers.google.com/earth-engine/datasets/catalog/UCSB-CHG_CHIRPS_DAILY
  ERA5-Land daily    https://developers.google.com/earth-engine/datasets/catalog/ECMWF_ERA5_LAND_DAILY_AGGR
  MODIS MOD13Q1 v061 https://developers.google.com/earth-engine/datasets/catalog/MODIS_061_MOD13Q1
  ESA WorldCover     https://developers.google.com/earth-engine/datasets/catalog/ESA_WorldCover_v200
  iSDAsoil           https://developers.google.com/earth-engine/datasets/catalog/ISDASOIL_Africa_v1_carbon_organic (and the
                     nitrogen_total, ph, clay_content and sand_content layers)
  travel time        https://developers.google.com/earth-engine/datasets/catalog/Oxford_MAP_accessibility_to_cities_2015_v1_0

Usage (from the package root):
  uv run --no-project --with earthengine-api --with pandas --with scipy \
      python code/gee/gee_household_points.py .
Output: data/raw/satellite/ext_satellite_points.csv (pid x wave), read by
05_merge_satellite.do
"""
import sys
import time

import ee
import numpy as np
import pandas as pd
from scipy import stats

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
ee.Initialize(project="emmanueltolani")

BUF = 5000
CHUNK = 800
WAVES = [2010, 2013, 2016, 2019, 2024]
SEASONS = list(range(1982, 2025))           # season ending in April of year
pts = pd.read_csv(f"{ROOT}/data/derived/ext_points.csv").dropna()
print(f"{len(pts)} points")


def season(y, m0="11-01", m1="05-01"):
    return f"{y - 1}-{m0}", f"{y}-{m1}"


# --------------------------------------------------------------------------
# images
# --------------------------------------------------------------------------
chirps = ee.ImageCollection("UCSB-CHG/CHIRPS/DAILY")
rain_bands = []
for y in SEASONS:
    a, b = season(y)
    rain_bands.append(chirps.filterDate(a, b).sum().rename(f"rain_{y}"))
for y in WAVES:
    a, b = season(y)
    rain_bands.append(chirps.filterDate(a, b).map(lambda i: i.gt(1)).sum().rename(f"rdays_{y}"))
rain_img = ee.Image.cat(rain_bands)

era = ee.ImageCollection("ECMWF/ERA5_LAND/DAILY_AGGR")
era_bands = []
for y in WAVES:
    dm = era.filterDate(f"{y - 1}-12-01", f"{y}-04-01")
    tmax = dm.select("temperature_2m_max").map(lambda i: i.subtract(273.15))
    era_bands.append(tmax.mean().rename(f"tmax_{y}"))
    era_bands.append(tmax.map(lambda i: i.gt(30)).sum().rename(f"hot30_{y}"))
    a, b = season(y)
    tmean = era.filterDate(a, b).select("temperature_2m").map(lambda i: i.subtract(273.15))
    era_bands.append(tmean.map(lambda i: i.min(30).subtract(10).max(0)).sum().rename(f"gdd_{y}"))
era_img = ee.Image.cat(era_bands)

crop = ee.ImageCollection("ESA/WorldCover/v200").first().eq(40)
modis = ee.ImageCollection("MODIS/061/MOD13Q1").select("EVI")


def evi_season(y):
    c = modis.filterDate(f"{y - 1}-12-01", f"{y}-05-01").map(
        lambda i: i.multiply(0.0001).updateMask(crop))
    return c.max(), c.mean()


evi_bands = []
for y in WAVES:
    mx, mn = evi_season(y)
    evi_bands += [mx.rename(f"evimax_{y}"), mn.rename(f"evimean_{y}")]
lr = ee.ImageCollection([evi_season(y)[0] for y in range(2001, 2025)]).mean().rename("evimax_lr")
evi_img = ee.Image.cat(evi_bands + [lr])

isda = "ISDASOIL/Africa/v1/"
soc = ee.Image(isda + "carbon_organic").select("mean_0_20").divide(10).exp().subtract(1).rename("soc")
nit = ee.Image(isda + "nitrogen_total").select("mean_0_20").divide(100).exp().subtract(1).rename("ntot")
ph = ee.Image(isda + "ph").select("mean_0_20").divide(10).rename("ph")
clay = ee.Image(isda + "clay_content").select("mean_0_20").rename("clay")
sand = ee.Image(isda + "sand_content").select("mean_0_20").rename("sand")
acc = ee.Image("Oxford/MAP/accessibility_to_cities_2015_v1_0").select("accessibility").rename("travel_min")
static_img = ee.Image.cat([soc, nit, ph, clay, sand, acc, crop.rename("crop_share")])

GROUPS = [("rain", rain_img, 5566), ("era5", era_img, 11132), ("evi", evi_img, 250), ("static", static_img, 250)]


# --------------------------------------------------------------------------
# extraction in chunks
# --------------------------------------------------------------------------
def extract(img, scale, df):
    feats = [ee.Feature(ee.Geometry.Point([float(r.lon), float(r.lat)]).buffer(BUF), {"pid": int(r.pid)})
             for r in df.itertuples()]
    fc = ee.FeatureCollection(feats)
    res = img.reduceRegions(collection=fc, reducer=ee.Reducer.mean(), scale=scale, tileScale=4)
    for attempt in range(4):
        try:
            return [f["properties"] for f in res.getInfo()["features"]]
        except Exception as e:  # transient server errors: retry
            print("  retry:", str(e)[:120])
            time.sleep(10 * (attempt + 1))
    raise RuntimeError("extraction failed")


out = None
for name, img, scale in GROUPS:
    rows = []
    for i in range(0, len(pts), CHUNK):
        t0 = time.time()
        rows += extract(img, scale, pts.iloc[i:i + CHUNK])
        print(f"{name}: points {i}-{min(i + CHUNK, len(pts))} in {time.time() - t0:.0f}s")
    d = pd.DataFrame(rows)
    out = d if out is None else out.merge(d, on="pid", how="outer")
out.to_csv(f"{ROOT}/data/derived/ext_satellite_points_wide.csv", index=False)

# --------------------------------------------------------------------------
# SPI of the survey seasons and long format (pid x wave)
# --------------------------------------------------------------------------
rain = out[[f"rain_{y}" for y in SEASONS]].to_numpy(dtype=float)
spi = np.full((len(out), len(WAVES)), np.nan)
for r in range(len(out)):
    x = rain[r]
    ok = np.isfinite(x) & (x > 0)
    if ok.sum() < 30:
        continue
    a, loc, sc = stats.gamma.fit(x[ok], floc=0)
    for j, y in enumerate(WAVES):
        v = rain[r, SEASONS.index(y)]
        p = np.clip(stats.gamma.cdf(v, a, loc=0, scale=sc), 1e-6, 1 - 1e-6)
        spi[r, j] = stats.norm.ppf(p)

long = []
for j, y in enumerate(WAVES):
    d = pd.DataFrame({
        "pid": out["pid"], "wave": y,
        "rain_season": out[f"rain_{y}"], "rain_days": out[f"rdays_{y}"], "spi": spi[:, j],
        "tmax": out[f"tmax_{y}"], "hot30": out[f"hot30_{y}"], "gdd": out[f"gdd_{y}"],
        "evi_max": out[f"evimax_{y}"], "evi_mean": out[f"evimean_{y}"],
        "evi_anom": out[f"evimax_{y}"] - out["evimax_lr"],
    })
    for v in ["soc", "ntot", "ph", "clay", "sand", "travel_min", "crop_share"]:
        d[v] = out[v]
    long.append(d)
long = pd.concat(long, ignore_index=True)
long.to_csv(f"{ROOT}/data/raw/satellite/ext_satellite_points.csv", index=False)
print(long.describe().T[["count", "mean", "std", "min", "max"]].round(3).to_string())
