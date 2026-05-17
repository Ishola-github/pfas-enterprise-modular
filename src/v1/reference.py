"""Component 2: NHANES reference engine.

Looks up percentile context for a serum PFOS/PFOA concentration
against the **precomputed weighted NHANES reference table**
(``data/reference_tables/nhanes_pfas_weighted_reference_tables_v1.csv``,
SHA-256 pinned in the ontology). The cycle-J governance anchor CSV
is **not** queried at runtime; it remains the frozen provenance
source documented in ``validation/serum_v1/``.

What it does:
    - Loads the weighted reference table ONCE per ReferenceEngine.
    - Verifies the on-disk SHA-256 against
      ``ontology.expected_reference_table_sha256``; raises
      ``ReferenceTableDrifted`` on mismatch.
    - Indexes rows by ``(cycle, analyte_id, sex, age_group)``.
    - For each query, walks the precomputed percentile knots
      (p5, p10, p25, p50, p75, p90, p95) with linear interpolation
      in concentration space to estimate P(reference <= query).
    - Returns ``pct_below_lod`` and sample-size metadata from the
      precomputed row (no raw XPT access at runtime).

What it does NOT do:
    - Diagnose anything.
    - Predict toxicity or risk.
    - Recompute weighted percentiles from raw NHANES microdata.
    - Use the unweighted first-pass table (replay-diff peer only).
"""
from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING

import numpy as np
import pandas as pd

if TYPE_CHECKING:
    from .ontology import Ontology


class ReferenceTableDrifted(RuntimeError):
    """Raised when the weighted reference table's SHA-256 disagrees
    with the documented hash. Maps to ``reference_table_drifted``.
    """


# Backward-compatible alias used in earlier V1 scaffolding.
ReferenceAnchorDrifted = ReferenceTableDrifted


class ReferenceStratumMissing(KeyError):
    """Raised when no precomputed row exists for the requested
    (cycle, analyte_id, sex, age_group). Maps to
    ``reference_stratum_missing``.
    """


_PERCENTILE_KNOTS = np.array([5.0, 10.0, 25.0, 50.0, 75.0, 90.0, 95.0], dtype=np.float64)
_PERCENTILE_COLUMNS = ("p5", "p10", "p25", "p50", "p75", "p90", "p95")


@dataclass(frozen=True)
class PercentileResult:
    """One percentile contextualization result.

    Fields:
        analyte_id: ontology analyte_id (e.g. "n_pfoa").
        query_value_ng_per_mL: the input concentration contextualized.
        percentile: estimated P(reference <= query) on [0, 100].
            None if the stratum has no usable knot values.
        n_reference: unweighted NHANES subsample count for the stratum.
        n_weighted: sum of subsample weights for the stratum.
        pct_below_lod_reference: fraction of stratum below LOD
            (from the precomputed table).
        imputed_below_lod_value_ng_per_mL: when the stratum is
            LOD-dominated (pct_below_lod >= 50%), the table p50
            (NHANES imputation concentrates at LOD/sqrt(2)).
        query_below_imputed_lod: True when query <= imputed value.
        weighted: always True for the official reference table.
        reference_cycle: NHANES cycle label (I, J, P).
        sex: stratum sex label.
        age_group: stratum age label.
        race_ethnicity: resolved reference-table race stratum.
        race_ethnicity_requested: granular input race label.
        race_ethnicity_lookup: collapsed label used for table lookup.
        race_stratum_fallback: True when lookup race was broader than resolved.
        bracket_low_pct / bracket_high_pct: percentile knot bracket
            used for interpolation (audit metadata).
    """

    analyte_id: str
    query_value_ng_per_mL: float
    percentile: float | None
    n_reference: int
    n_weighted: float | None
    pct_below_lod_reference: float | None
    imputed_below_lod_value_ng_per_mL: float | None
    query_below_imputed_lod: bool
    weighted: bool
    reference_cycle: str
    sex: str
    age_group: str
    race_ethnicity: str = "all"
    race_ethnicity_requested: str = "all"
    race_ethnicity_lookup: str = "all"
    race_stratum_fallback: bool = False
    bracket_low_pct: float | None = None
    bracket_high_pct: float | None = None


