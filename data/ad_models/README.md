# Applicability-Domain (AD) models — per-lane, hard refusal

This folder holds one **per-lane** AD model JSON for every matrix pipeline
defined in `data/config/matrix_pipeline_sop.csv`, plus a cross-lane
`index.json` catalog with SHA-256 hashes.

The AD framework enforces **scientifically valid use boundaries** on
predictions, uploads, and downstream training data. Rows outside the
validated envelope of their reference lane are **refused** (not warned).

> _"Prediction refused: outside validated applicability domain."_

That refusal is the design contract.

---

## Files

| File                              | Purpose                                                                 |
|-----------------------------------|-------------------------------------------------------------------------|
| `<lane>/ad_model.json`            | Per-lane AD model with envelope / categorical coverage + provenance     |
| `index.json`                      | Cross-lane catalog (one entry per lane, with `ad_model_sha256`)         |
| `../audit/ad_decisions.jsonl`     | Append-only audit log of every AD decision (one JSON object per row)    |

---

## Lane → AD method mapping

The AD framework refuses to ship a single "universal PFAS AD model". Each
lane has its **own** model, with semantics specific to the data it
represents.

| Lane                 | Method                          | Refusal semantics                                                                                  |
|----------------------|---------------------------------|-----------------------------------------------------------------------------------------------------|
| `drinking_water`     | `per_analyte_envelope_v1`       | UCMR5 finished-water log10 envelope per analyte                                                     |
| `serum`              | `per_analyte_envelope_v1`       | NHANES + SRM 1957 log10 envelope per analyte (ng/mL primary, ug/kg secondary)                       |
| `afff`               | `per_analyte_envelope_v1`       | NIST RM 8690 single-point reference envelope (n=1 per analyte → sparse warnings)                    |
| `methanol_standards` | `per_analyte_envelope_v1`       | NIST RM 8446 single-point calibration-space envelope                                                |
| `air_emissions`      | `per_analyte_envelope_v1`       | EPA OTM-50 stack-gas envelope per analyte (mixed-unit envelope preserves source unit families)      |
| `biosolids_sludge`   | `categorical_coverage_v1`       | Categorical coverage (matrix / state / method / value_type); concentration-claim rows are refused   |

The biosolids lane is intentionally **different**: it contains
program/facility metadata + Method 1633A method metadata, not nationwide
PFAS-in-biosolids concentrations. Its AD model therefore enforces metadata
validity (facility-type, state coverage, method coverage) and **refuses**
any row that claims an analytical concentration in this lane. That refusal
is by design — the analytical biosolids lane has not yet been built.

---

## AD output column contract (added to every gated row)

Every row passed through `scripts/apply_ad_guard.py` is annotated with the
following columns. They are **always present** in the output (added if
missing), regardless of the input schema.

| Column                       | Meaning                                                                    |
|------------------------------|----------------------------------------------------------------------------|
| `ad_status`                  | `in_domain` / `warning` / `reject`                                         |
| `ad_distance`                | log10 |z| envelope distance for value lanes; `inf` for hard rejections     |
| `ad_reason`                  | Human-readable cause (e.g. `value_out_of_range:log10_z=4.21`)              |
| `reference_lane`             | Governing `pipeline_lane`                                                  |
| `training_range_version`     | SHA-256 prefix (12 hex chars) of the lane's training.csv; stable across rebuilds with the same input |
| `ad_model_version`           | Framework semver (currently `1.0.0`)                                       |
| `ad_threshold`               | Reject threshold that was applied (`reject_z` for values; `1.0` categorical) |
| `nearest_training_source`    | Primary source organization for the matched analyte / lane                 |
| `ad_method`                  | `per_analyte_envelope_v1` or `categorical_coverage_v1`                     |

In **strict mode** (default), rows with `ad_status = "reject"` have their
analytical result columns blanked:

```
result_value_raw   ""
result_value_numeric  ""
result_unit        ""
qualifier          ""
mdl                ""
rl                 ""
```

The refusal is propagated into the row, the output CSV, and the audit log.

---

## Refusal rules (value-based lanes)

For `drinking_water`, `serum`, `afff`, `methanol_standards`, `air_emissions`:

1. `analyte` not in training set → **reject** (`analyte_unseen`)
2. `result_unit` not in lane's `unit_set` → **reject** (`unit_mismatch:<unit>`)
3. `qualifier = "ND"` AND no value → **in_domain** (`non_detect_no_concentration_claim`)
4. value missing or non-numeric → **reject** (`invalid_value`)
5. value ≤ 0 → **reject** (`non_positive_value:<v>`)
6. Per-analyte envelope has fewer than 2 detects → **warning** (`sparse_training:n=<n>`)
7. log10 standard deviation == 0 (degenerate single-point envelope):
   - log10(value) outside [log_min, log_max] → **reject** (`zero_std_out_of_range`)
   - else → **in_domain** (`zero_std_match`)
8. `|z| = |log10(v) - log_mean| / log_std`:
   - `z > reject_z` (default 3.0) → **reject** (`value_out_of_range:log10_z=<z>`)
   - `warning_z < z ≤ reject_z` (default 2.0) → **warning** (`value_warning:log10_z=<z>`)
   - else → **in_domain** (`value_in_envelope:log10_z=<z>`)

Log-space envelopes are used because PFAS concentrations span orders of
magnitude (e.g. UCMR5 PFOA detects span ~0.6–19 ng/L). Linear-space stats
are also recorded for transparency.

## Refusal rules (categorical lane: biosolids_sludge)

1. `matrix` not in `categorical.matrix_set` → **reject** (`matrix_mismatch:<m>`)
2. `value_type` ∈ {`field_measurement`, `non-certified`, `certified`} → **reject** (`concentration_claim_in_metadata_lane`) — this lane is governance/enrichment only
3. `state` (uppercased) not in `categorical.state_set` → **reject** (`state_unseen:<s>`)
4. `method_id` not in `categorical.method_set` → **reject** (`method_unseen:<m>`)
5. Else → **in_domain** (`metadata_in_coverage`)

---

## Reproducibility / governance

- Build models from canonical training CSVs:
  ```
  python scripts/build_ad_models.py --lane all
  ```
- Each `ad_model.json` is **deterministic** for a given training input:
  it records the training CSV's SHA-256 and exposes
  `training_range_version = "<sha256[:12]>"` (no build timestamp embedded,
  to keep the registered AD-model hash stable across rebuilds with the
  same data). If the training CSV changes, rebuild the lane's AD model —
  the registry hash will change and downstream gating will pin to the new
  envelope. Build / run timestamps live only in
  `data/audit/ad_decisions.jsonl` where each decision is timestamped.
- Every gated row is appended to `data/audit/ad_decisions.jsonl` with the
  row's SHA-256, the decision fields, and the training-range version, so
  any refusal can be reproduced months later from the audit alone.
- AD model JSONs are registered in
  `data/reference/registry/reference_registry.csv` so they participate in
  the same hash-verification pipeline as everything else
  (`python scripts/verify_reference_registry.py`).

---

## Smoke test

```
Rscript scripts/smoke_ad_enforcement.R
```

Stages synthetic in-domain and out-of-domain rows for every lane, runs
the guard in strict mode, asserts hard-refusal semantics, and verifies
that the audit log was written.

---

## Non-claims

The AD framework supports **safe inference**, not analytical accreditation.
Being `in_domain` means a candidate prediction is **within the same chemical
space as the training set**; it does not guarantee that the prediction is
correct, nor does it substitute for laboratory measurement, ISO/IEC 17025
accreditation, or regulatory approval. Refusals are conservative by design.
