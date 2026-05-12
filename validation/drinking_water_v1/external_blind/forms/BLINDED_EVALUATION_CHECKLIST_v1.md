# Blinded Evaluation Checklist (v1)

Use this checklist before and during external blind evaluation.

Workflow intent: screening / prioritization / governance platform.

## Freeze and Governance

- [ ] `FREEZE_v1.md` exists and threshold is frozen before scoring.
- [ ] Blind dataset hash recorded before predictions.
- [ ] No threshold sweep planned on blind dataset.
- [ ] No retraining planned on blind dataset.
- [ ] Applicability-domain scope documented.

## Data Handling

- [ ] Data source URL documented with retrieval timestamp.
- [ ] Dataset license/use terms documented.
- [ ] Matrix and method fields preserved.
- [ ] Exclusions predeclared (not post hoc).
- [ ] Label availability documented (full, partial, none).

## Execution Controls

- [ ] Prediction-only flow used (no train action).
- [ ] Script/app version and commit recorded.
- [ ] Runtime environment recorded (Docker/R/Python versions).
- [ ] Outputs saved under `external_blind/results/`.
- [ ] Screenshots saved under `external_blind/screenshots/`.

## Reporting Controls

- [ ] Limitations documented clearly.
- [ ] Applicability-domain warnings documented clearly.
- [ ] Failure cases documented (not hidden).
- [ ] Conservative wording used:
  - [ ] includes "screening / prioritization / governance"
  - [ ] excludes "accredited / certified / regulatory-approved / compliance automation"

## Final Gate

- [ ] `EXTERNAL_BLIND_RESULTS_v1.md` completed.
- [ ] Reviewer/owner sign-off captured.
