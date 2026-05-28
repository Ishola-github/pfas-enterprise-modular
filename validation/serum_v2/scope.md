# V2 scope — cross-cycle temporal contextualization

## Question V2 answers

> For this serum PFOS/PFOA concentration and demographic stratum, how does
> **population-referenced percentile context** differ across NHANES cycles
> **I (2015–2016)**, **J (2017–2018)**, and **P (2017–2020 pre-pandemic)**?

V2 answers that using the **same precomputed weighted reference table** as V1.1.
It does **not** follow the same person across time (NHANES is cross-sectional).

## Inputs (inherits V1.1 + one requirement)

Same governed columns as V1.1, with **`reference_cycle` required** on every row
(anchor cycle for primary interpretation — usually `J`).

## Outputs (per in-domain row)

| Field | Description |
|-------|-------------|
| `anchor_cycle` | Input `reference_cycle` |
| `percentile_cycle_I` / `_J` / `_P` | Percentile of `result_value` vs that cycle's reference stratum |
| `anchor_percentile` | Percentile in anchor cycle (equals matching cycle column) |
| `percentile_delta_J_minus_I` | `percentile_J - percentile_I` when both defined |
| `percentile_delta_P_minus_J` | `percentile_P - percentile_J` when both defined |
| `reference_p50_cycle_*` | Stratum median (p50 knot) per cycle |
| `ratio_to_p50_cycle_*` | `result_value / p50` per cycle |
| `temporal_context_flag` | Semicolon-separated governance flags |
| V1.1 columns | Anchor-cycle sex/age/race strata, LOD flags (via embedded V1 row) |

## Temporal flags

| Flag | Meaning |
|------|---------|
| `cross_cycle_percentile_shift_ge_15` | \|Δ percentile\| ≥ 15 points between adjacent cycles |
| `cross_cycle_stratum_incomplete` | One or more cycles lacked a reference stratum |
| `cycle_P_pre_pandemic_caveat` | Cycle P uses `WTSBAPRP`; not directly comparable to I/J weights without analyst review |

## Explicit non-goals (see `limitations.md`)

- Individual longitudinal trajectories
- Causal attribution of temporal change
- Regulatory trend compliance

## Cohort summary extension (v2 report post-processing)

V2 cohort summaries are computed from governed `v2_report_<run_id>.csv` outputs
using `python -m src.v2.cohort_cli`.

This extension produces subgroup aggregates (analyte x sex x age x race) and
keeps the same RUO and non-claim boundaries as V2 row-level outputs.
