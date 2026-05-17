"""Component 5: Governed report generator.

Emits a deterministic RUO CSV and a one-page PDF summary stub with:
    - per-row applicability outcome (in_domain or refused)
    - percentile context for in-domain rows
    - limitations / non-claims footer (PDF + manifest metadata)
    - reproducibility footer (run_id, content hashes)

The CSV body contains NO timestamps so identical inputs replay to
identical output_hash values. Timestamps live only in the provenance
manifest JSON written by the CLI.
"""
from __future__ import annotations

import csv
import io
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from .applicability import BatchValidation, ValidationResult
from .ontology import Ontology
from .provenance import ProvenanceRecord
from .lod_policy import parse_lod_code, resolve_lod_context_flag
from .reference import PercentileResult

# Fixed column order for deterministic CSV replay (V1.0).
REPORT_COLUMNS: tuple[str, ...] = (
    "row_index",
    "sample_matrix",
    "result_unit",
    "source_program",
    "analyte",
    "result_value",
    "ad_status",
    "ad_code",
    "ad_reason",
    "offending_field",
    "reference_cycle",
    "sex_stratum",
    "age_group_stratum",
    "percentile",
    "n_reference",
    "n_weighted",
    "pct_below_lod_reference",
    "imputed_below_lod_value_ng_per_mL",
    "query_below_imputed_lod",
    "bracket_low_pct",
    "bracket_high_pct",
    "lod_context_flag",
)

REPORT_COLUMNS_V1_1: tuple[str, ...] = REPORT_COLUMNS + (
    "race_ethnicity_requested",
    "race_ethnicity_lookup",
    "race_ethnicity_stratum",
    "race_stratum_fallback",
    "input_lod_code",
)

_LIMITATIONS_FOOTER_LINES: tuple[str, ...] = (
    "PFAS Enterprise 5.0 V1 — Research Use Only (RUO).",
    "Percentile context is against CDC NHANES population distributions.",
    "NOT diagnostic. NOT clinical. NOT regulatory. NOT exposure-risk prediction.",
    "NOT a toxicology AI. NOT a temporal-trend or cross-cycle comparison tool.",
    "Sb-PFOA strata with high below-LOD fractions: central percentiles reflect",
    "NHANES LOD/sqrt(2) imputation, not population signal.",
)


@dataclass(frozen=True)
class ContextualizationOutcome:
    """Combined validation + optional percentile for one input row."""

    validation: ValidationResult
    percentile: PercentileResult | None = None
    stratum_error: str | None = None


def report_columns_for(ontology: Ontology) -> tuple[str, ...]:
    """Return report CSV columns for the loaded ontology version."""
    if ontology.ontology_version.startswith("1.1"):
        return REPORT_COLUMNS_V1_1
    return REPORT_COLUMNS


def _fmt_float(v: Any, *, places: int = 4) -> str:
    if v is None or v == "":
        return ""
    try:
        f = float(v)
    except (TypeError, ValueError):
        return str(v)
    if not (f == f):  # NaN
        return ""
    return f"{f:.{places}f}"


def build_outcomes(
    input_rows: Sequence[Mapping[str, Any]],
    batch: BatchValidation,
    *,
    engine_percentiles: dict[int, PercentileResult],
    stratum_errors: dict[int, str] | None = None,
) -> list[ContextualizationOutcome]:
    """Zip validation results with optional percentile results."""
    errs = stratum_errors or {}
    out: list[ContextualizationOutcome] = []
    for i, vr in enumerate(batch.results):
        if vr.ad_status == "in_domain":
            out.append(
                ContextualizationOutcome(
                    validation=vr,
                    percentile=engine_percentiles.get(i),
                    stratum_error=errs.get(i),
                )
            )
        else:
            out.append(ContextualizationOutcome(validation=vr))
    if len(input_rows) != len(out):
        raise ValueError("input_rows and batch.results length mismatch")
    return out


def _empty_context_fields(*, v1_1: bool) -> dict[str, str]:
    base = {
        "reference_cycle": "",
        "sex_stratum": "",
        "age_group_stratum": "",
        "percentile": "",
        "n_reference": "",
        "n_weighted": "",
        "pct_below_lod_reference": "",
        "imputed_below_lod_value_ng_per_mL": "",
        "query_below_imputed_lod": "",
        "bracket_low_pct": "",
        "bracket_high_pct": "",
        "lod_context_flag": "",
    }
    if v1_1:
        base["race_ethnicity_requested"] = ""
        base["race_ethnicity_lookup"] = ""
        base["race_ethnicity_stratum"] = ""
        base["race_stratum_fallback"] = ""
        base["input_lod_code"] = ""
    return base


