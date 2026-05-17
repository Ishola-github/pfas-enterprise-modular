"""Stratum normalization and demographics preflight."""
from __future__ import annotations

from src.v1.lod_policy import parse_lod_code, resolve_lod_context_flag
from src.v1.reference import PercentileResult
from src.v1.strata import (
    input_demographics_summary,
    normalize_age_group,
    normalize_race_ethnicity,
    normalize_sex,
    stratum_lookup_candidates,
    stratum_lookup_candidates_v1_1,
)


def test_normalize_sex_missing_is_all():
    assert normalize_sex({}) == "all"
    assert normalize_sex({"sex": ""}) == "all"
    assert normalize_sex({"sex": None}) == "all"


def test_normalize_sex_codes():
    assert normalize_sex({"sex": "1"}) == "male"
    assert normalize_sex({"sex": 1}) == "male"
    assert normalize_sex({"sex": 1.0}) == "male"
    assert normalize_sex({"sex": "2"}) == "female"
    assert normalize_sex({"sex": "Female"}) == "female"


def test_normalize_age_from_years():
    assert normalize_age_group({"age_years": 35}) == "20-39"
    assert normalize_age_group({"age_years": "42"}) == "40-59"
    assert normalize_age_group({}) == "all_ages"


def test_demographics_summary():
    rows = [
        {"sex": "1", "age_years": 35},
        {"sex": "", "age_years": ""},
        {},
    ]
    s = input_demographics_summary(rows)
    assert s["n_rows"] == 3
    assert s["n_with_sex"] == 1
    assert s["n_with_age_years"] == 1


def test_stratum_fallback_order():
    cands = stratum_lookup_candidates("male", "20-39")
    assert cands[0] == ("male", "20-39")
    assert ("male", "all_ages") in cands
    assert cands[-1] == ("all", "all_ages")


def test_normalize_race_ridreth3():
    assert normalize_race_ethnicity({"race_ethnicity": "nh_white"}) == "nh_white"
    assert normalize_race_ethnicity({"ridreth3": 3}) == "nh_white"
    assert normalize_race_ethnicity({}) == "all"


def test_v1_1_stratum_fallback_includes_race():
    cands = stratum_lookup_candidates_v1_1("male", "20-39", "nh_black")
    assert cands[0] == ("male", "20-39", "nh_black")
    assert ("male", "20-39", "all") in cands


def test_lod_context_flag_input_below_lod():
    pr = PercentileResult(
        analyte_id="sb_pfoa",
        query_value_ng_per_mL=0.07,
        percentile=5.0,
        n_reference=100,
        n_weighted=100.0,
        pct_below_lod_reference=90.0,
        imputed_below_lod_value_ng_per_mL=0.07,
        query_below_imputed_lod=True,
        weighted=True,
        reference_cycle="J",
        sex="male",
        age_group="60_plus",
    )
    assert parse_lod_code({"lod_code": 1}) == 1
    flag = resolve_lod_context_flag({"lod_code": "1"}, pr)
    assert "input_reported_below_lod" in flag
    assert "query_at_or_below_imputed_lod" in flag
