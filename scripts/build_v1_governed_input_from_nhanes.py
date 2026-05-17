#!/usr/bin/env python3
"""Build a governed V1 input CSV from NHANES PFAS + DEMO XPT (SEQN join).

Joins participant-level PFAS laboratory results with demographics
(RIAGENDR -> sex, RIDAGEYR -> age_years) for stratified V1 contextualization.

Default: cycle J (2017-2018), matching V1 default reference cycle.

Example (from repo root)::

    python scripts/build_v1_governed_input_from_nhanes.py \\
        --cycle J \\
        --output data/v1/fixtures/nhanes_j_governed_v1_input.csv

Requires raw XPTs under data/raw/nhanes/<cycle_dir>/ (see
scripts/download_nhanes_pfas.ps1).
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = REPO_ROOT / "data" / "raw" / "nhanes"

RIDRETH3_TO_LABEL = {
    1: "mexican_american",
    2: "other_hispanic",
    3: "nh_white",
    4: "nh_black",
    6: "nh_asian",
    7: "other",
}

CYCLE_MAP = {
    "I": ("2015_2016", "PFAS_I.XPT", "DEMO_I.XPT", "WTSB2YR"),
    "J": ("2017_2018", "PFAS_J.XPT", "DEMO_J.XPT", "WTSB2YR"),
    "P": ("2017_2020", "P_PFAS.XPT", "P_DEMO.XPT", "WTSBAPRP"),
}

ANALYTES = (
    ("n_pfoa", "LBXNFOA", "LBDNFOAL"),
    ("sb_pfoa", "LBXBFOA", "LBDBFOAL"),
    ("n_pfos", "LBXNFOS", "LBDNFOSL"),
    ("sm_pfos", "LBXMFOS", "LBDMFOSL"),
)


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def _load_merged(cycle_dir: str, pfas_fname: str, demo_fname: str, weight_col: str) -> pd.DataFrame:
    pfas = pd.read_sas(RAW_ROOT / cycle_dir / pfas_fname, format="xport")
    demo = pd.read_sas(RAW_ROOT / cycle_dir / demo_fname, format="xport")
    demo_cols = ["SEQN", "RIAGENDR", "RIDAGEYR"]
    if "RIDRETH3" in demo.columns:
        demo_cols.append("RIDRETH3")
    demo = demo[demo_cols]
    merged = pfas.merge(demo, on="SEQN", how="inner")
    if weight_col not in merged.columns:
        raise RuntimeError(f"Missing weight column {weight_col!r} in {pfas_fname}")
    merged = merged[merged[weight_col] > 0]
    merged = merged[merged["RIDAGEYR"] >= 12]
    return merged


def build_governed_long(df: pd.DataFrame, *, cycle_label: str) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for _, rec in df.iterrows():
        sex = rec.get("RIAGENDR")
        age = rec.get("RIDAGEYR")
        sex_out = ""
        if pd.notna(sex) and float(sex) in (1.0, 2.0):
            sex_out = str(int(float(sex)))
        age_out = ""
        if pd.notna(age):
            age_out = str(int(float(age)))
        race_out = ""
        reth = rec.get("RIDRETH3")
        if pd.notna(reth):
            label = RIDRETH3_TO_LABEL.get(int(float(reth)))
            if label:
                race_out = label

        for analyte_id, val_col, lod_col in ANALYTES:
            if val_col not in df.columns:
                continue
            val = rec.get(val_col)
            if pd.isna(val) or not np.isfinite(float(val)):
                continue
            lod_code = "0"
            if lod_col in df.columns:
                flag = rec.get(lod_col)
                if pd.notna(flag) and int(float(flag)) == 1:
                    lod_code = "1"

            rows.append(
                {
                    "sample_matrix": "human_serum",
                    "result_unit": "ng/mL",
                    "source_program": "CDC NHANES",
                    "analyte": analyte_id,
                    "result_value": float(val),
                    "sex": sex_out,
                    "age_years": age_out,
                    "race_ethnicity": race_out,
                    "reference_cycle": cycle_label,
                    "lod_code": lod_code,
                    "seqn": int(rec["SEQN"]) if pd.notna(rec.get("SEQN")) else "",
                }
            )

    out = pd.DataFrame(rows)
    out.insert(0, "row_index", range(len(out)))
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Build governed V1 CSV from NHANES PFAS+DEMO XPT (SEQN join).",
    )
    parser.add_argument(
        "--cycle",
        default="J",
        choices=sorted(CYCLE_MAP),
        help="NHANES cycle label (default J = 2017-2018)",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        default=REPO_ROOT / "data" / "v1" / "fixtures" / "nhanes_j_governed_v1_input.csv",
    )
    parser.add_argument(
        "--analyte",
        choices=[a[0] for a in ANALYTES] + ["all"],
        default="all",
        help="Emit one analyte or all four isomers (default all)",
    )
    parser.add_argument(
        "--all-cycles",
        action="store_true",
        help="Build governed inputs for cycles I, J, and P",
    )
    args = parser.parse_args(argv)

    if args.all_cycles:
        rc = 0
        for cycle in sorted(CYCLE_MAP):
            out = REPO_ROOT / "data" / "v1" / "fixtures" / f"nhanes_{cycle.lower()}_governed_v1_input.csv"
            rc |= main(
                [
                    "--cycle",
                    cycle,
                    "-o",
                    str(out),
                    "--analyte",
                    args.analyte,
                ]
            )
        return rc

    cycle_dir, pfas_fname, demo_fname, weight_col = CYCLE_MAP[args.cycle.upper()]
    pfas_path = RAW_ROOT / cycle_dir / pfas_fname
    demo_path = RAW_ROOT / cycle_dir / demo_fname
    if not pfas_path.is_file() or not demo_path.is_file():
        raise SystemExit(
            f"Missing XPT under {RAW_ROOT / cycle_dir}. "
            "Run: powershell -File scripts/download_nhanes_pfas.ps1"
        )

    print(f"Loading {cycle_dir} PFAS+DEMO (join SEQN) ...")
    merged = _load_merged(cycle_dir, pfas_fname, demo_fname, weight_col)
    print(f"  participants (weighted, age>=12): {len(merged)}")

    governed = build_governed_long(merged, cycle_label=args.cycle.upper())
    if args.analyte != "all":
        governed = governed[governed["analyte"] == args.analyte].reset_index(drop=True)
        governed["row_index"] = range(len(governed))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    governed.to_csv(args.output, index=False)

    n_sex = (governed["sex"] != "").sum()
    n_age = (governed["age_years"] != "").sum()
    n_race = (governed["race_ethnicity"] != "").sum() if "race_ethnicity" in governed.columns else 0
    print(f"Wrote {args.output} ({len(governed)} rows)")
    print(f"  rows with sex: {n_sex}  rows with age_years: {n_age}  rows with race_ethnicity: {n_race}")
    print(f"  analyte counts:\n{governed['analyte'].value_counts().to_string()}")
    print(f"  PFAS XPT sha256: {_sha256(pfas_path)[:16]}…")
    print(f"  DEMO XPT sha256: {_sha256(demo_path)[:16]}…")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
