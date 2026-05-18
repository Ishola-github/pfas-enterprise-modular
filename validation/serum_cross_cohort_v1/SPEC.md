# Cross-cohort contextualization spec (v1)

## Objective

Compare two governed cohort summary outputs using the same key strata:

- analyte
- sex_stratum
- age_group_stratum
- race_ethnicity_stratum

This supports external validation questions such as:
"How does exposed cohort context differ from NHANES baseline context?"

## Inputs

Two CSVs, each produced by governed cohort summarization flow
(`src.v2.cohort_cli` or equivalent contract-compliant process).

## Output

One manifest-backed comparison table with:

- aligned rows (outer-join on key strata),
- per-side metrics,
- deltas (`right - left`) for selected metrics,
- row provenance category: `both`, `left_only`, `right_only`.

## Governance constraints

1. No raw data ingestion in this lane.
2. No clinical, diagnostic, or regulatory claims.
3. No causal inference claims.
4. No silent schema mutation; required columns are schema-locked.
5. All runs emit manifest + SHA256.

## Default delta set

- `delta_n_rows`
- `delta_median_result_value`
- `delta_median_anchor_percentile`
- `delta_shift_ge_15_pct`

## Promotion gate from scaffold to active

Before active use with external cohorts:

1. At least one non-NHANES cohort summary with pinned manifest is available.
2. Schema contract remains unchanged or version-bumped with migration note.
3. Docker/PowerShell parity check passes with deterministic run_id behavior.
