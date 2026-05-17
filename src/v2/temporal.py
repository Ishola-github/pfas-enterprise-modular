"""Cross-cycle temporal contextualization (V2 core)."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from src.v1.applicability import ValidationResult
from src.v1.reference import PercentileResult, ReferenceEngine, ReferenceStratumMissing
from src.v1.strata import (
    normalize_age_group,
    normalize_race_ethnicity,
    normalize_race_ethnicity_lookup,
    normalize_reference_cycle,
    normalize_sex,
)

COMPARISON_CYCLES: tuple[str, ...] = ("I", "J", "P")
PERCENTILE_SHIFT_WARN = 15.0


@dataclass(frozen=True)
class CrossCycleTemporalResult:
    """Cross-cycle comparison for one in-domain row."""

    anchor_cycle: str
    analyte_id: str
    query_value_ng_per_mL: float
    percentiles_by_cycle: dict[str, float | None]
    reference_p50_by_cycle: dict[str, float | None]
    ratio_to_p50_by_cycle: dict[str, float | None]
    percentile_delta_J_minus_I: float | None
    percentile_delta_P_minus_J: float | None
    anchor_percentile: float | None
    anchor_v1: PercentileResult
    results_by_cycle: dict[str, PercentileResult]
    temporal_context_flag: str
    cycles_missing_stratum: tuple[str, ...]


def _fmt_delta(a: float | None, b: float | None) -> float | None:
    if a is None or b is None:
        return None
    return float(b) - float(a)


def _p50_from_table(
    engine: ReferenceEngine,
    pr: PercentileResult,
) -> float | None:
    if pr.imputed_below_lod_value_ng_per_mL is not None:
        return pr.imputed_below_lod_value_ng_per_mL
    try:
        row = engine._get_row(  # noqa: SLF001
            cycle=pr.reference_cycle,
            analyte_id=pr.analyte_id,
            sex=pr.sex,
            age_group=pr.age_group,
            race_ethnicity=pr.race_ethnicity,
        )
        return float(row["p50"])
    except (ReferenceStratumMissing, KeyError, TypeError, ValueError):
        return None


def resolve_temporal_flags(
    *,
    delta_j_i: float | None,
    delta_p_j: float | None,
    missing_cycles: tuple[str, ...],
) -> str:
    flags: list[str] = []
    if missing_cycles:
        flags.append("cross_cycle_stratum_incomplete")
    if "P" not in missing_cycles:
        flags.append("cycle_P_pre_pandemic_caveat")
    for delta in (delta_j_i, delta_p_j):
        if delta is not None and abs(delta) >= PERCENTILE_SHIFT_WARN:
            flags.append("cross_cycle_percentile_shift_ge_15")
            break
    return ";".join(flags)


def contextualize_cross_cycle(
    row: Mapping[str, Any],
    validation: ValidationResult,
    engine: ReferenceEngine,
    *,
    default_anchor_cycle: str = "J",
) -> CrossCycleTemporalResult:
    """Compute multi-cycle percentiles and deltas for one validated row."""
    if validation.ad_status != "in_domain" or validation.analyte_id is None:
        raise ValueError("contextualize_cross_cycle requires an in-domain validation result")

    analyte_id = validation.analyte_id
    query = float(validation.normalized_value_ng_per_mL)  # type: ignore[arg-type]
    sex = normalize_sex(row)
    age_group = normalize_age_group(row)
    race_lookup = normalize_race_ethnicity_lookup(row)
    race_requested = normalize_race_ethnicity(row)
    anchor = normalize_reference_cycle(row, default_cycle=default_anchor_cycle)

    percentiles: dict[str, float | None] = {}
    p50s: dict[str, float | None] = {}
    ratios: dict[str, float | None] = {}
    by_cycle: dict[str, PercentileResult] = {}
    missing: list[str] = []

    for cycle in COMPARISON_CYCLES:
        try:
            pr = engine.percentile(
                analyte_id,
                query,
                cycle=cycle,
                sex=sex,
                age_group=age_group,
                race_ethnicity=race_lookup,
                race_ethnicity_requested=race_requested,
            )
            by_cycle[cycle] = pr
            percentiles[cycle] = pr.percentile
            p50 = _p50_from_table(engine, pr)
            p50s[cycle] = p50
            ratios[cycle] = (query / p50) if p50 and p50 > 0 else None
        except ReferenceStratumMissing:
            percentiles[cycle] = None
            p50s[cycle] = None
            ratios[cycle] = None
            missing.append(cycle)

    if anchor not in by_cycle:
        raise ReferenceStratumMissing(
            f"Anchor cycle {anchor!r} stratum missing; V2 requires anchor cycle reference row."
        )

    anchor_v1 = by_cycle[anchor]
    delta_j_i = _fmt_delta(percentiles.get("I"), percentiles.get("J"))
    delta_p_j = _fmt_delta(percentiles.get("J"), percentiles.get("P"))
    flags = resolve_temporal_flags(
        delta_j_i=delta_j_i,
        delta_p_j=delta_p_j,
        missing_cycles=tuple(missing),
    )

    return CrossCycleTemporalResult(
        anchor_cycle=anchor,
        analyte_id=analyte_id,
        query_value_ng_per_mL=query,
        percentiles_by_cycle=percentiles,
        reference_p50_by_cycle=p50s,
        ratio_to_p50_by_cycle=ratios,
        percentile_delta_J_minus_I=delta_j_i,
        percentile_delta_P_minus_J=delta_p_j,
        anchor_percentile=percentiles.get(anchor),
        anchor_v1=anchor_v1,
        results_by_cycle=by_cycle,
        temporal_context_flag=flags,
        cycles_missing_stratum=tuple(missing),
    )
