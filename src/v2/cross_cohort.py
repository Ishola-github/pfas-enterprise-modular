"""Cross-cohort comparison utilities for governed cohort summaries."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import pandas as pd

KEY_COLUMNS: tuple[str, ...] = (
    "analyte",
    "sex_stratum",
    "age_group_stratum",
    "race_ethnicity_stratum",
)

VALUE_COLUMNS: tuple[str, ...] = (
    "n_rows",
    "median_result_value",
    "median_anchor_percentile",
    "shift_ge_15_pct",
)


@dataclass(frozen=True)
class CrossCohortResult:
    comparison_df: pd.DataFrame
    n_left_rows: int
    n_right_rows: int
    n_rows_out: int


def _prepare_side(df: pd.DataFrame, side: str) -> pd.DataFrame:
    missing = [c for c in list(KEY_COLUMNS) + list(VALUE_COLUMNS) if c not in df.columns]
    if missing:
        raise ValueError(f"{side} summary missing required columns: {missing}")
    out = df[list(KEY_COLUMNS) + list(VALUE_COLUMNS)].copy()
    for c in VALUE_COLUMNS:
        out[c] = pd.to_numeric(out[c], errors="coerce")
    return out.rename(columns={c: f"{side}_{c}" for c in VALUE_COLUMNS})


def compare_cohort_summaries(left: pd.DataFrame, right: pd.DataFrame) -> CrossCohortResult:
    """Compare two governed cohort summary CSV dataframes.

    Rows are aligned by analyte + sex + age_group + race.
    """
    left_in = _prepare_side(left, "left")
    right_in = _prepare_side(right, "right")
    merged = left_in.merge(right_in, on=list(KEY_COLUMNS), how="outer", indicator=True)

    merged["row_source"] = merged["_merge"].map(
        {"left_only": "left_only", "right_only": "right_only", "both": "both"}
    )
    merged = merged.drop(columns=["_merge"])

    for c in ("median_result_value", "median_anchor_percentile", "shift_ge_15_pct"):
        merged[f"delta_{c}"] = merged[f"right_{c}"] - merged[f"left_{c}"]

    merged["left_n_rows"] = merged["left_n_rows"].fillna(0).astype(int)
    merged["right_n_rows"] = merged["right_n_rows"].fillna(0).astype(int)
    merged["delta_n_rows"] = merged["right_n_rows"] - merged["left_n_rows"]

    merged = merged.sort_values(
        by=["analyte", "race_ethnicity_stratum", "sex_stratum", "age_group_stratum"],
        kind="stable",
    ).reset_index(drop=True)

    return CrossCohortResult(
        comparison_df=merged,
        n_left_rows=int(len(left)),
        n_right_rows=int(len(right)),
        n_rows_out=int(len(merged)),
    )


def to_csv_bytes(df: pd.DataFrame) -> bytes:
    return df.to_csv(index=False, lineterminator="\n").encode("utf-8")


def build_overview(result: CrossCohortResult) -> dict[str, Any]:
    df = result.comparison_df
    both = int((df["row_source"] == "both").sum()) if "row_source" in df.columns else 0
    left_only = int((df["row_source"] == "left_only").sum()) if "row_source" in df.columns else 0
    right_only = int((df["row_source"] == "right_only").sum()) if "row_source" in df.columns else 0
    return {
        "n_left_rows": result.n_left_rows,
        "n_right_rows": result.n_right_rows,
        "n_rows_out": result.n_rows_out,
        "n_matched_rows": both,
        "n_left_only_rows": left_only,
        "n_right_only_rows": right_only,
    }
