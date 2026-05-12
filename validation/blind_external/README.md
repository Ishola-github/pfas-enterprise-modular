# Sealed external blind-validation harness

Preregistration-grade external evaluation of PFAS prediction models
against datasets the system has never seen before. Submissions are
**hash-sealed** before any scoring; reveals are **single-shot** and
**immutable**; sealed-byte tampering is **refused** at score time via
SHA-256 verification.

## Ground rules

> No retuning. No threshold change. No model change. No dataset editing
> after hash submission.

These are not aspirations — they are enforced by:

| Rule | Enforcement |
|------|-------------|
| Dataset cannot be edited after seal | `score_blind_validation.py` recomputes the dataset SHA-256 at reveal time and **refuses** (`status: REFUSED`, exit code 3) on mismatch. |
| Manifest cannot be edited after seal | Same — manifest_sha256 is recomputed by canonicalizing the body minus the `manifest_sha256` field; mismatch → refusal. |
| AD policy cannot silently change | `ad_policy_version` is captured at seal time. At reveal time, the live AD model SHA is re-computed; any change is flagged as `ad_policy_drift: true` in `score.json` and `reveals_index.jsonl`. |
| Threshold cannot silently change | Same enforcement for `threshold_version`. |
| Reveal cannot be re-run silently | Once `revealed/<id>/score.json` exists, the scorer returns `ALREADY_REVEALED`. Re-running requires explicit `--force`, the prior reveal is archived as `score_prior_<UTC>.json`, and the action is logged. |

## Folder layout

```
validation/blind_external/
  submissions/         scratch area for staged CSVs before sealing
  sealed/<id>/         dataset.csv + submission.json + SEAL.txt (read-only intent)
  revealed/<id>/       score.json (immutable result) + score_prior_*.json (archived re-scores)
  manifests/
    submissions_index.jsonl   append-only audit log of every seal
    reveals_index.jsonl       append-only audit log of every reveal
```

A submission id has the shape `<lane>_<UTC>_<dataset_sha[:12]>` (e.g.
`drinking_water_20260512T094156Z_23512bf23194`).

## Workflow

### Step 1 — Seal a submission

```bash
python scripts/build_blind_validation_pack.py \
  --input my_external_dataset.csv \
  --lane drinking_water \
  --truth-column truth_label \
  --predicted-score-column predicted_score \
  --predicted-label-column predicted_label \
  --submitted-by "my_lab" \
  --model-version "my_model_v1.2+commit_abc1234" \
  --note "External validation of the calibrated logistic baseline"
```

The packer:

1. Validates the lane against `data/config/matrix_pipeline_sop.csv`.
2. Validates that the truth column (and at least one predicted column)
   exist in the input.
3. Hashes the input dataset → `dataset_sha256`.
4. Hashes the lane's `data/ad_models/<lane>/ad_model.json` → `ad_policy_version`.
5. Hashes the lane's threshold config (currently
   `data/config/ucmr_analyte_limits_ngl.csv` for drinking_water; `"none"`
   for other lanes) → `threshold_version`.
6. Builds the canonical manifest (sorted keys, indented JSON) and
   computes `manifest_sha256` over body minus the manifest_sha256 field.
7. Copies the dataset and writes `submission.json` + `SEAL.txt` into
   `sealed/<submission_id>/`, marks them read-only (advisory on Windows).
8. Appends an entry to `manifests/submissions_index.jsonl`.

### Step 2 — Reveal (score)

```bash
python scripts/score_blind_validation.py --submission-id <submission_id>
```

The scorer:

1. Reads `sealed/<id>/{dataset.csv, submission.json}`.
2. **Verifies** `dataset_sha256` and `manifest_sha256`. Mismatch → `REFUSED` (exit 3).
3. **Re-resolves** `ad_policy_version` and `threshold_version` against
   the current repo state and records any drift in `score.json`.
4. AD-gates the dataset (`apply_ad_guard.py --mode annotate --no-audit`)
   so the metrics are computed on **in-domain rows only**, and the AD
   counts are reported alongside.
