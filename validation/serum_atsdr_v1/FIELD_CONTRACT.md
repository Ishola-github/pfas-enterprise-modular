# ATSDR serum field contract (v1)

Fields to extract or map when harmonizing **PFAS Exposure Assessment** row-level serum data.
Summary-only site tables do not satisfy this contract unless explicitly labeled as summary lane.

---

## Required (ingest blocked without)

| Field | Importance | Governed column / notes |
|-------|------------|-------------------------|
| Serum PFAS concentration | CRITICAL | `result_value` |
| Analyte name | CRITICAL | `analyte` — crosswalk to PFOS/PFOA/PFHxS/PFNA isomers where applicable |
| Units | CRITICAL | `result_unit` — typically ng/mL; refuse if ambiguous |
| Sample matrix | CRITICAL | `sample_matrix` — serum or plasma |
| Cohort / site identifier | HIGH | `cohort_id` or `source_site` |
| Collection year or window | HIGH | `collection_year` / `collection_cycle` |
| LOD / censored flag | HIGH | `lod_code` or `below_lod` per lane policy |
| Record provenance | HIGH | source file, row ID, download SHA |

---

## Strongly preferred (V1.1-style strata)

| Field | Importance | Notes |
|-------|------------|-------|
| Age | HIGH | `age_years` for stratum alignment with NHANES |
| Sex | HIGH | harmonize to NHANES coding where possible |
| Race/ethnicity | HIGH | publish category crosswalk; do not assume NHANES 1:1 |
| PFOS / PFOA / PFHxS / PFNA | HIGH | primary analytes in EA program |
| Exposure site / community | HIGH | for cohort labeling and reports |
| Drinking-water linkage | HIGH | separate env fields; optional join key only |
| Household exposure variables | MEDIUM | document if used; no causal claims |

---

## Allowed analytical uses (post-ingest)

| Use | Allowed |
|-----|---------|
| Cohort contextualization vs NHANES percentiles | Yes |
| Elevated-exposure comparison / deviation scoring | Yes |
| Percentile shift and cross-cohort tables | Yes |
| Exposure clustering / hotspot profiling (RUO) | Yes |
| Demographic-normalized contrast | Yes |
| Temporal cohort analysis (if year metadata present) | Yes |
| Disease prediction / outcome ML | **No** |
| Black-box ML / ungoverned training | **No** |
| Health outcome inference | **No** |
| Pooling into NHANES reference builders | **No** |

---

## Output path (after harmonization)

1. Run ATSDR-specific contextualization (separate ontology pin) **or**
2. Produce governed cohort summary CSV → compare to NHANES via `validation/serum_multi_reference_v1/` (planned).

All outputs: manifest + SHA-256 + RUO labeling.
