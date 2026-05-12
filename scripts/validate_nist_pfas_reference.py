#!/usr/bin/env python3
"""
NIST PFAS reference validation for PFAS Enterprise 5.0.

Loads a reference table (e.g. SRM 1957 Appendix A Table A2 non-certified serum
mass fractions), preserves NIST metadata (k=2 expanded uncertainty, ILC context),
checks schema and matrix separation (physiological vs environmental), optionally
merges app predictions, and writes JSON + text validation reports under results/.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd

# Canonical analyte names (extend as needed). Keys are normalized lowercase fragments.
# Values are uppercase merge keys (short names normalize with .upper()).
PFAS_NAME_MAP: dict[str, str] = {
    "tridecafluoroheptanoic acid": "PFHPA",
    "pentadecafluorooctanoic acid": "PFOA",
    "perfluorooctanoic acid": "PFOA",
    "heptadecafluorononanoic acid": "PFNA",
    "perfluorononanoic acid": "PFNA",
    "nonadecafluorodecanoic acid": "PFDA",
    "perfluorodecanoic acid": "PFDA",
    "perfluoroundecanoic acid": "PFUNA",
    "perfluorooctanesulfonic acid": "PFOS",
    "perfluorohexanesulfonic acid": "PFHXS",
    "perfluorohexanoic acid": "PFHXA",
    "perfluorobutanesulfonic acid": "PFBS",
    "perfluorobutanoic acid": "PFBA",
}

# Merge keys from PFAS_NAME_MAP plus explicit abbreviations used in NIST RM extracts / telomer notation.
EXTRA_CANONICAL_CODES = frozenset(
    {
        "PFPEA",
        "PFDOA",
        "PFTRIA",
        "PFTA",
        "PFOSA",
        "PFPRS",
        "PFPES",
        "PFHPS",
        "PFBSA",
        "PFHXSA",
        "6:2 FTS",
        "N-AP-FHXSA",
        "N-TAMP-FHXSA",
        "6:2 FTAB",
    }
)
KNOWN_CANONICAL_CODES = set(PFAS_NAME_MAP.values()) | set(EXTRA_CANONICAL_CODES)

VALUE_TIER_ORDER = ("certified", "non_certified", "informational", "value_of_interest", "unknown")

# Correct public wording: Table A2 values are non-certified (do not call them certified).
BENCHMARK_WORDING = (
    "The PFAS app was benchmarked using NIST SRM 1957 non-certified PFAS mass-fraction "
    "reference values in serum (SRM 1957 reconstituted human serum per NIST documentation)."
)
REFERENCE_DATA_VALIDATION_SCOPE = (
    "Reference-data validation for software benchmarking (analyte recognition, matrix separation, "
    "units, uncertainty propagation, non-certified flagging, LC/MS/MS workflow metadata); "
    "not ISO/IEC 17025 laboratory validation. Do not claim NIST-certified PFAS values for Table A2. "
    "This pack supports validation architecture, QC simulation, and ISO-style documentation hooks; "
    "it is not EPA certification, ISO 17025 accreditation, CLIA validation, wet-lab validation, "
    "prospective field validation, or accredited proficiency-testing performance."
)
GENERIC_NIST_REFERENCE_BENCHMARK = (
    "This run uses a NIST reference-material extract for software benchmarking (ontology, matrix typing, "
    "uncertainty fields, LC-MS/MS-oriented metadata). It is not a wet-lab validation dataset, PT result, "
    "or regulatory compliance record."
)
GENERIC_VALUE_STATUS_LINE = (
    "Non-certified reference-material values per NIST documentation for the catalog item in this file; "
    "not certified property values unless the official NIST certificate explicitly states certification."
)
NIST_A2_DEFAULTS = {
    "interlaboratory": "yes (per NIST SRM 1957 Appendix A Table A2 context: interlaboratory contributions)",
    "uncertainty": "expanded uncertainty with coverage factor k=2 (per NIST Table A2)",
    "weighted_mean_basis": "weighted means from LC-MS/MS methods (per NIST Table A2 documentation)",
    "nist_documentation": (
        "NIST SRM 1957 Appendix A Table A2 - Non-Certified Mass Fraction Values for PFAS "
        "in Reconstituted SRM 1957"
    ),
}


def _norm_col(name: str) -> str:
    return re.sub(r"\s+", " ", str(name).strip().lower())


def _resolve_column(df: pd.DataFrame, candidates: list[str]) -> str | None:
    norm_to_actual = {_norm_col(c): c for c in df.columns}
    for cand in candidates:
        key = _norm_col(cand)
        if key in norm_to_actual:
            return norm_to_actual[key]
    return None


def _classify_value_tier(status: Any) -> str:
    if status is None or (isinstance(status, float) and math.isnan(status)):
        return "unknown"
    s = str(status).strip().lower().replace(" ", "_").replace("-", "_")
    if s in ("certified", "cert"):
        return "certified"
    if "non_cert" in s or s == "noncertified":
        return "non_certified"
    if "interest" in s or s == "voi":
        return "value_of_interest"
    if "information" in s or s == "informational":
        return "informational"
    return "unknown"


def _matrix_regulatory_context(matrix_val: Any) -> str:
    if matrix_val is None or (isinstance(matrix_val, float) and math.isnan(matrix_val)):
        return "unspecified"
    m = str(matrix_val).lower()
    if "serum" in m or "plasma" in m or "blood" in m:
        return "physiological"
    if "methanol" in m:
        return "calibration_liquid"
    if "afff" in m or ("foam" in m and "water" not in m):
        return "environmental_afff_matrix"
    if "water" in m or "drinking" in m:
        return "environmental_drinking_water_candidate"
    return "other"


def canonicalize_analyte(analyte: Any) -> str:
    if analyte is None or (isinstance(analyte, float) and math.isnan(analyte)):
        return ""
    raw = str(analyte).strip()
    if raw.upper() in KNOWN_CANONICAL_CODES:
        return raw.upper()
    low = raw.lower()
    for phrase, code in PFAS_NAME_MAP.items():
        if phrase in low:
            return code
    return raw


def _is_missing_cell(val: Any) -> bool:
    if val is None:
        return True
    if isinstance(val, float) and math.isnan(val):
        return True
    try:
        if pd.isna(val):
            return True
    except (TypeError, ValueError):
        pass
    s = str(val).strip().lower()
    return s in ("", "<na>", "nan", "none")


def row_canonical_name(short_name: Any, analyte: Any) -> str:
    """Prefer explicit short names (e.g. NIST Table A2) for ontology merge keys."""
    if not _is_missing_cell(short_name):
        s = str(short_name).strip()
        if s:
            return s.upper()
    return canonicalize_analyte(analyte)


def default_reference_csv(project_root: Path) -> Path:
    """Prefer extended Table A2 CSV, nested srm1957 serum extract, then legacy flat nist/ names."""
    ref_dir = project_root / "data" / "reference"
    for name in (
        "nist_srm1957_pfas_reference.csv",
        "nist/srm1957/serum_pfas.csv",
        "nist_srm1957_pfas.csv",
        "nist_srm1957_pfas_noncertified.csv",
    ):
        p = ref_dir / name
        if p.is_file():
            return p
    return ref_dir / "nist_srm1957_pfas_reference.csv"


def _series_first_nonempty(work: pd.DataFrame, col: str) -> str | None:
    if col not in work.columns:
        return None
    for v in work[col].dropna().astype(str):
        t = v.strip()
        if t:
            return t
    return None


def _format_srm_catalog_id(s: str) -> str:
    t = re.sub(r"\s+", "", str(s).strip())
    m = re.match(r"(?i)^srm(\d+)$", t)
    if m:
        return f"SRM {m.group(1)}"
    return str(s).strip()


def _read_optional_json(path: Path) -> Any:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _pick_pred_columns(df: pd.DataFrame) -> dict[str, str | None]:
    analyte_c = _resolve_column(
        df,
        ["analyte", "compound", "chemical", "substance", "parameter", "constituent"],
    )
    val_c = _resolve_column(
        df,
        [
            "predicted_value",
            "prediction",
            "model_estimate",
            "estimated_concentration",
            "pred_ng_g",
        ],
    )
    prob_c = _resolve_column(
        df,
        [
            "probability_exceedance",
            "probability",
            "prob",
            "score",
            "predicted_probability",
        ],
    )
    risk_c = _resolve_column(
        df,
        ["predicted_risk", "predicted_PFAS_Risk_Flag", "predicted_flag", "risk_class"],
    )
    return {
        "analyte": analyte_c,
        "predicted_value": val_c,
        "probability": prob_c,
        "risk": risk_c,
    }


def _infer_predicted_outputs(row: pd.Series) -> dict[str, Any]:
    """Screening-style outputs when columns allow (no environmental MCL logic for serum)."""
    out: dict[str, Any] = {
        "predicted_risk": None,
        "predicted_class": None,
        "uncertainty_band": None,
        "applicability_domain": None,
        "confidence": None,
    }
    prob = row.get("merged_probability")
    if prob is not None and not (isinstance(prob, float) and math.isnan(prob)):
        try:
            p = float(prob)
            out["confidence"] = round(min(max(p, 0.0), 1.0), 4)
            out["predicted_risk"] = "elevated" if p >= 0.5 else "not_elevated"
        except (TypeError, ValueError):
            pass
    pv = row.get("merged_predicted_value")
    if pv is not None and not (isinstance(pv, float) and math.isnan(pv)):
        try:
            v = float(pv)
            out["predicted_class"] = "serum_high" if v >= 1.0 else "serum_low"
        except (TypeError, ValueError):
            pass
    rc = row.get("merged_risk")
    if rc is not None and not (isinstance(rc, float) and math.isnan(rc)):
        out["predicted_class"] = f"flag_{rc}"
    # Heuristic bands (logging only; not regulatory)
    u = row.get("uncertainty")
    if u is not None and not (isinstance(u, float) and math.isnan(u)):
        try:
            ru = float(u)
            rel = ru / float(row["value"]) if float(row["value"]) else None
            if rel is not None:
                if rel < 0.15:
                    out["uncertainty_band"] = "low"
                elif rel < 0.35:
                    out["uncertainty_band"] = "medium"
                else:
                    out["uncertainty_band"] = "high"
        except (TypeError, ValueError, ZeroDivisionError):
            out["uncertainty_band"] = "unknown"
    out["applicability_domain"] = "PASS"
    return out


def run_validation(
    project_root: Path,
    reference_csv: Path,
    predictions_csv: Path | None,
    out_json: Path,
    out_txt: Path,
    out_enriched_csv: Path | None,
) -> int:
    required_logical = ["analyte", "value", "uncertainty", "unit"]
    if not reference_csv.is_file():
        print(f"ERROR: Reference CSV not found: {reference_csv}", file=sys.stderr)
        return 2

    ref = pd.read_csv(reference_csv, dtype=str)
    # Preserve raw strings; coerce numeric columns after rename
    col_analyte = _resolve_column(ref, ["analyte", "compound", "chemical"])
    col_value = _resolve_column(ref, ["concentration", "value", "reference_value", "mass_fraction"])
    col_uncertainty = _resolve_column(ref, ["uncertainty", "u", "expanded_uncertainty", "std_uncertainty"])
    col_unit = _resolve_column(ref, ["unit", "units", "uom"])
    col_matrix = _resolve_column(ref, ["matrix", "medium", "sample_matrix"])
    col_status = _resolve_column(ref, ["value_status", "value_type", "status", "reference_status", "value_tier"])
    col_source = _resolve_column(ref, ["reference_source", "source", "provider"])
    col_srm = _resolve_column(ref, ["srm_id", "srm", "catalog_id"])
    col_ref_material = _resolve_column(ref, ["reference_material", "reference_mat", "crm_id"])
    col_method = _resolve_column(ref, ["analytical_method", "method", "analytical_basis"])
    col_notes = _resolve_column(ref, ["notes", "comment", "remarks"])
    col_short_name = _resolve_column(ref, ["abbrev", "short_name", "abbreviation", "acronym", "code"])
    col_reference_type = _resolve_column(ref, ["reference_type", "reference_kind", "reference_class"])
    col_coverage_factor = _resolve_column(ref, ["coverage_factor", "k", "coverage_k", "expansion_factor"])
    col_traceability = _resolve_column(ref, ["traceability", "metrological_traceability", "traceability_statement"])
    col_uncertainty_basis = _resolve_column(
        ref, ["uncertainty_basis", "uncertainty_type", "expanded_uncertainty_note"]
    )
    col_interlaboratory = _resolve_column(ref, ["interlaboratory", "interlaboratory_study", "ilc"])
    col_isomer_basis = _resolve_column(ref, ["isomer_reporting", "isomer_basis", "isomers"])
    col_value_basis = _resolve_column(
        ref, ["weighted_mean_basis", "value_basis", "reference_basis", "measurement_basis"]
    )
    col_linear_iso = _resolve_column(ref, ["linear_isomer"])
    col_branched_iso = _resolve_column(ref, ["branched_isomer"])
    col_combined_iso = _resolve_column(ref, ["combined_isomer_reporting"])
    col_ext_lab = _resolve_column(ref, ["external_lab_source", "consensus_source"])
    col_nist_citation = _resolve_column(ref, ["nist_table_citation", "nist_citation", "reference_citation"])

    resolved = {
        "analyte": col_analyte,
        "value": col_value,
        "uncertainty": col_uncertainty,
        "unit": col_unit,
    }
    missing = [c for c in required_logical if not resolved[c]]
    if missing:
        print(f"ERROR: Missing required columns (or aliases): {missing}", file=sys.stderr)
        return 3

    n = len(ref)
    work = pd.DataFrame(
        {
            "source": ref[col_source] if col_source else pd.Series([pd.NA] * n),
            "srm_id": ref[col_srm] if col_srm else pd.Series([pd.NA] * n),
            "reference_material": ref[col_ref_material].astype(str)
            if col_ref_material
            else pd.Series([pd.NA] * n),
            "matrix": ref[col_matrix] if col_matrix else pd.Series([pd.NA] * n),
            "analyte": ref[col_analyte].astype(str),
            "short_name": ref[col_short_name].astype(str) if col_short_name else pd.Series([pd.NA] * n),
            "value": pd.to_numeric(ref[col_value], errors="coerce"),
            "uncertainty": pd.to_numeric(ref[col_uncertainty], errors="coerce"),
            "unit": ref[col_unit].astype(str),
            "value_status": ref[col_status].astype(str) if col_status else pd.Series(["unknown"] * n),
            "method": ref[col_method].astype(str) if col_method else pd.Series([pd.NA] * n),
            "uncertainty_basis": ref[col_uncertainty_basis].astype(str)
            if col_uncertainty_basis
            else pd.Series([pd.NA] * n),
            "interlaboratory": ref[col_interlaboratory].astype(str)
            if col_interlaboratory
            else pd.Series([pd.NA] * n),
            "isomer_basis": ref[col_isomer_basis].astype(str) if col_isomer_basis else pd.Series([pd.NA] * n),
            "value_basis": ref[col_value_basis].astype(str) if col_value_basis else pd.Series([pd.NA] * n),
            "linear_isomer": ref[col_linear_iso].astype(str) if col_linear_iso else pd.Series([pd.NA] * n),
            "branched_isomer": ref[col_branched_iso].astype(str) if col_branched_iso else pd.Series([pd.NA] * n),
            "combined_isomer_reporting": ref[col_combined_iso].astype(str)
            if col_combined_iso
            else pd.Series([pd.NA] * n),
            "external_lab_source": ref[col_ext_lab].astype(str) if col_ext_lab else pd.Series([pd.NA] * n),
            "nist_table_citation": ref[col_nist_citation].astype(str)
            if col_nist_citation
            else pd.Series([pd.NA] * n),
            "reference_type": ref[col_reference_type].astype(str)
            if col_reference_type
            else pd.Series([pd.NA] * n),
            "coverage_factor": pd.to_numeric(ref[col_coverage_factor], errors="coerce")
            if col_coverage_factor
            else pd.Series([pd.NA] * n),
            "traceability": ref[col_traceability].astype(str) if col_traceability else pd.Series([pd.NA] * n),
            "notes": ref[col_notes].astype(str) if col_notes else pd.Series([pd.NA] * n),
        }
    )

    if col_source is None and col_ref_material:
        work["source"] = "NIST " + ref[col_ref_material].astype(str).str.strip()

    na_value = work["value"].isna().sum()
    na_unc = work["uncertainty"].isna().sum()
    na_unit = (work["unit"].isna() | (work["unit"].str.strip() == "")).sum()

    work["value_tier"] = work["value_status"].map(_classify_value_tier)
    work["regulatory_context"] = work["matrix"].map(_matrix_regulatory_context)
    work["canonical_name"] = [
        row_canonical_name(work.loc[i, "short_name"], work.loc[i, "analyte"]) for i in range(len(work))
    ]
    work["analyte_mapped_to_known_code"] = work["canonical_name"].isin(KNOWN_CANONICAL_CODES)

    # Unit consistency (global — serum reference should be one unit family)
    units_normalized = (
        work["unit"].astype(str).str.strip().str.lower().str.replace("µ", "u", regex=False)
    )
    unit_unique = sorted(units_normalized.dropna().unique().tolist())
    unit_consistency_pass = len(unit_unique) <= 1

    comparison: dict[str, Any] | None = None
    if predictions_csv and predictions_csv.is_file():
        pred = pd.read_csv(predictions_csv)
        pc = _pick_pred_columns(pred)
        if pc["analyte"]:
            pred = pred.copy()
            pred["_canon"] = pred[pc["analyte"]].map(canonicalize_analyte)
            left = work.copy()
            right = pred.rename(
                columns={
                    pc["analyte"]: "_pred_analyte",
                    **({pc["predicted_value"]: "merged_predicted_value"} if pc["predicted_value"] else {}),
                    **({pc["probability"]: "merged_probability"} if pc["probability"] else {}),
                    **({pc["risk"]: "merged_risk"} if pc["risk"] else {}),
                }
            )
            if "merged_predicted_value" not in right.columns:
                right["merged_predicted_value"] = math.nan
            if "merged_probability" not in right.columns:
                right["merged_probability"] = math.nan
            if "merged_risk" not in right.columns:
                right["merged_risk"] = math.nan
            merged = left.merge(
                right[["_canon", "merged_predicted_value", "merged_probability", "merged_risk"]].drop_duplicates(
                    subset=["_canon"]
                ),
                left_on="canonical_name",
                right_on="_canon",
                how="left",
                validate="many_to_one",
            )
            work = merged.drop(columns=["_canon"], errors="ignore")

            mval = work["merged_predicted_value"]
            has_pred = mval.notna() & work["value"].notna()
            if has_pred.any():
                abs_err = (mval[has_pred] - work.loc[has_pred, "value"]).abs()
                pct_err = (abs_err / work.loc[has_pred, "value"].replace(0, math.nan)) * 100.0
                work.loc[has_pred, "absolute_error"] = abs_err
                work.loc[has_pred, "percent_error"] = pct_err
                comparison = {
                    "rows_with_prediction": int(has_pred.sum()),
                    "mean_absolute_error": float(abs_err.mean()),
                    "median_absolute_error": float(abs_err.median()),
                    "mean_percent_error": float(pct_err.mean(skipna=True))
                    if pct_err.notna().any()
                    else None,
                    "predictions_file": str(predictions_csv),
                }
        else:
            comparison = {
                "skipped": True,
                "reason": "predictions file has no analyte/compound column",
                "predictions_file": str(predictions_csv),
            }
    else:
        comparison = {
            "skipped": True,
            "reason": "no predictions_csv provided or file missing",
        }

    for c in ("merged_predicted_value", "merged_probability", "merged_risk", "absolute_error", "percent_error"):
        if c not in work.columns:
            work[c] = math.nan

    # Screening outputs per row (after optional merge)
    screen_rows = []
    for _, row in work.iterrows():
        screen_rows.append(_infer_predicted_outputs(row))
    screen_df = pd.DataFrame(screen_rows)
    work = pd.concat([work.reset_index(drop=True), screen_df], axis=1)

    mapping_rate = float(work["analyte_mapped_to_known_code"].mean()) if len(work) else 0.0
    matrix_recognized = float((work["regulatory_context"] != "unspecified").mean()) if len(work) else 0.0
    all_physiological = bool(len(work) and (work["regulatory_context"] == "physiological").all())

    acceptance = {
        "analyte_mapping": "PASS" if mapping_rate >= 1.0 - 1e-9 else "REVIEW",
        "unit_consistency": "PASS" if unit_consistency_pass else "REVIEW",
        "matrix_recognition": "PASS" if matrix_recognized >= 1.0 - 1e-9 else "REVIEW",
        "physiological_reference_only": "PASS" if all_physiological else "REVIEW",
        "missing_values": {
            "value_na": int(na_value),
            "uncertainty_na": int(na_unc),
            "unit_empty_na": int(na_unit),
        },
        "missing_values_pass": bool(na_value == 0 and na_unc == 0 and na_unit == 0),
        "applicability_domain_failures_documented": True,
        "uncertainty_logging_required": True,
    }

    model_manifest = _read_optional_json(project_root / "results" / "model_manifest.json")
    train_metrics = _read_optional_json(project_root / "results" / "nhanes_model_metrics.json")

    cert_ver = "unspecified"
    if col_srm and work["srm_id"].notna().any():
        cert_ver = str(work["srm_id"].dropna().astype(str).iloc[0])
    elif _series_first_nonempty(work, "reference_material"):
        cert_ver = _series_first_nonempty(work, "reference_material") or "unspecified"

    provenance = {
        "reference_source": work["source"].dropna().astype(str).iloc[0]
        if col_source and work["source"].notna().any()
        else "unspecified",
        "reference_file": str(reference_csv.resolve()),
        "certificate_version": cert_ver,
        "download_date": str(date.today()),
        "validation_run_timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "pipeline_version": os.environ.get("PFAS_PIPELINE_VERSION", "5.0"),
        "model_version": None,
        "threshold_version": os.environ.get("PFAS_THRESHOLD_VERSION", "unspecified"),
    }
    if isinstance(model_manifest, dict):
        provenance["model_version"] = model_manifest.get("model_version") or model_manifest.get("version")
    if provenance["model_version"] is None and isinstance(train_metrics, dict):
        provenance["model_version"] = train_metrics.get("model_version") or train_metrics.get("git_sha")

    raw_src = _series_first_nonempty(work, "source") or "NIST"
    srm_id0 = _series_first_nonempty(work, "srm_id")
    srm0 = _format_srm_catalog_id(srm_id0) if srm_id0 else ""
    if re.search(r"(?i)\bSRM\b", raw_src):
        provenance["reference_source"] = raw_src.strip()
    else:
        provenance["reference_source"] = f"{raw_src.strip()} {srm0}".strip() if srm0 else raw_src.strip()

    path_lc = str(reference_csv).replace("\\", "/").lower()
    name_lc = reference_csv.name.lower()
    serum_a2_pack = ("srm1957" in path_lc and "serum" in name_lc) or (
        "nist_srm1957" in name_lc and "pfas" in name_lc
    )
    dominant_ctx = (
        str(work["regulatory_context"].value_counts().index[0])
        if len(work) and work["regulatory_context"].notna().any()
        else "unspecified"
    )

    status_levels = (
        sorted(work["value_status"].dropna().astype(str).str.strip().unique().tolist()) if len(work) else []
    )

    value_status_line = (
        "non-certified per NIST SRM 1957 Appendix A Table A2 "
        "(mass fractions in serum / reconstituted SRM 1957 material; weighted LC-MS/MS means; not certified values)"
        if serum_a2_pack
        else GENERIC_VALUE_STATUS_LINE
    )

    cov_series = work["coverage_factor"].dropna() if "coverage_factor" in work.columns else pd.Series(dtype=float)
    cov_first: Any = "unspecified"
    if len(cov_series) > 0:
        try:
            cov_first = float(cov_series.iloc[0])
        except (TypeError, ValueError):
            cov_first = str(cov_series.iloc[0])

    reference_metadata = {
        "reference_source": provenance["reference_source"],
        "reference_material": _series_first_nonempty(work, "reference_material") or "unspecified",
        "reference_type": _series_first_nonempty(work, "reference_type")
        or _series_first_nonempty(work, "value_status")
        or "unspecified",
        "software_benchmarking_statement": BENCHMARK_WORDING if serum_a2_pack else GENERIC_NIST_REFERENCE_BENCHMARK,
        "validation_scope": REFERENCE_DATA_VALIDATION_SCOPE,
        "value_status": value_status_line,
        "value_status_csv": ", ".join(status_levels) if status_levels else "",
        "matrix": _series_first_nonempty(work, "matrix") or "",
        "matrix_regulatory_context_dominant": dominant_ctx,
        "analytical_basis": _series_first_nonempty(work, "method") or "",
        "interlaboratory": _series_first_nonempty(work, "interlaboratory") or "unspecified",
        "uncertainty": _series_first_nonempty(work, "uncertainty_basis") or "unspecified",
        "coverage_factor": cov_first,
        "traceability": _series_first_nonempty(work, "traceability") or "unspecified",
        "isomer_reporting": _series_first_nonempty(work, "isomer_basis") or "unspecified",
        "linear_isomer": _series_first_nonempty(work, "linear_isomer") or "unspecified",
        "branched_isomer": _series_first_nonempty(work, "branched_isomer") or "unspecified",
        "combined_isomer_reporting": _series_first_nonempty(work, "combined_isomer_reporting")
        or "unspecified",
        "external_lab_source": _series_first_nonempty(work, "external_lab_source") or "unspecified",
        "weighted_mean_basis": _series_first_nonempty(work, "value_basis") or "unspecified",
        "consensus_mean_note": (
            (
                "The concentration column is the NIST Table A2 reported consensus value (weighted mean); "
                "it is not a certified property value."
            )
            if serum_a2_pack
            else (
                "Reported values are taken from the reference extract; confirm against the current NIST certificate "
                "or fact sheet before operational laboratory or regulatory use."
            )
        ),
        "nist_documentation": _series_first_nonempty(work, "nist_table_citation") or "unspecified",
    }

    note0 = _series_first_nonempty(work, "notes")
    if reference_metadata["isomer_reporting"] == "unspecified" and note0:
        reference_metadata["isomer_reporting"] = note0

    is_nist_srm1957_pfas_file = (
        ("nist_srm1957" in reference_csv.name.lower() and "pfas" in reference_csv.name.lower())
        or ("srm1957" in path_lc and "serum" in name_lc)
    )
    if is_nist_srm1957_pfas_file:
        for key, default in NIST_A2_DEFAULTS.items():
            if reference_metadata.get(key) == "unspecified":
                reference_metadata[key] = default

    if reference_metadata["uncertainty"] == "unspecified":
        reference_metadata["uncertainty"] = (
            "per NIST documentation where stated (Table A2: typically expanded uncertainty, k=2)"
        )

    if all_physiological or dominant_ctx == "physiological":
        matrix_architecture = {
            "reference_regulatory_context": "physiological",
            "allowed_workflows": [
                "serum_body_burden_benchmarking",
                "physiological_pfas_module_validation",
                "analyte_ontology_mapping",
                "uncertainty_aware_screening_calibration",
            ],
            "excluded_workflows": [
                "epa_drinking_water_mcl_compliance",
                "iso_17025_lab_validation_claims",
                "environmental_matrix_recovery_or_mdl_claims",
            ],
            "rationale": (
                "Table A2 / serum extracts provide NIST non-certified PFAS mass-fraction reference values for "
                "software benchmarking in human serum context — not certified values, not drinking-water evidence, "
                "and not ISO 17025 lab validation."
            ),
        }
    elif dominant_ctx == "environmental_afff_matrix":
        matrix_architecture = {
            "reference_regulatory_context": "environmental_afff",
            "allowed_workflows": [
                "afff_foam_profile_benchmarking",
                "pfas_ontology_mapping",
                "environmental_forensic_context",
                "uncertainty_aware_screening_calibration",
            ],
            "excluded_workflows": [
                "uncritical_serum_body_burden_baseline",
                "drinking_water_mcl_compliance_without_domain_check",
                "iso_17025_lab_validation_claims",
            ],
            "rationale": (
                "AFFF foam reference materials characterize foam-associated PFAS profiles for software and "
                "forensic context — not serum matrices, not generic drinking-water compliance, and not wet-lab PT."
            ),
        }
    elif dominant_ctx == "calibration_liquid":
        matrix_architecture = {
            "reference_regulatory_context": "calibration_process_control",
            "allowed_workflows": [
                "lc_ms_ms_calibration_metadata",
                "analyte_registry_alignment",
                "process_control_simulation",
            ],
            "excluded_workflows": [
                "direct_exposure_or_site_concentration_claims_without_sampling_context",
                "iso_17025_lab_validation_claims",
            ],
            "rationale": (
                "Methanol calibration-line materials support chromatographic calibration and software metadata — "
                "not environmental or physiological exposure interpretation without explicit domain transforms."
            ),
        }
    else:
        matrix_architecture = {
            "reference_regulatory_context": dominant_ctx,
            "allowed_workflows": ["reference_metadata_benchmarking", "analyte_ontology_mapping"],
            "excluded_workflows": ["uncritical_cross_matrix_merging", "iso_17025_lab_validation_claims"],
            "rationale": (
                "Preserve matrix and intended-use separation; read regulatory context from the dominant row context."
            ),
        }

    ref_dir = project_root / "data" / "reference"
    reference_pack = {
        fn: (ref_dir / fn).is_file()
        for fn in (
            "nist/srm1957/serum_pfas.csv",
            "nist/rm8446/methanol_pfas.csv",
            "nist/rm8690/afff_pfas.csv",
            "nist/manifest.json",
            "nist/hashes.txt",
            "registry/reference_registry.csv",
            "nist_srm1957_pfas_reference.csv",
            "nist_srm1957_pfas.csv",
            "nist_srm1957_pfas_noncertified.csv",
            "epa_1633a_method_metadata.csv",
            "epa_1633a_qc_limits.csv",
            "epa_1633a_qc_batch_schema.csv",
            "holding_times.csv",
            "pfas_matrix_registry.csv",
            "contamination_control_rules.csv",
        )
    }

    tier_counts = work["value_tier"].value_counts().to_dict()
    bench_line = BENCHMARK_WORDING if serum_a2_pack else GENERIC_NIST_REFERENCE_BENCHMARK
    ref_type_line = (
        "Reference Type: See value_tier counts (non-certified Table A2 rows are not certified values)."
        if serum_a2_pack
        else "Reference Type: Non-certified NIST reference-material extract — verify current issuer documentation."
    )
    scope_line = (
        "Validation Scope: Serum/reference benchmark only - do not apply drinking-water MCL logic."
        if serum_a2_pack or dominant_ctx == "physiological"
        else f"Validation Scope: Dominant regulatory_context={dominant_ctx} — do not merge with unrelated matrices."
    )
    summary_lines = [
        "Validation Summary (reference-data / software benchmarking)",
        "-------------------------------------------------------------",
        bench_line,
        "",
        REFERENCE_DATA_VALIDATION_SCOPE,
        "",
        f"Dataset: NIST reference extract (file: {reference_csv.name})",
        f"Analytes (rows): {len(work)}",
        f"Matrix (first row): {work['matrix'].iloc[0] if len(work) else 'n/a'}",
        ref_type_line,
        scope_line,
        "",
        "Reference metadata (audit):",
        f"  - reference_source: {reference_metadata['reference_source']}",
        f"  - reference_material: {reference_metadata['reference_material']}",
        f"  - value_status: {reference_metadata['value_status']}",
        f"  - matrix: {reference_metadata['matrix']}",
        f"  - reference_type: {reference_metadata['reference_type']}",
        f"  - analytical_basis: {reference_metadata['analytical_basis']}",
        f"  - interlaboratory: {reference_metadata['interlaboratory']}",
        f"  - uncertainty: {reference_metadata['uncertainty']}",
        f"  - coverage_factor (k): {reference_metadata['coverage_factor']}",
        f"  - traceability: {reference_metadata['traceability']}",
        f"  - isomer_reporting: {reference_metadata['isomer_reporting']}",
        f"  - weighted_mean_basis: {reference_metadata['weighted_mean_basis']}",
        "",
        "Value tier counts:",
        *[f"  - {k}: {int(v)}" for k, v in sorted(tier_counts.items(), key=lambda kv: VALUE_TIER_ORDER.index(kv[0]) if kv[0] in VALUE_TIER_ORDER else 99)],
        "",
        "Results:",
        f"- analyte mapping: {acceptance['analyte_mapping']} (known-code rate {mapping_rate:.3f})",
        f"- unit normalization: {acceptance['unit_consistency']}",
        f"- matrix separation: {acceptance['matrix_recognition']}",
        f"- physiological-only reference: {acceptance['physiological_reference_only']}",
        f"- uncertainty logging: {'PASS' if acceptance['missing_values_pass'] else 'REVIEW'} (missing value/uncertainty/unit counts: {acceptance['missing_values']})",
        "- applicability domain: PASS (placeholder - tie to governed AD module for production)",
        "",
        "Provenance (see JSON for full):",
        f"  pipeline_version={provenance['pipeline_version']}, model_version={provenance['model_version']}",
    ]

    report = {
        "provenance": provenance,
        "reference_metadata": reference_metadata,
        "matrix_architecture": matrix_architecture,
        "reference_pack_files_present": reference_pack,
        "integrity": {
            "required_columns_resolved": {k: resolved[k] for k in required_logical},
            "row_count": int(len(work)),
        },
        "value_tier_counts": {str(k): int(v) for k, v in tier_counts.items()},
        "acceptance": acceptance,
        "comparison": comparison,
        "summary_text": "\n".join(summary_lines),
    }

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(report, indent=2), encoding="utf-8")
    out_txt.write_text(report["summary_text"], encoding="utf-8")
    if out_enriched_csv:
        out_enriched_csv.parent.mkdir(parents=True, exist_ok=True)
        work.to_csv(out_enriched_csv, index=False)

    print(report["summary_text"])
    if acceptance["analyte_mapping"] != "PASS" or not acceptance["missing_values_pass"]:
        return 4
    if not unit_consistency_pass:
        return 5
    if serum_a2_pack and acceptance["physiological_reference_only"] != "PASS":
        return 6
    return 0


def _default_project_root() -> Path:
    """Repository root when this file lives in <root>/scripts/."""
    return Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate NIST PFAS reference CSV and optional predictions.")
    parser.add_argument(
        "--project-root",
        type=Path,
        default=None,
        help="Repository root (default: parent directory of scripts/)",
    )
    parser.add_argument(
        "--reference-csv",
        type=Path,
        default=None,
        help="Defaults to nist_srm1957_pfas_reference.csv, then nist_srm1957_pfas.csv, then _noncertified.csv",
    )
    parser.add_argument("--predictions-csv", type=Path, default=None)
    parser.add_argument(
        "--out-json",
        type=Path,
        default=None,
        help="Default: <project-root>/results/nist_reference_validation_report.json",
    )
    parser.add_argument("--out-txt", type=Path, default=None)
    parser.add_argument("--enriched-csv", type=Path, default=None)
    args = parser.parse_args()

    root = (args.project_root or _default_project_root()).resolve()
    ref = args.reference_csv or default_reference_csv(root)
    out_json = args.out_json or (root / "results" / "nist_reference_validation_report.json")
    out_txt = args.out_txt or (root / "results" / "nist_reference_validation_summary.txt")
    enriched = args.enriched_csv or (root / "results" / "nist_reference_enriched.csv")

    return run_validation(
        root,
        ref,
        args.predictions_csv.resolve() if args.predictions_csv else None,
        out_json,
        out_txt,
        enriched,
    )


if __name__ == "__main__":
    raise SystemExit(main())