5. Computes the nine required metric fields (see below).
6. Writes `revealed/<id>/score.json` (immutable; subsequent re-runs without
   `--force` return `ALREADY_REVEALED`).
7. Appends an entry to `manifests/reveals_index.jsonl`.

## Required manifest fields (sealed `submission.json`)

| Field                    | Source                                                              |
|--------------------------|---------------------------------------------------------------------|
| `submission_id`          | `<lane>_<UTC>_<dataset_sha[:12]>`                                   |
| `dataset_sha256`         | SHA-256 of the submitted CSV                                        |
| `submitted_by`           | Submitter-supplied string                                           |
| `submitted_at`           | UTC ISO timestamp captured at seal time                             |
| `matrix_lane`            | Must match a `pipeline_id` in `data/config/matrix_pipeline_sop.csv` |
| `ad_policy_version`      | SHA-256 of `data/ad_models/<lane>/ad_model.json`                    |
| `model_version`          | Submitter-supplied (semver + commit hash recommended)               |
| `threshold_version`      | SHA-256 of the lane's threshold config, or `"none"`                 |
| `manifest_sha256`        | SHA-256 of the canonicalized manifest body                          |

Provenance / context fields that ride along: `ad_framework_version`,
`training_range_version`, `ad_model_path`, `threshold_path`, `sop_row`,
`n_rows`, `truth_column`, `predicted_score_column`,
`predicted_label_column`, `dataset_path_relative`, `submission_rules`,
`note`.

## Required scoring output (revealed `score.json` → `metrics` block)

All nine fields are **always present** when scoring succeeds:

| Field                  | Source                                                          |
|------------------------|-----------------------------------------------------------------|
| `roc_auc`              | Pairwise Mann-Whitney U on `(truth_label, predicted_score)` over in-domain rows; `null` if no `predicted_score_column` |
| `precision`            | TP / (TP + FP) on in-domain rows with predicted_label            |
| `recall`               | TP / (TP + FN)                                                   |
| `f1`                   | Harmonic mean of precision and recall                            |
| `flags_per_10k`        | (TP + FP) × 10000 / n_scored                                     |
| `FP_per_TP`            | FP / TP (∞ if FP>0 and TP=0; `null` if both 0)                   |
| `ad_reject_count`      | Number of input rows refused by AD guard                         |
| `ad_warning_count`     | Number of input rows warned (sparse training / borderline z)     |
| `ad_in_domain_count`   | Number of in-domain rows that fed the binary metrics             |

The reveal also carries the full sealed manifest, drift flags, the AD
counts dictionary, the confusion matrix, and counts of total / in-domain /
scored rows for transparency.

## Freeze drift

A reveal is still produced if the AD policy or threshold config has
changed since the seal — drift is **not** silent. The reveal records:

```json
"seal_verification": {
  "dataset_sha256_match": true,
  "manifest_sha256_match": true,
  "ad_policy_version_at_reveal": "<sha>",
  "ad_policy_drift": true|false,
  "threshold_version_at_reveal": "<sha>",
  "threshold_drift": true|false
}
"freeze_drift_warnings": ["ad_policy drifted: sealed=<old12> now=<new12>", ...]
```

This is the difference between a scientifically defensible blind-eval
and one that quietly retunes between submission and reveal.

## Smoke test

```bash
Rscript scripts/smoke_blind_validation.R
```

The smoke test runs the full cycle (seal → reveal → re-score refusal →
tamper refusal → indexes) in a scratch project root so it does NOT
write into the canonical `validation/blind_external/` tree. 7/7
assertions PASS as of the last reference build.

## Non-claims

This harness establishes that **the recorded metrics correspond to the
exact data and predictions sealed at submission time** — it does not
make any claim about model goodness, regulatory acceptance, or ISO/IEC
17025 accreditation. The credibility comes from the **discipline of the
freeze**, not from the metrics themselves.
