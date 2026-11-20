"""gee/gee_chirps_spi12.py -- 12-month SPI for the rainfall shock of the frontier.

The paper (Section 5) uses the Standardised Precipitation Index at 12 months
and a positive-shock dummy SPI > 1.5. This script computes it from CHIRPS daily
rainfall (Earth Engine project "emmanueltolani") for every household location
in data/derived/ext_points.csv (survey-displaced coordinates, 5 km buffer):

  rain12   rainfall total July (t-1) to June (t), mm: the survey's reference
           year ("starting July t-1") for round t = 2010, 2013, 2016, 2019, 2024
  spi12    gamma distribution fitted to the point's July-June totals
           1981/82-2023/24 (43 years), transformed to the standard normal
           (Guttman 1999; McKee et al. 1993)

Data: CHIRPS daily rainfall (Funk et al. 2015), https://www.chc.ucsb.edu/data/chirps,
  Earth Engine https://developers.google.com/earth-engine/datasets/catalog/UCSB-CHG_CHIRPS_DAILY

Output, read by code/03_build_panel.do (stored with the raw data because it
needs an Earth Engine account to rebuild):
  data/raw/satellite/chirps_spi12_households.csv  (wave, hhkey, pid, rain12, spi12)

Usage (from the package root, after 04_export_coordinates.do):
  uv run --no-project --with earthengine-api --with pandas --with scipy \
      python code/gee/gee_chirps_spi12.py .
"""
import os
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
YEARS = list(range(1982, 2025))        # reference year ending in June of the year
pts = pd.read_csv(f"{ROOT}/data/derived/ext_points.csv").dropna()
xw = pd.read_stata(f"{ROOT}/data/derived/ext_point_xwalk.dta")[["wave", "hhkey", "pid"]]
print(f"{len(pts)} points, {len(xw)} household-rounds")

chirps = ee.ImageCollection("UCSB-CHG/CHIRPS/DAILY")
img = ee.Image.cat([chirps.filterDate(f"{y - 1}-07-01", f"{y}-07-01").sum().rename(f"r12_{y}") for y in YEARS])


def extract(df):
    feats = [ee.Feature(ee.Geometry.Point([float(r.lon), float(r.lat)]).buffer(BUF), {"pid": int(r.pid)})
             for r in df.itertuples()]
    res = img.reduceRegions(collection=ee.FeatureCollection(feats), reducer=ee.Reducer.mean(),
                            scale=5566, tileScale=4)
    for attempt in range(4):
        try:
            return [f["properties"] for f in res.getInfo()["features"]]
        except Exception as e:  # transient server errors: retry
            print("  retry:", str(e)[:120])
            time.sleep(10 * (attempt + 1))
    raise RuntimeError("extraction failed")


rows = []
for i in range(0, len(pts), CHUNK):
    t0 = time.time()
    rows += extract(pts.iloc[i:i + CHUNK])
    print(f"points {i}-{min(i + CHUNK, len(pts))} in {time.time() - t0:.0f}s")
w = pd.DataFrame(rows)

rain = w[[f"r12_{y}" for y in YEARS]].to_numpy(dtype=float)
out = []
for r in range(len(w)):
    x = rain[r]
    ok = np.isfinite(x) & (x > 0)
    spi = {y: np.nan for y in WAVES}
    if ok.sum() >= 30:
        a, _, sc = stats.gamma.fit(x[ok], floc=0)
        for y in WAVES:
            p = np.clip(stats.gamma.cdf(x[YEARS.index(y)], a, loc=0, scale=sc), 1e-6, 1 - 1e-6)
            spi[y] = stats.norm.ppf(p)
    for y in WAVES:
        out.append({"pid": int(w["pid"].iloc[r]), "wave": y, "rain12": x[YEARS.index(y)], "spi12": spi[y]})
out = pd.DataFrame(out)

hh = xw.merge(out, on=["pid", "wave"], how="left")
os.makedirs(f"{ROOT}/data/raw/satellite", exist_ok=True)
hh.to_csv(f"{ROOT}/data/raw/satellite/chirps_spi12_households.csv", index=False)
print(hh.groupby("wave")[["rain12", "spi12"]].describe().round(2).T.to_string())
print("share SPI > 1.5 by wave:\n", hh.assign(s=hh.spi12 > 1.5).groupby("wave")["s"].mean().round(3).to_string())
