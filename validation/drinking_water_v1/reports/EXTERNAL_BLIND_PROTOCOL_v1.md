# External blind validation — protocol (v1)

This is the **highest-value** scientific step after internal holdout is frozen: **proof the model generalizes to unseen external PFAS data** — without turning the exercise into another training round.

## Objective

```text
Train on one source; validate on a completely different source; do not change threshold τ.
```

## Non-negotiables

| Do | Do not |
| -- | ------ |
| Keep **τ** exactly as in **`FREEZE_v1.md`** (v1.0: **0.25**) | Threshold sweep or “optimize” on the blind set |
| **Predict / score** only with the frozen model | Retrain or fine-tune on the external file |
| Pre-declare filters (date range, geography) **before** scoring | Cherry-pick rows after seeing predictions |
| Document failures, exclusions, and applicability gaps | Hide silent drops |

## Recommended independent source (v1)

**California PFAS / GAMA-style groundwater (or similar state public PFAS releases)** — geographically and contextually distinct from typical UCMR-centric training; strong regulatory relevance. Verify **license**, **method**, and **matrix** vs **`applicability_domain.txt`**.

**Discovery:** Use official California Water Boards / related program pages; URLs change — record the exact link and retrieval date in **`../external_blind/results/EXTERNAL_BLIND_RESULTS_v1.md`**.

Other credible options: held-out **UCMR** time/utility slices you did **not** use in training; other states’ public drinking-water PFAS databases — same rules apply.

## Folder layout

See **`../external_blind/README.md`**.

- **`external_blind/data/`** — downloads + hash manifest
- **`external_blind/results/`** — predictions, metrics, **`EXTERNAL_BLIND_RESULTS_v1.md`**
- **`external_blind/screenshots/`** — UI and governance captures

## App workflow (conceptual)

1. **Freeze** is already recorded in **`FREEZE_v1.md`**.
2. Use **prediction-only** flow (e.g. “Run PFAS Prediction” / batch equivalent) — **not** the full **train** action.
3. Export predictions CSV and any metrics to **`external_blind/results/`**.
4. Complete **`EXTERNAL_BLIND_RESULTS_v1.md`**.

## Optional run manifest

Create **`runs/external-blind-<slug>/manifest.json`** (copy from **`runs/_TEMPLATE/`**) documenting external file hashes and **τ**; you can hash **`external_blind/`** outputs with **`scripts/write_run_hashes.ps1`** by extending paths later if needed — for v1, manual hashes in the results doc are acceptable.

## What “good” looks like

- Recall / NPV remain **useful for screening** (some modest degradation vs holdout is acceptable if explained).
- Applicability domain and schema checks behave **honestly** (warnings documented).
- Report is **complete** on failures and limitations.

## Deliverable

Honest performance (or honest prediction-only summary if labels are partial) with limitations; **no** claim of regulatory release or ISO 17025 analytical validation.
