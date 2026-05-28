# Schema contract — serum lane v1.0

| Field | Value |
| --- | --- |
| Lane | `serum` |
| Lane kind | `human_biomonitoring` |
| Version | 1.0 |
| Issued | 2026-05-13 |
| Status | DRAFT — promotes only after reviewer sign-off (see `README.md`) |
| Machine-readable mirror | `schema_contract.json` (this file is its human-readable contract) |
| Canonical CSV | `data/training/serum/nhanes_serum_pfas_2017_2018.csv` |
| Column naming convention | `snake_case` (`janitor::clean_names` applied to the raw SAS field names) |

This document **locks** the required columns, types, and analyte
pairings for the serum lane. Any change must be issued as a new
versioned artifact (`serum_v1.1` or `serum_v2`); silent column
additions, renames, retypings, or analyte swaps are governance
violations.

## 1. Anchor dataset

```text
Source name : NHANES 2017-2018 PFAS Special Subsample
Cycle       : J (2017-2018)
Source URL  : https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/PFAS_J.xpt
Raw file    : PFAS_J.XPT  (SAS XPT, public NCHS release)
Release     : public
Units       : ng/mL (serum concentration)
Expected n  : 2,133 respondents in the PFAS subsample
Measured n  : 1,929 respondents with at least one analyte value
```

The full chain of custody (download, conversion, hashing) is captured
in `provenance.md`.

## 2. Required structural columns

| Column | Raw NHANES field | Dtype | Role | Nullable | Notes |
| --- | --- | --- | --- | --- | --- |
| `seqn` | `SEQN` | `int64` | respondent_id (**primary key**) | no | NHANES respondent sequence number; one row per respondent |
| `wtsb2yr` | `WTSB2YR` | `float64` | sample_weight | no | Two-year subsample weight; **required** for any prevalence-style summary |

A row missing either of these is **not** a valid serum-lane row and
must be rejected at ingestion.

## 3. Analyte panel (9 analytes, paired with LOD codes)

All concentration columns are `float64` in `ng/mL`. Every concentration
column is paired with one LOD-comment column (`0` = at/above LOD,
`1` = below LOD; NHANES imputes below-LOD values at `LOD / sqrt(2)`).

| Concentration column | LOD code column | Analyte | Raw value | Raw LOD code |
| --- | --- | --- | --- | --- |
| `lbxnfoa` | `lbdnfoal` | n-PFOA (linear PFOA) | `LBXNFOA` | `LBDNFOAL` |
| `lbxbfoa` | `lbdbfoal` | Sb-PFOA (sum branched) | `LBXBFOA` | `LBDBFOAL` |
| `lbxnfos` | `lbdnfosl` | n-PFOS (linear PFOS) | `LBXNFOS` | `LBDNFOSL` |
| `lbxmfos` | `lbdmfosl` | Sm-PFOS (sum branched) | `LBXMFOS` | `LBDMFOSL` |
| `lbxpfhs` | `lbdpfhsl` | PFHxS | `LBXPFHS` | `LBDPFHSL` |
| `lbxpfna` | `lbdpfnal` | PFNA | `LBXPFNA` | `LBDPFNAL` |
| `lbxpfde` | `lbdpfdel` | PFDA | `LBXPFDE` | `LBDPFDEL` |
| `lbxpfua` | `lbdpfual` | PFUnDA | `LBXPFUA` | `LBDPFUAL` |
| `lbxmpah` | `lbdmpahl` | Me-PFOSA-AcOH (PFOS precursor) | `LBXMPAH` | `LBDMPAHL` |

### 3.1 LOD-code semantics

| Code | Meaning |
| --- | --- |
| `0` | At or above LOD; reported value is the measured serum concentration |
| `1` | Below LOD; reported value is imputed by NHANES at `LOD / sqrt(2)` |

Any statistic that depends on the censored portion of the distribution
(percentiles near or below the LOD, fraction-detected metrics) **MUST**
consult the paired LOD column. Treating the imputed value as a real
measurement is a governance violation.

## 4. Observed envelope (cycle J, n = 1,929 measured)

Concentrations in `ng/mL`. These bounds anchor the applicability-domain
refusal in `applicability_domain.txt`. A reported value outside the
observed envelope by more than 3 sigma must be refused unless paired
with supporting batch metadata.

