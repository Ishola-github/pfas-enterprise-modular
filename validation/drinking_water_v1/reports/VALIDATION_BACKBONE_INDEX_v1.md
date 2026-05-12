# Validation Backbone Index (v1)

One-page navigation for the PFAS Enterprise 5.0 drinking-water validation backbone.

Scope framing: screening / prioritization / governance platform.

## 1) Governance and Freeze

- Core plan: `validation/drinking_water_v1/VALIDATION_PLAN.md`
- Freeze record: `validation/drinking_water_v1/reports/FREEZE_v1.md`
- Acceptance criteria: `validation/drinking_water_v1/reports/acceptance_criteria_v1.md`
- Product status note: `validation/drinking_water_v1/reports/STRICT_VERDICT_PRODUCT_STATUS.md`

## 2) Deployment and Reproducibility

- Deployment verification: `validation/drinking_water_v1/reports/DEPLOYMENT_VERIFICATION_v1.md`
- Clean-machine runbook: `validation/drinking_water_v1/reports/CLEAN_MACHINE_RUNBOOK_v1.md`
- Independent execution template: `validation/drinking_water_v1/reports/INDEPENDENT_CLEAN_MACHINE_EXECUTION_LOG_TEMPLATE_v1.md`
- Governing run manifest: `validation/drinking_water_v1/runs/v1-dw-20260510-freeze/manifest.json`
- Governing run hashes: `validation/drinking_water_v1/runs/v1-dw-20260510-freeze/hashes.txt`

## 3) Repeatability Evidence (3-Run)

- Protocol/guidance: `validation/drinking_water_v1/reports/REPEATABILITY_v1.md`
- Execution status: `validation/drinking_water_v1/reports/REPEATABILITY_EXECUTION_STATUS_v1.md`
- Launcher script: `validation/drinking_water_v1/scripts/launch_repeatability_3run.ps1`
- Metric summary script: `validation/drinking_water_v1/scripts/summarize_repeatability.py`
- Evidence report generator: `validation/drinking_water_v1/scripts/generate_repeatability_evidence_report.py`
- Executed summary: `validation/drinking_water_v1/runs/v1-dw-20260510-freeze-repeatability-20260511-005846/REPEATABILITY_SUMMARY_EXECUTED_v1.md`
- Evidence report: `validation/drinking_water_v1/runs/v1-dw-20260510-freeze-repeatability-20260511-005846/REPEATABILITY_EVIDENCE_REPORT_v1.md`
- Evidence JSON: `validation/drinking_water_v1/runs/v1-dw-20260510-freeze-repeatability-20260511-005846/repeatability_evidence.json`

## 4) External Blind Evaluation

- External blind overview: `validation/drinking_water_v1/external_blind/README.md`
- Protocol: `validation/drinking_water_v1/reports/EXTERNAL_BLIND_PROTOCOL_v1.md`
- Prospective validation plan: `validation/drinking_water_v1/reports/EXTERNAL_PROSPECTIVE_VALIDATION_PLAN_v1.md`
- Blinded evaluation checklist: `validation/drinking_water_v1/external_blind/forms/BLINDED_EVALUATION_CHECKLIST_v1.md`
- Blind data contract: `validation/drinking_water_v1/external_blind/forms/BLIND_DATA_CONTRACT_v1.md`
- Results template/report: `validation/drinking_water_v1/external_blind/results/EXTERNAL_BLIND_RESULTS_v1.md`
- Run log template: `validation/drinking_water_v1/external_blind/results/EXTERNAL_BLIND_RUN_LOG_v1.md`
- Metric table template: `validation/drinking_water_v1/external_blind/results/EXTERNAL_BLIND_METRIC_TABLE_v1.csv`
- Limitations statement template: `validation/drinking_water_v1/external_blind/results/EXTERNAL_BLIND_LIMITATIONS_v1.md`
- Decision memo template: `validation/drinking_water_v1/external_blind/results/EXTERNAL_BLIND_DECISION_MEMO_v1.md`

## 5) Pilot Reviewer Program

- Pilot overview: `validation/drinking_water_v1/pilot_review/README.md`
- Protocol: `validation/drinking_water_v1/reports/PILOT_REVIEW_PROTOCOL_v1.md`
- Reviewer feedback form: `validation/drinking_water_v1/pilot_review/forms/reviewer_feedback_template.md`
- Session template: `validation/drinking_water_v1/pilot_review/templates/PILOT_REVIEW_SESSION_PLAN_v1.md`
- Observation log template: `validation/drinking_water_v1/pilot_review/templates/PILOT_REVIEW_OBSERVATION_LOG_v1.csv`
- Synthesis template: `validation/drinking_water_v1/pilot_review/templates/PILOT_REVIEW_SYNTHESIS_v1.md`

## 6) Reference and Method Data Pack

Located under `data/reference/`:

- Curated reference registry (paths + SHA-256): `data/reference/registry/reference_registry.csv` — verify with `python scripts/verify_reference_registry.py --project-root .`
- NIST matrix-separated extracts: `data/reference/nist/srm1957/serum_pfas.csv`, `data/reference/nist/rm8446/methanol_pfas.csv`, `data/reference/nist/rm8690/afff_pfas.csv` (bundle: `nist/manifest.json`, `nist/hashes.txt`)
- NIST core reference (extended columns): `data/reference/nist_srm1957_pfas_reference.csv`
- NIST compatibility copies:
  - `data/reference/nist_srm1957_pfas.csv`
  - `data/reference/nist_srm1957_pfas_noncertified.csv`
- Method metadata: `data/reference/epa_1633a_method_metadata.csv`
- QC limits: `data/reference/epa_1633a_qc_limits.csv`
- QC batch schema: `data/reference/epa_1633a_qc_batch_schema.csv`
- Holding times: `data/reference/holding_times.csv`
- Matrix registry: `data/reference/pfas_matrix_registry.csv`
- Contamination controls: `data/reference/contamination_control_rules.csv`

## 7) Supporting Reports

- Validation summary outline: `validation/drinking_water_v1/reports/VALIDATION_SUMMARY_PDF_OUTLINE.md`
- Failure-case checks: `validation/drinking_water_v1/reports/failure_case_validation.md`
- Evidence copy checklist: `validation/drinking_water_v1/reports/EVIDENCE_COPY_CHECKLIST.md`

## Conservative Claim Guardrail

Allowed:

- screening / prioritization / governance platform

Not allowed:

- accredited
- certified
- regulatory-approved
- compliance automation

## Scientific Limitation Note

This package supports reproducibility, traceability, and validation architecture evidence. It does not by itself establish EPA certification, ISO 17025 accreditation, CLIA validation, wet-lab validation, or prospective field validation.
