"""
Build first-pass UNWEIGHTED NHANES PFOS/PFOA serum reference tables.

Purpose
-------
Reads the raw PFAS + DEMO XPT files we already fetched into
``data/raw/nhanes/<cycle>/`` and computes simple stratified
percentile tables for the four isomer-resolved analytes that
``src/v1/data/ontology/pfos_pfoa_v1.json`` recognizes:

    LBXNFOA   n-PFOA
    LBXBFOA   Sb-PFOA
    LBXNFOS   n-PFOS
    LBXMFOS   Sm-PFOS

Each percentile row is keyed by (cycle, analyte, sex, age_group) and
includes the count of contributing rows, the LOD-flag fraction, and
the percentiles p5, p10, p25, p50, p75, p90, p95.

Strict caveats (kept honest)
----------------------------
1. This is an UNWEIGHTED first pass.  NHANES distributions are
   probability-sampled, so the population-representative table is
   produced by ``scripts/build_nhanes_weighted_reference_tables.py``
   and is the one the V1 reference engine must consume.  This file
   exists so the weighted version has an immediate, hash-stable
   counterpart for replay-diff tests.

2. Cycle 2013-2014 (PFAS_H.XPT) is intentionally EXCLUDED here.
   PFAS_H does not contain the four isomer-resolved columns; those
   live in SSPFAS_H.XPT, which is governance-recorded but NOT
   admitted (see ``validation/serum_h_v1/schema_contract.md``).
   The exclusion is logged into the run footer so it is not silent.

3. NHANES sets ``LBXxxxx`` to ``LOD / sqrt(2)`` when ``LBDxxxxL = 1``
   (sample below limit of detection).  The percentile output here
   uses the value as-stored; the ``pct_below_lod`` column carries
   the share of contributing rows that were imputed.

4. Output is written to ``data/reference_tables/`` only.  No file
   under ``data/training/`` or ``validation/`` is touched.
"""

from __future__ import annotations

import datetime as _dt
import hashlib
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = REPO_ROOT / "data" / "raw" / "nhanes"
OUT_DIR = REPO_ROOT / "data" / "reference_tables"
OUT_CSV = OUT_DIR / "nhanes_pfas_reference_tables_v1.csv"
OUT_LOG = OUT_DIR / "nhanes_pfas_reference_tables_v1.log"

# Analytes recognized by the V1 ontology -- the isomer columns and
# their LOD-flag companions.  Order is the ontology order so the
# output CSV stays diff-stable across reruns.
ANALYTES: List[Tuple[str, str, str]] = [
    ("n_pfoa", "LBXNFOA", "LBDNFOAL"),
    ("sb_pfoa", "LBXBFOA", "LBDBFOAL"),
    ("n_pfos", "LBXNFOS", "LBDNFOSL"),
    ("sm_pfos", "LBXMFOS", "LBDMFOSL"),
]

# Cycles that contribute (cycle_dir, label, pfas_file, demo_file).
# 2013_2014 omitted on purpose -- see module docstring.
CYCLES: List[Tuple[str, str, str, str]] = [
    ("2015_2016", "I", "PFAS_I.XPT", "DEMO_I.XPT"),
    ("2017_2018", "J", "PFAS_J.XPT", "DEMO_J.XPT"),
    ("2017_2020", "P", "P_PFAS.XPT", "P_DEMO.XPT"),
]

# Standard biomonitoring age strata for serum PFAS.  Lower bound is
# inclusive, upper bound is inclusive.  12-19 matches the NHANES
# adolescent stratum that CDC reports separately.
AGE_GROUPS: List[Tuple[str, int, int]] = [
    ("12-19", 12, 19),
    ("20-39", 20, 39),
    ("40-59", 40, 59),
    ("60_plus", 60, 200),
    ("all_ages", 12, 200),
]

SEX_LEVELS: Dict[str, str] = {
    "1": "male",
    "2": "female",
    "all": "all",
}

PERCENTILES = [0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95]
PERCENTILE_LABELS = ["p5", "p10", "p25", "p50", "p75", "p90", "p95"]


def _ts() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def _load_cycle(
    cycle_dir: str, pfas_fname: str, demo_fname: str
) -> pd.DataFrame:
    pfas = pd.read_sas(RAW_ROOT / cycle_dir / pfas_fname, format="xport")
    demo = pd.read_sas(RAW_ROOT / cycle_dir / demo_fname, format="xport")
    keep_demo = ["SEQN", "RIAGENDR", "RIDAGEYR"]
    demo = demo[keep_demo]
    merged = pfas.merge(demo, on="SEQN", how="inner")
    return merged


