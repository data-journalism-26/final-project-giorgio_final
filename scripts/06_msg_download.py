"""
06_msg_download.py — MSG SEVIRI IR_108 over the Mediterranean for the storm
    window.

Purpose:
    Loop strategy — download one .nat product, immediately extract IR_108
    cropped to the Mediterranean as a ~5 MB NetCDF, delete the 271 MB .nat,
    move on. Peak transient storage stays around one .nat at a time.

Window:
    2026-01-12 to 2026-01-24 inclusive, 3-hourly cadence (~104 frames).

Inputs:
    Requires the eumdac CLI + EUMETSAT credentials at ~/.eumdac/credentials,
    and the HRSEVIRI usage licenses (general + > 1 hr latency tier).

Outputs:
    data/msg/ir108/msg_ir108_YYYYMMDDTHHMM.nc    (one NetCDF per timestep)

Usage:
    python3 scripts/06_msg_download.py
    python3 scripts/06_msg_download.py --dry-run     # list what would be fetched
    python3 scripts/06_msg_download.py --cadence 6   # 6-hourly instead of 3
"""
import argparse
import shutil
import signal
import socket
import sys
import time
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path

import eumdac
from pyresample import create_area_def
from satpy import Scene

# Layered timeouts:
#  - socket-level (180s): protects future sockets from blocking forever on read
#  - signal-based watchdog (300s): forcibly interrupts download_nat at the
#    process level after 5 minutes -- works even when an in-flight socket
#    read is blocked in the kernel (which the socket timeout cannot save us
#    from once the recv has started).
socket.setdefaulttimeout(180)
DOWNLOAD_DEADLINE_SEC = 480
RETRIES_PER_FRAME = 3


class DownloadDeadlineExceeded(Exception):
    pass


@contextmanager
def deadline(seconds: int):
    """Raise DownloadDeadlineExceeded if the wrapped block takes too long."""
    def _handler(signum, frame):
        raise DownloadDeadlineExceeded(f"download exceeded {seconds}s")
    prev = signal.signal(signal.SIGALRM, _handler)
    signal.alarm(seconds)
    try:
        yield
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, prev)

ROOT = Path(__file__).resolve().parent.parent
NAT_DIR = ROOT / "data/msg/_nat_tmp"
NC_DIR = ROOT / "data/msg/ir108"

COLLECTION = "EO:EUM:DAT:MSG:HRSEVIRI"
START = datetime(2026, 1, 12, 0, 0)
END = datetime(2026, 2, 17, 21, 0)
SEARCH_TOL = timedelta(minutes=8)  # SEVIRI scans every 15 min

# Med target grid -- 0.05 deg, matches the existing R animation extent.
TARGET = create_area_def(
    "med",
    {"proj": "longlat", "datum": "WGS84"},
    width=600, height=340,
    area_extent=(-5.0, 28.0, 25.0, 45.0),
)


def load_credentials() -> tuple[str, str]:
    f = Path.home() / ".eumdac" / "credentials"
    return tuple(f.read_text().strip().split(","))


def out_path_for(t: datetime) -> Path:
    return NC_DIR / f"ir108_{t:%Y-%m-%dT%H%M}.nc"


def download_nat(product, out_dir: Path) -> Path:
    """Stream the .nat into out_dir. Atomic rename so a partial download from
    a previous run cannot be mistaken for a complete one."""
    nat_name = next(e for e in product.entries if e.endswith(".nat"))
    target = out_dir / nat_name
    if target.exists():
        return target  # complete file from a previous run
    out_dir.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(target.suffix + ".part")
    if tmp.exists():
        tmp.unlink()  # leftover from a prior interrupted run
    try:
        with product.open(entry=nat_name) as src, open(tmp, "wb") as dst:
            shutil.copyfileobj(src, dst)
        tmp.rename(target)
    except BaseException:
        if tmp.exists():
            tmp.unlink()
        raise
    return target


def process_to_netcdf(nat_path: Path, out_nc: Path) -> None:
    scn = Scene(filenames=[str(nat_path)], reader="seviri_l1b_native")
    scn.load(["IR_108"])
    local = scn.resample(TARGET, resampler="nearest")
    out_nc.parent.mkdir(parents=True, exist_ok=True)
    local.save_datasets(filename=str(out_nc), writer="cf")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cadence", type=int, default=3,
                    help="hours between frames (default 3)")
    ap.add_argument("--dry-run", action="store_true",
                    help="list timestamps but don't fetch")
    args = ap.parse_args()

    schedule = []
    t = START
    while t <= END:
        schedule.append(t)
        t += timedelta(hours=args.cadence)
    print(f"Schedule: {len(schedule)} frames @ {args.cadence}h cadence "
          f"({START:%Y-%m-%d} -- {END:%Y-%m-%d})")

    if args.dry_run:
        for t in schedule:
            present = "EXISTS" if out_path_for(t).exists() else "todo"
            print(f"  {t:%Y-%m-%d %H:%M}  {present}")
        return 0

    key, secret = load_credentials()
    token = eumdac.AccessToken((key, secret))
    ds = eumdac.DataStore(token)
    coll = ds.get_collection(COLLECTION)
    NAT_DIR.mkdir(parents=True, exist_ok=True)
    NC_DIR.mkdir(parents=True, exist_ok=True)

    n_done = n_skip = n_fail = 0
    t_start = time.time()
    for i, t in enumerate(schedule, 1):
        out_nc = out_path_for(t)
        if out_nc.exists():
            n_skip += 1
            continue
        prefix = f"[{i:3d}/{len(schedule)}] {t:%Y-%m-%d %H:%M}"
        last_err = None
        for attempt in range(1, RETRIES_PER_FRAME + 1):
            try:
                products = list(coll.search(dtstart=t - SEARCH_TOL,
                                            dtend=t + SEARCH_TOL))
                if not products:
                    print(f"{prefix}  NO PRODUCT in search window -- skip", flush=True)
                    last_err = "no_product"
                    break
                product = products[0]
                t0 = time.time()
                with deadline(DOWNLOAD_DEADLINE_SEC):
                    nat = download_nat(product, NAT_DIR)
                t_dl = time.time() - t0
                t0 = time.time()
                process_to_netcdf(nat, out_nc)
                t_proc = time.time() - t0
                nat.unlink()
                print(f"{prefix}  dl={t_dl:5.1f}s proc={t_proc:4.1f}s "
                      f"-> {out_nc.name} ({out_nc.stat().st_size/1e6:.1f} MB)",
                      flush=True)
                n_done += 1
                last_err = None
                break
            except Exception as e:
                last_err = e
                print(f"{prefix}  attempt {attempt}/{RETRIES_PER_FRAME} "
                      f"FAILED: {type(e).__name__}: {e}", flush=True)
                time.sleep(5)
        if last_err is not None and last_err != "no_product":
            n_fail += 1

    elapsed = (time.time() - t_start) / 60
    print(f"\nDone in {elapsed:.1f} min  |  {n_done} downloaded, "
          f"{n_skip} skipped (already present), {n_fail} failed")
    if NAT_DIR.exists() and not any(NAT_DIR.iterdir()):
        NAT_DIR.rmdir()
    return 0 if n_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
