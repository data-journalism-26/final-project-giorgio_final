"""TEST: open one MSG SEVIRI .nat, extract IR_108 over the Med, save NetCDF.

If this completes and produces a file roughly a few MB in size, the bulk
download->process->delete loop will work.
"""
from pathlib import Path
import time

from satpy import Scene
from pyresample import create_area_def

ROOT = Path(__file__).resolve().parent.parent
NAT = ROOT / "data/msg/test/MSG3-SEVI-MSG15-0100-NA-20260115084241.531000000Z-NA/MSG3-SEVI-MSG15-0100-NA-20260115084241.531000000Z-NA.nat"
OUT = ROOT / "data/msg/test/ir108_2026-01-15T0842.nc"

# Mediterranean target grid -- matches the existing R animation extent.
# Grid spacing ~0.05 deg = ~5 km, comparable to native SEVIRI nadir resolution.
target_area = create_area_def(
    "med",
    {"proj": "longlat", "datum": "WGS84"},
    width=600,     # 30 deg lon / 0.05 = 600 cells
    height=340,    # 17 deg lat / 0.05 = 340 cells
    area_extent=(-5.0, 28.0, 25.0, 45.0),  # lon_min, lat_min, lon_max, lat_max
)

print(f"input:  {NAT}  ({NAT.stat().st_size:,} bytes)")
t0 = time.time()
scn = Scene(filenames=[str(NAT)], reader="seviri_l1b_native")
print(f"available channels: {scn.available_dataset_names()}")

scn.load(["IR_108"])
print(f"loaded in {time.time()-t0:.1f}s")
print(f"IR_108 native shape: {scn['IR_108'].shape}")
print(f"IR_108 attrs: units={scn['IR_108'].attrs.get('units')} "
      f"start_time={scn['IR_108'].attrs.get('start_time')}")

t0 = time.time()
local = scn.resample(target_area, resampler="nearest")
print(f"resampled in {time.time()-t0:.1f}s; shape={local['IR_108'].shape}")

OUT.parent.mkdir(parents=True, exist_ok=True)
local.save_datasets(filename=str(OUT), writer="cf")
size = OUT.stat().st_size
print(f"saved: {OUT}  ({size:,} bytes = {size/1e6:.1f} MB)")
