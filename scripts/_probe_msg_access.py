"""Tiny probe: is the EUMETSAT license for HRSEVIRI active yet?

Tries to read the first 64 bytes of the storm-peak product. Prints LICENSE OK
or STILL BLOCKED with the underlying error. Delete this file once we're past
the license-propagation phase.
"""
from datetime import datetime
from pathlib import Path
import eumdac

key, secret = (Path.home() / ".eumdac" / "credentials").read_text().strip().split(",")
token = eumdac.AccessToken((key, secret))
ds = eumdac.DataStore(token)

products = list(ds.get_collection("EO:EUM:DAT:MSG:HRSEVIRI").search(
    dtstart=datetime(2026, 1, 22, 14, 52),
    dtend=datetime(2026, 1, 22, 15, 8),
))
prod = products[0]
print("product:", prod)

try:
    with prod.open() as src:
        head = src.read(64)
    print("LICENSE OK -- proceed. First bytes:", head[:16])
except Exception as e:
    print("STILL BLOCKED:", type(e).__name__, e)
