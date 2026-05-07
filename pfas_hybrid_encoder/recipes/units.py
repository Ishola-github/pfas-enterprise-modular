"""Canonical concentration units for PFAS ETL (environmental vs clinical)."""


from __future__ import annotations

import math
import re
from typing import Optional


def normalize_unit_key(raw: Optional[str]) -> str:
    """Lowercase, unicode-safe, strip punctuation to a token key."""
    if raw is None or (isinstance(raw, float) and math.isnan(raw)):
        return ""
    s = str(raw).strip().lower().replace("μ", "u")
    for ch in ("³", "²"):
        repl = {"³": "3", "²": "2"}[ch]
        s = s.replace(ch, repl)
    s = re.sub(r"\s+", "_", s)
    s = s.replace("/", "_").replace("-", "_").replace(".", "").replace(",", "")
    return s.strip("_")


def conc_to_ng_per_l(value: float, unit_raw: Optional[str]) -> float:
    """Target: ng/L (mass per volume, water / environmental liquid)."""
    key = normalize_unit_key(unit_raw)
    if key in ("", "missing", "unknown"):
        raise ValueError("conc_unit is required for recipe conversion to ng/L")
    if key in ("ng_l", "ppt"):  # ppt informal for trace water — treat as ng/L in v1
        return float(value)
    if key in ("ug_l", "ugl", "µg_l"):
        return float(value) * 1000.0
    if key in ("mg_l", "mgl"):
        return float(value) * 1e6
    if key in ("pg_l", "pgl"):
        return float(value) / 1000.0
    if key in ("g_l",):
        return float(value) * 1e9
    # Common mistakes: serum ng/mL labeled on water — caller must not mis-label matrix
    if key in ("ng_ml", "ngml"):
        return float(value) * 1000.0  # 1 ng/mL -> 1000 ng/L
    raise ValueError(f"Unsupported water conc_unit for v1 recipe: {unit_raw!r}")


def conc_to_ng_per_ml(value: float, unit_raw: Optional[str]) -> float:
    """Target: ng/mL (serum / plasma style reporting)."""
    key = normalize_unit_key(unit_raw)
    if key in ("", "missing", "unknown"):
        raise ValueError("conc_unit is required for recipe conversion to ng/mL")
    if key in ("ng_ml", "ngml"):
        return float(value)
    # 1 µg/L === 1 ng/mL numerically (both 1000 ng/L)
    if key in ("ug_l", "ugl", "µg_l"):
        return float(value)
    if key in ("ng_l", "ppt"):
        return float(value) / 1000.0
    if key in ("ug_ml", "ugml"):
        return float(value) * 1000.0
    if key in ("mg_l",):
        return float(value) * 1000.0  # 1 mg/L -> 1000 ng/mL
    raise ValueError(f"Unsupported serum conc_unit for v1 recipe: {unit_raw!r}")


def lod_pair_to_ng_per_l(lod: float, unit_raw: Optional[str]) -> float:
    return conc_to_ng_per_l(float(lod), unit_raw)


def lod_pair_to_ng_per_ml(lod: float, unit_raw: Optional[str]) -> float:
    return conc_to_ng_per_ml(float(lod), unit_raw)


def conc_to_ng_per_m3(value: float, unit_raw: Optional[str]) -> float:
    """Target: ng/m³ (ambient/stack air conventions). µg/m³ → ×1000."""

    key = normalize_unit_key(unit_raw)
    if key in ("", "missing", "unknown"):
        raise ValueError("conc_unit is required for recipe conversion to ng/m³")
    if key in ("ng_m3", "ngm3"):
        return float(value)
    if key in ("ug_m3", "ugm3", "ug_m_3"):
        return float(value) * 1000.0
    if key in ("mg_m3", "mgm3"):
        return float(value) * 1e6
    if key in ("pg_m3",):
        return float(value) / 1000.0
    raise ValueError(f"Unsupported air conc_unit for v1 recipe: {unit_raw!r}")


def lod_pair_to_ng_per_m3(lod: float, unit_raw: Optional[str]) -> float:
    return conc_to_ng_per_m3(float(lod), unit_raw)


def conc_to_ng_per_g_dw(value: float, unit_raw: Optional[str]) -> float:
    """Target: ng/g dry weight (solids — soil / sludge / sediment)."""

    key = normalize_unit_key(unit_raw)
    if key in ("", "missing", "unknown"):
        raise ValueError("conc_unit is required for recipe conversion to ng/g dw")
    if key in ("ng_g", "ng_g_dw", "ng_dw", "ppb_dw"):
        return float(value)
    if key in ("ug_g", "ugg", "ug_g_dw", "ug_dw"):
        return float(value) * 1000.0
    if key in ("mg_kg", "mgkg"):  # ≈ µg/g
        return float(value) * 1000.0
    if key in ("mg_g", "mgg"):
        return float(value) * 1e6
    if key in ("ug_kg",):
        return float(value)
    if key in ("g_g", "gg"):  # rare
        return float(value) * 1e9
    raise ValueError(f"Unsupported solids conc_unit for v1 recipe: {unit_raw!r}")


def lod_pair_to_ng_per_g_dw(lod: float, unit_raw: Optional[str]) -> float:
    return conc_to_ng_per_g_dw(float(lod), unit_raw)
