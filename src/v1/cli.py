"""V1 CLI orchestrator — end-to-end governed serum PFOS/PFOA contextualization.

Usage (from repo root)::

    python -m src.v1.cli \\
        --input data/v1/fixtures/sample_input.csv \\
        --output-dir data/v1/outputs

Writes:
    v1_report_<run_id>.csv
    v1_report_<run_id>.pdf
    v1_manifest_<run_id>.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import pandas as pd

from . import (
    ONTOLOGY_PATH,
    REFERENCE_CSV_PATH,
    REFERENCE_CSV_SHA256,
    REFERENCE_TABLE_PATH,
    REFERENCE_TABLE_SHA256,
    __version__,
)
from .applicability import validate_rows
from .ontology import load_ontology
from .provenance import build_provenance
from .reference import ReferenceEngine, ReferenceStratumMissing, ReferenceTableDrifted
from .report import build_outcomes, build_report_bundle
from .strata import normalize_age_group, normalize_reference_cycle, normalize_sex


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _read_input_csv(path: Path) -> list[dict[str, Any]]:
    df = pd.read_csv(path)
    return [dict(r) for r in df.to_dict(orient="records")]


def run_pipeline(
    *,
    input_csv: Path,
    output_dir: Path,
    ontology_path: Path | None = None,
    reference_table_path: Path | None = None,
    anchor_csv_path: Path | None = None,
    default_cycle: str | None = None,
    repo_root: Path | None = None,
) -> dict[str, Any]:
    """Execute the full V1 pipeline; return a summary dict."""
    root = repo_root or _repo_root()
    out_dir = output_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    ont_path = ontology_path or (root / ONTOLOGY_PATH)
    ref_table = reference_table_path or (root / REFERENCE_TABLE_PATH)
    anchor = anchor_csv_path or (root / REFERENCE_CSV_PATH)

    ontology = load_ontology(ont_path)
    ReferenceEngine.verify_anchor_csv(ontology, anchor)
    engine = ReferenceEngine.load(ontology, ref_table)

    use_cycle = (default_cycle or ontology.default_reference_cycle).upper()

    input_rows = _read_input_csv(input_csv)
    batch = validate_rows(input_rows, ontology)

    engine_results: dict[int, Any] = {}
    stratum_errors: dict[int, str] = {}

    for i, vr in enumerate(batch.results):
        if vr.ad_status != "in_domain":
            continue
        row = input_rows[i]
        sex = normalize_sex(row)
        age_group = normalize_age_group(row)
        cycle = normalize_reference_cycle(row, default_cycle=use_cycle)
        try:
            engine_results[i] = engine.percentile(
                vr.analyte_id,  # type: ignore[arg-type]
                vr.normalized_value_ng_per_mL,  # type: ignore[arg-type]
                cycle=cycle,
                sex=sex,
                age_group=age_group,
            )
        except ReferenceStratumMissing as exc:
            stratum_errors[i] = str(exc)

    provenance = build_provenance(
        input_csv_path=input_csv,
        reference_table_path=ref_table,
        ontology_path=ont_path,
        reference_table_documented_sha256=REFERENCE_TABLE_SHA256,
        anchor_csv_path=anchor,
        anchor_csv_documented_sha256=REFERENCE_CSV_SHA256,
        code_version=__version__,
        ontology_version=ontology.ontology_version,
        repo_root=root,
        extra={
            "default_reference_cycle": use_cycle,
            "n_input_rows": len(input_rows),
        },
    )

    outcomes = build_outcomes(
        input_rows,
        batch,
        engine_percentiles=engine_results,
        stratum_errors=stratum_errors,
    )
    csv_bytes, pdf_bytes, stamped = build_report_bundle(
        ontology=ontology,
        provenance=provenance,
        input_rows=input_rows,
        outcomes=outcomes,
    )

    run_id = stamped.run_id
    csv_path = out_dir / f"v1_report_{run_id}.csv"
    pdf_path = out_dir / f"v1_report_{run_id}.pdf"
    manifest_path = out_dir / f"v1_manifest_{run_id}.json"

    csv_path.write_bytes(csv_bytes)
    pdf_written: str | None = None
    if pdf_bytes is not None:
        pdf_path.write_bytes(pdf_bytes)
        pdf_written = str(pdf_path)
    manifest_path.write_bytes(stamped.to_json_bytes())

    n_in = sum(
        1
        for o in outcomes
        if o.validation.ad_status == "in_domain" and o.percentile is not None
    )
    n_ref = len(outcomes) - n_in

    return {
        "run_id": run_id,
        "csv_path": str(csv_path),
        "pdf_path": pdf_written,
        "pdf_skipped": pdf_written is None,
        "manifest_path": str(manifest_path),
        "output_csv_sha256": stamped.output_csv_sha256,
        "n_rows": len(outcomes),
        "n_in_domain": n_in,
        "n_refused": n_ref,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="PFAS Enterprise 5.0 V1 — governed serum PFOS/PFOA contextualization",
    )
    parser.add_argument(
        "--input",
        required=True,
        type=Path,
        help="Input CSV with required columns per ontology",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
        help="Directory for report CSV, PDF, and manifest JSON",
    )
    parser.add_argument("--ontology", type=Path, default=None)
    parser.add_argument("--reference-table", type=Path, default=None)
    parser.add_argument("--anchor-csv", type=Path, default=None)
    parser.add_argument(
        "--default-cycle",
        type=str,
        default=None,
        help="NHANES cycle label when input rows omit cycle (default: J)",
    )
    args = parser.parse_args(argv)

    if not args.input.is_file():
        print(f"ERROR: input not found: {args.input}", file=sys.stderr)
        return 2

    try:
        summary = run_pipeline(
            input_csv=args.input,
            output_dir=args.output_dir,
            ontology_path=args.ontology,
            reference_table_path=args.reference_table,
            anchor_csv_path=args.anchor_csv,
            default_cycle=args.default_cycle,
        )
    except (ReferenceTableDrifted, RuntimeError, FileNotFoundError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
