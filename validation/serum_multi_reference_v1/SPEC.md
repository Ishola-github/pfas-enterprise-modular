# Multi-reference percentile comparison — technical spec (v1)

## Problem statement

Institutional users need to answer:

> How elevated is this cohort relative to **U.S. population (NHANES)** and relative to
> **known exposed communities (ATSDR)** — and optionally **Europe (HBM4EU)** — under
> governed, reproducible rules?

This is **not** disease prediction. It is **cross-reference exposure contextualization**.

## Inputs (v1 planned)

| Input | Source | Required |
|-------|--------|----------|
| Governed serum rows or cohort summary | User upload or prior CLI output | Yes |
| NHANES reference table pin | `nhanes_pfas_weighted_reference_tables_v1_1.csv` | Yes |
| ATSDR reference artifact pin | TBD post-acquisition | No (until lane active) |
| HBM4EU reference artifact pin | TBD post-harmonization | No (until lane active) |
| Strata definition | sex, age_group, race_ethnicity, analyte | Yes |

## Outputs (v1 planned)

One manifest-backed table per run:

| Column group | Example columns |
|--------------|-----------------|
| Keys | `analyte`, `sex_stratum`, `age_group_stratum`, `race_ethnicity_stratum`, `cohort_label` |
| NHANES | `nhanes_median_percentile`, `nhanes_p75`, `nhanes_exceed_p90_flag` |
| ATSDR | `atsdr_median_percentile`, `atsdr_nhanes_delta_percentile` |
| HBM4EU | `hbm4eu_median_percentile`, `hbm4eu_nhanes_delta_percentile` |
| Deviation | `max_cross_reference_spread`, `interpretation_band_ruo` |

Exact column list frozen in `schema_contract.json` before implementation.

## Processing rules

1. **Never pool** NHANES + ATSDR + HBM4EU into one reference distribution.
2. Compute percentiles **per reference layer** using that layer's pinned table only.
3. Refuse rows outside each layer's applicability domain independently.
4. Emit one `multi_reference_manifest_<run_id>.json` with all input/output SHAs.
5. Deterministic `run_id` from hashed inputs + reference pins + code version.

## Implementation phases

| Phase | Deliverable | Dependency |
|-------|-------------|------------|
| 0 | This spec + schema contract | — |
| 1 | NHANES-only multi-strata deviation export (extends cohort summary) | Operational |
| 2 | ATSDR reference table + percentile join | `serum_atsdr_v1` P0 ingest |
| 3 | HBM4EU harmonized reference pin | `serum_hbm4eu_v1` harmonization |
| 4 | Shiny read-only panel | Phases 1–2 stable |

## Non-goals (v1)

- Automated health risk scoring
- Litigation outcome prediction
- Mixing environmental (UCMR5) rows into serum percentile engine
- Training ML models on pooled multi-reference tables

## Promotion gate (scaffold → active)

1. ATSDR P0 row-level data ingested with registry pins.
2. Schema-lock test for output columns.
3. Docker + PowerShell parity on canonical fixture.
4. `limitations.md` and `intended_use.txt` approved.
