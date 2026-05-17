# Data dictionary — serum_h lane v1.0

| Field | Value |
| --- | --- |
| Lane | `serum_h` (human biomonitoring, NHANES cycle H) |
| Anchor | NHANES 2013-2014 PFAS Special Subsample (`PFAS_H.XPT`) |
| Version | 1.0 (`serum_h_v1`) |
| Canonical CSV | `data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv` |
| Anchor SHA-256 | `98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f` |
| Column count | 18 (2 structural + 8 analyte values + 8 LOD-code columns) |
| Row count | 2,339 (one row per respondent in the cycle-H PFAS subsample) |
| Machine-readable mirror | `data_dictionary.csv` (this file is its human-readable companion) |
| Companion documents | `schema_contract.md`, `applicability_domain.txt`, `provenance.md`, `limitations.md` |
| Sibling lane (frozen, unaffected) | `serum` v1.0 — `validation/serum_v1/data_dictionary.md` governs the cycle-J panel |

This document maps each column in the canonical serum_h CSV to its
raw NHANES field, its dtype, its units, its role, the analyte it
measures (for value columns), the column it is paired with (for
LOD-code columns), and the governance notes a reviewer needs to
read the column correctly.

Column-naming convention: `snake_case` (`janitor::clean_names`
applied to the raw NHANES SAS uppercase names; e.g. `LBXPFDE → lbxpfde`).
This is the **same** pipeline the cycle-J anchor uses, so a
reviewer can compare the two anchors with a single column-naming
mental model.

---

## 1. Structural columns

These two columns are **required** on every row. A row missing
either is not a valid serum_h-lane row.

| Column | Raw NHANES | Dtype | Units | Role | Nullable | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `seqn` | `SEQN` | `int64` | — | respondent_id (primary key) | no | NHANES respondent sequence number; unique within cycle H |
| `wtsb2yr` | `WTSB2YR` | `float64` | respondents per 2-year subsample | sample_weight | no | Cycle-H two-year subsample weight (surplus-serum subsample, 1/3 of MEC examinees). **Required** for prevalence-style summaries. Unweighted statistics are descriptive only. |

## 2. Analyte value columns (8, all `ng/mL` after the label-unit reconciliation in `schema_contract.md` §3.2)

Every concentration column is paired with exactly one LOD-code
column (§3). Values below the analyte's limit of detection are
imputed by NHANES at `LOD / sqrt(2)`. Cycle H uses a **constant
0.10 ng/mL** LLOD for every analyte, so the imputed below-LOD
value is ~`0.0707` ng/mL for every below-LOD row across every
analyte.

| Column | Raw NHANES | Dtype | Units | Analyte | Paired LOD code | Nullable | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `lbxpfde` | `LBXPFDE` | `float64` | `ng/mL` | PFDeA (PFDA) | `lbdpfdel` | yes | LLOD 0.10 ng/mL; ~36.7% below LOD |
| `lbxpfhs` | `LBXPFHS` | `float64` | `ng/mL` | PFHxS | `lbdpfhsl` | yes | LLOD 0.10 ng/mL; ~0.6% below LOD; widely detected |
| `lbxmpah` | `LBXMPAH` | `float64` | `ng/mL` | Me-PFOSA-AcOH (PFOS precursor) | `lbdmpahl` | yes | LLOD 0.10 ng/mL; ~56.4% below LOD |
| `lbxpfbs` | `LBXPFBS` | `float64` | `ng/mL` | PFBS **(cycle-H only; not in cycle-J anchor)** | `lbdpfbsl` | yes | LLOD 0.10 ng/mL; **~96.9% below LOD** — central-tendency statistics are dominated by the imputed value |
| `lbxpfhp` | `LBXPFHP` | `float64` | `ng/mL` | PFHpA **(cycle-H only; not in cycle-J anchor)** | `lbdpfhpl` | yes | LLOD 0.10 ng/mL; ~89.2% below LOD |
| `lbxpfna` | `LBXPFNA` | `float64` | `ng/mL` | PFNA | `lbdpfnal` | yes | LLOD 0.10 ng/mL; ~1.2% below LOD; widely detected |
| `lbxpfua` | `LBXPFUA` | `float64` | `ng/mL` | PFUnDA (PFUA) | `lbdpfual` | yes | LLOD 0.10 ng/mL; ~56.8% below LOD |
| `lbxpfdo` | `LBXPFDO` | `float64` | `ng/mL` | PFDoA **(cycle-H only; not in cycle-J anchor)** | `lbdpfdol` | yes | LLOD 0.10 ng/mL; ~90.4% below LOD |

