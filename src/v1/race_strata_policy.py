"""Governed race/ethnicity stratum policy for V1.1+ reference lookup.

NHANES RIDRETH3 granular labels are preserved on input rows
(``race_ethnicity_requested``). Reference-table lookup uses collapsed
``hispanic`` (RIDRETH3 codes 1+2) to stabilize cell sizes. Race-specific
reference rows are built only when ``n_unweighted >= MIN_N_RACE_STRATUM``.
"""
from __future__ import annotations

from typing import Mapping

# Governed minimum unweighted *n* for race-specific reference rows.
MIN_N_RACE_STRATUM = 20

# Granular RIDRETH3 labels stored on governed inputs and in reports.
RIDRETH3_TO_GRANULAR: dict[int, str] = {
    1: "mexican_american",
    2: "other_hispanic",
    3: "nh_white",
    4: "nh_black",
    6: "nh_asian",
    7: "other",
}

GRANULAR_RACE_LABELS: tuple[str, ...] = (
    "mexican_american",
    "other_hispanic",
    "nh_white",
    "nh_black",
    "nh_asian",
    "other",
)

# Collapsed labels present in the V1.1 reference table.
REFERENCE_RACE_LEVELS: tuple[str, ...] = (
    "all",
    "hispanic",
    "nh_white",
    "nh_black",
    "nh_asian",
    "other",
)

# Granular label -> reference lookup label.
COLLAPSE_TO_LOOKUP: dict[str, str] = {
    "mexican_american": "hispanic",
    "other_hispanic": "hispanic",
    "nh_white": "nh_white",
    "nh_black": "nh_black",
    "nh_asian": "nh_asian",
    "other": "other",
    "hispanic": "hispanic",
    "all": "all",
}

# RIDRETH3 code -> reference lookup label (skips granular).
RIDRETH3_TO_LOOKUP: dict[int, str] = {
    1: "hispanic",
    2: "hispanic",
    3: "nh_white",
    4: "nh_black",
    6: "nh_asian",
    7: "other",
}


def collapse_race_for_lookup(granular_label: str) -> str:
    """Map a granular or lookup label to the reference-table race key."""
    if not granular_label or granular_label == "all":
        return "all"
    return COLLAPSE_TO_LOOKUP.get(granular_label, "all")


def race_stratum_fallback(*, lookup_race: str, resolved_race: str) -> bool:
    """True when a specific race was requested but a broader stratum was used."""
    if lookup_race == "all":
        return False
    return resolved_race != lookup_race


def ridreth3_codes_for_reference_race(race_label: str) -> tuple[int, ...]:
    """NHANES RIDRETH3 codes included in a reference race level."""
    if race_label == "hispanic":
        return (1, 2)
    if race_label == "nh_white":
        return (3,)
    if race_label == "nh_black":
        return (4,)
    if race_label == "nh_asian":
        return (6,)
    if race_label == "other":
        return (7,)
    return ()
