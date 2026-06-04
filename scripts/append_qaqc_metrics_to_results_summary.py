"""
Append/update computed reviewer metrics into results_summary.csv.

This helper reads reviewer comparison rows, computes metrics using
compute_qaqc_reviewer_metrics.py logic, then upserts a study/protocol row
into validation/studies/epa1633_qaqc_v1/results_summary.csv.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
from pathlib import Path
from typing import Any

from compute_qaqc_reviewer_metrics import _load_rows, compute_metrics


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _fmt(value: Any, digits: int = 6) -> str:
    if value is None:
        return ""
    if isinstance(value, float):
        return f"{value:.{digits}f}".rstrip("0").rstrip(".")
    return str(value)


def _read_csv_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        fieldnames = list(reader.fieldnames or [])
        rows = [{str(k): (v or "") for k, v in row.items()} for row in reader]
    return fieldnames, rows


def _write_csv_rows(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _upsert_summary_row(
    rows: list[dict[str, str]],
    fieldnames: list[str],
    row_payload: dict[str, str],
    study_id: str,
    protocol_version: str,
    run_label: str,
) -> list[dict[str, str]]:
    if "study_id" not in fieldnames or "protocol_version" not in fieldnames:
        raise SystemExit("ERROR: results_summary.csv must contain study_id and protocol_version columns.")

    match_on_run_label = bool(run_label) and "run_label" in fieldnames
    target_index = None
    for i, row in enumerate(rows):
        base_match = (
            str(row.get("study_id", "")).strip() == study_id
            and str(row.get("protocol_version", "")).strip() == protocol_version
        )
        if not base_match:
            continue
        if match_on_run_label:
            if str(row.get("run_label", "")).strip() != run_label:
                continue
        if base_match:
            target_index = i
            break

    if target_index is None:
        rows.append({k: row_payload.get(k, "") for k in fieldnames})
    else:
        merged = dict(rows[target_index])
        merged.update(row_payload)
        rows[target_index] = {k: merged.get(k, "") for k in fieldnames}
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description="Upsert reviewer metrics into results_summary.csv")
    ap.add_argument(
        "--comparison-csv",
        default="validation/studies/epa1633_qaqc_v1/reviewer_comparison_template.csv",
        help="Path to reviewer comparison CSV input.",
    )
    ap.add_argument(
        "--results-summary-csv",
        default="validation/studies/epa1633_qaqc_v1/results_summary.csv",
        help="Path to results summary CSV to update.",
    )
    ap.add_argument("--study-id", default="EPA1633_QAQC_V1", help="Study ID key.")
    ap.add_argument("--protocol-version", default="v1", help="Protocol version key.")
    ap.add_argument(
        "--run-label",
        default="",
        help=(
            "Optional run label to preserve scenario history (e.g. template3, starter20, passcase20). "
            "When provided, upsert key becomes (study_id, protocol_version, run_label)."
        ),
    )
    ap.add_argument("--reviewers-n", default="", help="Optional reviewer count to set.")
    ap.add_argument("--batches-blinded", default="", help="Optional blinded batch count to set.")
    ap.add_argument("--status", default="computed_pending_review", help="Status text.")
    ap.add_argument(
        "--notes",
        default="Computed from reviewer comparison CSV via append_qaqc_metrics_to_results_summary.py",
        help="Notes text to store in summary row.",
    )
    args = ap.parse_args()

    comparison_csv = Path(args.comparison_csv).resolve()
    results_summary_csv = Path(args.results_summary_csv).resolve()
    if not comparison_csv.is_file():
        raise SystemExit(f"ERROR: comparison CSV not found: {comparison_csv}")
    if not results_summary_csv.is_file():
        raise SystemExit(f"ERROR: results summary CSV not found: {results_summary_csv}")

    comparison_rows = _load_rows(comparison_csv)
    metrics = compute_metrics(comparison_rows)
    fieldnames, summary_rows = _read_csv_rows(results_summary_csv)
    if "run_label" not in fieldnames:
        insert_idx = 2 if len(fieldnames) >= 2 else len(fieldnames)
        fieldnames.insert(insert_idx, "run_label")
        for row in summary_rows:
            row["run_label"] = row.get("run_label", "")

    row_payload = {
        "study_id": args.study_id,
        "protocol_version": args.protocol_version,
        "run_label": args.run_label.strip(),
        "analysis_date_utc": _now_iso(),
        "batches_total": _fmt(metrics.get("rows_total")),
        "batches_blinded": args.batches_blinded or _fmt(metrics.get("rows_compared")),
        "reviewers_n": args.reviewers_n,
        "agreement_pct": _fmt(metrics.get("agreement_pct")),
        "cohens_kappa": _fmt(metrics.get("cohens_kappa")),
        "false_positive_rate": _fmt(metrics.get("false_positive_rate")),
        "false_negative_rate": _fmt(metrics.get("false_negative_rate")),
        "escalation_rate": _fmt(metrics.get("escalation_rate")),
        "missed_failure_rate": _fmt(metrics.get("missed_failure_rate")),
        "status": args.status,
        "notes": args.notes,
    }

    summary_rows = _upsert_summary_row(
        rows=summary_rows,
        fieldnames=fieldnames,
        row_payload=row_payload,
        study_id=args.study_id,
        protocol_version=args.protocol_version,
        run_label=args.run_label.strip(),
    )
    _write_csv_rows(results_summary_csv, fieldnames=fieldnames, rows=summary_rows)

    print("Updated results summary row:")
    print(
        f"  study_id={args.study_id} protocol_version={args.protocol_version} run_label={args.run_label.strip() or '(none)'} "
        f"agreement_pct={row_payload['agreement_pct']} kappa={row_payload['cohens_kappa']}"
    )
    print(f"WROTE {results_summary_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
