"""Soil / sludge / sediment ETL v1 → canonical ng/g dry weight."""

from __future__ import annotations

import math

import numpy as np
import pandas as pd

from recipes.units import lod_pair_to_ng_per_g_dw

SOLIDS_CANONICAL_UNIT = "ng/g_dw"


def preprocess_solids_v1(df: pd.DataFrame) -> pd.DataFrame:
    """
    - Canonical **ng/g dry weight**.
    - ``method_id`` often **1633A** (or variants) → ``etl_method_*``.
    - Optional ``dry_solids_frac`` / ``percent_solids``: copied to ``etl_*`` if present.
    - Separate regulatory lane from water MCL matrices.
    """

    out = df.copy()
    if "conc_unit" not in out.columns:
        raise ValueError("solids_v1 requires conc_unit on each row")

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
            vals.append(lod_pair_to_ng_per_g_dw(float(v), u))
    out["conc"] = vals

    if "lod" in out.columns:
        out["lod"] = [
            (math.nan if (v is None or (isinstance(v, float) and math.isnan(v))) else lod_pair_to_ng_per_g_dw(float(v), u))
            for v, u in zip(pd.to_numeric(out["lod"], errors="coerce").tolist(), units.tolist())
        ]
    if "reporting_limit" in out.columns:
        out["reporting_limit"] = [
            (math.nan if (v is None or (isinstance(v, float) and math.isnan(v))) else lod_pair_to_ng_per_g_dw(float(v), u))
            for v, u in zip(pd.to_numeric(out["reporting_limit"], errors="coerce").tolist(), units.tolist())
        ]

    out["canonical_conc_unit"] = SOLIDS_CANONICAL_UNIT
    out["recipe_id"] = "solids_v1"
    out["imputation"] = "sqrt_half_lod"
    out["is_non_detect"] = nd.astype(bool)
    out["etl_not_water_mcl_lane"] = 1

    if "dry_solids_frac" in out.columns:
        out["etl_dry_solids_frac"] = pd.to_numeric(out["dry_solids_frac"], errors="coerce")
        out.drop(columns=["dry_solids_frac"], inplace=True)
    if "percent_solids" in out.columns:
        out["etl_percent_solids"] = pd.to_numeric(out["percent_solids"], errors="coerce")
        out.drop(columns=["percent_solids"], inplace=True)

    gcol = "comptox_dtxsid" if "comptox_dtxsid" in out.columns else ("analyte" if "analyte" in out.columns else None)
    if gcol is not None:
        det = (~nd) & out["conc"].notna() & np.isfinite(out["conc"])
        med = out.groupby(gcol)["conc"].transform("median")
        out["etl_outlier_flag"] = ((det) & (out["conc"] > 100.0 * med) & med.notna() & (med > 0)).astype(int)
    else:
        out["etl_outlier_flag"] = 0

    if "method_id" in out.columns:
        md = out["method_id"].astype(str)
        out = pd.concat([out.drop(columns=["method_id"]), pd.get_dummies(md, prefix="etl_method", dummy_na=False)], axis=1)

    out["conc_unit"] = SOLIDS_CANONICAL_UNIT
    return out
