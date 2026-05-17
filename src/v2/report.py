"""V2 governed report CSV (cross-cycle columns + V1.1 anchor columns)."""
from __future__ import annotations

import csv
import io
from dataclasses import dataclass
from io import BytesIO
from typing import Any, Mapping, Sequence

from src.v1.applicability import ValidationResult
from src.v1.lod_policy import parse_lod_code, resolve_lod_context_flag
from src.v1.provenance import ProvenanceRecord

from .temporal import CrossCycleTemporalResult

REPORT_COLUMNS_V2: tuple[str, ...] = (
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
    "anchor_cycle",
    "percentile_cycle_I",
    "percentile_cycle_J",
    "percentile_cycle_P",
    "anchor_percentile",
    "percentile_delta_J_minus_I",
    "percentile_delta_P_minus_J",
    "reference_p50_cycle_I",
    "reference_p50_cycle_J",
    "reference_p50_cycle_P",
    "ratio_to_p50_cycle_I",
    "ratio_to_p50_cycle_J",
    "ratio_to_p50_cycle_P",
    "sex_stratum",
    "age_group_stratum",
    "race_ethnicity_requested",
    "race_ethnicity_lookup",
    "race_ethnicity_stratum",
    "race_stratum_fallback",
    "lod_context_flag",
    "input_lod_code",
    "temporal_context_flag",
    "cycles_missing_stratum",
)


@dataclass(frozen=True)
class V2Outcome:
    validation: ValidationResult
    temporal: CrossCycleTemporalResult | None = None


def _fmt(v: Any, places: int = 2) -> str:
    if v is None or v == "":
        return ""
    try:
        f = float(v)
    except (TypeError, ValueError):
        return str(v)
    if f != f:
        return ""
    return f"{f:.{places}f}"


def _row_dict(
    row_index: int,
    inp: Mapping[str, Any],
    outcome: V2Outcome,
) -> dict[str, str]:
    vr = outcome.validation
    base = {
        "row_index": str(row_index),
        "sample_matrix": str(inp.get("sample_matrix", "")),
        "result_unit": str(inp.get("result_unit", "")),
        "source_program": str(inp.get("source_program", "")),
        "analyte": str(inp.get("analyte", "")),
        "result_value": _fmt(inp.get("result_value"), places=4),
        "ad_status": vr.ad_status,
        "ad_code": vr.ad_code or "",
        "ad_reason": vr.ad_reason,
        "offending_field": vr.offending_field,
    }
    if vr.ad_status == "refused" or outcome.temporal is None:
        empty = {c: "" for c in REPORT_COLUMNS_V2 if c not in base}
        return {**base, **empty}

    t = outcome.temporal
    pr = t.anchor_v1
    lod = resolve_lod_context_flag(inp, pr)
    return {
        **base,
        "anchor_cycle": t.anchor_cycle,
        "percentile_cycle_I": _fmt(t.percentiles_by_cycle.get("I")),
        "percentile_cycle_J": _fmt(t.percentiles_by_cycle.get("J")),
        "percentile_cycle_P": _fmt(t.percentiles_by_cycle.get("P")),
        "anchor_percentile": _fmt(t.anchor_percentile),
        "percentile_delta_J_minus_I": _fmt(t.percentile_delta_J_minus_I),
        "percentile_delta_P_minus_J": _fmt(t.percentile_delta_P_minus_J),
        "reference_p50_cycle_I": _fmt(t.reference_p50_by_cycle.get("I"), places=4),
        "reference_p50_cycle_J": _fmt(t.reference_p50_by_cycle.get("J"), places=4),
        "reference_p50_cycle_P": _fmt(t.reference_p50_by_cycle.get("P"), places=4),
        "ratio_to_p50_cycle_I": _fmt(t.ratio_to_p50_by_cycle.get("I")),
        "ratio_to_p50_cycle_J": _fmt(t.ratio_to_p50_by_cycle.get("J")),
        "ratio_to_p50_cycle_P": _fmt(t.ratio_to_p50_by_cycle.get("P")),
        "sex_stratum": pr.sex,
        "age_group_stratum": pr.age_group,
        "race_ethnicity_requested": pr.race_ethnicity_requested,
        "race_ethnicity_lookup": pr.race_ethnicity_lookup,
        "race_ethnicity_stratum": pr.race_ethnicity,
        "race_stratum_fallback": "true" if pr.race_stratum_fallback else "false",
        "lod_context_flag": lod,
        "input_lod_code": "" if parse_lod_code(inp) is None else str(parse_lod_code(inp)),
        "temporal_context_flag": t.temporal_context_flag,
        "cycles_missing_stratum": ",".join(t.cycles_missing_stratum),
    }


def render_report_csv_bytes(
    input_rows: Sequence[Mapping[str, Any]],
    outcomes: Sequence[V2Outcome],
) -> bytes:
    buf = io.StringIO(newline="")
    writer = csv.DictWriter(
        buf,
        fieldnames=list(REPORT_COLUMNS_V2),
        lineterminator="\n",
        quoting=csv.QUOTE_MINIMAL,
    )
    writer.writeheader()
    for i, (inp, oc) in enumerate(zip(input_rows, outcomes)):
        writer.writerow(_row_dict(i, inp, oc))
    return buf.getvalue().encode("utf-8")


def render_pdf_stub_bytes(
    *,
    provenance: ProvenanceRecord,
    outcomes: Sequence[V2Outcome],
    n_in_domain: int,
    n_refused: int,
) -> bytes:
    from reportlab.lib.pagesizes import letter
    from reportlab.pdfgen import canvas

    buf = BytesIO()
    c = canvas.Canvas(buf, pagesize=letter)
    y = 750
    c.setFont("Helvetica-Bold", 14)
    c.drawString(40, y, "PFAS Enterprise 5.0 V2 — Cross-cycle temporal contextualization (RUO)")
    y -= 24
    c.setFont("Helvetica", 9)
    for line in (
        f"run_id={provenance.run_id}",
        f"Rows: {len(outcomes)} | in_domain={n_in_domain} | refused={n_refused}",
        "Compares NHANES cycles I, J, P population references (not individual longitudinal).",
        "NOT diagnostic. NOT clinical. NOT regulatory.",
    ):
        c.drawString(40, y, line)
        y -= 14
    c.showPage()
    c.save()
    return buf.getvalue()
