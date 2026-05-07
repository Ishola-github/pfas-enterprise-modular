"""Serum / plasma matrix ETL v1 → canonical ng/mL prior to encoder."""

from __future__ import annotations

import math

import numpy as np
import pandas as pd

from recipes.units import lod_pair_to_ng_per_ml


def preprocess_serum_v1(df: pd.DataFrame) -> pd.DataFrame:
    """Canonical **ng/mL** serum / plasma; ND uses encoder ``sqrt_half_lod``.

    Duplicate NHANES survey / demographics columns upstream via :mod:`preprocess_matrix` aliases
    (``WTSAF2YR``, ``RIDAGEYR``, …). **No** ambient-water MCL exceedance semantics here — downstream heads only.
    """

    out = df.copy()
    if "conc_unit" not in out.columns:
        raise ValueError("serum_v1 requires conc_unit on each row")

    conc_raw = pd.to_numeric(out["conc"], errors="coerce") if "conc" in out.columns else pd.Series(np.nan, index=out.index)
    units = out["conc_unit"]

    nd = pd.Series(False, index=out.index)
    if "is_non_detect" in out.columns:
        nd = out["is_non_detect"].fillna(False).astype(bool)
    nd = nd | conc_raw.isna()

    conc_can = []
    for v, u, flagged_nd in zip(conc_raw.tolist(), units.tolist(), nd.tolist()):
        if flagged_nd or v is None or (isinstance(v, float) and (math.isnan(v) or np.isnan(v))):
            conc_can.append(math.nan)
        else:
            conc_can.append(lod_pair_to_ng_per_ml(float(v), u))
    out["conc"] = conc_can

    if "lod" in out.columns:
        lods = []
        for v, u in zip(pd.to_numeric(out["lod"], errors="coerce").tolist(), units.tolist()):
            if v is None or (isinstance(v, float) and math.isnan(v)):
                lods.append(math.nan)
            else:
                lods.append(lod_pair_to_ng_per_ml(float(v), u))
        out["lod"] = lods
    if "reporting_limit" in out.columns:
        rls = []
        for v, u in zip(pd.to_numeric(out["reporting_limit"], errors="coerce").tolist(), units.tolist()):
            if v is None or (isinstance(v, float) and math.isnan(v)):
                rls.append(math.nan)
            else:
                rls.append(lod_pair_to_ng_per_ml(float(v), u))
        out["reporting_limit"] = rls

    out["canonical_conc_unit"] = "ng/mL"
    out["recipe_id"] = "serum_v1"
    out["imputation"] = "sqrt_half_lod"
    out["is_non_detect"] = nd.astype(bool)

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
        dummies = pd.get_dummies(md, prefix="etl_method", dummy_na=False)
        out = pd.concat([out.drop(columns=["method_id"]), dummies], axis=1)

    out["conc_unit"] = "ng/mL"
    return out
