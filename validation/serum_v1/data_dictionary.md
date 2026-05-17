# Data dictionary — serum lane v1.0

| Field | Value |
| --- | --- |
| Lane | `serum` (human biomonitoring) |
| Anchor | NHANES 2017-2018 PFAS Special Subsample (`PFAS_J.XPT`) |
| Version | 1.0 |
| Canonical CSV | `data/training/serum/nhanes_serum_pfas_2017_2018.csv` |
| Column count | 20 (2 structural + 9 analyte values + 9 LOD-code columns) |
| Row count | 2,133 (one row per respondent in the PFAS subsample) |
| Machine-readable mirror | `data_dictionary.csv` (this file is its human-readable companion) |
| Companion documents | `schema_contract.md`, `applicability_domain.txt`, `provenance.md`, `limitations.md` |

This document maps each column in the canonical serum CSV to its
raw NHANES field, its dtype, its units, its role, the analyte it
measures (for value columns), the column it is paired with (for
LOD-code columns), and the governance notes a reviewer needs to
read the column correctly.

Column-naming convention: `snake_case` (`janitor::clean_names`
applied to the raw NHANES SAS uppercase names; e.g. `LBXNFOA → lbxnfoa`).

---

## 1. Structural columns

These two columns are **required** on every row. A row missing
either is not a valid serum-lane row.

| Column | Raw NHANES | Dtype | Units | Role | Nullable | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `seqn` | `SEQN` | `int64` | — | respondent_id (primary key) | no | NHANES respondent sequence number; unique within cycle J |
| `wtsb2yr` | `WTSB2YR` | `float64` | respondents per 2-year subsample | sample_weight | no | Two-year subsample weight. **Required** for prevalence-style summaries. Unweighted statistics are descriptive only. |

## 2. Analyte value columns (9, all `ng/mL`)

Every concentration column is paired with exactly one LOD-code
column (§3). Values below the analyte's limit of detection are
imputed by NHANES at `LOD / sqrt(2)`; the paired LOD-code column
is the only authoritative signal that a value is censored.

| Column | Raw NHANES | Dtype | Units | Analyte | Paired LOD code | Nullable | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `lbxnfoa` | `LBXNFOA` | `float64` | `ng/mL` | n-PFOA (linear PFOA) | `lbdnfoal` | yes | Linear PFOA isomer; ~0.4% below LOD in PFAS_J |
| `lbxbfoa` | `LBXBFOA` | `float64` | `ng/mL` | Sb-PFOA (sum branched PFOA) | `lbdbfoal` | yes | **~90% below LOD** in PFAS_J; central-tendency statistics are dominated by the imputed value |
| `lbxnfos` | `LBXNFOS` | `float64` | `ng/mL` | n-PFOS (linear PFOS) | `lbdnfosl` | yes | Linear PFOS isomer; dominant detected PFOS species in NHANES J |
| `lbxmfos` | `LBXMFOS` | `float64` | `ng/mL` | Sm-PFOS (sum branched PFOS) | `lbdmfosl` | yes | Sum of perfluoromethylheptane sulfonic acid isomers (branched PFOS) |
| `lbxpfhs` | `LBXPFHS` | `float64` | `ng/mL` | PFHxS | `lbdpfhsl` | yes | Perfluorohexanesulfonic acid; widely detected (~0.7% below LOD) |
| `lbxpfna` | `LBXPFNA` | `float64` | `ng/mL` | PFNA | `lbdpfnal` | yes | Perfluorononanoic acid |
| `lbxpfde` | `LBXPFDE` | `float64` | `ng/mL` | PFDA | `lbdpfdel` | yes | Perfluorodecanoic acid (NHANES code spells the analyte as 'PFDe') |
| `lbxpfua` | `LBXPFUA` | `float64` | `ng/mL` | PFUnDA | `lbdpfual` | yes | Perfluoroundecanoic acid; ~34% below LOD in PFAS_J |
| `lbxmpah` | `LBXMPAH` | `float64` | `ng/mL` | Me-PFOSA-AcOH | `lbdmpahl` | yes | 2-(N-methylperfluorooctane sulfonamido) acetic acid; PFOS precursor (~41% below LOD) |

## 3. LOD-code columns (9, paired one-to-one with §2)

Each LOD-code column carries the NHANES below-LOD comment flag for
exactly one analyte. Semantics:

| Code | Meaning |
| --- | --- |
| `0` | At or above LOD; the paired value column carries the measured concentration |
| `1` | Below LOD; the paired value column carries an imputed value at `LOD / sqrt(2)` |

| Column | Raw NHANES | Dtype | Pairs with value | For analyte | Nullable | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `lbdnfoal` | `LBDNFOAL` | `float64` | `lbxnfoa` | n-PFOA | yes | — |
| `lbdbfoal` | `LBDBFOAL` | `float64` | `lbxbfoa` | Sb-PFOA | yes | Dominant value is `1` (≈90% below LOD) |
| `lbdnfosl` | `LBDNFOSL` | `float64` | `lbxnfos` | n-PFOS | yes | — |
| `lbdmfosl` | `LBDMFOSL` | `float64` | `lbxmfos` | Sm-PFOS | yes | — |
| `lbdpfhsl` | `LBDPFHSL` | `float64` | `lbxpfhs` | PFHxS | yes | — |
| `lbdpfnal` | `LBDPFNAL` | `float64` | `lbxpfna` | PFNA | yes | — |
| `lbdpfdel` | `LBDPFDEL` | `float64` | `lbxpfde` | PFDA | yes | — |
| `lbdpfual` | `LBDPFUAL` | `float64` | `lbxpfua` | PFUnDA | yes | ~34% of rows are `1` |
| `lbdmpahl` | `LBDMPAHL` | `float64` | `lbxmpah` | Me-PFOSA-AcOH | yes | ~41% of rows are `1` |

