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


def _cell_str(value: Any) -> str:
    """Normalize a CSV cell for demographic parsers (handles pandas NaN / 1.0)."""
    if _missing(value):
        return ""
    if isinstance(value, float) and value == int(value):
        return str(int(value))
    return str(value).strip()


# NHANES RIDRETH3 (2017-2018 DEMO) -> governed V1.1 labels.
RIDRETH3_TO_LABEL: dict[int, str] = {
    1: "mexican_american",
    2: "other_hispanic",
    3: "nh_white",
    4: "nh_black",
    6: "nh_asian",
    7: "other",
}

RACE_ETHNICITY_LABELS: tuple[str, ...] = (
    "mexican_american",
    "other_hispanic",
    "nh_white",
    "nh_black",
    "nh_asian",
    "other",
    "all",
)


def input_demographics_summary(rows: list[Mapping[str, Any]]) -> dict[str, int]:
    """Count how many rows carry sex / age / race for preflight messaging."""
    n = len(rows)
    n_sex = 0
    n_age = 0
    n_race = 0
    for row in rows:
        for key in ("sex", "riagendr", "gender"):
            if key in row and not _missing(row[key]):
                n_sex += 1
                break
        for key in ("age_years", "ridageyr", "age", "age_group"):
            if key in row and not _missing(row[key]):
                n_age += 1
                break
        for key in ("race_ethnicity", "ridreth3"):
            if key in row and not _missing(row[key]):
                n_race += 1
                break
    return {
        "n_rows": n,
        "n_with_sex": n_sex,
        "n_with_age_years": n_age,
        "n_with_race_ethnicity": n_race,
        "n_without_sex": n - n_sex,
        "n_without_age_years": n - n_age,
        "n_without_race_ethnicity": n - n_race,
    }


def normalize_sex(row: Mapping[str, Any]) -> str:
    """Return ``male``, ``female``, or ``all`` for reference lookup."""
    for key in ("sex", "riagendr", "gender"):
        if key not in row or _missing(row[key]):
            continue
        raw = _cell_str(row[key]).lower()
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


def normalize_race_ethnicity(row: Mapping[str, Any]) -> str:
    """Return a reference-table race_ethnicity label or ``all``."""
    for key in ("race_ethnicity", "ridreth3"):
        if key not in row or _missing(row[key]):
            continue
        raw = _cell_str(row[key])
        if raw in RACE_ETHNICITY_LABELS:
            return raw
        try:
            code = int(float(raw))
        except (TypeError, ValueError):
            continue
        label = RIDRETH3_TO_LABEL.get(code)
        if label:
            return label
    return "all"


def stratum_lookup_candidates(sex: str, age_group: str) -> list[tuple[str, str]]:
    """Ordered NHANES stratum keys to try (requested → broader fallbacks)."""
    seen: set[tuple[str, str]] = set()
    ordered: list[tuple[str, str]] = []
    for pair in (
        (sex, age_group),
        (sex, "all_ages"),
        ("all", age_group),
        ("all", "all_ages"),
    ):
        if pair not in seen:
            seen.add(pair)
            ordered.append(pair)
    return ordered


def stratum_lookup_candidates_v1_1(
    sex: str,
    age_group: str,
    race_ethnicity: str,
) -> list[tuple[str, str, str]]:
    """Ordered (sex, age_group, race_ethnicity) keys for V1.1 tables."""
    seen: set[tuple[str, str, str]] = set()
    ordered: list[tuple[str, str, str]] = []
    races = [race_ethnicity, "all"] if race_ethnicity != "all" else ["all"]
    for race in races:
        for pair in stratum_lookup_candidates(sex, age_group):
            triple = (pair[0], pair[1], race)
            if triple not in seen:
                seen.add(triple)
                ordered.append(triple)
    return ordered
