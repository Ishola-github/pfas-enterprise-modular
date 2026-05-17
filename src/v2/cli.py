"""V2 CLI — cross-cycle temporal contextualization.

Usage::

    python -m src.v2.cli \\
        --input data/v1/fixtures/nhanes_j_governed_v1_input.csv \\
        --output-dir data/v2/outputs
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import pandas as pd

from src.v1.applicability import ValidationResult
from src.v1.ontology import load_ontology as load_v1_ontology
from src.v1.provenance import build_provenance, stamp_output
from src.v1.reference import ReferenceEngine, ReferenceTableDrifted
from src.v1.strata import input_demographics_summary

from . import ONTOLOGY_PATH, V1_1_ONTOLOGY_PATH, __version__
from .applicability import validate_row_v2
from .ontology import load_ontology
from .report import V2Outcome, render_pdf_stub_bytes, render_report_csv_bytes
from .temporal import contextualize_cross_cycle


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _read_csv(path: Path) -> list[dict[str, Any]]:
    df = pd.read_csv(path)
    rows: list[dict[str, Any]] = []
    for raw in df.to_dict(orient="records"):
        clean: dict[str, Any] = {}
        for k, v in raw.items():
            clean[k] = None if pd.isna(v) else v
        rows.append(clean)
    return rows


def run_pipeline(
    *,
    input_csv: Path,
    output_dir: Path,
    repo_root: Path | None = None,
) -> dict[str, Any]:
    root = repo_root or _repo_root()
    out_dir = output_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    v2_ont_path = root / ONTOLOGY_PATH
    v1_ont_path = root / V1_1_ONTOLOGY_PATH
    v2_ontology = load_ontology(v2_ont_path)
    v1_ontology = load_v1_ontology(v1_ont_path)

    ref_table = root / v2_ontology.expected_reference_table_path
    engine = ReferenceEngine.load(v1_ontology, ref_table)

    rows = _read_csv(input_csv)
    demo = input_demographics_summary(rows)

    outcomes: list[V2Outcome] = []
    n_in = 0
    n_ref = 0
    n_large_shift = 0

    for i, row in enumerate(rows):
        vr = validate_row_v2(row, v2_ontology, v1_ontology=v1_ontology, row_index=i)
        if vr.ad_status != "in_domain":
            outcomes.append(V2Outcome(validation=vr))
            n_ref += 1
            continue
        try:
            temporal = contextualize_cross_cycle(
                row,
                vr,
                engine,
                default_anchor_cycle=v2_ontology.default_reference_cycle,
            )
        except Exception as exc:
            outcomes.append(
                V2Outcome(
                    validation=ValidationResult(
                        ad_status="refused",
                        ad_reason=str(exc),
                        ad_code="reference_stratum_missing",
                        analyte_id=vr.analyte_id,
                        normalized_value_ng_per_mL=None,
                        offending_field="reference_stratum",
                        row_index=i,
                    )
                )
            )
            n_ref += 1
            continue
        outcomes.append(V2Outcome(validation=vr, temporal=temporal))
        n_in += 1
        if "cross_cycle_percentile_shift_ge_15" in temporal.temporal_context_flag:
            n_large_shift += 1

    provenance = build_provenance(
        input_csv_path=input_csv,
        reference_table_path=ref_table,
        ontology_path=v2_ont_path,
        reference_table_documented_sha256=v2_ontology.expected_reference_table_sha256,
        code_version=__version__,
        ontology_version=v2_ontology.ontology_version,
        repo_root=root,
        extra={"comparison_cycles": list(v2_ontology.scope["comparison_cycles"])},
    )

    csv_bytes = render_report_csv_bytes(rows, outcomes)
    stamped = stamp_output(provenance, csv_bytes)
    run_id = stamped.run_id

    csv_path = out_dir / f"v2_report_{run_id}.csv"
    manifest_path = out_dir / f"v2_manifest_{run_id}.json"
    csv_path.write_bytes(csv_bytes)
    manifest_path.write_bytes(stamped.to_json_bytes())

    pdf_path: str | None = None
    try:
        pdf_bytes = render_pdf_stub_bytes(
            provenance=stamped,
            outcomes=outcomes,
            n_in_domain=n_in,
            n_refused=n_ref,
        )
        pdf_out = out_dir / f"v2_report_{run_id}.pdf"
        pdf_out.write_bytes(pdf_bytes)
        pdf_path = str(pdf_out)
    except Exception:
        pdf_path = None

    return {
        "run_id": run_id,
        "csv_path": str(csv_path),
        "pdf_path": pdf_path,
        "manifest_path": str(manifest_path),
        "output_csv_sha256": stamped.output_csv_sha256,
        "n_rows": len(outcomes),
        "n_in_domain": n_in,
        "n_refused": n_ref,
        "n_cross_cycle_shift_ge_15": n_large_shift,
        "input_demographics": demo,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PFAS Enterprise V2 cross-cycle contextualization")
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(argv)

    if not args.input.is_file():
        print(f"ERROR: input not found: {args.input}", file=sys.stderr)
        return 2

    try:
        summary = run_pipeline(input_csv=args.input, output_dir=args.output_dir)
    except (ReferenceTableDrifted, RuntimeError, FileNotFoundError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
