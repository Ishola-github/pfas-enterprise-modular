# Scope — serum lane ATSDR scaffold (v1)

## Question this lane is expected to answer

> How do exposed-community serum PFAS distributions compare to NHANES
> population-reference contextualization outputs under governed, reproducible
> conditions?

## In scope

- Serum/plasma PFAS data from ATSDR exposure-assessment programs.
- Cohort-level external validation and contrast analysis against NHANES
  contextualization results.
- Manifested ingestion and reproducible transformations with SHA pinning.

## Out of scope

- Replacing or rewriting NHANES weighted reference tables.
- Cross-matrix merges (water/sludge/air/AFFF) without separate governance lane.
- Patient-level medical interpretation or diagnostic recommendations.

## Minimum ingestion contract (pre-implementation)

Required fields before any contextualization:
- analyte identifier
- numeric concentration
- concentration unit
- sample matrix (serum/plasma)
- cohort/site identifier
- record-level or batch-level provenance

Optional but strongly preferred:
- sex
- age
- race/ethnicity (if published)
- collection window and method metadata
