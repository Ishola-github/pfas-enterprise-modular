"""LOD interpretation policy for V1.1+ governed contextualization."""
from __future__ import annotations

import math
from typing import Any, Mapping

from .reference import PercentileResult


def parse_lod_code(row: Mapping[str, Any]) -> int | None:
    """Return 0, 1, or None when lod_code is absent or unparseable."""
    if "lod_code" not in row:
        return None
    raw = row["lod_code"]
    if raw is None:
        return None
    if isinstance(raw, float) and math.isnan(raw):
        return None
    s = str(raw).strip().lower()
    if s in {"", "nan", "na", "null", "none"}:
        return None
    try:
        code = int(float(s))
    except (TypeError, ValueError):
        return None
    if code in (0, 1):
        return code
    return None


def resolve_lod_context_flag(
    row: Mapping[str, Any],
    pr: PercentileResult,
) -> str:
    """Combine input LOD flag with reference-stratum LOD context.

    NHANES stores ``LOD/sqrt(2)`` in ``result_value`` when the lab flag
    is below LOD; V1 still contextualizes that imputed value but must
    surface the limitation explicitly in the report.
    """
    flags: list[str] = []
    input_lod = parse_lod_code(row)
    if input_lod == 1:
        flags.append("input_reported_below_lod")
    if pr.query_below_imputed_lod:
        flags.append("query_at_or_below_imputed_lod")
    elif pr.pct_below_lod_reference is not None and pr.pct_below_lod_reference >= 50.0:
        flags.append("reference_stratum_lod_dominated")
    return ";".join(flags)
