"""
Matrix-safe preprocessing: **raw ingest → normalized rows** for parquet + encoder.

This is the orchestration boundary the parquet builder relies on — no downstream MLP/tabular model here.
"""

from __future__ import annotations

from typing import FrozenSet, Iterable, Mapping, Optional, Sequence, Tuple

import pandas as pd

PRIMARY_CONC_COLUMNS: Sequence[str] = ("conc", "result_value", "meas_conc")

LOD_FALLBACK_COLUMNS: Sequence[str] = ("lod", "mrl", "mdl", "dl", "method_detection_limit")

REPORT_LIMIT_FALLBACKS: Sequence[str] = ("reporting_limit", "rl", "pql", "practical_quantitation_limit")

NHANES_NUMERIC_COPIES: Tuple[Tuple[str, str], ...] = (
    ("WTSAF2YR", "etl_survey_wtsaf2yr"),
    ("WTSAFPRC", "etl_survey_wtsafprc"),
    ("WTSAFA2YR", "etl_survey_wtsafa2yr"),
    ("SDMVPSU", "etl_survey_sdpsu"),
    ("SDMVSTRA", "etl_survey_sdstra"),
)

NHANES_DEMO_COPIES: Tuple[Tuple[str, str], ...] = (
    ("RIDAGEYR", "etl_participant_age_years"),
    ("RIAGENDR", "etl_participant_sex"),
    ("BMXBMI", "etl_participant_bmi"),
)

MATRIX_CANONICAL_UNITS_EXPECTED: Mapping[str, FrozenSet[str]] = {
    "water": frozenset({"ng/L"}),
    "serum": frozenset({"ng/mL"}),
    "air": frozenset({"ng/m³", "ng/m3"}),
    "solids": frozenset({"ng/g_dw"}),
}


def _first_present_alias(df: pd.DataFrame, candidates: Iterable[str]) -> Optional[str]:
    for n in candidates:
        if n in df.columns:
            return n
    return None


def apply_column_aliases_for_matrix_etl(df: pd.DataFrame) -> pd.DataFrame:
    """
    Harmonize regulatory / lab schemas.

    Water UCMR: ``result_value`` + MRL/DL aliases.
    Serum / NHANES: duplicate survey weights + demographics to stable ``etl_*`` targets (additive only).
    """

    out = df.copy()

    if "conc" not in out.columns:
        pc = _first_present_alias(out, [c for c in PRIMARY_CONC_COLUMNS if c != "conc"])
        if pc is not None:
            out["conc"] = out[pc]

    if "lod" not in out.columns:
        lc = _first_present_alias(out, [c for c in LOD_FALLBACK_COLUMNS if c != "lod"])
        if lc is not None:
            out["lod"] = out[lc]

    if "reporting_limit" not in out.columns:
        rc = _first_present_alias(out, [c for c in REPORT_LIMIT_FALLBACKS if c != "reporting_limit"])
        if rc is not None:
            out["reporting_limit"] = out[rc]

    for src, tgt in NHANES_NUMERIC_COPIES:
        if src in out.columns and tgt not in out.columns:
            out[tgt] = pd.to_numeric(out[src], errors="coerce")
    for src, tgt in NHANES_DEMO_COPIES:
        if src in out.columns and tgt not in out.columns:
            out[tgt] = out[src]

    return out


def assert_preprocessing_inputs(df: pd.DataFrame, matrix_col: str) -> None:
    if matrix_col not in df.columns:
        raise ValueError(f"matrix column {matrix_col!r} not in dataframe.")
    if "conc_unit" not in df.columns:
        raise ValueError("conc_unit is required — never infer units implicitly across matrices.")
    if "conc" not in df.columns:
        raise ValueError("conc missing after aliasing — provide conc, result_value, or meas_conc.")


def preprocess_for_shared_encoder(
    df: pd.DataFrame,
    matrix_col: str,
    *,
    strict_unknown_matrix: bool = False,
    run_validators: bool = True,
) -> pd.DataFrame:
    """
    Canonical chain invoked by parquet build::

        aliases → routed recipes (water / serum / air / solids) → unit consistency assertions

    **Serum / NHANES:** survey weights & demographics are propagated via ``etl_*`` duplicates; serum rows are
    **not** given drinking-water MCL exceedance semantics (keep separate heads downstream).

    **Air:** ``etl_not_drinking_water_mcl_lane`` flags stack/ambient stacks vs municipal water QA.

    **Solids:** dry-weight normalization only; uncertainty still matrix-specific downstream.
    """

    df0 = apply_column_aliases_for_matrix_etl(df)
    assert_preprocessing_inputs(df0, matrix_col)

    from recipes import (
        assert_no_cross_matrix_unit_violation,
        assert_no_heterogeneous_canonical_units_per_matrix_class,
        apply_etl_recipes_v1,
    )

    out = apply_etl_recipes_v1(df0, matrix_col, strict_other=strict_unknown_matrix)
    if run_validators:
        assert_no_cross_matrix_unit_violation(out, matrix_col)
        assert_no_heterogeneous_canonical_units_per_matrix_class(out, matrix_col)
    return out


def summarize_matrix_routes(df: pd.DataFrame, matrix_col: str) -> pd.Series:
    from recipes.matrix_class import matrix_route_key

    return df[matrix_col].map(matrix_route_key).value_counts()