## 3. LOD-code columns (8, paired one-to-one with §2)

Each LOD-code column carries the NHANES below-LOD comment flag for
exactly one analyte. Semantics:

| Code | Meaning |
| --- | --- |
| `0` | At or above LOD; the paired value column carries the measured concentration |
| `1` | Below LOD; the paired value column carries an imputed value at `LOD / sqrt(2)` ≈ `0.0707` ng/mL |

| Column | Raw NHANES | Dtype | Pairs with value | For analyte | Nullable | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `lbdpfdel` | `LBDPFDEL` | `float64` | `lbxpfde` | PFDeA | yes | ~36.7% of rows are `1` |
| `lbdpfhsl` | `LBDPFHSL` | `float64` | `lbxpfhs` | PFHxS | yes | ~0.6% below LOD |
| `lbdmpahl` | `LBDMPAHL` | `float64` | `lbxmpah` | Me-PFOSA-AcOH | yes | ~56.4% below LOD |
| `lbdpfbsl` | `LBDPFBSL` | `float64` | `lbxpfbs` | PFBS | yes | Dominant value is `1` (~96.9% below LOD) |
| `lbdpfhpl` | `LBDPFHPL` | `float64` | `lbxpfhp` | PFHpA | yes | ~89.2% below LOD |
| `lbdpfnal` | `LBDPFNAL` | `float64` | `lbxpfna` | PFNA | yes | ~1.2% below LOD |
| `lbdpfual` | `LBDPFUAL` | `float64` | `lbxpfua` | PFUnDA | yes | ~56.8% below LOD |
| `lbdpfdol` | `LBDPFDOL` | `float64` | `lbxpfdo` | PFDoA | yes | ~90.4% below LOD |

## 4. Column order in the canonical CSV

```text
seqn, wtsb2yr,
lbxpfde, lbdpfdel,
lbxpfhs, lbdpfhsl,
lbxmpah, lbdmpahl,
lbxpfbs, lbdpfbsl,
lbxpfhp, lbdpfhpl,
lbxpfna, lbdpfnal,
lbxpfua, lbdpfual,
lbxpfdo, lbdpfdol
```

The order reflects the NHANES PFAS_H SAS Transport field ordering
as read by `haven::read_xpt()` and re-emitted by
`readr::write_csv()`. Downstream code MUST NOT assume any
particular column position; reference columns by name.

## 5. Cycle-J panel comparison (intentional non-coverage)

| Cycle-J analyte | In cycle-H anchor? | Where it lives in cycle H |
| --- | --- | --- |
| n-PFOA (`lbxnfoa`) | **no** | `SSPFAS_H.XPT` (isomer file; recorded but not admitted under serum_h_v1) |
| Sb-PFOA (`lbxbfoa`) | **no** | `SSPFAS_H.XPT` |
| n-PFOS (`lbxnfos`) | **no** | `SSPFAS_H.XPT` |
| Sm-PFOS (`lbxmfos`) | **no** | `SSPFAS_H.XPT` |
| PFHxS (`lbxpfhs`) | yes | `PFAS_H.XPT` (this dictionary) |
| PFDeA / PFDA (`lbxpfde`) | yes | `PFAS_H.XPT` |
| PFNA (`lbxpfna`) | yes | `PFAS_H.XPT` |
| PFUnDA (`lbxpfua`) | yes | `PFAS_H.XPT` |
| Me-PFOSA-AcOH (`lbxmpah`) | yes | `PFAS_H.XPT` |

And cycle-H-only analytes (not in the cycle-J anchor):

| Cycle-H analyte | NHANES code |
| --- | --- |
| PFBS | `LBXPFBS` |
| PFHpA | `LBXPFHP` |
| PFDoA | `LBXPFDO` |

## 6. Reading rules (normative)

These rules are governance-level, not stylistic. Violating any of
them is a misuse of the serum_h v1.0 contract.

1. **Always read by column name**, never by position.
2. **Always consult the paired LOD-code column** before reporting a
   percentile near or below the analyte's LOD, or a "fraction
   detected" metric. Cycle H is dominated by below-LOD rows for 5
   of 8 analytes; central-tendency statistics computed without the
   LOD code are misleading.
3. **Always apply `wtsb2yr`** when computing a prevalence-style or
   population-distribution statistic. Unweighted means are
   descriptive only and must be labeled as such.
