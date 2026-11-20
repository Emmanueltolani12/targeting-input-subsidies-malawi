"""gee/gee_national_grid.py -- Sentinel-2 crop vigour and static covariates on a
1 km grid of Malawi and at the IHPS household locations (out-of-sample
targeting maps, 10_grid_predictions.R).

Earth Engine project "emmanueltolani". Features (time-invariant, available
everywhere before a season):
  s2_peak      Sentinel-2 L2A (S2_SR_HARMONIZED, SCL cloud/shadow mask) NDVI,
               90th percentile of the rainy season (Dec-Apr) on ESA WorldCover
               2021 cropland, mean over the seasons 2018/19-2022/23
  s2_peak24    the same for 2023/24 (El Nino drought); s2_anom24 = s2_peak24 - s2_peak
  crop_share   cropland share of the cell (WorldCover 2021)
  soc ntot ph clay sand   iSDAsoil 0-20 cm
  travel_min   travel time to the nearest city (MAP 2015)
  rain_lr, rain_cv  CHIRPS July-June totals, mean and coefficient of variation 1991/92-2020/21
  tmax_lr      ERA5-Land mean daily maximum temperature Dec-Mar, 1991-2020
Sentinel-2 is composited at 100 m (image pyramids) and averaged to 1 km.
Grid cells: 0.01 degree (about 1.1 km), EPSG:4326, Malawi (LSIB 2017).
Household locations: 5 km buffer means of this grid, computed in 10_grid_predictions.R
(reduceRegions over the buffers exceeds the Earth Engine user memory limit).

Data (Earth Engine catalog):
  Sentinel-2 L2A     https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S2_SR_HARMONIZED
  CHIRPS daily       https://developers.google.com/earth-engine/datasets/catalog/UCSB-CHG_CHIRPS_DAILY
  ERA5-Land monthly  https://developers.google.com/earth-engine/datasets/catalog/ECMWF_ERA5_LAND_MONTHLY_AGGR
  ESA WorldCover     https://developers.google.com/earth-engine/datasets/catalog/ESA_WorldCover_v200
  iSDAsoil           https://developers.google.com/earth-engine/datasets/catalog/ISDASOIL_Africa_v1_carbon_organic (and related layers)
  travel time        https://developers.google.com/earth-engine/datasets/catalog/Oxford_MAP_accessibility_to_cities_2015_v1_0
  country outline    https://developers.google.com/earth-engine/datasets/catalog/USDOS_LSIB_SIMPLE_2017

Usage (package root):
  uv run --no-project --with earthengine-api --with pandas --with numpy --with requests \
      python code/gee/gee_national_grid.py .
Output: data/raw/satellite/grid/tile_*.tif (one band per feature), read by
10_grid_predictions.R
"""
import os
import sys
import time

import ee
import pandas as pd
import requests

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
ee.Initialize(project="emmanueltolani")
OUT = f"{ROOT}/data/raw/satellite/grid"
os.makedirs(OUT, exist_ok=True)

mwi = ee.FeatureCollection("USDOS/LSIB_SIMPLE/2017").filter(ee.Filter.eq("country_na", "Malawi")).geometry()
crop = ee.ImageCollection("ESA/WorldCover/v200").first().eq(40)


def s2_season(y):
    """90th percentile NDVI, Dec (y-1) - Apr (y), cloud and shadow masked."""
    def prep(i):
        scl = i.select("SCL")
        ok = scl.eq(4).Or(scl.eq(5)).Or(scl.eq(6)).Or(scl.eq(7))
        return i.normalizedDifference(["B8", "B4"]).rename("ndvi").updateMask(ok)
    c = (ee.ImageCollection("COPERNICUS/S2_SR_HARMONIZED")
         .filterBounds(mwi).filterDate(f"{y - 1}-12-01", f"{y}-05-01")
         .filter(ee.Filter.lt("CLOUDY_PIXEL_PERCENTAGE", 70)).map(prep))
    return c.reduce(ee.Reducer.percentile([90])).rename("ndvi")


proj100 = ee.Projection("EPSG:4326").atScale(100)
proj1k = ee.Projection("EPSG:4326").scale(0.01, 0.01)


def to_grid(img):
    """composite at 100 m on cropland, then mean over the 1 km cell"""
    return (img.updateMask(crop).reproject(proj100)
            .reduceResolution(ee.Reducer.mean(), maxPixels=1024).reproject(proj1k))


peak = ee.ImageCollection([s2_season(y) for y in range(2019, 2024)]).mean()
peak24 = s2_season(2024)
s2 = ee.Image.cat([to_grid(peak).rename("s2_peak"), to_grid(peak24).rename("s2_peak24")])
s2 = s2.addBands(s2.select("s2_peak24").subtract(s2.select("s2_peak")).rename("s2_anom24"))

