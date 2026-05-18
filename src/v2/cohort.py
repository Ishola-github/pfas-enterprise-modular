"""Cohort-level summaries for V2 cross-cycle report outputs."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import pandas as pd

GROUP_KEYS: tuple[str, ...] = (
    "analyte",
    "sex_stratum",
    "age_group_stratum",
    "race_ethnicity_stratum",
)


@dataclass(frozen=True)
class CohortSummaryResult:
    summary_df: pd.DataFrame
    n_input_rows: int
    n_in_domain_rows: int
    n_groups: int


def _to_numeric(df: pd.DataFrame, cols: list[str]) -> pd.DataFrame:
    out = df.copy()
    for c in cols:
        if c in out.columns:
            out[c] = pd.to_numeric(out[c], errors="coerce")
    return out


def summarize_v2_report(df: pd.DataFrame) -> CohortSummaryResult:
    """Build stratum-level cohort summaries from a V2 report dataframe.

    The input is expected to be a CSV produced by ``src.v2.cli``.
    """
    n_input = int(len(df))
    in_domain = df[df.get("ad_status", "") == "in_domain"].copy()
    n_in_domain = int(len(in_domain))
    if in_domain.empty:
        empty = pd.DataFrame(
            columns=(
                list(GROUP_KEYS)
                + [
                    "n_rows",
                    "median_result_value",
                    "median_anchor_percentile",
                    "p25_anchor_percentile",
                    "p75_anchor_percentile",
                    "median_percentile_cycle_I",
                    "median_percentile_cycle_J",
                    "median_percentile_cycle_P",
                    "median_percentile_delta_J_minus_I",
                    "median_percentile_delta_P_minus_J",
                    "shift_ge_15_count",
                    "shift_ge_15_pct",
                ]
            )
        )
        return CohortSummaryResult(
            summary_df=empty, n_input_rows=n_input, n_in_domain_rows=n_in_domain, n_groups=0
        )

    in_domain = _to_numeric(
        in_domain,
        [
            "result_value",
            "anchor_percentile",
            "percentile_cycle_I",
            "percentile_cycle_J",
            "percentile_cycle_P",
            "percentile_delta_J_minus_I",
            "percentile_delta_P_minus_J",
        ],
    )
    flags = in_domain.get("temporal_context_flag", pd.Series([""] * len(in_domain))).fillna("")
    in_domain["shift_ge_15_flag"] = flags.str.contains("cross_cycle_percentile_shift_ge_15", regex=False)

    grouped = in_domain.groupby(list(GROUP_KEYS), dropna=False)
    summary = grouped.agg(
        n_rows=("row_index", "count"),
        median_result_value=("result_value", "median"),
        median_anchor_percentile=("anchor_percentile", "median"),
        p25_anchor_percentile=("anchor_percentile", lambda s: s.quantile(0.25)),
        p75_anchor_percentile=("anchor_percentile", lambda s: s.quantile(0.75)),
        median_percentile_cycle_I=("percentile_cycle_I", "median"),
        median_percentile_cycle_J=("percentile_cycle_J", "median"),
        median_percentile_cycle_P=("percentile_cycle_P", "median"),
        median_percentile_delta_J_minus_I=("percentile_delta_J_minus_I", "median"),
        median_percentile_delta_P_minus_J=("percentile_delta_P_minus_J", "median"),
        shift_ge_15_count=("shift_ge_15_flag", "sum"),
    ).reset_index()
    summary["shift_ge_15_count"] = summary["shift_ge_15_count"].astype(int)
    summary["shift_ge_15_pct"] = (
        (summary["shift_ge_15_count"] / summary["n_rows"]) * 100.0
    ).round(2)
    summary = summary.sort_values(
        by=["analyte", "race_ethnicity_stratum", "sex_stratum", "age_group_stratum"],
        kind="stable",
    ).reset_index(drop=True)

    return CohortSummaryResult(
        summary_df=summary,
        n_input_rows=n_input,
        n_in_domain_rows=n_in_domain,
        n_groups=int(len(summary)),
    )


def to_csv_bytes(df: pd.DataFrame) -> bytes:
    return df.to_csv(index=False, lineterminator="\n").encode("utf-8")


def build_overview(summary: CohortSummaryResult) -> dict[str, Any]:
    return {
        "n_rows_input_report": summary.n_input_rows,
        "n_rows_in_domain": summary.n_in_domain_rows,
        "n_groups": summary.n_groups,
        "analytes": sorted(summary.summary_df.get("analyte", pd.Series(dtype=str)).dropna().unique().tolist()),
    }
