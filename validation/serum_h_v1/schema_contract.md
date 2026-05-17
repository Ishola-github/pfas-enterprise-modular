# Schema contract — serum_h lane v1.0

| Field | Value |
| --- | --- |
| Lane | `serum_h` (peer of `serum`; NHANES cycle H is its own panel) |
| Lane kind | `physiological_biomonitoring` |
| Version | 1.0 (`serum_h_v1`) |
| Issued | 2026-05-13 |
| Status | DRAFT — promotes only after reviewer sign-off (see `README.md`) |
| Machine-readable mirror | `schema_contract.json` (this file is its human-readable contract) |
| Anchor CSV | `data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv` |
| Anchor CSV SHA-256 | `98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f` |
| Column naming convention | `snake_case` (`janitor::clean_names` applied to the raw SAS field names) |
| Sibling lane (frozen) | `serum` v1.0 — `validation/serum_v1/` (cycle J, 2017-2018; SHA-256 `dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f`). The cycle-J anchor is **not** affected by this contract. |

This document **locks** the required columns, types, and analyte
pairings for the cycle-H serum lane. The cycle-H panel is **not** a
superset or subset of the cycle-J panel: it adds three analytes
(`PFBS`, `PFHpA`, `PFDoA`) and lacks the four isomer-resolved
PFOA/PFOS columns that PFAS_J carries (those live in the
`SSPFAS_H.XPT` companion file, documented as a paired artifact in
§7). Any change must be issued as a new versioned artifact
(`serum_h_v1.1` or `serum_h_v2`); silent column additions, renames,
retypings, or analyte swaps are governance violations.

Why this is a peer lane, not a `serum_v1.1` successor: harmonizing
cycle J and cycle H into one contract would require either dropping
to the 5 shared analytes (losing v1.0 coverage), padding each row
with 4–7 NULLs (losing the "panel completeness" property), or
shipping a cross-cycle harmonization artifact (a separate piece of
work). Until that harmonization exists, the two cycles are
governance-separate.

## 1. Anchor dataset

```text
Source name : NHANES 2013-2014 PFAS Special Subsample (cycle H)
Cycle       : H (2013-2014)
Source URL  : https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/PFAS_H.xpt
Raw file    : PFAS_H.XPT  (SAS XPT, public NCHS release)
Release     : public
Units       : ng/mL (serum concentration) -- see §3.2 for the label-unit reconciliation
Population  : participants 12 years and older
Expected n  : 2,339 rows in the public release
Measured n  : 2,170 rows with at least one non-missing analyte value
Method      : online SPE-HPLC-TIS-MS/MS (Kuklenyik 2005); same method family as cycle J
LLOD        : constant 0.10 ng/mL per analyte (one of the cycle-H specifics; cycle J uses per-analyte LLODs)
```

Method family and population are compatible with cycle J. The
**analyte panel** and the **SAS variable unit labels** are not (see
§3.2 and §7).

The full chain of custody (download, conversion, hashing — the
Docker / Ubuntu pipeline) is captured in `provenance.md`.

## 2. Required structural columns

| Column | Raw NHANES field | Dtype | Role | Nullable | Notes |
| --- | --- | --- | --- | --- | --- |
| `seqn` | `SEQN` | `int64` | respondent_id (**primary key**) | no | NHANES respondent sequence number; one row per respondent in the cycle-H PFAS subsample |
| `wtsb2yr` | `WTSB2YR` | `float64` | sample_weight | no | Two-year subsample weight; **required** for any prevalence-style summary. WTSB2YR in cycle H is the surplus-serum subsample weight (1/3 of MEC examinees). |

A row missing either of these is **not** a valid serum_h-lane row
and must be rejected at ingestion.

## 3. Analyte panel (8 analytes, paired with LOD codes)

All concentration columns are `float64` in `ng/mL` (see §3.2 for the
label-unit reconciliation). Every concentration column is paired
with one LOD-comment column (`0` = at/above LOD, `1` = below LOD;
NHANES imputes below-LOD values at `LOD / sqrt(2)` = `0.0707…` for
every analyte in cycle H).

