"""
Build the OFFICIAL weighted NHANES PFOS/PFOA serum reference tables.

This is the table the V1 reference engine must consume.  The
unweighted peer in ``scripts/build_nhanes_reference_tables.py``
exists only for replay-diff sanity; never use it as the
population-representative reference.

Why weighted matters
--------------------
NHANES is a complex probability sample (stratified, clustered,
disproportionate selection of minorities, the elderly, and children
12+).  An unweighted percentile mixes a non-uniform sample of
subgroups and is not representative of the U.S. non-institutionalized
civilian population.  CDC's Analytic and Reporting Guidelines instruct
that the appropriate subsample weight must be used for any reported
percentile.  The relevant weights here are:

    Cycle I  (PFAS_I, 2015-2016)  -> WTSB2YR    (2-year subsample weight)
    Cycle J  (PFAS_J, 2017-2018)  -> WTSB2YR
    Cycle P  (P_PFAS, 2017-2020)  -> WTSBAPRP   (pre-pandemic combined)

Cycle H (PFAS_H, 2013-2014) is intentionally excluded for the same
governance reason as the unweighted builder: PFAS_H lacks the four
isomer-resolved columns; those live in the non-admitted SSPFAS_H.

Weighted percentile algorithm
-----------------------------
Hazen-style linear interpolation of the weighted empirical CDF.
For sorted (value, weight) pairs with cumulative weight ``cw``::

    pos_i = (cw_i - 0.5 * w_i) / cw_total
    p(q)  = linear_interp(q, pos, value)

This is the form used by NHANES analyst-reported percentiles and
matches SUDAAN PROC DESCRIPT / Stata ``svy: epctile`` reasonably
closely without re-implementing Taylor linearization for variance.

Strict caveats
--------------
1. This table does NOT carry variance/CI columns; only point
   percentiles.  The V1 reference engine reports percentile context
   only, not significance.
2. ``LBXxxxx`` is left as stored (NHANES already imputes
   ``LOD / sqrt(2)`` when ``LBDxxxxL = 1``).  The fraction of below-
   LOD observations is recorded in ``pct_below_lod``.
3. Outputs go to ``data/reference_tables/`` only.
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
OUT_CSV = OUT_DIR / "nhanes_pfas_weighted_reference_tables_v1.csv"
OUT_LOG = OUT_DIR / "nhanes_pfas_weighted_reference_tables_v1.log"

ANALYTES: List[Tuple[str, str, str]] = [
    ("n_pfoa", "LBXNFOA", "LBDNFOAL"),
    ("sb_pfoa", "LBXBFOA", "LBDBFOAL"),
    ("n_pfos", "LBXNFOS", "LBDNFOSL"),
    ("sm_pfos", "LBXMFOS", "LBDMFOSL"),
]

# (cycle_dir, label, pfas_fname, demo_fname, weight_col_in_pfas)
CYCLES: List[Tuple[str, str, str, str, str]] = [
    ("2015_2016", "I", "PFAS_I.XPT", "DEMO_I.XPT", "WTSB2YR"),
    ("2017_2018", "J", "PFAS_J.XPT", "DEMO_J.XPT", "WTSB2YR"),
    ("2017_2020", "P", "P_PFAS.XPT", "P_DEMO.XPT", "WTSBAPRP"),
]

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


def _weighted_quantiles(
    values: np.ndarray,
    weights: np.ndarray,
    qs: List[float],
) -> List[float]:
    """Hazen-style weighted quantiles. Drops NaN value/weight pairs."""
    mask = (
        ~np.isnan(values)
        & ~np.isnan(weights)
        & (weights > 0)
    )
    v = values[mask]
    w = weights[mask]
    if len(v) == 0:
        return [float("nan")] * len(qs)
    order = np.argsort(v, kind="mergesort")
    v = v[order]
    w = w[order]
    cw = np.cumsum(w)
    total = cw[-1]
    if total <= 0:
        return [float("nan")] * len(qs)
    pos = (cw - 0.5 * w) / total
    return [float(np.interp(q, pos, v)) for q in qs]


def _load_cycle(
    cycle_dir: str, pfas_fname: str, demo_fname: str, weight_col: str
) -> pd.DataFrame:
    pfas = pd.read_sas(RAW_ROOT / cycle_dir / pfas_fname, format="xport")
    if weight_col not in pfas.columns:
        raise RuntimeError(
            f"weight column {weight_col!r} missing from {cycle_dir}/{pfas_fname}"
        )
    demo = pd.read_sas(RAW_ROOT / cycle_dir / demo_fname, format="xport")
    demo = demo[["SEQN", "RIAGENDR", "RIDAGEYR"]]
    merged = pfas.merge(demo, on="SEQN", how="inner")
    return merged


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    log_lines: List[str] = []

    def log(line: str) -> None:
        print(line, flush=True)
        log_lines.append(line)

    log(f"{_ts()}  START  build_nhanes_weighted_reference_tables (official)")
    log(f"{_ts()}  out_csv={OUT_CSV}")
    log(f"{_ts()}  cycles={[c[1] for c in CYCLES]}  (cycle H intentionally excluded)")

    rows: List[Dict[str, object]] = []
    src_hashes: Dict[str, str] = {}

    for cycle_dir, cycle_label, pfas_fname, demo_fname, weight_col in CYCLES:
        pfas_path = RAW_ROOT / cycle_dir / pfas_fname
        demo_path = RAW_ROOT / cycle_dir / demo_fname
        src_hashes[f"{cycle_dir}/{pfas_fname}"] = _sha256(pfas_path)
        src_hashes[f"{cycle_dir}/{demo_fname}"] = _sha256(demo_path)
        log(f"{_ts()}  loading {cycle_dir} (label={cycle_label}, weight={weight_col}) ...")
        df = _load_cycle(cycle_dir, pfas_fname, demo_fname, weight_col)
        log(f"{_ts()}    merged rows = {len(df)}")

        # Restrict to rows with a positive PFAS subsample weight; rows
        # outside the subsample by design have a zero weight and
        # contribute no signal.
        df = df[df[weight_col] > 0]
        log(f"{_ts()}    positive-weight rows = {len(df)}")

        for analyte_id, val_col, flag_col in ANALYTES:
            if val_col not in df.columns:
                log(f"{_ts()}    WARN: {analyte_id} ({val_col}) missing in {cycle_label}; skipping")
                continue
            for sex_code, sex_label in SEX_LEVELS.items():
                if sex_code == "all":
                    sex_mask = pd.Series(True, index=df.index)
                else:
                    sex_mask = df["RIAGENDR"] == float(sex_code)
                for age_label, age_lo, age_hi in AGE_GROUPS:
                    age_mask = (df["RIDAGEYR"] >= age_lo) & (df["RIDAGEYR"] <= age_hi)
                    sub = df[sex_mask & age_mask]
                    vals = sub[val_col].to_numpy(dtype=float)
                    wts = sub[weight_col].to_numpy(dtype=float)
                    pcts = _weighted_quantiles(vals, wts, PERCENTILES)
                    n_unweighted = int(
                        np.sum(
                            ~np.isnan(vals) & ~np.isnan(wts) & (wts > 0)
                        )
                    )
                    n_weighted = float(np.nansum(wts[~np.isnan(vals) & (wts > 0)]))
                    if flag_col in sub.columns and n_unweighted > 0:
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
                        "n_unweighted": n_unweighted,
                        "n_weighted": n_weighted,
                        "pct_below_lod": pct_lod,
                        "weighted": True,
                        "weight_column": weight_col,
                    }
                    for label, p in zip(PERCENTILE_LABELS, pcts):
                        row[label] = p
                    rows.append(row)

    out_df = pd.DataFrame(rows)
    out_df = out_df[[
        "cycle", "cycle_dir", "analyte_id", "analyte_column",
        "sex", "age_group", "n_unweighted", "n_weighted", "pct_below_lod",
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
    for k, v in src_hashes.items():
        log(f"{_ts()}  src  {v}  {k}")
    log(f"{_ts()}  DONE")

    OUT_LOG.write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