## 4. Column order in the canonical CSV

```text
seqn, wtsb2yr,
lbxpfde, lbdpfdel,
lbxpfhs, lbdpfhsl,
lbxmpah, lbdmpahl,
lbxpfna, lbdpfnal,
lbxpfua, lbdpfual,
lbxnfoa, lbdnfoal,
lbxbfoa, lbdbfoal,
lbxnfos, lbdnfosl,
lbxmfos, lbdmfosl
```

The order reflects the NHANES PFAS_J SAS Transport field ordering as
read by `haven::read_xpt()`. Downstream code MUST NOT assume any
particular column position; reference columns by name.

## 5. Reading rules (normative)

These rules are governance-level, not stylistic. Violating any of
them is a misuse of the v1.0 contract.

1. **Always read by column name**, never by position.
2. **Always consult the paired LOD-code column** before reporting a
   percentile near or below the analyte's LOD, or a "fraction
   detected" metric.
3. **Always apply `wtsb2yr`** when computing a prevalence-style or
   population-distribution statistic. Unweighted means are
   descriptive only and must be labeled as such.
4. **Never mix matrices.** A row that simultaneously carries any
   column from this dictionary AND any column from
   `drinking_water`, `biosolids_sludge`, `afff`,
   `methanol_standards`, `air_emissions`, `soil_sediment`, or
   `fish_tissue` is a mixed-matrix record and must be refused
   (see `schema_contract.md` §5 and `applicability_domain.txt` R5).
5. **Never silently extend the panel.** If a downstream artifact
   needs additional NHANES analytes (e.g. legacy panel from cycle
   C, or pre-pandemic merged file), it must be issued as
   `serum_v1.1` or `serum_v2` with its own dictionary.

## 6. Lane-stamped physiological classification (5 derived columns)

These five fields are not in the raw NHANES XPT and are not in the
v1.0 anchor CSV (`data/training/serum/nhanes_serum_pfas_2017_2018.csv`,
SHA-256 `dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f`,
which is frozen — see `provenance.md` §3). They live only in the
**derived** training table (`data/training/serum/training.csv`)
where they are appended by `_stamp_physiological_classification(row, "serum")`
in `scripts/run_matrix_pipeline.py` (and by `stamp_physiological_classification(df, "serum")`
for DataFrame-level callers). The Shiny app enforces them on every
validate / normalize / save / train pass via `physiological_guard()`
in `LatestPFAS.R`. The values are fixed by the lane contract
(`schema_contract.md` §9) and the same on every biomonitoring row.

| Column | Dtype | Value (for this lane) | Role | Origin |
| --- | --- | --- | --- | --- |
| `sample_domain` | string | `physiological` | classification_stamp | Lane contract (`schema_contract.md` §9) |
| `sample_matrix` | string | `human_serum` | classification_stamp | Lane contract (`schema_contract.md` §9) |
| `measurement_context` | string | `biomonitoring` | classification_stamp | Lane contract (`schema_contract.md` §9) |
| `source_program` | string | `CDC NHANES` | classification_stamp | Lane contract (`schema_contract.md` §1, §9). Specific cycle is recorded in the canonical `source_dataset` column, not duplicated here. |
| `governance_lane` | string | `serum_v1` | classification_stamp | Lane contract (`schema_contract.md` §9). The `(pipeline_id, governance_version)` coordinate that points back to `validation/serum_v1/` — a machine-checkable join key from a training row to the contract it was admitted under. |

Why no `units` column in the stamp: concentration units are a
**row** property, not a lane property. The canonical core already
records `result_unit` per row (ng/mL for NHANES biomonitoring rows,
ug/kg for the seven NIST SRM 1957 reference-material rows that
share this training table). Duplicating units as a lane-stamped
constant created two sources of truth that disagreed on SRM rows.

Per-row applicability: the stamp applies to NHANES biomonitoring
rows (`source = CDC_NHANES`); the seven NIST SRM 1957 rows
(`source = NIST_SRM1957`) intentionally carry blank values in all
five stamp columns, because they are reference material, not
biomonitoring. They live in the same training table only because
they anchor the AD envelope.

A row that omits any of these five fields is **refused** with reason
`physiological_classification_missing` (this is the correct verdict
for an SRM row pushed through the biomonitoring path). A row whose
value disagrees with the table is **refused** with reason
`physiological_classification_mismatch`. These refusals are
governance successes (see `schema_contract.md` §9.2), not bugs.

This stamp is **lane-specific**: the five fields apply only to the
serum lane and MUST NOT be borrowed by environmental or
reference-material lanes (`schema_contract.md` §9.3). The
`scripts/smoke_serum_anchor_invariants.R` smoke fails immediately
if any environmental or reference-material lane manifest grows a
`physiological_classification` block.

## 7. What is **not** in this dictionary (explicit non-coverage)

The following NHANES variables are **not** part of v1.0 and must not
be inferred from this CSV:

- Survey-design strata (`SDMVSTRA`) and PSUs (`SDMVPSU`) — required
  for variance estimation but live in `P_DEMO.XPT`, not `PFAS_J.XPT`.
- Demographic variables (age, sex, race/ethnicity, income index) —
  live in `P_DEMO.XPT` / `P_INQ.XPT`, not in v1.0's anchor.
- Analytes from the NHANES C (2003-2004) legacy panel
  (`L06AGE_C.XPT`).
- Analytes from the pre-pandemic combined release (`P_PFAS.XPT`).

Joining any of these into the serum lane requires a new versioned
artifact and a new dictionary. See `provenance.md` §6.
