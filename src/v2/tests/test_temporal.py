"""V2 temporal engine unit tests."""
from __future__ import annotations

from src.v1.applicability import validate_row
from src.v1.ontology import load_ontology as load_v1
from src.v1.reference import ReferenceEngine
from src.v2.ontology import load_ontology as load_v2
from src.v2.temporal import contextualize_cross_cycle, resolve_temporal_flags


def test_temporal_flags_shift():
    flags = resolve_temporal_flags(
        delta_j_i=18.0,
        delta_p_j=2.0,
        missing_cycles=(),
    )
    assert "cross_cycle_percentile_shift_ge_15" in flags
    assert "cycle_P_pre_pandemic_caveat" in flags


def test_cross_cycle_smoke():
    from pathlib import Path

    repo = Path(__file__).resolve().parents[3]
    v1 = load_v1(repo / "src/v1/data/ontology/pfos_pfoa_v1_1.json")
    engine = ReferenceEngine.load(v1, repo / v1.expected_reference_table_path)
    row = {
        "sample_matrix": "human_serum",
        "result_unit": "ng/mL",
        "source_program": "CDC NHANES",
        "analyte": "n_pfos",
        "result_value": 9.6,
        "sex": "1",
        "age_years": 35,
        "race_ethnicity": "nh_white",
        "reference_cycle": "J",
        "lod_code": 0,
    }
    vr = validate_row(row, v1)
    assert vr.ad_status == "in_domain"
    t = contextualize_cross_cycle(row, vr, engine, default_anchor_cycle="J")
    assert t.percentiles_by_cycle["J"] is not None
    assert t.anchor_percentile == t.percentiles_by_cycle["J"]
