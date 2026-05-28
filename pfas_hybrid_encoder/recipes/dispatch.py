"""Route rows to matrix-specific preprocessing recipes."""

from __future__ import annotations

from typing import List

import pandas as pd

from recipes.air_v1 import preprocess_air_v1
from recipes.matrix_class import matrix_route_key
from recipes.serum_v1 import preprocess_serum_v1
from recipes.solids_v1 import preprocess_solids_v1
from recipes.water_v1 import preprocess_water_v1

RECIPE_SUITE_ID = "etl_matrix_v2"


def apply_etl_recipes_v1(df: pd.DataFrame, matrix_col: str, *, strict_other: bool = False) -> pd.DataFrame:
    """
    Split by ``matrix_col`` label → ``water_v1`` | ``serum_v1`` | ``air_v1`` | ``solids_v1`` | ``other``.

    Raises if ``strict_other`` when any row is classified ``other`` (unknown matrix lane).
    """

    if matrix_col not in df.columns:
        raise ValueError(f"matrix column {matrix_col!r} missing (required for matrix ETL)")
    routes = df[matrix_col].map(matrix_route_key)
    idx_all = df.index
    chunks: List[pd.DataFrame] = []

    route_fn = (
        ("water", preprocess_water_v1),
        ("serum", preprocess_serum_v1),
        ("air", preprocess_air_v1),
        ("solids", preprocess_solids_v1),
    )
    for key, fn in route_fn:
        mask = routes == key
        if mask.any():
            chunks.append(fn(df.loc[mask]))

    o_mask = routes == "other"
    if o_mask.any():
        if strict_other:
            bad = df.loc[o_mask, matrix_col].head(20).tolist()
            raise ValueError(f"recipe strict mode: unsupported matrix rows (sample labels): {bad}")
        och = df.loc[o_mask].copy()
        och["canonical_conc_unit"] = "unspecified"
        och["recipe_id"] = "none"
        och["etl_outlier_flag"] = 0
        chunks.append(och)

    if not chunks:
        return df.copy()

    merged = pd.concat(chunks).reindex(idx_all)
    merged["etl_suite_id"] = RECIPE_SUITE_ID
    return merged
