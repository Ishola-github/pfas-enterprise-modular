from __future__ import annotations

import pandas as pd

from src.v2.cross_cohort import compare_cohort_summaries


def _base_row(anchor: float, shift: float, n_rows: int = 10) -> dict[str, object]:
    return {
        "analyte": "n_pfos",
        "sex_stratum": "male",
        "age_group_stratum": "20_39",
        "race_ethnicity_stratum": "nh_white",
        "n_rows": n_rows,
        "median_result_value": 7.5,
        "median_anchor_percentile": anchor,
        "shift_ge_15_pct": shift,
    }


def test_compare_cohort_summaries_deltas_and_sources():
    left = pd.DataFrame([_base_row(80.0, 10.0)])
    right = pd.DataFrame([_base_row(92.0, 25.0)])
    out = compare_cohort_summaries(left, right)
    assert out.n_left_rows == 1
    assert out.n_right_rows == 1
    assert out.n_rows_out == 1
    row = out.comparison_df.iloc[0]
    assert row["row_source"] == "both"
    assert row["delta_median_anchor_percentile"] == 12.0
    assert row["delta_shift_ge_15_pct"] == 15.0


def test_compare_cohort_summaries_outer_join_behavior():
    left = pd.DataFrame([_base_row(80.0, 10.0)])
    right = pd.DataFrame(
        [{**_base_row(90.0, 20.0), "race_ethnicity_stratum": "nh_black"}]
    )
    out = compare_cohort_summaries(left, right)
    assert out.n_rows_out == 2
    assert set(out.comparison_df["row_source"]) == {"left_only", "right_only"}
