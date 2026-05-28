"""ETL recipes + parquet validation guards."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pandas as pd
import pytest

HYBRID_ROOT = Path(__file__).resolve().parents[1]
REPO_APP_ROOT = HYBRID_ROOT.parent


@pytest.fixture(autouse=True)
def _paths():
    p = str(HYBRID_ROOT)
    if p not in sys.path:
        sys.path.insert(0, p)
    yield


def test_water_serum_recipes_emit_distinct_canonical_units():
    from recipes import apply_etl_recipes_v1

    df = pd.DataFrame(
        {
            "sid": ["a", "b"],
            "matrix": ["water", "serum"],
            "conc": [1.0, 1.0],
            "conc_unit": ["ng/L", "ng/mL"],
            "lod": [0.5, 0.1],
            "is_non_detect": [False, False],
        }
    )
    out = apply_etl_recipes_v1(df, "matrix", strict_other=False)
    rows = dict(zip(out["sid"], zip(out["canonical_conc_unit"], out["recipe_id"])))
    assert rows["a"][0] == "ng/L" and rows["a"][1] == "water_v1"
    assert rows["b"][0] == "ng/mL" and rows["b"][1] == "serum_v1"


def test_assert_no_cross_matrix_unit_violation_detects_manual_corruption():
    from recipes import assert_no_cross_matrix_unit_violation

    df = pd.DataFrame(
        {
            "matrix": ["water"],
            "canonical_conc_unit": ["ng/mL"],
            "recipe_id": ["water_v1"],
        }
    )
    with pytest.raises(ValueError, match="canonical unit"):
        assert_no_cross_matrix_unit_violation(df, "matrix")


def test_inhomogeneous_canonical_within_water_raises():
    from recipes import apply_etl_recipes_v1
    from recipes.validate import assert_no_heterogeneous_canonical_units_per_matrix_class

    df = pd.DataFrame(
        {
            "matrix": ["water", "water"],
            "conc": [1.0, 2.0],
            "conc_unit": ["ng/L", "ng/L"],
            "is_non_detect": [False, False],
        }
    )
    out = apply_etl_recipes_v1(df, "matrix")
    assert set(out["canonical_conc_unit"].unique()) == {"ng/L"}
    out2 = out.copy()
    # Artificial split (simulates buggy half-run ETL merge)
    out2.loc[out2.index[1], "canonical_conc_unit"] = "bad"
    with pytest.raises(ValueError, match="Inhomogeneous"):
        assert_no_heterogeneous_canonical_units_per_matrix_class(out2, "matrix")


@pytest.mark.parametrize(("matrix_label", "strict_other", "expect_err"), [("coffee", False, False), ("coffee", True, True)])
def test_strict_unknown_matrix_label(matrix_label, strict_other, expect_err):
    from recipes.dispatch import apply_etl_recipes_v1

    df = pd.DataFrame([{"matrix": matrix_label, "conc": 1.0, "conc_unit": "ng/L", "lod": 0.1}])
    if expect_err:
        with pytest.raises(ValueError, match="strict mode"):
            apply_etl_recipes_v1(df, "matrix", strict_other=True)
    else:
        out = apply_etl_recipes_v1(df, "matrix", strict_other=False)
        assert (out["canonical_conc_unit"] == "unspecified").all()


def test_solids_lane_uses_ng_per_g_dw():
    from recipes import apply_etl_recipes_v1

    df = pd.DataFrame(
        [{"matrix": "sludge", "conc": 2.5, "conc_unit": "ug/g", "lod": 0.001, "is_non_detect": False}]
    )
    out = apply_etl_recipes_v1(df, "matrix")
    assert out["canonical_conc_unit"].iloc[0] == "ng/g_dw"
    assert out["recipe_id"].iloc[0] == "solids_v1"
    assert out["conc"].iloc[0] == pytest.approx(2500.0)


def test_preprocess_matrix_aliases_result_value():
    from preprocess_matrix import preprocess_for_shared_encoder

    df = pd.DataFrame(
        [
            {
                "sample_id": "x1",
                "matrix": "water",
                "result_value": 1.0,
                "conc_unit": "ug/L",
                "lod": 0.5,
                "mrl": 0.5,
                "is_non_detect": False,
            }
        ]
    )
    out = preprocess_for_shared_encoder(df, "matrix")
    assert "conc" in out.columns
    assert out["canonical_conc_unit"].iloc[0] == "ng/L"


def test_air_lane_uses_ng_per_m3():
    from recipes import apply_etl_recipes_v1

    df = pd.DataFrame(
        [
            {
                "matrix": "stack",
                "conc": 0.5,
                "conc_unit": "ug/m3",
                "lod": 0.01,
                "is_non_detect": False,
            }
        ]
    )
    out = apply_etl_recipes_v1(df, "matrix")
    assert out["canonical_conc_unit"].iloc[0] in ("ng/m³",)
    assert abs(out["conc"].iloc[0] - 500.0) < 1e-6


def test_shared_encoder_parquet_requires_recipe_when_mixed_but_unit_ok():
    """Build script validates canonical units across matrix lanes — smoke CSV should pass."""

    ingest = REPO_APP_ROOT / "data" / "examples" / "encoder_ingest_smoke.csv"
    out_pq = REPO_APP_ROOT / "results" / "_pytest_shared_encoder.parquet"

    out_prv = REPO_APP_ROOT / "results" / "_pytest_shared_encoder_provenance.json"

    cmd = [
        sys.executable,
        str(HYBRID_ROOT / "build_shared_encoder_table.py"),
        "--input",
        str(ingest),
        "--output",
        str(out_pq),
        "--provenance",
        str(out_prv),
        "--derive-matrix-onehot",
        "matrix",
        "--recipe-etl-v1",
        "--id-cols",
        "sample_id",
    ]
    subprocess.run(
        cmd,
        cwd=str(REPO_APP_ROOT),
        check=True,
    )
    pq = pd.read_parquet(out_pq)
    assert "canonical_conc_unit" in pq.columns
    assert set(pq["canonical_conc_unit"].dropna()) == {"ng/L", "ng/mL"}
    out_pq.unlink(missing_ok=True)
    out_prv.unlink(missing_ok=True)
