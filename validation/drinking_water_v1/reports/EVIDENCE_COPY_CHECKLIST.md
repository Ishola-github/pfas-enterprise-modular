# Evidence to copy into `validation/drinking_water_v1/`

Copy from the **same** workflow you are freezing (evidence-governed: `results/`; exploratory screening: `results/screening/`). Prefer **hashes + small manifests** in git; keep large CSVs local or under `datasets/` with `.gitignore` as needed.

## Core files

| Source (typical path) | Copy to | Why |
| --------------------- | ------- | --- |
| `results/nhanes_model_metrics.json` or `results/nhanes_model_metrics_*.json` | `artifacts/` | Metrics evidence |
| `results/nhanes_model_metrics_by_task.json` (if present) | `artifacts/` | Task-level metrics |
| `results/nhanes_test_predictions.csv` (if present) | `artifacts/` or `datasets/` | Prediction audit trail |
| `results/nhanes_feature_importance.csv` (if present) | `artifacts/` | Explainability |
| `results/holdout_probability_debug.json` (if present) | `artifacts/` | Probability audit |
| `results/label_derivation_audit.json` (train script **3.2.4+**) | `artifacts/` | Label derivation traceability (NHANES serum quantile burden or future UCMR audits) |
| `data/training/ucmr_exceedance_manifest.json` or `data/training/screening/ucmr_exceedance_manifest.json` | `artifacts/` | ETL / training-table provenance |
| `results/last_train_workflow_context.json` | `artifacts/` | Workflow traceability (screening vs evidence-governed) |

For **screening** runs, mirror paths under `results/screening/` and `data/training/screening/` as applicable.

## Visual evidence

| Source | Copy to |
| ------ | ------- |
| ML results panel, disclaimers, workflow badges | `screenshots/` (PNG/JPG) — see `../screenshots/README.md` for drag/drop steps |

## Recordkeeping

1. Compute **SHA-256** for the whole frozen bundle in one step: from project root run **`scripts/write_run_hashes.ps1 -RunId <run_id>`** (writes `runs/<run_id>/hashes.txt`; optional **`-UpdateManifest`**). If execution policy blocks `.ps1`, use **`scripts/write_run_hashes.cmd`** with the same arguments. See `runs/_TEMPLATE/README.md`.
2. Or compute hashes per file manually and store in `runs/<run_id>/manifest.json` (see `runs/_TEMPLATE/`).
3. Note **threshold**, **R/Python/git versions**, and **which `results/` subtree** in the same manifest.