def _row_to_csv_dict(
    row_index: int,
    input_row: Mapping[str, Any],
    outcome: ContextualizationOutcome,
    *,
    v1_1: bool = False,
) -> dict[str, str]:
    vr = outcome.validation
    pr = outcome.percentile

    if vr.ad_status == "refused":
        return {
            "row_index": str(row_index),
            "sample_matrix": str(input_row.get("sample_matrix", "")),
            "result_unit": str(input_row.get("result_unit", "")),
            "source_program": str(input_row.get("source_program", "")),
            "analyte": str(input_row.get("analyte", "")),
            "result_value": _fmt_float(input_row.get("result_value")),
            "ad_status": "refused",
            "ad_code": vr.ad_code or "",
            "ad_reason": vr.ad_reason,
            "offending_field": vr.offending_field,
            **_empty_context_fields(v1_1=v1_1),
        }

    if outcome.stratum_error:
        return {
            "row_index": str(row_index),
            "sample_matrix": str(input_row.get("sample_matrix", "")),
            "result_unit": str(input_row.get("result_unit", "")),
            "source_program": str(input_row.get("source_program", "")),
            "analyte": str(input_row.get("analyte", "")),
            "result_value": _fmt_float(input_row.get("result_value")),
            "ad_status": "refused",
            "ad_code": "reference_stratum_missing",
            "ad_reason": outcome.stratum_error,
            "offending_field": "reference_stratum",
            **_empty_context_fields(v1_1=v1_1),
        }

    if pr is None:
        raise ValueError(f"row {row_index}: in_domain but no percentile result")

    lod_flag = resolve_lod_context_flag(input_row, pr)
    input_lod = parse_lod_code(input_row)

    row_out = {
        "row_index": str(row_index),
        "sample_matrix": str(input_row.get("sample_matrix", "")),
        "result_unit": str(input_row.get("result_unit", "")),
        "source_program": str(input_row.get("source_program", "")),
        "analyte": str(input_row.get("analyte", "")),
        "result_value": _fmt_float(input_row.get("result_value")),
        "ad_status": "in_domain",
        "ad_code": "",
        "ad_reason": "",
        "offending_field": "",
        "reference_cycle": pr.reference_cycle,
        "sex_stratum": pr.sex,
        "age_group_stratum": pr.age_group,
        "percentile": _fmt_float(pr.percentile, places=2),
        "n_reference": str(pr.n_reference),
        "n_weighted": _fmt_float(pr.n_weighted, places=0) if pr.n_weighted is not None else "",
        "pct_below_lod_reference": _fmt_float(pr.pct_below_lod_reference, places=2),
        "imputed_below_lod_value_ng_per_mL": _fmt_float(
            pr.imputed_below_lod_value_ng_per_mL, places=2
        ),
        "query_below_imputed_lod": "true" if pr.query_below_imputed_lod else "false",
        "bracket_low_pct": _fmt_float(pr.bracket_low_pct, places=1),
        "bracket_high_pct": _fmt_float(pr.bracket_high_pct, places=1),
        "lod_context_flag": lod_flag,
    }
    if v1_1:
        row_out["race_ethnicity_requested"] = pr.race_ethnicity_requested
        row_out["race_ethnicity_lookup"] = pr.race_ethnicity_lookup
        row_out["race_ethnicity_stratum"] = pr.race_ethnicity
        row_out["race_stratum_fallback"] = (
            "true" if pr.race_stratum_fallback else "false"
        )
        row_out["input_lod_code"] = "" if input_lod is None else str(input_lod)
    return row_out


def render_report_csv_bytes(
    input_rows: Sequence[Mapping[str, Any]],
    outcomes: Sequence[ContextualizationOutcome],
    *,
    ontology: Ontology | None = None,
) -> bytes:
    """Serialize the governed report to UTF-8 CSV bytes (LF, no BOM)."""
    columns = report_columns_for(ontology) if ontology is not None else REPORT_COLUMNS
    v1_1 = ontology is not None and ontology.ontology_version.startswith("1.1")
    buf = io.StringIO(newline="")
    writer = csv.DictWriter(
        buf,
        fieldnames=list(columns),
        lineterminator="\n",
        quoting=csv.QUOTE_MINIMAL,
    )
    writer.writeheader()
    for i, (inp, oc) in enumerate(zip(input_rows, outcomes)):
        writer.writerow(_row_to_csv_dict(i, inp, oc, v1_1=v1_1))
    return buf.getvalue().encode("utf-8")


