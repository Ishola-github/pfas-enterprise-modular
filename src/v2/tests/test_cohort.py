from __future__ import annotations

import pandas as pd

from src.v2.cohort import summarize_v2_report


def test_summarize_v2_report_grouping_and_shift_counts():
    df = pd.DataFrame(
        [
            {
                "row_index": 0,
                "ad_status": "in_domain",
                "analyte": "n_pfos",
                "sex_stratum": "male",
                "age_group_stratum": "20_39",
                "race_ethnicity_stratum": "nh_white",
                "result_value": 9.6,
                "anchor_percentile": 99.0,
                "percentile_cycle_I": 95.0,
                "percentile_cycle_J": 99.0,
                "percentile_cycle_P": 99.0,
                "percentile_delta_J_minus_I": 4.0,
                "percentile_delta_P_minus_J": 0.0,
                "temporal_context_flag": "cross_cycle_percentile_shift_ge_15;cycle_P_pre_pandemic_caveat",
            },
            {
                "row_index": 1,
                "ad_status": "in_domain",
                "analyte": "n_pfos",
                "sex_stratum": "male",
                "age_group_stratum": "20_39",
                "race_ethnicity_stratum": "nh_white",
                "result_value": 4.0,
                "anchor_percentile": 75.0,
                "percentile_cycle_I": 70.0,
                "percentile_cycle_J": 75.0,
                "percentile_cycle_P": 76.0,
                "percentile_delta_J_minus_I": 5.0,
                "percentile_delta_P_minus_J": 1.0,
                "temporal_context_flag": "cycle_P_pre_pandemic_caveat",
            },
            {
                "row_index": 2,
                "ad_status": "refused",
                "analyte": "n_pfos",
                "sex_stratum": "",
                "age_group_stratum": "",
                "race_ethnicity_stratum": "",
                "result_value": 0.0,
                "anchor_percentile": "",
                "temporal_context_flag": "",
            },
        ]
    )
    out = summarize_v2_report(df)
    assert out.n_input_rows == 3
    assert out.n_in_domain_rows == 2
    assert out.n_groups == 1
    row = out.summary_df.iloc[0]
    assert row["n_rows"] == 2
    assert row["shift_ge_15_count"] == 1
    assert row["shift_ge_15_pct"] == 50.0
    assert row["median_anchor_percentile"] == 87.0
