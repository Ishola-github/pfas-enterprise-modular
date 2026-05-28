"""Replay invariants for V1 deterministic governance."""
from __future__ import annotations

import json
import tempfile
from pathlib import Path

import pytest

from src.v1 import REFERENCE_TABLE_SHA256, __version__
from src.v1.applicability import validate_row
from src.v1.cli import run_pipeline
from src.v1.ontology import load_ontology
from src.v1.provenance import build_provenance


REPO = Path(__file__).resolve().parents[3]
FIXTURE = REPO / "data" / "v1" / "fixtures" / "sample_input.csv"


@pytest.fixture
def ontology():
    return load_ontology(REPO / "src" / "v1" / "data" / "ontology" / "pfos_pfoa_v1.json")


def test_same_input_same_output_hash(ontology):
    """Replay test #1: identical input -> identical output CSV hash."""
    inp = FIXTURE.read_bytes()
    with tempfile.TemporaryDirectory() as d1, tempfile.TemporaryDirectory() as d2:
        p1 = Path(d1) / "in.csv"
        p2 = Path(d2) / "in.csv"
        p1.write_bytes(inp)
        p2.write_bytes(inp)
        s1 = run_pipeline(input_csv=p1, output_dir=Path(d1) / "out", repo_root=REPO)
        s2 = run_pipeline(input_csv=p2, output_dir=Path(d2) / "out", repo_root=REPO)
    assert s1["output_csv_sha256"] == s2["output_csv_sha256"]
    assert s1["run_id"] == s2["run_id"]


def test_changed_ontology_changes_run_id(ontology):
    """Replay test #2: perturbed ontology -> different run_id."""
    inp_bytes = FIXTURE.read_bytes()
    ont_bytes = (REPO / "src" / "v1" / "data" / "ontology" / "pfos_pfoa_v1.json").read_bytes()
    perturbed = json.loads(ont_bytes.decode("utf-8"))
    perturbed["intent"] = perturbed["intent"] + " "
    perturbed_bytes = json.dumps(perturbed, sort_keys=True).encode("utf-8")

    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        inp = td_path / "in.csv"
        inp.write_bytes(inp_bytes)
        ont_a = td_path / "ont_a.json"
        ont_b = td_path / "ont_b.json"
        ont_a.write_bytes(ont_bytes)
        ont_b.write_bytes(perturbed_bytes)

        ref_table = REPO / "data" / "reference_tables" / "nhanes_pfas_weighted_reference_tables_v1.csv"
        anchor = REPO / "data" / "training" / "serum" / "nhanes_serum_pfas_2017_2018.csv"

        prov_a = build_provenance(
            input_csv_path=inp,
            reference_table_path=ref_table,
            ontology_path=ont_a,
            reference_table_documented_sha256=REFERENCE_TABLE_SHA256,
            code_version=__version__,
            ontology_version="1.0.1",
            anchor_csv_path=anchor,
        )
        prov_b = build_provenance(
            input_csv_path=inp,
            reference_table_path=ref_table,
            ontology_path=ont_b,
            reference_table_documented_sha256=REFERENCE_TABLE_SHA256,
            code_version=__version__,
            ontology_version="1.0.1",
            anchor_csv_path=anchor,
        )
    assert prov_a.run_id != prov_b.run_id


def test_unsupported_analyte_refusal(ontology):
    """Replay test #3: out-of-scope analyte -> refusal, no percentile."""
    row = {
        "sample_matrix": "human_serum",
        "result_unit": "ng/mL",
        "source_program": "CDC NHANES",
        "analyte": "pfda",
        "result_value": 1.0,
    }
    vr = validate_row(row, ontology)
    assert vr.ad_status == "refused"
    assert vr.ad_code == "analyte_not_in_pfos_pfoa_scope"


def test_water_matrix_hard_fail(ontology):
    row = {
        "sample_matrix": "drinking_water",
        "result_unit": "ng/mL",
        "source_program": "CDC NHANES",
        "analyte": "n_pfoa",
        "result_value": 1.0,
    }
    vr = validate_row(row, ontology)
    assert vr.ad_status == "refused"
    assert vr.ad_code == "matrix_not_serum"
