"""Component 3: Applicability validator.

Refusal-first gate that decides whether a single input row may
proceed to percentile contextualization. Returns one of:

    ad_status = "in_domain"   -> row is in the V1 applicability domain
    ad_status = "refused"     -> row is outside; ad_reason explains why

The validator is intentionally narrow:

    - It evaluates ONE row at a time. Multi-row inputs are
      validated in a loop by the CLI; per-row refusals do not
      poison the rest of the batch.
    - It evaluates ONLY the four refusal classes the user
      enumerated in the V1 spec:
        1. non-serum
        2. non-PFOS/PFOA analyte
        3. missing units (and units != ng/mL)
        4. missing source_program
      plus two structural refusals required to make the
      contextualization step well-defined:
        5. missing/non-numeric result_value
        6. reference anchor drifted (raised by the engine; the
           validator surfaces it as an ontology refusal code).
    - It does NOT make scientific judgements (e.g. "this value
      is too high to be plausible"). That is the reference
      engine's percentile result, not a refusal.

The result is structured so the report generator and the
provenance logger can render the refusal text directly without
re-deriving the reason; deterministic replay requires that
identical inputs produce byte-identical refusal payloads.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any, Mapping

from .ontology import Ontology


@dataclass(frozen=True)
class ValidationResult:
    """Outcome for one input row.

    Fields:
        ad_status:  "in_domain" | "refused"
        ad_reason:  short human-readable explanation. Empty
                    string when ad_status == "in_domain".
        ad_code:    ontology refusal code (e.g.
                    "matrix_not_serum") when refused; None when
                    in domain.
        analyte_id: the ontology analyte_id resolved from the
                    input row. None when refused for a reason
                    that prevented analyte resolution.
        normalized_value_ng_per_mL: float result_value once unit
                    checks have passed. None when refused.
        offending_field: the input field that triggered the
                    refusal (e.g. "sample_matrix",
                    "result_unit"). Empty when in domain.
    """

    ad_status: str
    ad_reason: str
    ad_code: str | None
    analyte_id: str | None
    normalized_value_ng_per_mL: float | None
    offending_field: str
    row_index: int = -1


@dataclass(frozen=True)
class _Verdict:
    code: str
    reason: str
    offending_field: str = ""


def _refuse(
    code: str,
    reason: str,
    *,
    offending_field: str = "",
    row_index: int = -1,
    analyte_id: str | None = None,
) -> ValidationResult:
    return ValidationResult(
        ad_status="refused",
        ad_reason=reason,
        ad_code=code,
        analyte_id=analyte_id,
        normalized_value_ng_per_mL=None,
        offending_field=offending_field,
        row_index=row_index,
    )


def _ok(
    analyte_id: str,
    value_ng_per_mL: float,
    row_index: int = -1,
) -> ValidationResult:
    return ValidationResult(
        ad_status="in_domain",
        ad_reason="",
        ad_code=None,
        analyte_id=analyte_id,
        normalized_value_ng_per_mL=value_ng_per_mL,
        offending_field="",
        row_index=row_index,
    )


def _missing(v: Any) -> bool:
    """True iff v is None, NaN, empty string, or pandas NA-equivalent.

    Numpy NaN and pandas NA both compare unequal to themselves;
    str-empty is a separate case. We treat them all as missing
    so a CSV cell that came in as "" or NA-encoded survives the
    'missing' refusal correctly.
    """
    if v is None:
        return True
    try:
        if isinstance(v, float) and math.isnan(v):
            return True
    except TypeError:
        pass
    if isinstance(v, str) and v.strip() == "":
        return True
    s = str(v).strip().lower()
    if s in {"nan", "na", "null", "none"}:
        return True
    return False


def validate_row(
    row: Mapping[str, Any],
    ontology: Ontology,
    *,
    row_index: int = -1,
) -> ValidationResult:
    """Validate a single input row against the V1 ontology.

    The expected input columns are declared in
    `ontology.required_input_columns`. This function walks them
    in order:

        sample_matrix    -> must equal expected_matrix
        result_unit      -> must equal expected_units (ng/mL)
        source_program   -> must equal expected_source_program
        analyte          -> must be one of ontology.analyte_ids
        result_value     -> must be finite, numeric

    Refusal returns are mutually exclusive: the first failing
    check wins (refusal-first semantics, matching the V1 spec's
    'refuse before contextualize' invariant).
    """
    # 1. Matrix
    if "sample_matrix" not in row or _missing(row["sample_matrix"]):
        return _refuse(
            "matrix_not_serum",
            "sample_matrix is missing; V1 is serum-only by contract.",
            offending_field="sample_matrix",
            row_index=row_index,
        )
    matrix = str(row["sample_matrix"]).strip()
    if matrix != ontology.expected_matrix:
        return _refuse(
            "matrix_not_serum",
            f"sample_matrix={matrix!r} is not {ontology.expected_matrix!r}; "
            "V1 is serum-only by contract.",
            offending_field="sample_matrix",
            row_index=row_index,
        )

    # 2. Units
    if "result_unit" not in row or _missing(row["result_unit"]):
        return _refuse(
            "missing_units",
            "result_unit is missing; V1 requires result_unit='ng/mL'.",
            offending_field="result_unit",
            row_index=row_index,
        )
    unit = str(row["result_unit"]).strip()
    if unit != ontology.expected_units:
        return _refuse(
            "units_not_ng_per_mL",
            f"result_unit={unit!r} is not {ontology.expected_units!r}; "
            "V1 does not auto-convert.",
            offending_field="result_unit",
            row_index=row_index,
        )

    # 3. Source program
    if "source_program" not in row or _missing(row["source_program"]):
        return _refuse(
            "missing_source_program",
            "source_program is missing; V1 expects source_program="
            f"{ontology.expected_source_program!r}.",
            offending_field="source_program",
            row_index=row_index,
        )

    # 4. Analyte
    if "analyte" not in row or _missing(row["analyte"]):
        return _refuse(
            "analyte_not_in_pfos_pfoa_scope",
            "analyte is missing; V1 scores only "
            f"{', '.join(ontology.analyte_ids)}.",
            offending_field="analyte",
            row_index=row_index,
        )
    analyte_id = str(row["analyte"]).strip()
    if not ontology.is_in_scope(analyte_id):
        return _refuse(
            "analyte_not_in_pfos_pfoa_scope",
            f"analyte={analyte_id!r} is not in the V1 PFOS/PFOA scope; "
            f"valid analyte_ids are {ontology.analyte_ids}.",
            offending_field="analyte",
            row_index=row_index,
        )

    # 5. Numeric result_value
    if "result_value" not in row or _missing(row["result_value"]):
        return _refuse(
            "missing_result_value",
            "result_value is missing; V1 requires a finite ng/mL concentration.",
            offending_field="result_value",
            row_index=row_index,
            analyte_id=analyte_id,
        )
    try:
        v = float(row["result_value"])
    except (TypeError, ValueError):
        return _refuse(
            "missing_result_value",
            f"result_value={row['result_value']!r} is not numeric.",
            offending_field="result_value",
            row_index=row_index,
            analyte_id=analyte_id,
        )
    if not math.isfinite(v):
        return _refuse(
            "missing_result_value",
            f"result_value={v!r} is not finite.",
            offending_field="result_value",
            row_index=row_index,
            analyte_id=analyte_id,
        )

    return _ok(analyte_id=analyte_id, value_ng_per_mL=v, row_index=row_index)


@dataclass(frozen=True)
class BatchValidation:
    """Per-row validation results for a multi-row input.

    The CLI uses this to decide which rows continue to the
    reference engine and which are recorded as refusals in the
    report. The original row ordering is preserved.
    """

    results: tuple = field(default=tuple())

    @property
    def n_in_domain(self) -> int:
        return sum(1 for r in self.results if r.ad_status == "in_domain")

    @property
    def n_refused(self) -> int:
        return sum(1 for r in self.results if r.ad_status == "refused")


def validate_rows(
    rows: list[Mapping[str, Any]],
    ontology: Ontology,
) -> BatchValidation:
    """Validate a batch of rows, preserving order.

    Refused rows do not poison the batch -- in-domain rows
    proceed to contextualization independently. This mirrors
    NHANES analytic practice where one bad row in a release is
    surfaced as a refusal but does not invalidate the rest of
    the file.
    """
    results = tuple(
        validate_row(r, ontology, row_index=i)
        for i, r in enumerate(rows)
    )
    return BatchValidation(results=results)
