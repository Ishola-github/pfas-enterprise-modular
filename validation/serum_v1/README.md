# Serum lane governance scaffolding (v1.0)

This directory holds the **minimum governance contract** for the
human serum biomonitoring lane of PFAS Enterprise 5.0, anchored to
the NHANES 2017-2018 PFAS Special Subsample (`PFAS_J.XPT`).

It is intentionally small. It is also intentionally **separate
from environmental-matrix lanes** (`drinking_water_v1`,
`biosolids_sludge_v1`, `afff_v1`, etc.) because human serum is
internal-exposure data, not environmental-source data.

## Files in this directory

| File | Purpose | Authority |
| --- | --- | --- |
| `intended_use.txt` | What this lane is for, and what it explicitly is **not** for | Lane-level scope statement |
| `applicability_domain.txt` | Concrete in-domain inputs, numeric envelope, refusal conditions | AD boundary for serum v1.0 |
| `schema_contract.md` | Human-readable schema: required columns, analyte/LOD pairings, observed envelope, matrix-isolation rule, refusal conditions, promotion gate | Lane ingestion contract (narrative) |
| `schema_contract.json` | Machine-readable mirror of `schema_contract.md` | Lane ingestion contract (machine) |
| `data_dictionary.md` | Per-column documentation in markdown: dtype, units, raw NHANES field, role, analyte, LOD pairing, nullability, reading rules | Reviewer-facing column reference (narrative) |
| `data_dictionary.csv` | Machine-readable mirror of `data_dictionary.md` | Reviewer-facing column reference (machine) |
| `limitations.md` | Explicit non-claims: not diagnostic, not clinical, not regulatory, not cross-matrix, not cross-cycle, not source-attribution | Lane-level non-claim register |
| `provenance.md` | NHANES CDC source URL, conversion path, SHA-256 of the canonical CSV, license, reproducibility recipe | Chain of custody for the v1.0 CSV |

## Anchor dataset

```text
Source:  https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/PFAS_J.xpt
Cycle:   J (NHANES 2017-2018)
n:       2,133 respondents in the PFAS subsample
         1,929 with at least one analyte value
Units:   ng/mL serum concentration
Panel:   9 analytes (n-PFOA, Sb-PFOA, n-PFOS, Sm-PFOS,
         PFHxS, PFNA, PFDA, PFUnDA, Me-PFOSA-AcOH)
```

The repo-canonical location of the converted CSV is:

```text
data/training/serum/nhanes_serum_pfas_2017_2018.csv
```

## Matrix-isolation requirement

This dataset must **not** be combined with environmental-matrix
datasets (drinking water, biosolids/sludge, AFFF, methanol
standards, air emissions, soil/sediment, fish/tissue) without an
explicit, documented cross-matrix harmonization artifact. The
enforcement is normative in `schema_contract.json`
(`matrix_isolation` block) and the refusal conditions in
`applicability_domain.txt`.

## Out-of-scope versions

- NHANES Pre-pandemic 2017-2020 (`P_PFAS.XPT`) -- not in v1.0.
- NHANES 2015-2016 (`PFAS_I.XPT`) -- not in v1.0.
- NHANES 2013-2014 (`PFAS_H.XPT`) -- not in v1.0 (peer lane issued).
  8-analyte panel that adds `LBXPFBS` / `LBXPFHP` / `LBXPFDO` and
  lacks v1.0's n-/Sb- PFOA and n-/Sm- PFOS isomer split (those live
  in the separate `SSPFAS_H.XPT` surplus-serum file). SAS labels
  read `(ug/L)` but the codebook LLOD table is in `ng/mL`; see
  `schema_contract.md` §7.1. **Cycle H is now governed as a peer
  lane under `validation/serum_h_v1/` (anchor SHA-256
  `98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f`).**
  That peer lane does **not** modify this v1.0 anchor and cannot
  be merged into it on a per-row basis without a documented
  cross-cycle harmonization artifact.
- NHANES 2013-2014 isomer companion (`SSPFAS_H.XPT`) -- not in v1.0.
  Recorded by SHA-256 in `validation/serum_h_v1/provenance.md`
  §3.1 but **not** admitted under serum_h_v1's anchor either.
- NHANES 2003-2004 (`L06AGE_C.XPT`, legacy panel) -- not in v1.0.

Each introduces a different analyte panel and / or concentration
regime relative to cycle J and requires a separate `serum_v1.1` or
`serum_v2` artifact, not a silent expansion of v1.0.

## Promotion

This directory is `draft` until:

1. A reviewer (the same reviewer-outreach packet under
   `validation/scope_freeze/v1.0/reviews/`, or an equivalent
   independent check) signs off that the AD and matrix-isolation
   statements are honest and defensible.
2. The converted CSV at `data/training/serum/nhanes_serum_pfas_2017_2018.csv`
   has its SHA-256 (recorded in `provenance.md` §3) added to a
   scope-freeze manifest entry for serum (or to the next
   scope-freeze version that supersedes v1.0).

Until then, no model trained on this lane may be promoted to a
deployed prediction endpoint.

## Read order (for a first-time external reviewer)

1. `intended_use.txt` — what this lane is for in one screen of text.
2. `limitations.md` — what this lane is **not** for (non-claims).
3. `applicability_domain.txt` — concrete inputs, envelope, refusals.
4. `schema_contract.md` — required columns, analyte panel, matrix
   isolation, promotion gate.
5. `data_dictionary.md` — per-column reference.
6. `provenance.md` — source URL, conversion path, SHA-256 anchor.

The machine-readable mirrors (`schema_contract.json`,
`data_dictionary.csv`) carry the same content as `schema_contract.md`
and `data_dictionary.md` respectively, and are consumed by code, not
by humans. If the narrative and the machine mirror disagree, the
narrative is the contract.
