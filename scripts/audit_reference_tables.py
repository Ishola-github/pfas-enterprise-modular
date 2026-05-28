"""
Audit the two NHANES reference tables we just built.

Reports
-------
* counts of cycle/analyte/sex/age cells with n=0 or NaN percentiles
* spot-check of cycle-J (anchor) median for each analyte against the
  cycle-J anchor CSV at ``data/training/serum/nhanes_serum_pfas_2017_2018.csv``
* pct_below_lod summary per analyte across cycles

Output:
  data/reference_tables/audit_report.txt
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[1]
UNW = REPO / "data" / "reference_tables" / "nhanes_pfas_reference_tables_v1.csv"
WTD = REPO / "data" / "reference_tables" / "nhanes_pfas_weighted_reference_tables_v1.csv"
ANCHOR_J = REPO / "data" / "training" / "serum" / "nhanes_serum_pfas_2017_2018.csv"
OUT = REPO / "data" / "reference_tables" / "audit_report.txt"


def audit(label: str, df: pd.DataFrame, n_col: str) -> list[str]:
    pcts = ["p5", "p10", "p25", "p50", "p75", "p90", "p95"]
    rows: list[str] = [f"=== {label} ===", f"shape={df.shape}"]
    rows.append(f"empty cells (n=0): {int((df[n_col] == 0).sum())}")
    nan_any = df[pcts].isna().any(axis=1)
    rows.append(f"rows with any NaN percentile: {int(nan_any.sum())}")
    rows.append(
        "per-cycle row counts: "
        + ", ".join(f"{c}={int(n)}" for c, n in df.groupby("cycle").size().items())
    )
    rows.append("median p50 per (cycle, analyte, sex=all, age=all_ages):")
    sel = df[(df["sex"] == "all") & (df["age_group"] == "all_ages")][
        ["cycle", "analyte_id", "p50", n_col, "pct_below_lod"]
    ]
    rows.append(sel.to_string(index=False))
    rows.append("")
    return rows


def spot_check_anchor() -> list[str]:
    rows = ["=== anchor spot-check ===",
            "Recomputing cycle-J p50 from anchor CSV and comparing to weighted table"]
    j = pd.read_csv(ANCHOR_J)
    wtd = pd.read_csv(WTD)
    # the anchor CSV is the janitor-cleaned cycle-J PFAS+DEMO merge
    col_map = {
        "n_pfoa": "lbxnfoa",
        "sb_pfoa": "lbxbfoa",
        "n_pfos": "lbxnfos",
        "sm_pfos": "lbxmfos",
    }
    for aid, col in col_map.items():
        if col not in j.columns:
            rows.append(f"  {aid}: anchor missing column {col!r}, skipping")
            continue
        anchor_median = float(np.nanmedian(j[col]))
        wtd_row = wtd[
            (wtd["cycle"] == "J")
            & (wtd["analyte_id"] == aid)
            & (wtd["sex"] == "all")
            & (wtd["age_group"] == "all_ages")
        ]
        wtd_median = float(wtd_row["p50"].iloc[0]) if len(wtd_row) else float("nan")
        rows.append(
            f"  {aid:8s}  anchor_unweighted_p50={anchor_median:6.3f}  "
            f"weighted_table_p50={wtd_median:6.3f}  "
            f"abs_diff={abs(anchor_median - wtd_median):6.3f}"
        )
    rows.append("")
    return rows


def main() -> int:
    unw = pd.read_csv(UNW)
    wtd = pd.read_csv(WTD)
    out_lines: list[str] = []
    out_lines += audit("unweighted (nhanes_pfas_reference_tables_v1.csv)", unw, "n")
    out_lines += audit("weighted (nhanes_pfas_weighted_reference_tables_v1.csv)", wtd, "n_unweighted")
    out_lines += spot_check_anchor()
    OUT.write_text("\n".join(out_lines), encoding="utf-8")
    print("\n".join(out_lines))
    print(f"\n[wrote] {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
