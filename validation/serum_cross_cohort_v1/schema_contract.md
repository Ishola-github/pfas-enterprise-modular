# Schema contract — serum cross-cohort comparator (v1)

## Input schema (both left and right summaries)

Required columns:

- `analyte` (string)
- `sex_stratum` (string)
- `age_group_stratum` (string)
- `race_ethnicity_stratum` (string)
- `n_rows` (int)
- `median_result_value` (float)
- `median_anchor_percentile` (float)
- `shift_ge_15_pct` (float)

## Output schema

Key columns:

- `analyte`
- `sex_stratum`
- `age_group_stratum`
- `race_ethnicity_stratum`

Per-side metrics:

- `left_n_rows`, `right_n_rows`
- `left_median_result_value`, `right_median_result_value`
- `left_median_anchor_percentile`, `right_median_anchor_percentile`
- `left_shift_ge_15_pct`, `right_shift_ge_15_pct`

Derived deltas:

- `delta_n_rows`
- `delta_median_result_value`
- `delta_median_anchor_percentile`
- `delta_shift_ge_15_pct`

Join provenance:

- `row_source` in `{both,left_only,right_only}`

## Manifest requirements

Comparator run manifest must include:

- left and right input paths + SHA256 + size,
- output CSV path + SHA256 + size,
- labels (`left_label`, `right_label`),
- overview counts for matched/left_only/right_only rows,
- code version, run_id, timestamp_utc.
