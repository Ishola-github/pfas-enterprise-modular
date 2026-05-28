"""
Recon: list NHANES PFAS + DEMO column names per cycle.

Reads each XPT we fetched, prints its column list, and flags which
PFOS / PFOA / weight / age / sex columns are present. The output is
used to drive the column mapping in
``scripts/build_nhanes_reference_tables.py`` and its weighted peer,
so the builders don't silently miss a column that exists.

Nothing under this script writes to ``data/training/`` or
``validation/`` -- only ``data/raw/nhanes/.recon_columns.txt``.
"""

from __future__ import annotations

import re
from pathlib import Path

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = REPO_ROOT / "data" / "raw" / "nhanes"
# Non-dotfile so on-access AV scans don't quarantine it silently.
OUT_PATH = RAW_ROOT / "recon_columns.txt"

CYCLES = [
    ("2013_2014", "PFAS_H.XPT", "DEMO_H.XPT"),
    ("2015_2016", "PFAS_I.XPT", "DEMO_I.XPT"),
    ("2017_2018", "PFAS_J.XPT", "DEMO_J.XPT"),
    ("2017_2020", "P_PFAS.XPT", "P_DEMO.XPT"),
]

PFOA_RX = re.compile(r"(NFOA|MFOA|BFOA|PFOA|FOAA)", re.I)
PFOS_RX = re.compile(r"(NFOS|MFOS|FOSA|PFOS)", re.I)
WGT_RX = re.compile(r"^WT", re.I)
AGE_RX = re.compile(r"^RIDAGEYR$", re.I)
SEX_RX = re.compile(r"^RIAGENDR$", re.I)


def report(label: str, df: pd.DataFrame) -> list[str]:
    out = [f"=== {label} ===", f"rows={len(df)}  cols={len(df.columns)}"]
    cols = list(df.columns)
    out.append("columns: " + ", ".join(cols))
    pfoa = [c for c in cols if PFOA_RX.search(c)]
    pfos = [c for c in cols if PFOS_RX.search(c)]
    wgt = [c for c in cols if WGT_RX.match(c)]
    age = [c for c in cols if AGE_RX.match(c)]
    sex = [c for c in cols if SEX_RX.match(c)]
    out.append(f"PFOA-ish cols : {pfoa}")
    out.append(f"PFOS-ish cols : {pfos}")
    out.append(f"weight cols   : {wgt}")
    out.append(f"age col       : {age}")
    out.append(f"sex col       : {sex}")
    out.append("")
    return out


def _append(lines: list[str]) -> None:
    with OUT_PATH.open("a", encoding="utf-8") as fh:
        for line in lines:
            fh.write(line + "\n")
            print(line, flush=True)


def main() -> int:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text("", encoding="utf-8")
    _append([f"[recon] writing to {OUT_PATH}"])
    for cycle, pfas, demo in CYCLES:
        for fname in (pfas, demo):
            path = RAW_ROOT / cycle / fname
            _append([f"[recon] reading {cycle}/{fname}"])
            try:
                df = pd.read_sas(path, format="xport")
                _append(report(f"{cycle}/{fname}", df))
                del df
            except Exception as exc:  # noqa: BLE001
                _append([f"=== {cycle}/{fname} ===", f"READ_ERROR: {exc}", ""])
    _append(["[recon] done"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
