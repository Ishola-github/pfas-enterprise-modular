"""Per-matrix ETL recipes (canonical units before encoder). Suite **etl_matrix_v2** — see `preprocess_matrix.py` for the consolidated entry point.
"""

from .dispatch import RECIPE_SUITE_ID, apply_etl_recipes_v1
from .validate import (
    assert_no_cross_matrix_unit_violation,
    assert_no_heterogeneous_canonical_units_per_matrix_class,
    assert_rows_have_required_for_recipes,
)

__all__ = [
    "RECIPE_SUITE_ID",
    "apply_etl_recipes_v1",
    "assert_no_cross_matrix_unit_violation",
    "assert_no_heterogeneous_canonical_units_per_matrix_class",
    "assert_rows_have_required_for_recipes",
]