def render_pdf_stub_bytes(
    *,
    ontology: Ontology,
    provenance: ProvenanceRecord,
    outcomes: Sequence[ContextualizationOutcome],
    n_in_domain: int,
    n_refused: int,
) -> bytes:
    """One-page PDF summary using reportlab (repo dependency)."""
    try:
        from reportlab.lib.pagesizes import letter
        from reportlab.pdfgen import canvas
    except ImportError as exc:
        raise RuntimeError(
            "reportlab is required for PDF output. Install requirements.txt."
        ) from exc

    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=letter)
    width, height = letter
    y = height - 72

    def line(text: str, *, size: int = 10, gap: int = 14) -> None:
        nonlocal y
        c.setFont("Helvetica", size)
        c.drawString(72, y, text[:110])
        y -= gap

    line("PFAS Enterprise 5.0 V1 — Governed Serum PFOS/PFOA Report", size=12, gap=18)
    line(f"Ontology: {ontology.ontology_id} v{ontology.ontology_version}")
    line(f"Run ID: {provenance.run_id}")
    line(f"Rows: {len(outcomes)} total | {n_in_domain} in_domain | {n_refused} refused")
    line(f"Reference table SHA-256: {provenance.reference_table_sha256[:16]}…")
    line(f"Ontology SHA-256: {provenance.ontology_sha256[:16]}…")
    y -= 6
    line("In-domain results (first 12 rows):", size=11, gap=16)

    shown = 0
    for i, oc in enumerate(outcomes):
        if oc.validation.ad_status != "in_domain" or oc.percentile is None:
            continue
        if shown >= 12:
            break
        pr = oc.percentile
        stratum = f"{pr.sex}/{pr.age_group}"
        if pr.race_ethnicity and pr.race_ethnicity != "all":
            stratum = f"{stratum}/{pr.race_ethnicity}"
        line(
            f"  [{i}] {pr.analyte_id} {pr.query_value_ng_per_mL:.2f} ng/mL → "
            f"pct={pr.percentile:.1f} (cycle {pr.reference_cycle}, {stratum})",
            size=9,
            gap=12,
        )
        shown += 1
    if n_in_domain > 12:
        line(f"  … and {n_in_domain - 12} more in-domain rows in the CSV.", size=9)

    y -= 8
    line("Limitations / non-claims:", size=11, gap=16)
    for lim in _LIMITATIONS_FOOTER_LINES:
        line(f"  {lim}", size=8, gap=11)

    y -= 4
    line("Reproducibility:", size=11, gap=16)
    line(f"  input_csv_sha256={provenance.input_csv_sha256}", size=8, gap=11)
    line(f"  reference_table_sha256={provenance.reference_table_sha256}", size=8, gap=11)
    line(f"  ontology_sha256={provenance.ontology_sha256}", size=8, gap=11)
    line(f"  code_version={provenance.code_version}", size=8, gap=11)

    c.showPage()
    c.save()
    return buf.getvalue()


def build_report_bundle(
    *,
    ontology: Ontology,
    provenance: ProvenanceRecord,
    input_rows: Sequence[Mapping[str, Any]],
    outcomes: Sequence[ContextualizationOutcome],
) -> tuple[bytes, bytes | None, ProvenanceRecord]:
    """Return (csv_bytes, pdf_bytes_or_none, provenance_with_output_hash).

    PDF generation is best-effort: if ``reportlab`` is not installed,
    ``pdf_bytes`` is ``None`` and the CSV + manifest still commit.
    """
    from .provenance import stamp_output

    csv_bytes = render_report_csv_bytes(input_rows, outcomes, ontology=ontology)
    n_in = sum(1 for o in outcomes if o.validation.ad_status == "in_domain" and o.percentile)
    n_ref = len(outcomes) - n_in
    try:
        pdf_bytes: bytes | None = render_pdf_stub_bytes(
            ontology=ontology,
            provenance=provenance,
            outcomes=outcomes,
            n_in_domain=n_in,
            n_refused=n_ref,
        )
    except RuntimeError as exc:
        if "reportlab" in str(exc).lower():
            pdf_bytes = None
        else:
            raise
    stamped = stamp_output(provenance, csv_bytes)
    return csv_bytes, pdf_bytes, stamped