| Concentration column | LOD code column | Analyte | Raw value | Raw LOD code |
| --- | --- | --- | --- | --- |
| `lbxpfde` | `lbdpfdel` | PFDeA (PFDA) | `LBXPFDE` | `LBDPFDEL` |
| `lbxpfhs` | `lbdpfhsl` | PFHxS | `LBXPFHS` | `LBDPFHSL` |
| `lbxmpah` | `lbdmpahl` | Me-PFOSA-AcOH (PFOS precursor) | `LBXMPAH` | `LBDMPAHL` |
| `lbxpfbs` | `lbdpfbsl` | PFBS **(not in cycle J)** | `LBXPFBS` | `LBDPFBSL` |
| `lbxpfhp` | `lbdpfhpl` | PFHpA **(not in cycle J)** | `LBXPFHP` | `LBDPFHPL` |
| `lbxpfna` | `lbdpfnal` | PFNA | `LBXPFNA` | `LBDPFNAL` |
| `lbxpfua` | `lbdpfual` | PFUnDA (PFUA) | `LBXPFUA` | `LBDPFUAL` |
| `lbxpfdo` | `lbdpfdol` | PFDoA **(not in cycle J)** | `LBXPFDO` | `LBDPFDOL` |

### 3.1 LOD-code semantics

| Code | Meaning |
| --- | --- |
| `0` | At or above LOD; reported value is the measured serum concentration |
| `1` | Below LOD; reported value is imputed by NHANES at `LOD / sqrt(2)` ≈ `0.0707` ng/mL (constant across analytes) |

Any statistic that depends on the censored portion of the
distribution (percentiles near or below the LOD, fraction-detected
metrics) **MUST** consult the paired LOD column. Treating the
imputed value as a real measurement is a governance violation.

### 3.2 Label-unit reconciliation (cycle-H specific, normative)

The SAS variable labels in `PFAS_H.XPT` annotate every concentration
column with `(ug/L)`. The NHANES PFAS_H online codebook simultaneously
documents the LLOD table in `ng/mL` and states that "values are
equivalent for aqueous matrices to within method tolerance".

```text
1 ug/L  ==  1 ng/mL   for aqueous matrices to within ~2.5%
                      (serum density ~1.025 g/mL accounts for the residual)
```

The cycle-H anchor CSV records the **numerical values exactly as
NHANES published them**. No unit conversion is applied. The lane
contract declares the units as `ng/mL` because:

1. CDC's PFAS-H codebook LLOD table is in `ng/mL`.
2. The numerical values agree with `ng/mL` to within the documented
   method tolerance.
3. The same numerical values, in the cycle-J anchor (`PFAS_J.XPT`),
   are labelled `(ng/mL)` — using a different label here for the
   same numerical regime would manufacture a unit difference.

**Enforcement.** Any ingestion code that reads this lane MUST:

- Treat the values as `ng/mL`.
- Record the upstream label discrepancy in the audit log when the
  source is `PFAS_H.XPT` (so the discrepancy is never silently
  forgotten).
- Refuse the row if a downstream caller attempts to relabel the
  values as `(ug/L)` *and* multiply by any conversion factor — that
  is a double conversion and is **never** authorized by this
  contract.

This rule lives in §3.2 because it is a row-level invariant of the
cycle-H ingestion, not a one-time provenance note.

## 4. Observed envelope (cycle H, n = 2,339 rows in the public release)

Concentrations in `ng/mL` (per §3.2). These bounds anchor the
applicability-domain refusal in `applicability_domain.txt`. A
reported value outside the observed envelope by more than 3 sigma
must be refused unless paired with supporting batch metadata.

The percent-below-LOD figures are reproduced from the CDC PFAS_H
analytic notes. They are deliberately presented as the **fraction of
respondents at the constant 0.10 ng/mL LLOD** so the cycle-H lane
cannot be misread as if it carried cycle-J's per-analyte LLODs.

| Analyte | LLOD (ng/mL) | % below LOD (cycle H) | Notes |
| --- | ---: | ---: | --- |
| PFDeA | 0.10 | 36.7 | Long-chain carboxylate; majority below LOD |
| PFHxS | 0.10 | 0.6 | Widely detected |
| Me-PFOSA-AcOH | 0.10 | 56.4 | PFOS precursor; majority below LOD |
| PFBS | 0.10 | 96.9 | Short-chain sulfonate; **almost entirely below LOD** in cycle H |
| PFHpA | 0.10 | 89.2 | Short-chain carboxylate; mostly below LOD |
| PFNA | 0.10 | 1.2 | Widely detected |
| PFUnDA | 0.10 | 56.8 | Long-chain carboxylate; majority below LOD |
| PFDoA | 0.10 | 90.4 | Long-chain carboxylate; almost entirely below LOD |

