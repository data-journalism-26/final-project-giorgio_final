"""TEST: download a single MSG SEVIRI timestep via EUMDAC + Data Tailor.

Sanity check before the full storm window. Downloads exactly ONE timestep
(2026-01-22 15:00 UTC, the storm peak) cropped to the Mediterranean and
reprojected to plate carree, in NetCDF4. Output goes to data/msg/test/.

Prereqs:
  pip3 install --user eumdac          # already done
  eumdac set-credentials KEY SECRET   # writes ~/.eumdac/credentials

Run:
  python3 scripts/06_download_msg_test.py

If this completes and the resulting NetCDF opens with `ncdump -h`, the next
step is to extend it to the full Jan 12 - Feb 17 window at 3-hour cadence
(scripts/06_download_msg.py) and add the IR_108 channel filter once we know
the band naming convention from this test's output.
"""

import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

import eumdac
from eumdac.tailor_models import Chain, RegionOfInterest

OUT_DIR = Path(__file__).resolve().parent.parent / "data" / "msg" / "test"
OUT_DIR.mkdir(parents=True, exist_ok=True)

COLLECTION_ID = "EO:EUM:DAT:MSG:HRSEVIRI"
TARGET = datetime(2026, 1, 22, 15, 0)        # storm peak (UTC)
WINDOW = timedelta(minutes=8)                 # SEVIRI scans every 15 min
NSWE = [45, 28, -5, 25]                       # north, south, west, east


def load_credentials() -> tuple[str, str]:
    f = Path.home() / ".eumdac" / "credentials"
    if not f.exists():
        sys.exit(f"Credentials file not found: {f}\n"
                 "Run: eumdac set-credentials KEY SECRET")
    raw = f.read_text().strip()
    parts = raw.split(",")
    if len(parts) != 2:
        sys.exit(f"Unexpected credentials format in {f}. Expected 'KEY,SECRET'.")
    return parts[0], parts[1]


def main() -> int:
    print(">>> Authenticating")
    key, secret = load_credentials()
    token = eumdac.AccessToken((key, secret))

    print(">>> Searching Data Store for storm-peak HRSEVIRI product")
    ds = eumdac.DataStore(token)
    collection = ds.get_collection(COLLECTION_ID)
    products = list(collection.search(
        dtstart=TARGET - WINDOW,
        dtend=TARGET + WINDOW,
    ))
    if not products:
        sys.exit("No HRSEVIRI products in search window. "
                 "Check the date and your account licenses at "
                 "https://user.eumetsat.int/profile?activeTab=data-licenses")
    product = products[0]
    print(f"    found {len(products)} product(s); using: {product}")

    print(">>> Submitting Data Tailor customisation (no band filter)")
    dt = eumdac.DataTailor(token)
    chain = Chain(
        product="HRSEVIRI",
        format="netcdf4",
        projection="geographic",
        roi=RegionOfInterest(NSWE=NSWE),
    )
    customisation = dt.new_customisation(product, chain)
    print(f"    customisation: {customisation}")
    print(f"    initial status: {customisation.status}")

    print(">>> Polling for completion (this is server-side; a few minutes)")
    last = None
    while customisation.status in ("QUEUED", "RUNNING", "INACTIVE"):
        msg = f"    status={customisation.status} progress={customisation.progress}%"
        if msg != last:
            print(msg)
            last = msg
        time.sleep(15)

    print(f"    final status: {customisation.status}")
    if customisation.status != "DONE":
        print(">>> Job log:")
        try:
            print(customisation.logfile)
        except Exception as e:
            print(f"    (could not fetch logfile: {e})")
        sys.exit(1)

    print(">>> Downloading outputs")
    outputs = customisation.outputs
    print(f"    outputs: {outputs}")
    for out_name in outputs:
        target = OUT_DIR / Path(out_name).name
        with customisation.stream_output(out_name) as src, open(target, "wb") as dst:
            for chunk in src:
                dst.write(chunk)
        print(f"    saved: {target} ({target.stat().st_size:,} bytes)")

    customisation.delete()
    print("    customisation cleaned up on server")
    print(">>> DONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
