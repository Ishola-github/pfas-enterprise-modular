"""Normalize free-text matrix labels → routing keys for recipes."""

from __future__ import annotations

import math
from typing import Any


def normalize_matrix_label(label: Any) -> str:
    if label is None:
        return ""
    if isinstance(label, float) and math.isnan(label):
        return ""
    s = str(label).strip().lower()
    if not s:
        return ""
    return "_".join(s.replace("-", " ").split())


def matrix_route_key(label: Any) -> str:
    """Return ``water`` | ``serum`` | ``air`` | ``solids`` | ``other``.

    Labels are disjoint by priority order (first match wins).
    """

    key = normalize_matrix_label(label)
    if not key:
        return "other"

    water = frozenset(
        {
            "water",
            "dw",
            "drinking",
            "drinking_water",
            "potable",
            "tap",
            "freshwater",
            "groundwater",
            "surface_water",
            "ucmr",
        }
    )
    serum = frozenset(
        {
            "serum",
            "blood",
            "plasma",
            "whole_blood",
            "cord_blood",
            "venous_blood",
            "nhanes_serum",
            "clinical_serum",
        }
    )

    air = frozenset(
        {
            "air",
            "ambient_air",
            "ambient",
            "ambientair",
            "outdoor_air",
            "stack",
            "stack_gas",
            "vapor",
            "canopy",
            "passive_air",
            "indoor_air",
            "fence_line",
            "fenceline",
        }
    )
    solids = frozenset(
        {
            "sludge",
            "soil",
            "sediment",
            "biosolid",
            "biosolids",
            "surface_soil",
            "land_application",
            "lagoon_solids",
            "lagoon_sludge",
            "contaminated_soil",
            "aquatic_sediment",
        }
    )

    if key in water:
        return "water"
    if key in serum:
        return "serum"
    if key in air:
        return "air"
    if key in solids:
        return "solids"
    return "other"