| Analyte | Median | p95 | Max | % below LOD |
| --- | ---: | ---: | ---: | ---: |
| n-PFOA | 1.30 | 3.7 | 52.8 | 0.4 |
| Sb-PFOA | 0.07 | 0.2 | 0.7 | 90.0 |
| n-PFOS | 3.00 | 14.5 | 88.4 | 0.3 |
| Sm-PFOS | 1.20 | 5.3 | 19.3 | 0.8 |
| PFHxS | 1.10 | 3.9 | 48.8 | 0.7 |
| PFNA | 0.40 | 1.5 | 6.5 | 7.5 |
| PFDA | 0.20 | 0.8 | 6.9 | 11.3 |
| PFUnDA | 0.10 | 0.5 | 4.8 | 34.0 |
| Me-PFOSA-AcOH | 0.10 | 0.6 | 4.5 | 41.0 |

## 5. Matrix isolation (normative)

This lane MUST NOT be combined, on a per-row or per-record basis, with
any of the following environmental matrices without an explicit,
documented cross-matrix harmonization artifact:

- `drinking_water`
- `biosolids_sludge`
- `afff`
- `methanol_standards`
- `air_emissions`
- `soil_sediment`
- `fish_tissue`

**Rationale.** Each matrix carries its own analytical method, unit
system, sampling frame, and regulatory framing. Cross-matrix
combination requires an explicit harmonization artifact and is **not
authorized** by this contract.

**Enforcement.** Lane ingestion code MUST reject any input row that
simultaneously carries a serum analyte value and a column from any
environmental matrix in the list above. The corresponding repository
checkpoints are described in `SCOPE_AND_INTENDED_USE.md` §6 (pipeline
layer, AD layer, API layer).

## 6. Refusal conditions

The lane MUST refuse the input when **any** of the following are true:

1. Input is not derived from human serum biomonitoring.
2. Cycle / population is beyond NHANES J coverage without a paired,
   documented harmonization artifact.
3. Analyte is not in the 9-member panel in §3.
4. Reported concentration is outside the observed envelope by more
   than 3 sigma (relative to the cycle J distribution for that
   analyte) without supporting batch metadata.
5. The row carries mixed-matrix payloads (serum + any environmental
   matrix in §5).
6. Units are anything other than `ng/mL` without an explicit,
   documented unit-conversion transformation in the ingestion pipeline.

A refusal under conditions 1–6 is a **governance success**, not a bug.

## 7. Out-of-scope versions (explicit non-claims)

| Dataset | Status under v1.0 | Required artifact |
| --- | --- | --- |
| NHANES Pre-pandemic 2017-2020 (`P_PFAS.XPT`) | **NOT** in v1.0 | Requires its own `serum_prepandemic_v1` lane or a `serum_v1.1`/`serum_v2` AD revision |
| NHANES 2003-2004 (`L06AGE_C.XPT`, legacy panel) | **NOT** in v1.0 | Requires its own `serum_c_v1` lane or a `serum_v1.1`/`serum_v2` AD revision |
| NHANES 2015-2016 (`PFAS_I.XPT`, cycle I) | **NOT** in v1.0 | Requires its own `serum_i_v1` lane |
| NHANES 2013-2014 (`PFAS_H.XPT`, cycle H) | **NOT** in v1.0 (peer lane issued: `validation/serum_h_v1/`, anchor SHA-256 `98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f`) | The cycle-H lane is now governance-separate from this v1.0 contract; cross-cycle merging still requires a documented harmonization artifact |
| NHANES 2013-2014 (`SSPFAS_H.XPT`, isomer companion) | **NOT** in v1.0; also **NOT** admitted under `serum_h_v1` (recorded by SHA-256 only) | Admission requires a follow-up artifact paired with `serum_h_v1` -- see `validation/serum_h_v1/schema_contract.md` §7.1 |

Each introduces a different analyte panel and / or concentration
regime relative to cycle J. They must not be silently merged into
the v1.0 contract.

### 7.1 Cycle H specifics that make silent admission a contract violation

| Property | v1.0 anchor (PFAS_J, 2017-2018) | PFAS_H (2013-2014) |
| --- | --- | --- |
| Analyte panel size | 9 (incl. isomer split) | 8 (no isomer split in the same file) |
| Analytes added vs v1.0 | -- | `LBXPFBS`, `LBXPFHP`, `LBXPFDO` |
| Analytes missing vs v1.0 | -- | `LBXNFOA`, `LBXBFOA`, `LBXNFOS`, `LBXMFOS` (isomer split lives in `SSPFAS_H.XPT`) |
| Isomer split | merged in PFAS_J | split across PFAS_H + SSPFAS_H |
| SAS variable label | `(ng/mL)` per CDC documentation | `(ug/L)` in the SAS labels, **but** the codebook's LLOD table is explicitly in `ng/mL` |
| Numerical equivalence of the unit labels | -- | `1 ug/L = 1 ng/mL` in aqueous matrix to within ~2.5 percent (serum density ~1.025 g/mL); equivalent values, but the **label** difference must be reconciled before ingestion |
| LLOD | per-analyte, see §3 | constant 0.10 ng/mL for every analyte |
| Population | 12 years and older | 12 years and older |
| Method family | online SPE-HPLC-TIS-MS/MS (Kuklenyik 2005) | online SPE-HPLC-TIS-MS/MS (Kuklenyik 2005) -- same method family |