def _unweighted_percentiles(
    values: pd.Series,
) -> Tuple[List[float], int, float]:
    """Drop NaN; return (percentiles, n, pct_below_lod_placeholder)."""
    vals = values.dropna().to_numpy(dtype=float)
    if len(vals) == 0:
        return [float("nan")] * len(PERCENTILES), 0, float("nan")
    return [float(np.quantile(vals, q)) for q in PERCENTILES], int(len(vals)), float("nan")


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    log_lines: List[str] = []

    def log(line: str) -> None:
        print(line, flush=True)
        log_lines.append(line)

    log(f"{_ts()}  START  build_nhanes_reference_tables (unweighted, first pass)")
    log(f"{_ts()}  out_csv={OUT_CSV}")
    log(f"{_ts()}  cycles={[c[1] for c in CYCLES]}  (cycle H intentionally excluded)")

    rows: List[Dict[str, object]] = []
    cycle_hashes: Dict[str, str] = {}

    for cycle_dir, cycle_label, pfas_fname, demo_fname in CYCLES:
        pfas_path = RAW_ROOT / cycle_dir / pfas_fname
        demo_path = RAW_ROOT / cycle_dir / demo_fname
        cycle_hashes[f"{cycle_dir}/{pfas_fname}"] = _sha256(pfas_path)
        cycle_hashes[f"{cycle_dir}/{demo_fname}"] = _sha256(demo_path)
        log(f"{_ts()}  loading {cycle_dir} (label={cycle_label}) ...")
        df = _load_cycle(cycle_dir, pfas_fname, demo_fname)
        log(f"{_ts()}    merged rows = {len(df)}")

        missing_isomers = [
            colname
            for _aid, colname, _flag in ANALYTES
            if colname not in df.columns
        ]
        if missing_isomers:
            log(f"{_ts()}    WARN: missing isomer columns in {cycle_label}: {missing_isomers} -- skipping cycle")
            continue

        for analyte_id, val_col, flag_col in ANALYTES:
            for sex_code, sex_label in SEX_LEVELS.items():
                if sex_code == "all":
                    sex_mask = pd.Series(True, index=df.index)
                else:
                    sex_mask = df["RIAGENDR"] == float(sex_code)
                for age_label, age_lo, age_hi in AGE_GROUPS:
                    age_mask = (df["RIDAGEYR"] >= age_lo) & (df["RIDAGEYR"] <= age_hi)
                    sub = df[sex_mask & age_mask]
                    pcts, n, _ = _unweighted_percentiles(sub[val_col])
                    if flag_col in sub.columns and n > 0:
                        flag_vals = sub[flag_col].dropna()
                        pct_lod = (
                            float((flag_vals == 1).mean()) if len(flag_vals) else float("nan")
                        )
                    else:
                        pct_lod = float("nan")
                    row: Dict[str, object] = {
                        "cycle": cycle_label,
                        "cycle_dir": cycle_dir,
                        "analyte_id": analyte_id,
                        "analyte_column": val_col,
                        "sex": sex_label,
                        "age_group": age_label,
                        "n": n,
                        "pct_below_lod": pct_lod,
                        "weighted": False,
                        "weight_column": "",
                    }
                    for label, p in zip(PERCENTILE_LABELS, pcts):
                        row[label] = p
                    rows.append(row)

    out_df = pd.DataFrame(rows)
    out_df = out_df[[
        "cycle", "cycle_dir", "analyte_id", "analyte_column",
        "sex", "age_group", "n", "pct_below_lod",
        "weighted", "weight_column",
        *PERCENTILE_LABELS,
    ]]
    out_df = out_df.sort_values(
        ["cycle", "analyte_id", "sex", "age_group"], kind="mergesort"
    ).reset_index(drop=True)

    out_df.to_csv(OUT_CSV, index=False, lineterminator="\n")
    out_sha = _sha256(OUT_CSV)
    log(f"{_ts()}  wrote {OUT_CSV}  rows={len(out_df)}  sha256={out_sha}")

    log(f"{_ts()}  --- source hashes ---")
    for k, v in cycle_hashes.items():
        log(f"{_ts()}  src  {v}  {k}")
    log(f"{_ts()}  DONE")

    OUT_LOG.write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