4. **Always treat values as `ng/mL`** despite the `(ug/L)` SAS
   variable label. See `schema_contract.md` §3.2. Never apply a
   ug/L → ng/mL conversion factor on top of the values in this
   CSV.
5. **Never mix matrices.** A row that simultaneously carries any
   column from this dictionary AND any column from
   `drinking_water`, `biosolids_sludge`, `afff`,
   `methanol_standards`, `air_emissions`, `soil_sediment`, or
   `fish_tissue` is a mixed-matrix record and must be refused
   (see `schema_contract.md` §5 and `applicability_domain.txt` R5).
6. **Never mix cycles.** A row that simultaneously carries any
   column from this dictionary AND any column from
   `validation/serum_v1/data_dictionary.md` (cycle J) is a
   cross-cycle record and must be refused (see
   `applicability_domain.txt` R8).
7. **Never silently extend the panel.** If a downstream artifact
   needs additional analytes (e.g. the isomer split from
   `SSPFAS_H.XPT`), it must be issued as `serum_h_v1.1` or
   `serum_h_v2` with its own dictionary.

## 7. Lane-stamped physiological classification (5 derived columns, NOT in the anchor)

These five fields are not in the raw NHANES XPT and are not in the
serum_h v1.0 anchor CSV
(`data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv`, SHA-256
`98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f`,
which is frozen — see `provenance.md` §3). They are the **lane
contract values** that will live only in the **derived** training
table once the lane is wired into the build pipeline (see
`schema_contract.md` §9.2; the lane is governance-only at this
issuance and not yet pipeline-integrated). The Shiny app will
enforce them on every validate / normalize / save / train pass via
`physiological_guard()` in `LatestPFAS.R` once the wiring is in
place. The values are fixed by the lane contract
(`schema_contract.md` §9) and the same on every cycle-H
biomonitoring row.

| Column | Dtype | Value (for this lane) | Role | Origin |
| --- | --- | --- | --- | --- |
| `sample_domain` | string | `physiological` | classification_stamp | Lane contract (`schema_contract.md` §9) |
| `sample_matrix` | string | `human_serum` | classification_stamp | Lane contract (`schema_contract.md` §9) |
| `measurement_context` | string | `biomonitoring` | classification_stamp | Lane contract (`schema_contract.md` §9) |
| `source_program` | string | `CDC NHANES` | classification_stamp | Lane contract (`schema_contract.md` §9, anchored to §1). Specific cycle (H 2013-2014) is recorded in the canonical `source_dataset` column, not duplicated here. |
| `governance_lane` | string | `serum_h_v1` | classification_stamp | Lane contract (`schema_contract.md` §9). The `(pipeline_id, governance_version)` coordinate that points back to `validation/serum_h_v1/` — distinct from cycle-J's `serum_v1`. |

Why no `units` column in the stamp: concentration units are a
**row** property handled by the label-unit reconciliation in
`schema_contract.md` §3.2, not a lane property. Duplicating units
as a lane-stamped constant would create two sources of truth.

A row that omits any of these five fields is **refused** with reason
`physiological_classification_missing`. A row whose value disagrees
with the table is **refused** with reason
`physiological_classification_mismatch`. These refusals are
governance successes (see `schema_contract.md` §9), not bugs.

This stamp is **lane-specific**: the five fields apply only to the
serum_h lane and MUST NOT be borrowed by cycle-J `serum` rows
(whose stamp uses `governance_lane=serum_v1`), nor by environmental
or reference-material lanes.

## 8. What is **not** in this dictionary (explicit non-coverage)

The following NHANES variables are **not** part of serum_h v1.0
and must not be inferred from this CSV:

- Survey-design strata (`SDMVSTRA`) and PSUs (`SDMVPSU`) — required
  for variance estimation but live in `DEMO_H.XPT`, not
  `PFAS_H.XPT`.
- Demographic variables (age, sex, race/ethnicity, income index) —
  live in `DEMO_H.XPT` / `INQ_H.XPT`, not in serum_h v1.0's
  anchor.
- The n-/Sb- PFOA and n-/Sm- PFOS isomer split — lives in
  `SSPFAS_H.XPT`, recorded in `provenance.md` §3.1 but **not**
  admitted under this anchor.
- Analytes from any other NHANES cycle (J, I, C, Pre-pandemic).

Joining any of these into the serum_h lane requires a new
versioned artifact and a new dictionary. See `provenance.md` §7.