The %-below-LOD figures show that **5 of the 8 cycle-H analytes**
(PFDeA, MPAH, PFBS, PFHpA, PFUnDA, PFDoA) are dominated by the
imputed `LOD / sqrt(2)` value. Any model that learns from this lane
must reproduce the population distribution of the LOD-code columns,
not just the concentration columns.

## 5. Matrix isolation (normative)

This lane MUST NOT be combined, on a per-row or per-record basis,
with any of the following environmental matrices without an
explicit, documented cross-matrix harmonization artifact:

- `drinking_water`
- `biosolids_sludge`
- `afff`
- `methanol_standards`
- `air_emissions`
- `soil_sediment`
- `fish_tissue`

It also MUST NOT be combined with the cycle-J serum lane (`serum`,
v1.0) on a per-row basis without a documented cross-cycle
harmonization artifact, because the analyte panels differ (§3, §7).
Cross-cycle joins for `(SEQN, cycle)` are allowed only at the
case-level join key and only with explicit cycle stratification.

**Rationale.** Each matrix carries its own analytical method, unit
system, sampling frame, and regulatory framing. Cross-matrix and
cross-cycle combination require explicit harmonization and are
**not authorized** by this contract.

**Enforcement.** Lane ingestion code MUST reject any input row that
simultaneously carries a `serum_h` analyte value and a column from
any environmental matrix in the list above, or from the cycle-J
serum lane.

## 6. Refusal conditions

The lane MUST refuse the input when **any** of the following are
true:

1. Input is not derived from human serum biomonitoring.
2. Source cycle is not NHANES H (2013-2014) or a future
   harmonization artifact that explicitly admits cycle H.
3. Analyte is not in the 8-member panel in §3.
4. Reported concentration is outside the observed envelope by more
   than 3 sigma (relative to the cycle-H distribution for that
   analyte) without supporting batch metadata.
5. The row carries mixed-matrix payloads (`serum_h` + any
   environmental matrix in §5, or `serum_h` + cycle-J `serum`
   without a documented harmonization).
6. Units are anything other than `ng/mL` without explicit
   reconciliation against §3.2.
7. The row claims an analyte from the isomer-resolved PFOA/PFOS
   panel (n-PFOA, Sb-PFOA, n-PFOS, Sm-PFOS) **without** the
   `SSPFAS_H.XPT` companion file being co-admitted; cycle H stores
   the isomer split in a separate file, and silently filling those
   columns from `PFAS_H.XPT` alone is a contract violation.

A refusal under conditions 1–7 is a **governance success**, not a
bug.

## 7. Paired and out-of-scope artifacts (explicit non-claims)

| Dataset | Status under serum_h v1.0 | Required artifact |
| --- | --- | --- |
| NHANES 2013-2014 surplus-serum isomer companion (`SSPFAS_H.XPT`) | **Documented companion, not admitted** (this contract covers PFAS_H only) | Will be admitted by a follow-up artifact in `validation/serum_h_v1/` once the isomer-pair conversion (`n-PFOA`/`Sb-PFOA`/`n-PFOS`/`Sm-PFOS`) is reviewed; SHA-256 recorded in `provenance.md` |
| NHANES 2017-2018 (`PFAS_J.XPT`) | **NOT** in serum_h | Already governed by `validation/serum_v1/` (frozen anchor). Cross-cycle merging requires a separate harmonization artifact |
| NHANES 2003-2004 (`L06AGE_C.XPT`, legacy panel) | **NOT** in serum_h | Requires its own `serum_c_v1` lane, not a `serum_h_v1.1` extension |
| NHANES Pre-pandemic 2017-2020 (`P_PFAS.XPT`) | **NOT** in serum_h | Requires its own `serum_prepandemic_v1` lane |
| NHANES 2015-2016 PFAS_I (`PFAS_I.XPT`) | **NOT** in serum_h | Requires its own `serum_i_v1` lane |

Each introduces a different analyte panel, LLOD regime, label
convention, or sampling frame relative to cycle H. They must not be
silently merged into this contract.

### 7.1 Why `SSPFAS_H.XPT` is recorded here but not admitted yet

The cycle-H isomer file (`SSPFAS_H.XPT`, SHA-256
`1e23688dfa6bdfdc14c0447f4d34032983271063a1a343c04338ae4258515c99`,
158,480 bytes) carries:

