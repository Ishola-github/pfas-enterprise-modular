# Limitations — serum lane v1.0

| Field | Value |
| --- | --- |
| Lane | `serum` (human biomonitoring) |
| Anchor | NHANES 2017-2018 PFAS Special Subsample (`PFAS_J.XPT`) |
| Version | 1.0 |
| Companion documents | `intended_use.txt`, `applicability_domain.txt`, `schema_contract.md`, `provenance.md`, `data_dictionary.md` |
| Authority | This file enumerates **non-claims** that bind this lane until a versioned successor is issued |

A bullet labeled **non-claim** is something operators must **not**
assert, even informally. Where a marketing claim or an external
narrative contradicts a non-claim in this document, **this document
wins**.

---

## 1. Not diagnostic, not clinical

- **Non-claim.** Nothing in this lane is a diagnostic result, an
  individual-level clinical interpretation, or a determination of
  PFAS-related disease, deficiency, or risk for any person.
- **Non-claim.** A PFAS serum concentration reported here does
  **not** constitute an individual reference interval, a clinical
  decision limit, a treatment indication, or a basis for
  patient-facing advice.
- **Non-claim.** Population biomonitoring percentiles (median, p95,
  observed max) are population-distribution statistics; they are
  **not** thresholds for individual clinical action.
- **Non-claim.** This lane is **not** a replacement for clinical
  laboratory testing (e.g. CLIA-certified serum PFAS assays for
  occupational or medical surveillance).

## 2. Screening / research only

- **Claim.** Permitted uses are: population-level exploration of
  PFAS serum distributions, applicability-domain boundary checks
  for the serum lane, descriptive contextualization of NHANES
  cycle J results, and reviewer-facing governance evidence.
- **Non-claim.** This lane is **not** validated for any
  regulatory exposure determination (ATSDR MRL adjudication, EPA
  reference-dose application, OSHA biological exposure index,
  state biomonitoring program reporting).
- **Non-claim.** No output of this lane is "EPA-approved",
  "ELAP-certified", "NELAP-certified", "ISO/IEC 17025 accredited",
  or recognized as a regulator-graded assay.

## 3. Not analytical chemistry

- **Non-claim.** This dataset does **not** identify PFAS in any
  biological specimen, does **not** quantify PFAS for compliance,
  and does **not** substitute for the LC-MS/MS isotope-dilution
  workflow that produced the NHANES values upstream.
- **Non-claim.** Re-using these numbers as method-validation
  artifacts for a wet-lab assay is out of scope.

## 4. Not source attribution

- **Non-claim.** Human serum PFAS concentrations describe
  **internal exposure**. They do **not** identify the
  environmental source matrix (drinking water, biosolids, AFFF,
  air emissions, food, occupational contact) that contributed
  any portion of a measured burden.
- **Non-claim.** No regression of serum concentration onto an
  environmental concentration anywhere in this repository
  constitutes a forensic source-attribution claim.

## 5. Not cross-cycle, not a temporal trend

- **Non-claim.** v1.0 is **anchored to a single NHANES cycle (J,
  2017-2018)**. It is **not** a time series. Comparing v1.0
  envelopes to NHANES C (2003-2004), NHANES H/I (2013-2016),
  Pre-pandemic 2017-2020 (`P_PFAS.XPT`), or any future cycle is
  **not authorized** without a separately issued harmonization
  artifact.
- **Non-claim.** Apparent declines in n-PFOA or n-PFOS relative
  to older NHANES literature are **not** inferable from v1.0
  alone; cross-cycle comparison requires `serum_v1.1` or `v2`.

## 6. Not cross-matrix

- **Non-claim.** A serum row cannot be scored against, merged
  with, or used to predict any environmental-matrix lane
  (`drinking_water`, `biosolids_sludge`, `afff`,
  `methanol_standards`, `air_emissions`, `soil_sediment`,
  `fish_tissue`). The matrix-isolation requirement is
  enforced by `schema_contract.md` §5 and refusal condition R5
  in `applicability_domain.txt`.
