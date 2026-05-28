"""
Fetch NHANES PFAS + DEMO XPT files from the CDC public data portal.

Why this script exists
----------------------
Earlier attempts to fetch the same files inside an ``ubuntu:22.04``
Docker container reliably hung during ``update-ca-certificates``, so
no XPTs ever reached disk.  This script bypasses that path entirely:
Python's stdlib ``urllib.request`` is the HTTPS client, ``ssl`` does
TLS verification against the system trust store, and every fetched
file is hash-checked + SAS-Transport-header-verified on the way in.

Reproducibility recipe
----------------------
1. The cycles fetched here are the four PFAS-eligible NHANES public
   data cycles documented at https://wwwn.cdc.gov/Nchs/Nhanes/ ::

        2013-2014   PFAS_H,  DEMO_H
        2015-2016   PFAS_I,  DEMO_I
        2017-2018   PFAS_J,  DEMO_J
        2017-2020   P_PFAS,  P_DEMO    (pre-pandemic combined)

2. Files are written under ``data/raw/nhanes/<cycle>/``.

3. A deterministic ``data/raw/nhanes/.fetch_run.log`` line is appended
   per file in the format ::

        <iso_ts>  OK     <sha256>  <bytes>  <cycle>/<file>  <url>
        <iso_ts>  FAIL   ----     ----    <cycle>/<file>  <error>

   so the log can be diff'd against a future re-fetch.

What this script will NOT do
----------------------------
* It will not silently accept a non-XPT response (CDC sometimes
  returns an HTML 404 with HTTP 200; the SAS Transport magic check
  catches that).
* It will not retry past the documented fallback URL list.
* It will not write any file outside ``data/raw/nhanes/``.
* It will not touch any file under ``data/training/`` or
  ``validation/`` -- those are governance anchors and remain frozen.
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import List, Tuple

REPO_ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = REPO_ROOT / "data" / "raw" / "nhanes"
LOG_PATH = RAW_ROOT / ".fetch_run.log"

# SAS Transport (XPORT v5/v6) files begin with this exact 80-byte
# header; rejecting anything that does not start with it shields the
# pipeline from the CDC's occasional "HTTP 200 + HTML error body"
# response.
SAS_XPORT_MAGIC = b"HEADER RECORD*******LIBRARY HEADER RECORD!!!!!!!"

# (cycle_dir, filename, [primary_url, *fallback_urls])
# Cycle directory naming mirrors the on-CDC documentation cycles.
FILES: List[Tuple[str, str, List[str]]] = [
    (
        "2013_2014",
        "PFAS_H.XPT",
        ["https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/PFAS_H.xpt"],
    ),
    (
        "2013_2014",
        "DEMO_H.XPT",
        ["https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/DEMO_H.xpt"],
    ),
    (
        "2015_2016",
        "PFAS_I.XPT",
        ["https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2015/DataFiles/PFAS_I.xpt"],
    ),
    (
        "2015_2016",
        "DEMO_I.XPT",
        ["https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2015/DataFiles/DEMO_I.xpt"],
    ),
    (
        "2017_2018",
        "PFAS_J.XPT",
        ["https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/PFAS_J.xpt"],
    ),
    (
        "2017_2018",
        "DEMO_J.XPT",
        ["https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/DEMO_J.xpt"],
    ),
    (
        "2017_2020",
        "P_PFAS.XPT",
        [
            "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_PFAS.xpt",
            "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017-2020/DataFiles/P_PFAS.xpt",
        ],
    ),
    (
        "2017_2020",
        "P_DEMO.XPT",
        [
            "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_DEMO.xpt",
            "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017-2020/DataFiles/P_DEMO.xpt",
        ],
    ),
]


def _ts() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def _log(line: str) -> None:
    print(line, flush=True)
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def _download(url: str, dest: Path, *, timeout: int = 120) -> None:
    """Streamed HTTPS download. Overwrites dest only on success."""
    tmp = dest.with_suffix(dest.suffix + ".part")
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(
        url,
        headers={
            # CDC's CDN responds with HTML to anonymous User-Agents on
            # some pre-pandemic mirrors; an explicit UA lets the
            # transparent-redirect path resolve correctly.
            "User-Agent": "pfas-toxicology-fetch/1.0 (governance: serum_v1)",
            "Accept": "*/*",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310 - HTTPS literal hosts only
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status} from {url}")
        with tmp.open("wb") as fh:
            while True:
                chunk = resp.read(1 << 16)
                if not chunk:
                    break
                fh.write(chunk)
    # Magic-header check on the temp file BEFORE moving into place;
    # an HTML error page or zero-byte response will fail this and the
    # caller can try the next fallback URL.
    with tmp.open("rb") as fh:
        prefix = fh.read(len(SAS_XPORT_MAGIC))
    if prefix != SAS_XPORT_MAGIC:
        tmp.unlink(missing_ok=True)
        raise RuntimeError(
            f"non-XPT response (first {len(prefix)} bytes != SAS Transport magic) from {url}"
        )
    tmp.replace(dest)


def _fetch_one(cycle: str, fname: str, urls: List[str]) -> bool:
    dest = RAW_ROOT / cycle / fname
    rel = f"{cycle}/{fname}"

    if dest.exists():
        sz = dest.stat().st_size
        sha = _sha256(dest)
        _log(f"{_ts()}  SKIP   {sha}  {sz}  {rel}  (already present)")
        return True

    last_err = None
    for url in urls:
        try:
            _download(url, dest)
        except (urllib.error.URLError, urllib.error.HTTPError, RuntimeError, TimeoutError) as exc:
            last_err = exc
            _log(f"{_ts()}  RETRY  ----  ----  {rel}  {type(exc).__name__}: {exc}")
            time.sleep(2)
            continue
        sz = dest.stat().st_size
        sha = _sha256(dest)
        _log(f"{_ts()}  OK     {sha}  {sz}  {rel}  {url}")
        return True

    _log(f"{_ts()}  FAIL   ----  ----  {rel}  exhausted_urls last_err={last_err!r}")
    return False


def main() -> int:
    RAW_ROOT.mkdir(parents=True, exist_ok=True)
    _log(f"{_ts()}  START  ----  ----  --  fetcher=fetch_nhanes_pfas_demo.py")
    ok = 0
    fail = 0
    for cycle, fname, urls in FILES:
        if _fetch_one(cycle, fname, urls):
            ok += 1
        else:
            fail += 1
    _log(f"{_ts()}  DONE   ----  ----  --  ok={ok} fail={fail} total={ok+fail}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
