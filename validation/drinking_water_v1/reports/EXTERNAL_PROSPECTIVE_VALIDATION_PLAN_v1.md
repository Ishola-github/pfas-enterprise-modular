# External Prospective Validation Plan (v1)

Purpose: define a pre-registered external validation protocol for the PFAS screening / prioritization / governance workflow after model freeze.

## 1) Scope and Intent

- Evaluate post-freeze performance on externally sourced data not used in development.
- Preserve separation between development and evaluation.
- Produce audit-oriented evidence, not accreditation claims.

## 2) Pre-Registration (Before Scoring)

Record the following before any prediction run:

- Frozen run reference: `v1-dw-20260510-freeze`
- Frozen threshold reference (`FREEZE_v1.md`):
- Model/script commit SHA:
- External dataset source URL(s):
- Retrieval timestamp (UTC):
- Dataset hash(es):
- Inclusion/exclusion rules (predeclared):
- Matrix domain statement:

## 3) Data Acceptance Criteria

Dataset must include (or be mappable to):

- `sample_id`
- matrix indicator
- analyte/value fields required by the prediction path
- units metadata
- date/time or batch context

Reject or quarantine data if:

- schema is unmappable,
- matrix is out of intended scope and not explicitly handled,
- provenance/license cannot be documented.

## 4) Freeze-Lock and No-Retune Policy

Non-negotiable controls:

1. No retraining on prospective data.
2. No threshold sweep or threshold retuning after seeing outcomes.
3. No post hoc row filtering outside predeclared exclusion rules.
4. Any exclusions must be logged with count + reason.

## 5) Third-Party / Independent Execution Checklist

- [ ] Independent operator identified (not primary model developer)
- [ ] Clean-machine runbook followed
- [ ] Commit SHA verified
- [ ] Docker/runtime versions captured
- [ ] Input dataset hash captured before scoring
- [ ] Prediction-only execution confirmed
- [ ] Outputs archived under governed paths

## 6) Evaluation Metrics and Decision Rules

Primary reporting metrics (as available):

- recall
- precision
- specificity
- NPV
- false_positive_rate_negative
- workload proxy (flags per 10k or equivalent)

Decision output:

- `PASS` / `REVIEW` / `FAIL` based on predeclared thresholds in this plan.
- If labels are partial/missing, use `REVIEW` with prediction-only transparency report.

## 7) Output Package

Store in:

- `validation/drinking_water_v1/external_blind/results/`

Required deliverables:

- predictions CSV
- metrics output (if labels available)
- prospective validation summary markdown
- dataset hash log
- applicability-domain notes
- known limitation notes

## 8) Reporting Template (Use in Final Summary)

Include:

- data source and provenance
- frozen model/threshold reference
- execution operator and runtime context
- pass/review/fail outcome with metric table
- exclusions and rationale
- limitation statement

## 9) Conservative Claim Language

Allowed:

- screening / prioritization / governance platform
- reproducibility controls
- reference-data benchmarking
- prospective external evaluation evidence

Not allowed:

- accredited
- certified analytical method
- regulatory-approved decision engine
- compliance automation

## 10) Scientific Limitation Statement

Even with prospective external evaluation, this software evidence package does not itself establish ISO 17025 accreditation, EPA approval, CLIA validation, or replacement of wet-lab LC-MS/MS analytical workflows.