The method family and population are compatible. The **panel** and
the **label-unit semantics** are not. Any future `serum_v1.1` /
`serum_v2` artifact that admits PFAS_H must:

1. Declare the merged analyte panel and re-derive the observed
   envelope in §3 against the union.
2. Record a unit-reconciliation step in the ingestion pipeline that
   maps `(ug/L)`-labelled rows to `ng/mL` explicitly (no silent
   relabel), and reject the row if the source label is anything
   other than the two documented equivalents.
3. Pair `PFAS_H.XPT` with `SSPFAS_H.XPT` (or refuse) so the isomer
   split is restored before any row is admitted to a model trained
   on the v1.0 isomer-resolved panel.

## 8. Promotion gate

This contract is `draft` until both of the following are recorded:

1. A reviewer (see `validation/scope_freeze/v1.0/reviews/`, or an
   equivalent independent check) signs off that the analyte panel,
   the observed envelope, and the matrix-isolation statement are
   honest and defensible.
2. The SHA-256 of `data/training/serum/nhanes_serum_pfas_2017_2018.csv`
   (see `provenance.md`) is recorded in the scope-freeze manifest for
   serum (or the next scope-freeze version that supersedes v1.0).

Until both are recorded, no model trained on this lane may be
promoted to a deployed prediction endpoint.

## 9. Physiological-sample classification stamp (lane-derived constants)

The serum lane is **physiological**, not environmental. To make that
distinction explicit at the row level instead of leaving it implicit
in the matrix name, every ingested serum row is stamped with the
following five classification fields. The values are **constants
derived from this lane contract**, not column mappings from the
upload, so an operator cannot accidentally point them at the wrong
upload column.

| Field | Value | Type | Origin |
| --- | --- | --- | --- |
| `sample_domain` | `physiological` | string (enum) | Lane-stamped (this contract \u00a79) |
| `sample_matrix` | `human_serum` | string (enum) | Lane-stamped (this contract \u00a79) |
| `measurement_context` | `biomonitoring` | string (enum) | Lane-stamped (this contract \u00a79) |
| `source_program` | `CDC NHANES` | string | Lane-stamped (this contract \u00a79, anchored to \u00a71) |
| `governance_lane` | `serum_v1` | string (enum) | Lane-stamped (this contract \u00a79; the `(pipeline_id, governance_version)` coordinate that points back to `validation/serum_v1/`) |

> Note on `units`. The stamp deliberately does **not** carry a `units`
> column. The canonical core already records `result_unit` at the
> row level, so duplicating it as a lane-stamped constant created
> two sources of truth that disagreed on NIST SRM 1957 rows (ng/mL
> vs. ug/kg). Concentration units are a row property; the four
> domain / matrix / context / source_program fields and the
> `governance_lane` pointer are lane properties. They live in
> different layers.

### 9.1 Why these five fields

| Environmental PFAS | Physiological PFAS |
| --- | --- |
| contamination | body burden |
| exposure source | internal exposure |
| ng/L or ng/g | ng/mL serum |
| EPA methods | CDC biomonitoring |
| site remediation | exposure epidemiology |

Without an explicit physiological classification, a reviewer reading
a serum row in isolation can plausibly mistake the value for an
environmental concentration. The five fields above are the minimum
needed to remove that ambiguity at the row level.

### 9.2 Enforcement (physiological guard)

Any code path that validates, normalizes, saves, or trains on serum
data MUST verify that every row carries the five fields above with
**exactly** the values listed in the table.

- A row that omits any of the five fields is **refused** with reason
  `physiological_classification_missing`.
- A row whose value for any of the five fields disagrees with the
  table is **refused** with reason `physiological_classification_mismatch`
  (the offending field is reported in the audit entry).

These refusals are governance successes, not bugs. They are the same
class of refusal as conditions 1\u20136 in \u00a76, and they enforce the
isolation declared in \u00a75 at the row level.

### 9.3 Scope of the stamp (matrix-specific, not global)

These five fields are **lane-specific** and apply only to the serum
lane. Other lanes (drinking_water, biosolids_sludge, air_emissions,
afff, methanol_standards) have their own classification semantics
and MUST NOT borrow this stamp; doing so would collapse the very
matrix isolation declared in \u00a75. Each matrix lane that needs a
similar row-level classification must add its own stamp section in
its own schema contract.
