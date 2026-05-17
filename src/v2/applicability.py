"""V2 applicability — V1 checks plus required reference_cycle."""
from __future__ import annotations

import math
from typing import Any, Mapping

from src.v1.applicability import ValidationResult, validate_row
from src.v1.ontology import Ontology


def _missing(v: Any) -> bool:
    if v is None:
        return True
    if isinstance(v, float) and math.isnan(v):
        return True
    if isinstance(v, str) and v.strip() == "":
        return True
    return False


def validate_row_v2(row: Mapping[str, Any], ontology: Ontology, *, v1_ontology: Ontology, row_index: int = -1) -> ValidationResult:
    """Run V1 validation then enforce V2-specific reference_cycle rules."""
    vr = validate_row(row, v1_ontology, row_index=row_index)
    if vr.ad_status == "refused":
        return vr

    if "reference_cycle" not in row or _missing(row["reference_cycle"]):
        return ValidationResult(
            ad_status="refused",
            ad_reason="reference_cycle is missing; V2 requires an anchor cycle (I, J, or P).",
            ad_code="missing_reference_cycle",
            analyte_id=vr.analyte_id,
            normalized_value_ng_per_mL=vr.normalized_value_ng_per_mL,
            offending_field="reference_cycle",
            row_index=row_index,
        )

    cycle = str(row["reference_cycle"]).strip().upper()
    allowed = tuple(str(c).upper() for c in ontology.scope["comparison_cycles"])
    if cycle not in allowed:
        return ValidationResult(
            ad_status="refused",
            ad_reason=f"reference_cycle={cycle!r} not in V2 comparison cycles {allowed}.",
            ad_code="missing_reference_cycle",
            analyte_id=vr.analyte_id,
            normalized_value_ng_per_mL=vr.normalized_value_ng_per_mL,
            offending_field="reference_cycle",
            row_index=row_index,
        )

    return vr
