# Limitations — serum lane ATSDR scaffold (v1)

| Field | Value |
|-------|-------|
| Lane | serum external-validation cohort (ATSDR) |
| Status | spec scaffold only; no raw ingest yet |
| Purpose | complement NHANES contextualization, not replace it |

## Binding non-claims

- **Not a replacement for NHANES reference distributions.**
- **Not clinical, not diagnostic, not regulatory.**
- **Not causal inference by default.** Cohort association signals require
  epidemiologic design and confounder controls.
- **Not cross-matrix evidence.** Serum lane only.
- **Not automatically harmonized with NHANES race strata.** Any mapping must be
  documented in an ontology or harmonization artifact.

## Required cautions after ingest

- Site-level cohort context, collection protocols, and lab methods may vary.
- Limits of detection and quantitation may differ from NHANES workflows.
- Some ATSDR deliverables are summary-level; row-level microdata availability
  must be verified before model development.
