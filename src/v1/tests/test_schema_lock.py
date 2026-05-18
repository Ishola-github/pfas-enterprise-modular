"""Schema lock tests for governed V1.1 outputs."""
from __future__ import annotations

import tempfile
from pathlib import Path

import pandas as pd

from src.v1.cli import run_pipeline


def test_v1_1_report_includes_race_aware_columns():
    repo = Path(__file__).resolve().parents[3]
    fixture = repo / "data" / "v1" / "fixtures" / "nhanes_j_governed_v1_input.csv"
    ont_v11 = repo / "src" / "v1" / "data" / "ontology" / "pfos_pfoa_v1_1.json"

    with tempfile.TemporaryDirectory() as td:
        out_dir = Path(td) / "v1_schema_lock"
        summary = run_pipeline(
            input_csv=fixture,
            output_dir=out_dir,
            ontology_path=ont_v11,
            repo_root=repo,
        )
        df = pd.read_csv(summary["csv_path"], nrows=1)

    required = {
        "race_ethnicity_requested",
        "race_ethnicity_lookup",
        "race_ethnicity_stratum",
        "race_stratum_fallback",
    }
    missing = sorted(required - set(df.columns))
    assert not missing, f"V1.1 schema lock failed; missing columns: {missing}"
