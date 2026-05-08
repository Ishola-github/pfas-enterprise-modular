"""UCMR5 occurrence file -> deterministic run folder (clean CSV, QC JSON, priority CSV, provenance, summary)."""

from __future__ import annotations

from pathlib import Path
import hashlib
import json
from datetime import datetime, timezone
import pandas as pd


REQUIRED_OUTPUTS = [
    "clean_dataset.csv",
    "qc_report.json",
    "priority_report.csv",
    "provenance.json",
    "summary_report.pdf",
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_ucmr5(input_file: Path) -> tuple[pd.DataFrame, dict]:
    warnings: list[str] = []

    try:
        df = pd.read_csv(input_file, sep="\t", dtype=str, encoding="latin1", low_memory=False)
        warnings.append("Read as tab-delimited latin1")
    except Exception:
        df = pd.read_csv(input_file, dtype=str, encoding="latin1", low_memory=False)
        warnings.append("Fallback read as comma-delimited latin1")

    return df, {"warnings": warnings}


def pick_col(df: pd.DataFrame, candidates: list[str]) -> str | None:
    lower = {c.lower(): c for c in df.columns}
    for c in candidates:
        if c.lower() in lower:
            return lower[c.lower()]
    return None


def _col(df: pd.DataFrame, col: str | None, default: str = "") -> pd.Series:
    if col and col in df.columns:
        return df[col].astype(str)
    return pd.Series([default] * len(df), index=df.index, dtype=str)


def normalize_ucmr5(df: pd.DataFrame, run_id: str, source_file: str) -> pd.DataFrame:
    contaminant_col = pick_col(df, ["Contaminant", "Analyte", "Parameter"])
    result_col = pick_col(df, ["AnalyticalResultValue", "Result", "ResultValue"])
    sign_col = pick_col(df, ["AnalyticalResultsSign", "ResultSign"])
    unit_col = pick_col(df, ["UnitOfMeasure", "Unit", "ResultUnit"])
    sample_col = pick_col(df, ["SampleID", "SampleIdentifier", "SamplePointID"])
    pwsid_col = pick_col(df, ["PWSID"])
    pws_name_col = pick_col(df, ["PWSName"])
    state_col = pick_col(df, ["State"])
    date_col = pick_col(df, ["CollectionDate", "SampleDate"])
    method_col = pick_col(df, ["MethodID", "Method"])
    mrl_col = pick_col(df, ["MRL", "MinimumReportingLevel"])

    n = len(df)
    out = pd.DataFrame(index=df.index if n else range(0))
    out["run_id"] = run_id
    out["source_file"] = source_file
    out["sample_id"] = _col(df, sample_col)
    out["pwsid"] = _col(df, pwsid_col)
    out["pws_name"] = _col(df, pws_name_col)
    out["state"] = _col(df, state_col)
    out["sample_date"] = _col(df, date_col)
    out["method_id"] = _col(df, method_col, "EPA_533")
    out["matrix"] = "water"

    out["raw_analyte"] = _col(df, contaminant_col)
    out["canonical_analyte"] = out["raw_analyte"].astype(str).str.strip().str.upper()

    out["casrn"] = ""
    out["dtxsid"] = ""

    raw_result_s = _col(df, result_col)
    out["raw_result"] = raw_result_s
    out["result_numeric"] = pd.to_numeric(
        raw_result_s.str.replace("<", "", regex=False).str.strip(),
        errors="coerce",
    )

    raw_unit_s = _col(df, unit_col, "ng/L")
    out["raw_unit"] = raw_unit_s
    out["canonical_unit"] = "ng/L"

    # UCMR5 PFAS values are usually already ng/L in many exports.
    # Keep conversion conservative for v1.
    out["result_ng_l"] = out["result_numeric"]

    sign_s = _col(df, sign_col)
    out["non_detect_flag"] = sign_s.str.strip().eq("<") | raw_result_s.str.strip().str.startswith("<")
    out["detect_flag"] = ~out["non_detect_flag"]

    if mrl_col:
        mrl_num = pd.to_numeric(
            _col(df, mrl_col).str.replace("<", "", regex=False).str.strip(),
            errors="coerce",
        )
        out["reporting_limit_ng_l"] = mrl_num
    else:
        out["reporting_limit_ng_l"] = ""

    out["normalization_notes"] = ""

    return out


def build_qc_report(
    raw_df: pd.DataFrame,
    clean_df: pd.DataFrame,
    run_id: str,
    source_file: str,
    read_warnings: list[str],
) -> dict:
    missing_required = []
    for col in ["raw_analyte", "result_numeric", "raw_unit"]:
        if col not in clean_df.columns:
            missing_required.append(col)

    rows_read = int(len(raw_df))
    rows_written = int(len(clean_df))
    unknown_analytes = int((clean_df["canonical_analyte"].astype(str).str.strip() == "").sum())
    missing_units = int((clean_df["raw_unit"].astype(str).str.strip() == "").sum())
    missing_dates = int((clean_df["sample_date"].astype(str).str.strip() == "").sum())
    duplicate_rows = int(clean_df.duplicated().sum())

    qc_score = 100
    qc_score -= min(30, unknown_analytes)
    qc_score -= min(20, missing_units)
    qc_score -= min(20, missing_dates)
    qc_score -= min(20, duplicate_rows)
    qc_score = max(0, qc_score)

    return {
        "run_id": run_id,
        "source_file": source_file,
        "rows_read": rows_read,
        "rows_written": rows_written,
        "rows_failed": max(0, rows_read - rows_written),
        "structural_qc": {
            "missing_required_output_columns": missing_required,
            "duplicate_rows": duplicate_rows,
        },
        "analytical_qc": {
            "unknown_analytes": unknown_analytes,
            "missing_units": missing_units,
            "non_detect_rows": int(clean_df["non_detect_flag"].sum()),
        },
        "metadata_qc": {
            "missing_dates": missing_dates,
            "missing_pwsid": int((clean_df["pwsid"].astype(str).str.strip() == "").sum()),
            "missing_state": int((clean_df["state"].astype(str).str.strip() == "").sum()),
        },
        "pipeline_qc": {
            "parser_warnings": read_warnings,
            "canonical_unit": "ng/L",
        },
        "warnings": read_warnings,
        "qc_score": qc_score,
    }


def build_priority_report(clean_df: pd.DataFrame) -> pd.DataFrame:
    df = clean_df.copy()
    df["priority_level"] = "low"
    df.loc[(df["detect_flag"]) & (df["result_ng_l"].fillna(0) > 0), "priority_level"] = "medium"
    df.loc[(df["detect_flag"]) & (df["result_ng_l"].fillna(0) >= 10), "priority_level"] = "high"

    df["reason"] = df["priority_level"].map({
        "high": "Detected PFAS result at or above simple v1 screening threshold",
        "medium": "Detected PFAS result below simple v1 screening threshold",
        "low": "Non-detect or missing numeric result",
    })

    df["confidence"] = "medium"
    df.loc[df["canonical_analyte"].astype(str).str.strip() == "", "confidence"] = "low"

    df["recommended_action"] = df["priority_level"].map({
        "high": "Review first; confirm against applicable regulatory/lab context",
        "medium": "Review after high-priority records",
        "low": "Archive or review if site context requires",
    })

    cols = [
        "state", "pwsid", "pws_name", "sample_id", "canonical_analyte",
        "result_ng_l", "reporting_limit_ng_l", "detect_flag",
        "priority_level", "reason", "confidence", "recommended_action",
    ]

    out = df[cols].copy()
    rank_order = {"high": 0, "medium": 1, "low": 2}
    out["_rank"] = out["priority_level"].map(rank_order)
    out = out.sort_values(["_rank", "result_ng_l"], ascending=[True, False])
    out.insert(0, "priority_rank", range(1, len(out) + 1))
    return out.drop(columns=["_rank"])


def write_summary_pdf(path: Path, qc: dict, provenance: dict) -> None:
    try:
        from reportlab.lib.pagesizes import letter
        from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
        from reportlab.lib.styles import getSampleStyleSheet

        doc = SimpleDocTemplate(str(path), pagesize=letter)
        styles = getSampleStyleSheet()
        story = [
            Paragraph("UCMR5 PFAS Triage Summary Report", styles["Title"]),
            Spacer(1, 12),
            Paragraph(f"Run ID: {qc['run_id']}", styles["BodyText"]),
            Paragraph(f"Rows read: {qc['rows_read']}", styles["BodyText"]),
            Paragraph(f"Rows written: {qc['rows_written']}", styles["BodyText"]),
            Paragraph(f"QC score: {qc['qc_score']}", styles["BodyText"]),
            Spacer(1, 12),
            Paragraph(
                "Scope: Screening and workflow support only. Not a regulatory determination.",
                styles["BodyText"],
            ),
            Paragraph(f"Input SHA256: {provenance['input_sha256']}", styles["BodyText"]),
        ]
        doc.build(story)
    except Exception:
        path.write_text(
            "UCMR5 PFAS Triage Summary Report\n"
            f"Run ID: {qc['run_id']}\n"
            f"Rows read: {qc['rows_read']}\n"
            f"Rows written: {qc['rows_written']}\n"
            f"QC score: {qc['qc_score']}\n"
            "Screening and workflow support only. Not a regulatory determination.\n",
            encoding="utf-8",
        )


def process_ucmr5(input_file: str, output_root: str = "runs", run_id: str | None = None) -> dict:
    input_path = Path(input_file).resolve()
    if not input_path.exists():
        raise FileNotFoundError(input_path)

    run_id = run_id or f"ucmr5_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    run_dir = Path(output_root) / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    provenance = {
        "run_id": run_id,
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "input_file": str(input_path),
        "input_sha256": sha256_file(input_path),
        "pipeline_version": "ucmr5_pipeline_v1",
        "software_version": "0.1.0",
        "analyte_dictionary_version": "none_v1",
        "limits_table_version": "none_v1",
        "operator": "",
        "warnings": [],
    }

    try:
        raw_df, read_meta = read_ucmr5(input_path)
        clean_df = normalize_ucmr5(raw_df, run_id, input_path.name)
        qc = build_qc_report(raw_df, clean_df, run_id, input_path.name, read_meta["warnings"])
        priority_df = build_priority_report(clean_df)

        clean_df.to_csv(run_dir / "clean_dataset.csv", index=False)
        priority_df.to_csv(run_dir / "priority_report.csv", index=False)

        with (run_dir / "qc_report.json").open("w", encoding="utf-8") as f:
            json.dump(qc, f, indent=2)

        provenance["warnings"] = qc["warnings"]
        with (run_dir / "provenance.json").open("w", encoding="utf-8") as f:
            json.dump(provenance, f, indent=2)

        write_summary_pdf(run_dir / "summary_report.pdf", qc, provenance)

        missing = [name for name in REQUIRED_OUTPUTS if not (run_dir / name).exists()]
        if missing:
            raise RuntimeError(f"Missing required outputs: {missing}")

        return {
            "status": "success",
            "run_id": run_id,
            "run_dir": str(run_dir),
            "outputs": {name: str(run_dir / name) for name in REQUIRED_OUTPUTS},
        }

    except Exception as e:
        failure_qc = {
            "run_id": run_id,
            "source_file": input_path.name,
            "rows_read": 0,
            "rows_written": 0,
            "rows_failed": 0,
            "structural_qc": {},
            "analytical_qc": {},
            "metadata_qc": {},
            "pipeline_qc": {"failure": str(e)},
            "warnings": [str(e)],
            "qc_score": 0,
        }
        with (run_dir / "qc_report.json").open("w", encoding="utf-8") as f:
            json.dump(failure_qc, f, indent=2)
        provenance["warnings"] = [str(e)]
        with (run_dir / "provenance.json").open("w", encoding="utf-8") as f:
            json.dump(provenance, f, indent=2)
        raise


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Process UCMR5 PFAS file into deterministic workflow outputs.")
    parser.add_argument("input_file")
    parser.add_argument("--output-root", default="runs")
    parser.add_argument("--run-id", default=None)
    args = parser.parse_args()

    result = process_ucmr5(args.input_file, args.output_root, args.run_id)
    print(json.dumps(result, indent=2))
