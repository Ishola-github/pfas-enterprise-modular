"""Map optional input demographics to NHANES reference strata."""
from __future__ import annotations

import math
from typing import Any, Mapping


def _missing(v: Any) -> bool:
    if v is None:
        return True
    if isinstance(v, float) and math.isnan(v):
        return True
    if isinstance(v, str) and v.strip() == "":
        return True
    return False


def normalize_sex(row: Mapping[str, Any]) -> str:
    """Return ``male``, ``female``, or ``all`` for reference lookup."""
    for key in ("sex", "riagendr", "gender"):
        if key not in row or _missing(row[key]):
            continue
        raw = str(row[key]).strip().lower()
        if raw in {"1", "male", "m"}:
            return "male"
        if raw in {"2", "female", "f"}:
            return "female"
        try:
            code = int(float(raw))
            if code == 1:
                return "male"
            if code == 2:
                return "female"
        except (TypeError, ValueError):
            pass
    return "all"


def normalize_age_group(row: Mapping[str, Any]) -> str:
    """Return a reference-table age_group label or ``all_ages``."""
    for key in ("age_group", "ridageyr", "age_years", "age"):
        if key not in row or _missing(row[key]):
            continue
        raw = str(row[key]).strip()
        if raw in {"12-19", "20-39", "40-59", "60_plus", "all_ages"}:
            return raw
        try:
            age = int(float(raw))
        except (TypeError, ValueError):
            continue
        if age < 12:
            return "all_ages"
        if age <= 19:
            return "12-19"
        if age <= 39:
            return "20-39"
        if age <= 59:
            return "40-59"
        return "60_plus"
    return "all_ages"


def normalize_reference_cycle(
    row: Mapping[str, Any],
    *,
    default_cycle: str,
) -> str:
    for key in ("reference_cycle", "nhanes_cycle", "cycle"):
        if key not in row or _missing(row[key]):
            continue
        return str(row[key]).strip().upper()
    return default_cycle.upper()
