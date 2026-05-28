"""Hybrid encoder width and matrix-flag wiring (must stay aligned with MEASUREMENT_BLOCK_NAMES)."""

from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(autouse=True)
def _path():
    p = str(ROOT)
    if p not in sys.path:
        sys.path.insert(0, p)
    yield


def test_hybrid_encoder_output_dim_matches_schema():
    pytest.importorskip("rdkit")

    from pfas_encoder_vector import (
        MEASUREMENT_BLOCK_NAMES,
        DESCRIPTOR_FUNCTIONS,
        HybridVectorEncoder,
        hybrid_encoder_output_dim,
        measurement_block_width,
    )

    assert measurement_block_width() == len(MEASUREMENT_BLOCK_NAMES)
    enc = HybridVectorEncoder()
    dim = hybrid_encoder_output_dim(
        include_morgan=enc.include_morgan,
        morgan_bits=enc.morgan_bits,
    )
    names = enc.all_feature_names()
    assert dim == len(names)
    assert dim == len(DESCRIPTOR_FUNCTIONS) + (enc.morgan_bits if enc.include_morgan else 0) + measurement_block_width()
    row = enc.encode("C").vector
    assert row.shape[0] == dim


def test_measurement_vector_air_vs_solids_flags():
    pytest.importorskip("rdkit")

    from pfas_encoder_vector import HybridVectorEncoder, MeasurementRow

    enc = HybridVectorEncoder()
    names = enc.all_feature_names()
    iair = names.index("meas_flag_matrix_air")
    isol = names.index("meas_flag_matrix_solids")
    io = names.index("meas_flag_matrix_other")

    va = enc.encode("C", MeasurementRow(matrix_air=True, quant_value=0.0)).vector
    assert float(va[iair]) == pytest.approx(1.0)
    assert float(va[isol]) == pytest.approx(0.0)
    assert float(va[io]) == pytest.approx(0.0)

    vs = enc.encode("C", MeasurementRow(matrix_solids=True, quant_value=0.0)).vector
    assert float(vs[iair]) == pytest.approx(0.0)
    assert float(vs[isol]) == pytest.approx(1.0)
    assert float(vs[io]) == pytest.approx(0.0)


def test_apply_matrix_group_flags_routes_air_and_solids():
    from pfas_encoder_vector import apply_matrix_group_flags_inplace

    df = pd.DataFrame({"m": ["stack", "sludge", "serum", "coffee"]})
    apply_matrix_group_flags_inplace(df, "m")
    assert df["matrix_air"].tolist() == [True, False, False, False]
    assert df["matrix_solids"].tolist() == [False, True, False, False]
    assert df["matrix_serum"].tolist() == [False, False, True, False]
    assert df["matrix_other"].tolist() == [False, False, False, True]