crop_share = crop.reproject(ee.Projection("EPSG:4326").atScale(10)).reduceResolution(
    ee.Reducer.mean(), maxPixels=65535).reproject(proj1k).rename("crop_share")
isda = "ISDASOIL/Africa/v1/"
soil = ee.Image.cat([
    ee.Image(isda + "carbon_organic").select("mean_0_20").divide(10).exp().subtract(1).rename("soc"),
    ee.Image(isda + "nitrogen_total").select("mean_0_20").divide(100).exp().subtract(1).rename("ntot"),
    ee.Image(isda + "ph").select("mean_0_20").divide(10).rename("ph"),
    ee.Image(isda + "clay_content").select("mean_0_20").rename("clay"),
    ee.Image(isda + "sand_content").select("mean_0_20").rename("sand"),
])
acc = ee.Image("Oxford/MAP/accessibility_to_cities_2015_v1_0").select("accessibility").rename("travel_min")
chirps = ee.ImageCollection("UCSB-CHG/CHIRPS/DAILY")
annual = ee.ImageCollection([chirps.filterDate(f"{y - 1}-07-01", f"{y}-07-01").sum() for y in range(1992, 2022)])
rain_lr = annual.mean().rename("rain_lr")
rain_cv = annual.reduce(ee.Reducer.stdDev()).divide(rain_lr).rename("rain_cv")
era = ee.ImageCollection("ECMWF/ERA5_LAND/MONTHLY_AGGR").select("temperature_2m_max").filterDate("1991-01-01", "2021-01-01")
tmax_lr = era.filter(ee.Filter.calendarRange(12, 3, "month")).mean().subtract(273.15).rename("tmax_lr")
static = ee.Image.cat([soil, acc, rain_lr, rain_cv, tmax_lr]).reproject(proj1k)
grid = ee.Image.cat([s2, crop_share, static]).toFloat().clip(mwi)
BANDS = ["s2_peak", "s2_peak24", "s2_anom24", "crop_share", "soc", "ntot", "ph", "clay", "sand",
         "travel_min", "rain_lr", "rain_cv", "tmax_lr"]


# --------------------------------------------------------------------------
# grid download in tiles (GeoTIFF); batch export to an asset if a tile fails
# --------------------------------------------------------------------------
def tiles():
    lon0, lon1, lat0, lat1 = 32.6, 36.0, -17.2, -9.3
    step = 1.0
    y = lat0
    while y < lat1:
        x = lon0
        while x < lon1:
            yield [x, y, min(x + step, lon1), min(y + step, lat1)]
            x += step
        y += step


def fetch(region, name):
    nx = int(round((region[2] - region[0]) / 0.01))
    ny = int(round((region[3] - region[1]) / 0.01))
    url = grid.select(BANDS).getDownloadURL({"crs": "EPSG:4326",
                                              "crs_transform": [0.01, 0, region[0], 0, -0.01, region[3]],
                                              "dimensions": f"{nx}x{ny}", "format": "GEO_TIFF"})
    r = requests.get(url, timeout=600)
    r.raise_for_status()
    with open(name, "wb") as f:
        f.write(r.content)


ok_tiles = []
failed = []
for i, t in enumerate(tiles()):
    name = f"{OUT}/tile_{i:02d}.tif"
    if os.path.exists(name):
        ok_tiles.append(name)
        continue
    t0 = time.time()
    try:
        fetch(t, name)
        ok_tiles.append(name)
        print(f"tile {i} {t} in {time.time() - t0:.0f}s")
    except Exception as e:
        print(f"tile {i} failed: {str(e)[:160]}")
        failed.append((i, t))
print(f"{len(ok_tiles)} tiles downloaded, {len(failed)} failed")
if failed:
    asset = "projects/emmanueltolani/assets/mwi_grid_features"
    task = ee.batch.Export.image.toAsset(image=grid.select(BANDS), description="mwi_grid_features",
                                         assetId=asset, region=mwi.bounds(), crs="EPSG:4326",
                                         crsTransform=[0.01, 0, 32.6, 0, -0.01, -9.3], maxPixels=1e9)
    task.start()
    print("batch export started:", asset, "- rerun this script when it has finished")
    while task.status()["state"] in ("READY", "RUNNING"):
        time.sleep(30)
    print("export state:", task.status()["state"])
    if task.status()["state"] == "COMPLETED":
        grid = ee.Image(asset)
        for i, t in failed:
            fetch(t, f"{OUT}/tile_{i:02d}.tif")

print("done (household-location means of the grid are computed in 10_grid_predictions.R)")
