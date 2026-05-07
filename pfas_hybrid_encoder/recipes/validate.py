"""Post-ETL validation for mixed canonical units."""

from __future__ import annotations

from typing import Iterable, Optional, Set

import pandas as pd

from preprocess_matrix import MATRIX_CANONICAL_UNITS_EXPECTED
from recipes.matrix_class import matrix_route_key


def assert_rows_have_required_for_recipes(df: pd.DataFrame, matrix_col: str, required: Optional[Iterable[str]] = None) -> None:
    """Fail fast before expensive encoder work (optional pre-alias guard)."""

    need = {"conc_unit", matrix_col}.union(required or ())
    miss = sorted(c for c in need if c not in df.columns)
    if miss:
        raise ValueError(f"ETL recipe missing required columns: {miss}")
    conc_cols = {"conc", "result_value", "meas_conc"}
    if not conc_cols.intersection(df.columns):
        raise ValueError("Need at least one of: conc, result_value, meas_conc (aliases map to conc).")


def assert_no_cross_matrix_unit_violation(df: pd.DataFrame, matrix_col: str) -> None:
    """
    After recipes, each matrix route must match its expected ``canonical_conc_unit`` set.
    """

    if "canonical_conc_unit" not in df.columns:
        raise ValueError("canonical_conc_unit missing — run matrix ETL before validation")

    bad: list[str] = []
    for idx, row in df.iterrows():
        route = matrix_route_key(row[matrix_col])
        cu = str(row["canonical_conc_unit"]).strip()
        exp = MATRIX_CANONICAL_UNITS_EXPECTED.get(route)
        if exp is None:
            continue
        if cu not in exp:
            bad.append(f"row {idx}: matrix_route={route!r} but canonical_conc_unit={cu!r} (expected one of {sorted(exp)})")
    if bad:
        raise ValueError("Cross-matrix / canonical unit violation:\n" + "\n".join(bad[:50]))


def assert_no_heterogeneous_canonical_units_per_matrix_class(df: pd.DataFrame, matrix_col: str) -> None:
    """Guards multiple canonical unit strings within the same route."""

    df = df.copy()
    df["_route"] = df[matrix_col].map(matrix_route_key)
    for route in sorted(MATRIX_CANONICAL_UNITS_EXPECTED.keys()):
        sub = df[df["_route"] == route]
        if sub.empty:
            continue
        units: Set[str] = set()
        for u in sub["canonical_conc_unit"].dropna().astype(str).tolist():
            t = str(u).strip()
            if t and t != "unspecified":
                units.add(t)
        if len(units) > 1:
            raise ValueError(f"Inhomogeneous canonical_conc_unit for route {route!r}: {sorted(units)}")
