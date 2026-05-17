"""
Build V1.1 weighted NHANES reference tables (sex × age × race/ethnicity).

Extends the V1.0 official table with ``race_ethnicity`` strata from
``RIDRETH3`` (NHANES DEMO). Rows with ``race_ethnicity=all`` match the
V1.0 sex/age-only strata. Race-specific rows are emitted only when
``n_unweighted >= MIN_N_RACE_STRATUM`` (default 30).

Output: ``data/reference_tables/nhanes_pfas_weighted_reference_tables_v1_1.csv``
"""
from __future__ import annotations

import datetime as _dt
import hashlib
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[1]

RIDRETH3_TO_LABEL: dict[int, str] = {
    1: "mexican_american",
    2: "other_hispanic",
    3: "nh_white",
    4: "nh_black",
    6: "nh_asian",
    7: "other",
}
RAW_ROOT = REPO_ROOT / "data" / "raw" / "nhanes"
OUT_DIR = REPO_ROOT / "data" / "reference_tables"
OUT_CSV = OUT_DIR / "nhanes_pfas_weighted_reference_tables_v1_1.csv"
OUT_LOG = OUT_DIR / "nhanes_pfas_weighted_reference_tables_v1_1.log"

MIN_N_RACE_STRATUM = 30

ANALYTES: List[Tuple[str, str, str]] = [
    ("n_pfoa", "LBXNFOA", "LBDNFOAL"),
    ("sb_pfoa", "LBXBFOA", "LBDBFOAL"),
    ("n_pfos", "LBXNFOS", "LBDNFOSL"),
    ("sm_pfos", "LBXMFOS", "LBDMFOSL"),
]

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

SEX_LEVELS: Dict[str, str] = {"1": "male", "2": "female", "all": "all"}

RACE_LEVELS: Tuple[str, ...] = (
    "all",
    "mexican_american",
    "other_hispanic",
    "nh_white",
    "nh_black",
    "nh_asian",
    "other",
)

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


def _weighted_quantiles(values: np.ndarray, weights: np.ndarray, qs: List[float]) -> List[float]:
    mask = ~np.isnan(values) & ~np.isnan(weights) & (weights > 0)
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


def _race_label(series: pd.Series) -> pd.Series:
    def _one(v: object) -> str:
        if pd.isna(v):
            return ""
        code = int(float(v))
        return RIDRETH3_TO_LABEL.get(code, "")

    return series.map(_one)


def _load_cycle(cycle_dir: str, pfas_fname: str, demo_fname: str, weight_col: str) -> pd.DataFrame:
    pfas = pd.read_sas(RAW_ROOT / cycle_dir / pfas_fname, format="xport")
    if weight_col not in pfas.columns:
        raise RuntimeError(f"weight column {weight_col!r} missing from {cycle_dir}/{pfas_fname}")
    demo = pd.read_sas(RAW_ROOT / cycle_dir / demo_fname, format="xport")
    demo = demo[["SEQN", "RIAGENDR", "RIDAGEYR", "RIDRETH3"]]
    merged = pfas.merge(demo, on="SEQN", how="inner")
    merged["race_ethnicity"] = _race_label(merged["RIDRETH3"])
    return merged


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    log_lines: List[str] = []

    def log(line: str) -> None:
        print(line, flush=True)
        log_lines.append(line)

    log(f"{_ts()}  START  build_nhanes_weighted_reference_tables_v1_1")
    rows: List[Dict[str, object]] = []

    for cycle_dir, cycle_label, pfas_fname, demo_fname, weight_col in CYCLES:
        pfas_path = RAW_ROOT / cycle_dir / pfas_fname
        if not pfas_path.is_file():
            log(f"{_ts()}  SKIP {cycle_label}: missing {pfas_path}")
            continue
        log(f"{_ts()}  loading {cycle_dir} (label={cycle_label}) ...")
        df = _load_cycle(cycle_dir, pfas_fname, demo_fname, weight_col)
        df = df[df[weight_col] > 0]
        log(f"{_ts()}    positive-weight rows = {len(df)}")

        for analyte_id, val_col, flag_col in ANALYTES:
            if val_col not in df.columns:
                log(f"{_ts()}    WARN: {analyte_id} missing in {cycle_label}")
                continue
            for sex_code, sex_label in SEX_LEVELS.items():
                sex_mask = pd.Series(True, index=df.index) if sex_code == "all" else df["RIAGENDR"] == float(sex_code)
                for age_label, age_lo, age_hi in AGE_GROUPS:
                    age_mask = (df["RIDAGEYR"] >= age_lo) & (df["RIDAGEYR"] <= age_hi)
                    for race_label in RACE_LEVELS:
                        if race_label == "all":
                            race_mask = pd.Series(True, index=df.index)
                        else:
                            race_mask = df["race_ethnicity"] == race_label
                        sub = df[sex_mask & age_mask & race_mask]
                        n_unweighted = int(
                            np.sum(
                                ~np.isnan(sub[val_col].to_numpy(dtype=float))
                                & (sub[weight_col].to_numpy(dtype=float) > 0)
                            )
                        )
                        if race_label != "all" and n_unweighted < MIN_N_RACE_STRATUM:
                            continue
                        vals = sub[val_col].to_numpy(dtype=float)
                        wts = sub[weight_col].to_numpy(dtype=float)
                        pcts = _weighted_quantiles(vals, wts, PERCENTILES)
                        n_weighted = float(np.nansum(wts[~np.isnan(vals) & (wts > 0)]))
                        if flag_col in sub.columns and n_unweighted > 0:
                            flag_vals = sub[flag_col].dropna()
                            pct_lod = float((flag_vals == 1).mean()) if len(flag_vals) else float("nan")
                        else:
                            pct_lod = float("nan")
                        row: Dict[str, object] = {
                            "cycle": cycle_label,
                            "cycle_dir": cycle_dir,
                            "analyte_id": analyte_id,
                            "analyte_column": val_col,
                            "sex": sex_label,
                            "age_group": age_label,
                            "race_ethnicity": race_label,
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
    out_df = out_df.sort_values(
        ["cycle", "analyte_id", "sex", "age_group", "race_ethnicity"],
        kind="mergesort",
    ).reset_index(drop=True)
    out_df.to_csv(OUT_CSV, index=False, lineterminator="\n")
    out_sha = _sha256(OUT_CSV)
    log(f"{_ts()}  wrote {OUT_CSV}  rows={len(out_df)}  sha256={out_sha}")
    OUT_LOG.write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