def _interpolate_percentile(
    query_value: float,
    knot_values: np.ndarray,
) -> tuple[float, float | None, float | None]:
    """Map *query_value* onto [0, 100] via linear interpolation.

    Parameters
    ----------
    query_value
        Concentration in ng/mL.
    knot_values
        Seven ascending concentration values at p5..p95.

    Returns
    -------
    (percentile, bracket_low_pct, bracket_high_pct)
    """
    v = float(query_value)
    vals = np.asarray(knot_values, dtype=np.float64)
    if vals.size != _PERCENTILE_KNOTS.size:
        raise ValueError(f"expected {len(_PERCENTILE_KNOTS)} knot values, got {vals.size}")
    if np.any(~np.isfinite(vals)):
        return float("nan"), None, None

    # Below the p5 knot: scale linearly from 0 at v=0 to 5 at v=p5.
    p5 = vals[0]
    if v <= p5:
        if p5 <= 0.0:
            pct = 5.0 if v <= 0.0 else float("nan")
        else:
            pct = max(0.0, min(5.0, 5.0 * v / p5))
        return pct, 0.0, 5.0

    p95 = vals[-1]
    p90 = vals[-2]
    if v >= p95:
        # Above p95: gentle extrapolation capped at 99.
        if p95 > p90:
            extra = min(4.0, 5.0 * (v - p95) / (p95 - p90))
        else:
            extra = 0.0
        return min(99.0, 95.0 + extra), 95.0, 99.0

    for i in range(len(vals) - 1):
        lo_v, hi_v = vals[i], vals[i + 1]
        if lo_v <= v <= hi_v:
            if hi_v == lo_v:
                frac = 0.0
            else:
                frac = (v - lo_v) / (hi_v - lo_v)
            lo_p = float(_PERCENTILE_KNOTS[i])
            hi_p = float(_PERCENTILE_KNOTS[i + 1])
            return lo_p + frac * (hi_p - lo_p), lo_p, hi_p

    return float("nan"), None, None


