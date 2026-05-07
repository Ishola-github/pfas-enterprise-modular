"""Ambient / stack air ETL v1 → canonical ng/m³."""

from __future__ import annotations

import math

import numpy as np
import pandas as pd

from recipes.units import lod_pair_to_ng_per_m3

# Display string (unicode) — parquet-safe UTF-8.
AIR_CANONICAL_UNIT = "ng/m³"


def preprocess_air_v1(df: pd.DataFrame) -> pd.DataFrame:
    """
    - Canonical **ng/m³** (µg/m³ → ×1000).
    - ND policy: ``sqrt_half_lod`` (see encoder).
    - ``method_id``: expect ``OTM-50`` / ``OTM-45`` (or variants) → ``etl_method_*`` dummies.
    - Context: ``control_device``, ``source_type`` (if present) → ``etl_air_*`` dummies.
    - **Do not** merge these rows with drinking-water MCL / UCMR exceedance logic downstream.
    """

    out = df.copy()
    if "conc_unit" not in out.columns:
        raise ValueError("air_v1 requires conc_unit on each row")

    conc_raw = pd.to_numeric(out["conc"], errors="coerce") if "conc" in out.columns else pd.Series(np.nan, index=out.index)
    units = out["conc_unit"]

    nd = pd.Series(False, index=out.index)
    if "is_non_detect" in out.columns:
        nd = out["is_non_detect"].fillna(False).astype(bool)
    nd = nd | conc_raw.isna()

    vals = []
    for v, u, flagged_nd in zip(conc_raw.tolist(), units.tolist(), nd.tolist()):
        if flagged_nd or v is None or (isinstance(v, float) and (math.isnan(v) or np.isnan(v))):
            vals.append(math.nan)
        else:
            vals.append(lod_pair_to_ng_per_m3(float(v), u))
    out["conc"] = vals

    if "lod" in out.columns:
        out["lod"] = [
            (math.nan if (v is None or (isinstance(v, float) and math.isnan(v))) else lod_pair_to_ng_per_m3(float(v), u))
            for v, u in zip(pd.to_numeric(out["lod"], errors="coerce").tolist(), units.tolist())
        ]
    if "reporting_limit" in out.columns:
        out["reporting_limit"] = [
            (math.nan if (v is None or (isinstance(v, float) and math.isnan(v))) else lod_pair_to_ng_per_m3(float(v), u))
            for v, u in zip(pd.to_numeric(out["reporting_limit"], errors="coerce").tolist(), units.tolist())
        ]

    out["canonical_conc_unit"] = AIR_CANONICAL_UNIT
    out["recipe_id"] = "air_v1"
    out["imputation"] = "sqrt_half_lod"
    out["is_non_detect"] = nd.astype(bool)
    out["etl_not_drinking_water_mcl_lane"] = 1

    gcol = "comptox_dtxsid" if "comptox_dtxsid" in out.columns else ("analyte" if "analyte" in out.columns else None)
    if gcol is not None:
        det = (~nd) & out["conc"].notna() & np.isfinite(out["conc"])
        med = out.groupby(gcol)["conc"].transform("median")
        out["etl_outlier_flag"] = ((det) & (out["conc"] > 100.0 * med) & med.notna() & (med > 0)).astype(int)
    else:
        out["etl_outlier_flag"] = 0

    if "month" in out.columns:
        m = pd.to_numeric(out["month"], errors="coerce").clip(1, 12)
        out["etl_month_sin"] = np.sin(2 * math.pi * (m - 1) / 12.0)
        out["etl_month_cos"] = np.cos(2 * math.pi * (m - 1) / 12.0)

    if "method_id" in out.columns:
        md = out["method_id"].astype(str)
        out = pd.concat([out.drop(columns=["method_id"]), pd.get_dummies(md, prefix="etl_method", dummy_na=False)], axis=1)

    for ctx_col, pref in (("control_device", "etl_air_control"), ("source_type", "etl_air_src")):
        if ctx_col in out.columns:
            cv = out[ctx_col].astype(str)
            out = pd.concat([out.drop(columns=[ctx_col]), pd.get_dummies(cv, prefix=pref, dummy_na=False)], axis=1)

    out["conc_unit"] = AIR_CANONICAL_UNIT
    return out
