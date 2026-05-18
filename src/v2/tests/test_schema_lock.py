"""Schema lock tests for V2 cohort summary outputs."""
from __future__ import annotations

import tempfile
from pathlib import Path

import pandas as pd

from src.v2.cli import run_pipeline as run_v2_pipeline
from src.v2.cohort_cli import run_pipeline as run_cohort_pipeline


def test_v2_cohort_summary_columns_locked():
    repo = Path(__file__).resolve().parents[3]
    fixture = repo / "data" / "v1" / "fixtures" / "nhanes_j_governed_v1_input.csv"

    with tempfile.TemporaryDirectory() as td:
        out_v2 = Path(td) / "v2"
        v2_summary = run_v2_pipeline(input_csv=fixture, output_dir=out_v2, repo_root=repo)
        out_cohort = Path(td) / "cohort"
        cohort_summary = run_cohort_pipeline(
            input_report_csv=Path(v2_summary["csv_path"]),
            output_dir=out_cohort,
            repo_root=repo,
        )
        df = pd.read_csv(cohort_summary["csv_path"], nrows=1)

    required = {
        "analyte",
        "sex_stratum",
        "age_group_stratum",
        "race_ethnicity_stratum",
        "n_rows",
        "median_result_value",
        "median_anchor_percentile",
        "median_percentile_delta_J_minus_I",
        "median_percentile_delta_P_minus_J",
        "shift_ge_15_count",
        "shift_ge_15_pct",
    }
    missing = sorted(required - set(df.columns))
    assert not missing, f"V2 cohort schema lock failed; missing columns: {missing}"
