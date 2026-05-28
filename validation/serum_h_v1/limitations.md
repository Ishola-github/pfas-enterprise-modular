# Limitations — serum_h lane v1.0

| Field | Value |
| --- | --- |
| Lane | `serum_h` (human biomonitoring, NHANES cycle H) |
| Anchor | NHANES 2013-2014 PFAS Special Subsample (`PFAS_H.XPT`) |
| Version | 1.0 (`serum_h_v1`) |
| Companion documents | `intended_use.txt`, `applicability_domain.txt`, `schema_contract.md`, `provenance.md`, `data_dictionary.md` |
| Authority | This file enumerates **non-claims** that bind this lane until a versioned successor is issued |
| Sibling lane (frozen, unaffected) | `serum` v1.0 — `validation/serum_v1/` — its own `limitations.md` governs |

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
  PFAS serum distributions for NHANES cycle H, applicability-domain
  boundary checks for the cycle-H serum lane, descriptive
  contextualization of NHANES cycle H results, and reviewer-facing
  governance evidence.
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

- **Non-claim.** serum_h v1.0 is **anchored to a single NHANES
  cycle (H, 2013-2014)**. It is **not** a time series. Comparing
  cycle-H envelopes to cycle J (`PFAS_J.XPT`, 2017-2018), cycle I
  (`PFAS_I.XPT`, 2015-2016), cycle C (`L06AGE_C.XPT`, 2003-2004),
  Pre-pandemic 2017-2020 (`P_PFAS.XPT`), or any future cycle is
  **not authorized** without a separately issued harmonization
  artifact.
- **Non-claim.** Apparent trends between cycle H and cycle J are
  **not** inferable from this lane alone. The two lanes carry
  different analyte panels and different LLOD regimes (cycle H
  uses a constant 0.10 ng/mL LLOD for every analyte; cycle J uses
  per-analyte LLODs). Even for the five shared analytes (PFDeA,
  PFHxS, MPAH, PFNA, PFUnDA), the below-LOD imputation
  proportions differ substantially.

## 6. Not cross-matrix

- **Non-claim.** A serum_h row cannot be scored against, merged
  with, or used to predict any environmental-matrix lane
  (`drinking_water`, `biosolids_sludge`, `afff`,
  `methanol_standards`, `air_emissions`, `soil_sediment`,
  `fish_tissue`). The matrix-isolation requirement is
  enforced by `schema_contract.md` §5 and refusal condition R5
  in `applicability_domain.txt`.
- **Non-claim.** No "universal PFAS model" pooling matrices is
  authorized by this lane.

## 7. Below-LOD imputation caveats (cycle-H specific)

- NHANES imputes any value below the analyte's limit of detection
  (LOD) at `LOD / sqrt(2)`. With cycle H's constant 0.10 ng/mL
  LLOD, the imputed value is ~`0.0707` ng/mL for **every**
  below-LOD row across **every** analyte.
- The paired LOD-code column (`0` = at/above LOD, `1` = below LOD)
  is the **only** authoritative signal that a value is censored.
- **Non-claim.** A percentile that is at or below the imputed
  LOD value is **not** a true population percentile; it is an
  artifact of the imputation rule.
- **Non-claim.** "Fraction detected" or "fraction above LOD"
  metrics computed without consulting the paired LOD column are
  **incorrect** under this contract.
- Cycle H is **dominated** by below-LOD values for 5 of 8
  analytes. Special caution for:
  - **PFBS**: 96.9% below LOD. Central-tendency statistics for
    PFBS are essentially the imputed value.
  - **PFDoA**: 90.4% below LOD.
  - **PFHpA**: 89.2% below LOD.
  - **MPAH**: 56.4% below LOD.
  - **PFUnDA**: 56.8% below LOD.

## 8. Sample-weight caveats

- NHANES is a complex multi-stage probability survey. **Unweighted**
  summary statistics are descriptive only; they do **not**
  represent the U.S. civilian non-institutionalized population.
