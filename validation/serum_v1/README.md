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
| `schema_contract.json` | Machine-readable schema, analyte/LOD column pairing, observed envelope, matrix-isolation rule | Lane ingestion contract |
| `data_dictionary.csv` | Per-column documentation: dtype, units, raw NHANES field, role, analyte, LOD pairing, nullability | Reviewer-facing column reference |

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
- NHANES 2003-2004 (`L06AGE_C.XPT`, legacy panel) -- not in v1.0.

Both introduce different analyte panels and concentration regimes
relative to cycle J and require a separate `serum_v1.1` or
`serum_v2` artifact, not a silent expansion of v1.0.

## Promotion

This directory is `draft` until:

1. A reviewer (the same reviewer-outreach packet under
   `validation/scope_freeze/v1.0/reviews/`, or an equivalent
   independent check) signs off that the AD and matrix-isolation
   statements are honest and defensible.
2. The converted CSV at `data/training/serum/nhanes_serum_pfas_2017_2018.csv`
   has its SHA-256 added to a scope-freeze manifest entry for serum
   (or to the next scope-freeze version that supersedes v1.0).

Until then, no model trained on this lane may be promoted to a
deployed prediction endpoint.
