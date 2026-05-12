# Repeatability Execution Status (v1)

Date: 2026-05-11  
Base run: `v1-dw-20260510-freeze`

## Executed Artifacts

- Repeatability scaffold folder:
  - `validation/drinking_water_v1/runs/v1-dw-20260510-freeze-repeatability-20260511-005846`
- Evidence report:
  - `validation/drinking_water_v1/runs/v1-dw-20260510-freeze-repeatability-20260511-005846/REPEATABILITY_EVIDENCE_REPORT_v1.md`
- Evidence JSON:
  - `validation/drinking_water_v1/runs/v1-dw-20260510-freeze-repeatability-20260511-005846/repeatability_evidence.json`

## Current Findings

- Hash comparison across 3 repeats:
  - `manifest.json` stability: PASS
  - `hashes.txt` stability: PASS
- Metric drift comparison:
  - PASS (`REPEATABILITY_SUMMARY_EXECUTED_v1.md` shows exact metric match across all 3 runs)

## Verdict

`PASS` for 3-run artifact + scientific metric repeatability at the configured seed and threshold.

Interpretation: governance artifact stability and model metric repeatability are both demonstrated for this frozen execution profile.

## Evidence Files

- `validation/drinking_water_v1/runs/v1-dw-20260510-freeze-repeatability-20260511-005846/REPEATABILITY_SUMMARY_EXECUTED_v1.md`
- `validation/drinking_water_v1/runs/v1-dw-20260510-freeze-repeatability-20260511-005846/REPEATABILITY_EVIDENCE_REPORT_v1.md`
- `validation/drinking_water_v1/runs/v1-dw-20260510-freeze-repeatability-20260511-005846/repeatability_evidence.json`

## Next Step

Run the same protocol on an independent clean machine/operator and compare outputs against this baseline evidence set.

Conservative scope: screening / prioritization / governance platform repeatability only.