- Any prevalence-style or population-distribution claim **MUST**
  apply the two-year subsample weight `wtsb2yr` (and, where the
  intended statistic requires it, the full NHANES survey-design
  stratum and PSU variables drawn from the cycle-H demographics
  file `DEMO_H.XPT`, which are **not** included in
  `PFAS_H.XPT`).
- **Non-claim.** A weighted mean produced without the design
  strata/PSU is a point estimate without a defensible variance
  estimate.

## 9. Label-unit caveat (cycle-H specific)

- The SAS variable labels in `PFAS_H.XPT` annotate every value
  column with `(ug/L)` while the CDC online codebook documents the
  LLOD table in `ng/mL`. The two unit strings denote the same
  numerical scale within method tolerance.
- **Non-claim.** This lane does **not** claim that `ng/mL` and
  `ug/L` are interchangeable for downstream operations outside
  aqueous biological matrices. The equivalence is matrix- and
  density-specific (serum density ~1.025 g/mL).
- **Non-claim.** A downstream user cannot relabel cycle-H values
  as `(ug/L)` **and** multiply by a unit-conversion factor. That
  is double conversion and is refused under R6 in
  `applicability_domain.txt`.

## 10. Isomer-resolved companion file (SSPFAS_H.XPT) is not admitted here

- The cycle-H surplus-serum isomer file `SSPFAS_H.XPT` carries
  the n-/Sb- PFOA and n-/Sm- PFOS split that cycle J carries
  directly. It is **recorded** by SHA-256 in `provenance.md` §3.1
  and **not** admitted under this anchor.
- **Non-claim.** A row that simultaneously cites an isomer-resolved
  analyte (n-PFOA, Sb-PFOA, n-PFOS, Sm-PFOS) and an analyte from
  the cycle-H 8-member panel is **not** authorized under
  serum_h_v1; admission of the isomer split requires a follow-up
  artifact (`schema_contract.md` §7.1).

## 11. Single-cycle / single-population anchor

- The lane covers the U.S. civilian non-institutionalized
  population aged ≥12 years, in 2013-2014, drawn under the NHANES
  cycle H sampling design.
- **Non-claim.** Inferences about children aged <12,
  institutionalized populations, occupational cohorts,
  international populations, or any non-U.S. population are **not
  supported** by serum_h v1.0.
- **Non-claim.** Inferences about specific U.S. demographic
  subgroups (race/ethnicity, income, geography) require linkage
  to `DEMO_H.XPT` and the corresponding subgroup variance
  estimation; raw concentration columns alone do not support
  those claims.

## 12. Subjects of NHANES, not subjects here

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

## 13. Model status under serum_h v1.0

- **Non-claim.** As of this document, the repository **does not**
  ship a production-trained cycle-H serum classifier. The lane is
  **governance-only**: the anchor CSV is on disk, the contract is
  fixed, but the lane is **not** wired into the build pipeline
  (`scripts/run_matrix_pipeline.py`), is **not** registered in
  `data/config/matrix_pipeline_sop.csv`, has no
  `data/training/serum_h/manifest.json`, and has no
  `data/ad_models/serum_h/`. Wiring is a separate follow-up.
- **Non-claim.** Any future cycle-H serum model will not move
  past the promotion gate in `schema_contract.md` §8 without:
  independent reviewer sign-off, recorded scope-freeze hash, and
  AD refusal smoke tests for this lane.

## 14. Provenance limits

- **Non-claim.** Provenance is hash-based (SHA-256), not
  cryptographically signed. The platform provides
  **tamper-evidence**, not non-repudiation or 21 CFR Part 11 /
  GLP digital signatures.

---

## Summary line (for reviewers)

> The `serum_h_v1.0` lane is a governance-bounded, NHANES-cycle-H,
> screening/research artifact. It is **not** diagnostic, **not**
> clinical, **not** regulatory, **not** cross-matrix, **not**
> cross-cycle (including no cross-cycle merge with the frozen
> cycle-J `serum_v1.0` lane), and **not** a source-attribution
> tool. The cycle-H isomer companion file `SSPFAS_H.XPT` is
> recorded but **not** admitted.
