# External blind validation — results summary (v1)

**Status:** Draft — complete after running the frozen model on an independent dataset.

## Integrity statements (required)

- [ ] **No retraining** on the external dataset.
- [ ] **No threshold tuning** on the external dataset; threshold **τ** fixed to **`reports/FREEZE_v1.md`** (currently **0.25**).
- [ ] **No cherry-picking** of rows after seeing outcomes (document any **pre-declared** inclusion filters).

## Source dataset

| Field | Value |
| ----- | ----- |
| Dataset name | |
| Publisher / program | (e.g. state groundwater / GAMA-style release) |
| Download URL | |
| Download date | |
| License / use terms | |
| Files on disk (under `../data/`) | |
| SHA-256 (per file) | |

## Applicability

- **Matrix:** (e.g. groundwater vs finished drinking water — note any gap vs **`applicability_domain.txt`**)
- **Methods / analyte list:** |
- **Units handled:** |
- **Rows excluded** (pre-declared rule only) | |

## Model and threshold

| Field | Value |
| ----- | ----- |
| Frozen product / freeze doc | `reports/FREEZE_v1.md` |
| Decision threshold τ | 0.25 (must match freeze) |
| Model artifact / version | (as deployed for prediction-only run) |

## Metrics (external evaluation)

*Fill only if **labeled** external outcomes exist; otherwise report **prediction distribution** and qualitative review.*

| Metric | Value |
| ------ | ----- |
| n (scored) | |
| Confusion matrix [TN, FP; FN, TP] | |
| Recall | |
| Precision | |
| NPV | |
| Specificity | |
| FPR (among negatives) | |

## Observed failures and limitations

- Applicability-domain warnings:
- Schema / unit rejects:
- Analyst interpretation notes:

## Conclusion (screening only)

One paragraph: what external stress-test shows, what degraded vs internal holdout, and **explicit** statement that this does **not** constitute regulatory compliance validation or ISO 17025 analytical proof.

## Artifacts

| Artifact | Path |
| -------- | ---- |
| Predictions CSV | `results/...` |
| Screenshots | `../screenshots/` |
| Other | |
