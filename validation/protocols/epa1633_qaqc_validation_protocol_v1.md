# External Blinded Validation Protocol v1

## Study Title
External Blinded Validation of Automated EPA 1633 PFAS QA/QC Review

## Objective
Evaluate whether the PFAS Enterprise QA/QC engine reproduces human EPA 1633
batch-review decisions with high reliability and reduced review time.

## Hypothesis
The automated QA/QC engine achieves:

- >=90% agreement with blinded human reviewers
- Cohen's kappa >=0.80
- >=50% median review-time reduction

## Scope Boundaries

### Included
- EPA Method 1633 PFAS analytical batches
- QA/QC records: calibration checks, blanks, spikes/recoveries, duplicates,
  and holding-time compliance fields
- Batch-level pass/fail decisions with reason codes

### Excluded
- Non-EPA 1633 workflows
- Non-PFAS analytical methods
- Non-target screening workflows
- Human health risk assessment decisions
- Regulatory compliance determinations

## Dataset Plan
- Target batches: 100
- Dataset split:
  - Development/tuning: 40
  - Locked holdout: 20
  - Blinded external validation: 40

All split assignments and source files must be frozen before blinded review
with manifest and SHA256 hashes.

## Reviewer Plan
- Independent blinded reviewers: 2-3
- Reviewers are blinded to model outputs and each other
- Reviewers use a standardized case-report form aligned to QA/QC reason codes

## Endpoints

### Primary Endpoint
Percent agreement between automated and human QA/QC review decisions.

### Secondary Endpoints
- Cohen's kappa coefficient
- False-positive rate
- False-negative rate
- Median review-time reduction
- Reviewer confidence scores (Likert 1-5)

## Statistical Analysis
- Compute percent agreement with 95% confidence intervals
- Compute Cohen's kappa and interpret as:
  - <0.60: weak
  - 0.60-0.79: moderate
  - >=0.80: strong
- Stratify discordance by QC type:
  - method_blank
  - calibration_check
  - ipr/opr/llopr
  - duplicate checks
  - mdl/loq rows
- Perform root-cause analysis on discordant cases

## Blinding and Integrity Controls
- Pre-register protocol version and acceptance thresholds
- Freeze QA/QC rules and method-reference bundle before blinded phase
- No rule edits during blinded scoring
- Preserve request IDs, audit log entries, artifact hashes, and manifests

## Risk Mitigation
- Applicability-domain refusal logic for out-of-scope inputs
- Human-review override maintained for pilot operations
- Transparent reason codes in all automated decisions
- Explicit documentation of limitations

## Deliverables
- Validation report
- Reproducibility package (manifests, hashes, scripts)
- Governance documentation
- SOP mapping documentation
- Reviewer packet and completed blinded review forms

## Go / No-Go Criteria
Go if all three are met:

- >=90% agreement
- kappa >=0.80
- >=50% median review-time reduction

If criteria are not met, publish transparent error analysis and remediation
plan before deployment expansion.
