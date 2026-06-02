# Reviewer Instructions v1

## Purpose
This packet supports blinded external review for the study:
"External Blinded Validation of Automated EPA 1633 PFAS QA/QC Review."

## Reviewer Role
You are asked to independently evaluate PFAS EPA 1633 QA/QC batches and assign
batch-level pass/fail outcomes with reason codes.

Do not coordinate with other reviewers during scoring.

## Blinding Rules
- Do not access automated engine outputs before completing your review.
- Do not share decisions with other reviewers during the blinded phase.
- Do not modify the provided batch records.

## Materials Provided
- Batch files (CSV/JSON) with QA/QC fields
- Case report form template:
  `validation/protocols/epa1633_qaqc_case_report_form_v1.csv`
- Reason code glossary in this document

## Required Decision Fields per Batch
- `review_decision`: pass | fail
- `primary_reason_code`
- `secondary_reason_code` (optional)
- `review_time_minutes`
- `reviewer_confidence` (1-5)
- `notes`

## Reason Code Glossary
- `method_blank_failed`
- `calibration_failed`
- `recovery_gate_failed`
- `duplicate_rpd_out_of_range`
- `mdl_loq_missing_or_invalid`
- `holding_time_failed`
- `batch_id_inconsistency`
- `insufficient_information`
- `other`

## Decision Guidance
Apply laboratory-standard EPA 1633 QA/QC expectations and your institutional
SOP interpretation. Use `insufficient_information` when required fields are
missing and a confident decision is not possible.

## Confidence Scale
- 1: very low confidence
- 2: low confidence
- 3: moderate confidence
- 4: high confidence
- 5: very high confidence

## Submission Instructions
- Complete one row per batch in the case report form.
- Save completed form as:
  `epa1633_qaqc_case_report_form_<reviewer_id>_v1.csv`
- Return only completed forms; do not include interim comments in external
  channels during blinding.

## Conflict of Interest
Disclose any direct involvement in generating the evaluated batches before
participating.

## Contact
For data integrity questions (not interpretation questions), contact study
coordinator listed in the pilot packet.
