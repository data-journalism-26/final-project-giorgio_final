"""Verbose diagnostic for the 403 — bypasses eumdac and uses raw requests
so we can see the full server response (status, headers, body).
"""
from base64 import b64encode
from pathlib import Path
import requests

KEY, SECRET = (Path.home() / ".eumdac" / "credentials").read_text().strip().split(",")

# 1) Mint a fresh access token via OAuth2 client_credentials.
print("=" * 70)
print("STEP 1: token endpoint")
print("=" * 70)
basic = b64encode(f"{KEY}:{SECRET}".encode()).decode()
tr = requests.post(
    "https://api.eumetsat.int/token",
    headers={"Authorization": f"Basic {basic}"},
    data={"grant_type": "client_credentials"},
    timeout=30,
)
print("status:", tr.status_code)
print("body:  ", tr.text[:500])
if tr.status_code != 200:
    raise SystemExit("Token mint failed -- stop here.")
tok = tr.json()
access = tok["access_token"]
print(f"token: {access[:12]}... (len={len(access)})  expires_in={tok.get('expires_in')}s")
print()

# 2) Probe the userinfo endpoint to see what scopes/licenses the token carries.
print("=" * 70)
print("STEP 2: who am I according to this token?")
print("=" * 70)
for path in ("/userinfo", "/api-key", "/token/info"):
    url = f"https://api.eumetsat.int{path}"
    r = requests.get(url, headers={"Authorization": f"Bearer {access}"}, timeout=30)
    print(f"{path}: {r.status_code}  {r.text[:300]}")
print()

# 3) Try to download the actual product and dump the full response.
print("=" * 70)
print("STEP 3: download attempt")
print("=" * 70)
url = ("https://api.eumetsat.int/data/download/1.0.0/collections/"
       "EO%3AEUM%3ADAT%3AMSG%3AHRSEVIRI/products/"
       "MSG3-SEVI-MSG15-0100-NA-20260122151244.008000000Z-NA")
r = requests.get(url, headers={"Authorization": f"Bearer {access}"},
                 stream=True, timeout=30, allow_redirects=False)
print("status: ", r.status_code)
print("headers:")
for k, v in r.headers.items():
    print(f"  {k}: {v}")
print("body (first 1000 chars):")
print(r.text[:1000])