- **Non-claim.** No "universal PFAS model" pooling matrices is
  authorized by this lane. The architecture refuses that
  collapse at three checkpoints (pipeline, AD, API) per
  `SCOPE_AND_INTENDED_USE.md` §6.

## 7. Below-LOD imputation caveats

- NHANES imputes any value below the analyte's limit of detection
  (LOD) at `LOD / sqrt(2)`. The paired LOD-code column
  (`0` = at/above LOD, `1` = below LOD) is the **only** authoritative
  signal that a value is censored.
- **Non-claim.** A percentile that is at or below the imputed
  LOD value (e.g. an analyte where 41% of respondents are
  censored) is **not** a true population percentile; it is an
  artifact of the imputation rule.
- **Non-claim.** "Fraction detected" or "fraction above LOD"
  metrics computed without consulting the paired LOD column are
  **incorrect** under this contract.
- Two analytes are particularly affected in cycle J:
  - **Sb-PFOA**: ~90% below LOD. Any central-tendency statistic
    for Sb-PFOA is dominated by the imputed value.
  - **Me-PFOSA-AcOH**: ~41% below LOD. p50 is at or below the
    imputed value.

## 8. Sample-weight caveats

- NHANES is a complex multi-stage probability survey. **Unweighted**
  summary statistics are descriptive only; they do **not**
  represent the U.S. civilian non-institutionalized population.
- Any prevalence-style or population-distribution claim **MUST**
  apply the two-year subsample weight `wtsb2yr` (and, where the
  intended statistic requires it, the full NHANES survey-design
  stratum and PSU variables drawn from the NHANES demographics
  file, which are **not** included in `PFAS_J.XPT`).
- **Non-claim.** A weighted mean produced without the design
  strata/PSU is a point estimate without a defensible variance
  estimate; uncertainty bands published without the design are
  unsupported.

## 9. Single-cycle / single-population anchor

- The lane covers the U.S. civilian non-institutionalized
  population aged ≥12 years, in 2017-2018, drawn under the NHANES
  cycle J sampling design.
- **Non-claim.** Inferences about children aged <12, institutionalized
  populations, occupational cohorts, international populations, or
  any non-U.S. population are **not supported** by v1.0.
- **Non-claim.** Inferences about specific U.S. demographic
  subgroups (race/ethnicity, income, geography) require the NHANES
  demographics linkage and the corresponding subgroup variance
  estimation; raw concentration columns alone do not support those
  claims.

## 10. Subjects of NHANES, not subjects here

- NHANES is collected and released by the U.S. CDC / NCHS under
  participant informed consent for **public-use** statistical
  research. Public-use NHANES files are de-identified.
- **Non-claim.** The CDC's release of these files does **not**
  constitute consent for clinical-grade, individual-level, or
  re-identifying use. Operators must not attempt re-identification
  of any respondent.
- **Non-claim.** Inclusion of NHANES in this repository does
  **not** imply CDC, NCHS, NIH, or HHS endorsement of this
  platform or of any model trained on this lane.

## 11. Model status under v1.0

- **Non-claim.** As of this document, the repository **does not**
  ship a production-trained serum classifier.
- **Non-claim.** Any future serum model will not move past the
  promotion gate in `schema_contract.md` §8 without: independent
  reviewer sign-off, recorded scope-freeze hash, and AD refusal
  smoke tests for this lane analogous to the drinking-water
  lane's `smoke_ad_enforcement` battery.

## 12. Provenance limits

- **Non-claim.** Provenance is hash-based (SHA-256), not
  cryptographically signed. The platform provides
  **tamper-evidence**, not non-repudiation or 21 CFR Part 11 /
  GLP digital signatures. See `SCOPE_AND_INTENDED_USE.md` §8.

---

## Summary line (for reviewers)

> The `serum_v1.0` lane is a governance-bounded, NHANES-cycle-J,
> screening/research artifact. It is **not** diagnostic, **not**
> clinical, **not** regulatory, **not** cross-matrix, **not**
> cross-cycle, and **not** a source-attribution tool.