| Column | Raw | Analyte |
| --- | --- | --- |
| `lbxnfoa` | `LBXNFOA` | n-PFOA |
| `lbxbfoa` | `LBXBFOA` | Sb-PFOA |
| `lbxnfos` | `LBXNFOS` | n-PFOS |
| `lbxmfos` | `LBXMFOS` | Sm-PFOS |

(plus the paired LOD-code columns and a different subsample weight,
`WTSB2YR` is **not** the right weight for the isomer file — the
surplus-serum subsample is a subset of the PFAS subsample, with its
own weight column).

Admitting it cleanly requires:

1. Computing and recording the conversion SHA-256.
2. Resolving the per-respondent subsample-weight overlap (which
   respondents appear in both files?).
3. A reviewer sign-off that joining the isomer file with the
   cycle-H 8-analyte file does not double-count any analyte.

Until that is done, the file is recorded by SHA-256 in
`provenance.md` and treated as a **paired non-admitted** artifact.

## 8. Promotion gate

This contract is `draft` until both of the following are recorded:

1. A reviewer (see `validation/scope_freeze/`, or an equivalent
   independent check) signs off that the analyte panel, the
   observed envelope, the label-unit reconciliation (§3.2), and the
   matrix-isolation statement are honest and defensible.
2. The SHA-256 of `data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv`
   (see `provenance.md`) is recorded in the scope-freeze manifest
   for `serum_h` (or the next scope-freeze version that supersedes
   serum_h v1.0).

Until both are recorded, no model trained on this lane may be
promoted to a deployed prediction endpoint.

## 9. Physiological-sample classification stamp (lane-derived constants)

The serum_h lane is **physiological**, not environmental. To make
that distinction explicit at the row level instead of leaving it
implicit in the matrix name, every ingested serum_h row that
reaches a derived training table is stamped with the following five
classification fields. The values are **constants derived from this
lane contract**, not column mappings from the upload.

| Field | Value | Type | Origin |
| --- | --- | --- | --- |
| `sample_domain` | `physiological` | string (enum) | Lane-stamped (this contract §9) |
| `sample_matrix` | `human_serum` | string (enum) | Lane-stamped (this contract §9) |
| `measurement_context` | `biomonitoring` | string (enum) | Lane-stamped (this contract §9) |
| `source_program` | `CDC NHANES` | string | Lane-stamped (this contract §9, anchored to §1) |
| `governance_lane` | `serum_h_v1` | string (enum) | Lane-stamped (this contract §9; the `(pipeline_id, governance_version)` coordinate that points back to `validation/serum_h_v1/`). Distinct from cycle-J's `serum_v1` value. |

> Note on `units`. The stamp deliberately does **not** carry a
> `units` column. The canonical core already records `result_unit`
> at the row level, and §3.2 of this contract handles the cycle-H
> label-unit reconciliation. Duplicating units as a lane-stamped
> constant would create two sources of truth.

### 9.1 Scope of the stamp

These five fields apply only to the serum_h lane. They MUST NOT be
borrowed by cycle-J `serum` rows (whose stamp uses
`governance_lane=serum_v1`), nor by environmental or
reference-material lanes. The same enforcement logic
(`physiological_guard()` in `LatestPFAS.R`,
`_stamp_physiological_classification` in
`scripts/run_matrix_pipeline.py`) applies, but with the cycle-H
`governance_lane` value.

### 9.2 Not yet wired into the build pipeline

As of this contract's draft issuance (2026-05-13), the serum_h lane
exists as a **governance-only** artifact: the anchor CSV is on
disk, the contract is fixed, but the lane is **not** yet a
`pipeline_id` in `data/config/matrix_pipeline_sop.csv`, has no
`data/training/serum_h/manifest.json`, and has no `ad_models/serum_h/`.
Wiring it into the build pipeline is a separate work item that
must (a) update the SOP, (b) emit a stamped training table, (c)
build an AD model, and (d) extend the `PHYSIOLOGICAL_LANE_STAMPS`
registry in both `scripts/run_matrix_pipeline.py` (Python) and
`LatestPFAS.R` (R) to include `serum_h`. The smoke
`scripts/smoke_serum_anchor_invariants.R` will need its narrowness
assertion updated at that point; until then, that smoke continues
to enforce that `serum` is the **only** registered physiological
lane, which is the correct invariant for the current state.
