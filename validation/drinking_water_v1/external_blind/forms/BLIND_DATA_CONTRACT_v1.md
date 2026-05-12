# Blind Data Contract (v1)

This contract defines how an external blind dataset is handled for objective evaluation.

## Purpose

Evaluate generalization of a frozen screening / prioritization / governance workflow on unseen data.

## Required Dataset Fields

| Field | Required | Notes |
|---|---|---|
| `sample_id` | Yes | Stable row identifier |
| `matrix` | Yes | Used for applicability checks |
| `method` | Preferred | Method-aware reporting |
| `input_features_*` | Yes | Model inputs, frozen schema |
| `label` | Preferred | Optional if prediction-only blind run |

## Governance Terms

1. Threshold remains frozen from `FREEZE_v1.md`.
2. No retraining or tuning on blind data.
3. No row filtering after predictions except predeclared exclusion rules.
4. All exclusions must be documented with reason + count.
5. Dataset hash must be captured before scoring.

## Deliverables

- `external_blind/results/predictions_<dataset>.csv`
- `external_blind/results/EXTERNAL_BLIND_RESULTS_v1.md`
- Supporting screenshots in `external_blind/screenshots/`

## Non-Claims

This activity does not establish:

- accreditation
- certification
- regulatory approval
- compliance automation

## Signatures

Data provider: ____________________  
Date: ____________________

Evaluation owner: ____________________  
Date: ____________________
