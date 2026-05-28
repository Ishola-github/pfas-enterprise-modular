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

Full field priorities: `FIELD_CONTRACT.md`.  
Download targets: `ACQUISITION_TARGETS.md`.

**Required** before contextualization:

- serum PFAS concentration, analyte, units, matrix
- cohort/site identifier, collection year/window, LOD flags
- record-level provenance (source file + SHA)

**Strongly preferred:** sex, age, race/ethnicity, PFOS/PFOA/PFHxS/PFNA, water-source linkage.

**Allowed uses:** cohort contextualization, NHANES deviation scoring, percentile shift,
exposure clustering, hotspot profiling (RUO).

**Forbidden:** disease prediction, black-box ML, health-outcome inference, pooling into NHANES reference tables.