@dataclass
class ReferenceEngine:
    """Hash-verified lookup engine over the precomputed weighted table.

    Construct with ``ReferenceEngine.load(ontology)``; the engine
    reads the table once, verifies its hash, and indexes rows by
    stratum key.
    """

    ontology: "Ontology"
    reference_table_path: Path
    reference_table_sha256: str
    _table: pd.DataFrame = field(repr=False)
    _index: dict[tuple[str, ...], pd.Series] = field(
        default_factory=dict, repr=False
    )
    _uses_race_strata: bool = field(default=False, repr=False)

    @classmethod
    def load(
        cls,
        ontology: "Ontology",
        reference_table_path: str | Path | None = None,
    ) -> "ReferenceEngine":
        path = Path(
            reference_table_path
            if reference_table_path is not None
            else ontology.expected_reference_table_path
        )
        if not path.is_file():
            raise FileNotFoundError(
                f"Weighted reference table not found at {path}. "
                "Run scripts/build_nhanes_weighted_reference_tables.py first."
            )

        raw = path.read_bytes()
        on_disk_hash = hashlib.sha256(raw).hexdigest()
        expected = ontology.expected_reference_table_sha256.lower()
        if on_disk_hash.lower() != expected:
            raise ReferenceTableDrifted(
                f"Reference table at {path} has SHA-256 {on_disk_hash}, "
                f"expected {expected}. Rebuild with "
                "scripts/build_nhanes_weighted_reference_tables.py and "
                "update the ontology pin if the rebuild was intentional."
            )

        table = pd.read_csv(path)
        required_cols = {
            "cycle",
            "analyte_id",
            "sex",
            "age_group",
            "n_unweighted",
            "pct_below_lod",
            *_PERCENTILE_COLUMNS,
        }
        missing = required_cols - set(table.columns)
        if missing:
            raise ReferenceTableDrifted(
                f"Reference table at {path} is missing columns: {sorted(missing)}"
            )

        if "weighted" in table.columns and not table["weighted"].astype(bool).all():
            raise ReferenceTableDrifted(
                f"Reference table at {path} is not marked weighted=True throughout. "
                "V1 requires the official weighted table, not the unweighted peer."
            )

        uses_race = "race_ethnicity" in table.columns
        engine = cls(
            ontology=ontology,
            reference_table_path=path,
            reference_table_sha256=on_disk_hash,
            _table=table,
            _uses_race_strata=uses_race,
        )
        for _, row in table.iterrows():
            key: tuple[str, ...] = (
                str(row["cycle"]),
                str(row["analyte_id"]),
                str(row["sex"]),
                str(row["age_group"]),
            )
            if uses_race:
                key = (*key, str(row["race_ethnicity"]))
            engine._index[key] = row
        return engine

    def _get_row(
        self,
        *,
        cycle: str,
        analyte_id: str,
        sex: str,
        age_group: str,
        race_ethnicity: str = "all",
    ) -> pd.Series:
        key: tuple[str, ...] = (cycle, analyte_id, sex, age_group)
        if self._uses_race_strata:
            key = (*key, race_ethnicity)
        row = self._index.get(key)
        if row is None:
            detail = (
                f"cycle={cycle!r}, analyte_id={analyte_id!r}, sex={sex!r}, "
                f"age_group={age_group!r}"
            )
            if self._uses_race_strata:
                detail += f", race_ethnicity={race_ethnicity!r}"
            raise ReferenceStratumMissing(
                f"No precomputed reference row for {detail}. "
                f"Available cycles: {self.ontology.reference_cycles_available}"
            )
        return row

    def percentile(
        self,
        analyte_id: str,
        query_value_ng_per_mL: float,
        *,
        cycle: str | None = None,
        sex: str = "all",
        age_group: str = "all_ages",
        race_ethnicity: str = "all",
        race_ethnicity_requested: str | None = None,
        weighted: bool = True,  # noqa: ARG002 - always weighted; kept for API compat
    ) -> PercentileResult:
        """Return percentile context for one query concentration.

        Parameters
        ----------
        analyte_id
            One of the four ontology analyte_ids.
        query_value_ng_per_mL
            Serum concentration in ng/mL.
        cycle
            NHANES cycle label (I, J, P). Defaults to
            ``ontology.default_reference_cycle`` (J).
        sex
            ``male``, ``female``, or ``all``.
        age_group
            One of ``12-19``, ``20-39``, ``40-59``, ``60_plus``,
            ``all_ages``.
        race_ethnicity
            V1.1+ race/ethnicity label or ``all``.
        weighted
            Ignored (always True). Present so callers written against
            the earlier runtime-compute API do not break.
        """
        if not self.ontology.is_in_scope(analyte_id):
            raise KeyError(
                f"Analyte {analyte_id!r} not in V1 ontology. "
                "The applicability validator should have refused this row."
            )

        use_cycle = cycle if cycle is not None else self.ontology.default_reference_cycle
        if use_cycle not in self.ontology.reference_cycles_available:
            raise ReferenceStratumMissing(
                f"Cycle {use_cycle!r} is not in reference_cycles_available "
                f"{self.ontology.reference_cycles_available}"
            )

        from .race_strata_policy import race_stratum_fallback as _race_fallback

        lookup_race = race_ethnicity
        requested_race = (
            race_ethnicity_requested
            if race_ethnicity_requested is not None
            else race_ethnicity
        )

        row = None
        resolved_sex = sex
        resolved_age = age_group
        resolved_race = lookup_race if self._uses_race_strata else "all"

        if self._uses_race_strata:
            from .strata import stratum_lookup_candidates_v1_1

            candidates = stratum_lookup_candidates_v1_1(
                sex, age_group, lookup_race
            )
            for cand_sex, cand_age, cand_race in candidates:
                try:
                    row = self._get_row(
                        cycle=use_cycle,
                        analyte_id=analyte_id,
                        sex=cand_sex,
                        age_group=cand_age,
                        race_ethnicity=cand_race,
                    )
                    resolved_sex = cand_sex
                    resolved_age = cand_age
                    resolved_race = cand_race
                    break
                except ReferenceStratumMissing:
                    continue
        else:
            from .strata import stratum_lookup_candidates

            for cand_sex, cand_age in stratum_lookup_candidates(sex, age_group):
                try:
                    row = self._get_row(
                        cycle=use_cycle,
                        analyte_id=analyte_id,
                        sex=cand_sex,
                        age_group=cand_age,
                    )
                    resolved_sex = cand_sex
                    resolved_age = cand_age
                    break
                except ReferenceStratumMissing:
                    continue

        if row is None:
            msg = (
                f"No precomputed reference row for cycle={use_cycle!r}, "
                f"analyte_id={analyte_id!r} after stratum fallback "
                f"(requested sex={sex!r}, age_group={age_group!r}"
            )
            if self._uses_race_strata:
                msg += f", race_ethnicity_lookup={lookup_race!r}"
            raise ReferenceStratumMissing(msg + ").")

        did_race_fallback = (
            self._uses_race_strata
            and _race_fallback(lookup_race=lookup_race, resolved_race=resolved_race)
        )

        knot_values = np.array(
            [float(row[c]) for c in _PERCENTILE_COLUMNS],
            dtype=np.float64,
        )
        pct, br_lo, br_hi = _interpolate_percentile(
            float(query_value_ng_per_mL), knot_values
        )

        n_reference = int(row["n_unweighted"])
        n_weighted = (
            float(row["n_weighted"]) if "n_weighted" in row.index else None
        )
        pct_below_lod = float(row["pct_below_lod"])
        # Fraction in [0,1] in the table; expose as percent for the
        # result object to match the earlier anchor-CSV engine.
        pct_below_lod_pct = pct_below_lod * 100.0 if pct_below_lod <= 1.0 else pct_below_lod

        imputed_value: float | None
        if pct_below_lod >= 0.5:
            imputed_value = float(row["p50"])
        else:
            imputed_value = None

        query_below_imputed = bool(
            imputed_value is not None
            and float(query_value_ng_per_mL) <= imputed_value
        )

        percentile_out: float | None
        if not np.isfinite(pct):
            percentile_out = None
        else:
            percentile_out = float(pct)

        return PercentileResult(
            analyte_id=analyte_id,
            query_value_ng_per_mL=float(query_value_ng_per_mL),
            percentile=percentile_out,
            n_reference=n_reference,
            n_weighted=n_weighted,
            pct_below_lod_reference=float(pct_below_lod_pct),
            imputed_below_lod_value_ng_per_mL=imputed_value,
            query_below_imputed_lod=query_below_imputed,
            weighted=True,
            reference_cycle=use_cycle,
            sex=resolved_sex,
            age_group=resolved_age,
            race_ethnicity=resolved_race,
            race_ethnicity_requested=requested_race,
            race_ethnicity_lookup=lookup_race,
            race_stratum_fallback=did_race_fallback,
            bracket_low_pct=br_lo,
            bracket_high_pct=br_hi,
        )

    @staticmethod
    def verify_anchor_csv(ontology: "Ontology", anchor_csv_path: str | Path | None = None) -> str:
        """Verify the frozen cycle-J anchor CSV hash (provenance chain).

        Returns the on-disk SHA-256. Raises ``ReferenceAnchorDrifted``
        if the hash disagrees with ``ontology.expected_anchor_csv_sha256``.
        This is separate from the weighted table check and is intended
        for provenance logging, not percentile lookup.
        """
        path = Path(
            anchor_csv_path
            if anchor_csv_path is not None
            else ontology.expected_anchor_csv_path
        )
        if not path.is_file():
            raise FileNotFoundError(f"Anchor CSV not found at {path}")
        on_disk = hashlib.sha256(path.read_bytes()).hexdigest()
        expected = ontology.expected_anchor_csv_sha256.lower()
        if on_disk.lower() != expected:
            raise ReferenceTableDrifted(
                f"Anchor CSV at {path} has SHA-256 {on_disk}, expected {expected}."
            )
        return on_disk
