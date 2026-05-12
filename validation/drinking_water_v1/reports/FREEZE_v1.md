# Official validation freeze — **PFAS Drinking Water Screening v1.0**

This file is the **frozen validation declaration** for the environmental screening workflow package. It ties together intended use, declared threshold, summarized metrics, limitations, artifact references, and governance state. Treat it as the anchor document for sponsors, QA, and internal release notes.

**Validation is only meaningful against a stable target.** Any intentional change to the frozen elements below **voids** this declaration until you bump the version (e.g. v1.1) and re-document evidence.

---

## 1. Intended use (authoritative text)

The legal and product meaning of “what this software is” is stated in:

- **`intended_use.txt`** (same directory as this file)

That text governs claims: **screening / prioritization / triage decision-support** — not EPA method execution, not LC-MS/MS confirmation, not ISO/IEC 17025 analytical reporting, not regulatory compliance determination.

---

## 2. Applicability and limitations

- **In scope:** drinking water; UCMR5-like structures; EPA 533 / 537.1–style data (see **`applicability_domain.txt`**).
- **Out of scope (v1):** serum, sludge, air, tissues, biosolids — do not claim validation there.
- **Interpretation:** High recall at a chosen threshold may imply substantial review burden (false positives); that trade-off is **screening / triage**, not standalone compliance.

Full validation design and checklists: **`../VALIDATION_PLAN.md`**.  
Acceptance criteria table: **`acceptance_criteria_v1.md`**.

---

## 3. Governance state at freeze

| Item | Record here |
| ---- | ----------- |
| **Workflow path** | Evidence-governed (`results/`) **or** screening (`results/screening/`) — must match `artifacts/last_train_workflow_context.json` |
| **Evidence-governed vs exploratory** | No silent mixing; UI and logs must match the path above |
| **UCMR training table** | Default `data/training/` **or** screening `data/training/screening/` — must match `artifacts/ucmr_exceedance_manifest.json` |

---

## 4. Frozen artifact references (v1 evidence bundle)

Relative to **`validation/drinking_water_v1/`**:

| Role | Path |
| ---- | ---- |
| Primary metrics | `artifacts/nhanes_model_metrics.json` |
| Metrics by task | `artifacts/nhanes_model_metrics_by_task.json` |
| Holdout / test predictions | `artifacts/nhanes_test_predictions.csv` |
| Feature list / importance | `artifacts/nhanes_feature_importance.csv` |
| ETL / training provenance | `artifacts/ucmr_exceedance_manifest.json` |
| Workflow traceability | `artifacts/last_train_workflow_context.json` |
| Visual evidence | `screenshots/*.png` (or `.jpg`) |

**Optional (if present in pipeline):** `artifacts/holdout_probability_debug.json`

**Strongly recommended:** add **`runs/<run_id>/manifest.json`** with **SHA-256** for each file above (see **`../runs/_TEMPLATE/`**).

---

## 5. Declared model and threshold (sign-off values)

Values below match the frozen ML results panel and **`artifacts/nhanes_model_metrics.json`** for this v1.0 declaration.

| Field | Value |
| ----- | ----- |
| **Decision threshold (τ)** | P(exceedance) ≥ 0.25 |
| **Recall (holdout)** | 0.933 |
| **Precision (PPV)** | 0.3467 |
| **NPV** | 0.9469 |
| **Specificity** | 0.4049 |
| **FPR among true negatives** | 0.5951 |
| **Group overlap count** | 0 |
| **Confusion matrix [TN, FP; FN, TP]** | [232, 341; 13, 181] |
| **n_train / n_test (evaluation split)** | 2301 / 767 |

If **`model_matrix_task_counts`** totals differ from the evaluation split, note that here:

Task totals differ from the evaluation split because the task matrix aggregates additional multi-task rows beyond the frozen holdout evaluation subset.

---

## 6. Frozen elements (do not change without version bump)

| Element | Rule |
| ------- | ---- |
| **Product name / scope label** | PFAS Drinking Water Screening **v1.0** (this freeze) |
| **Model** | Fixed training snapshot; document git SHA / artifact id in `manifest.json` |
| **Threshold** | Fixed at value in Section 5 |
| **Feature list** | Fixed set; must match `artifacts/nhanes_feature_importance.csv` (or exported model config) |
| **Training / holdout / ETL inputs** | Fixed; hash each file in manifest |
| **Workflow & paths** | As in Section 3 |
| **Disclaimer & intended-use language** | Locked to **`intended_use.txt`** + UI text for this release |

---

## 7. Reproducibility status

| Check | Status |
| ----- | ------ |
| Three identical runs (same inputs, seed, model, threshold) | Pending — see **`REPEATABILITY_v1.md`** |
| Metrics stable across repeats | Pending |

---

## 8. What “change” means

Any intentional change to Section **6** **invalidates** this freeze for formal claims until v1.1 (or later) is declared with a new **`FREEZE_v1.md`** successor (e.g. **`FREEZE_v1_1.md`**) and refreshed artifacts.

---

## 9. Sign-off

| Role | Name | Date |
| ---- | ---- | ---- |
| Technical owner | Sunday Ishola | 2026-05-10 |
| QA / validation | Pending | Pending |

**Freeze effective date:** 2026-05-10

---

*With metrics, predictions, manifests, workflow context, and screenshots under `validation/drinking_water_v1/`, this project is no longer “only a model experiment”; it is the start of a **governed** drinking-water screening workflow evidence package — bounded by intended use and applicability above.*
