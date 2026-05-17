# Serum_h lane governance scaffolding (v1.0)

This directory holds the **minimum governance contract** for the
NHANES cycle-H (2013-2014) human serum biomonitoring lane of PFAS
Enterprise 5.0, anchored to the NHANES 2013-2014 PFAS Special
Subsample (`PFAS_H.XPT`).

It is intentionally small. It is also intentionally **separate
from environmental-matrix lanes** (`drinking_water_v1`,
`biosolids_sludge_v1`, `afff_v1`, etc.) because human serum is
internal-exposure data, not environmental-source data — and
intentionally **separate from the cycle-J serum lane**
(`validation/serum_v1/`) because the cycle-H analyte panel and
label-unit semantics differ from cycle J in ways that cannot be
silently merged.

## Files in this directory

| File | Purpose | Authority |
| --- | --- | --- |
| `intended_use.txt` | What this lane is for, and what it explicitly is **not** for | Lane-level scope statement |
| `applicability_domain.txt` | Concrete in-domain inputs, numeric envelope (cycle-H constant 0.10 ng/mL LLOD), refusal conditions | AD boundary for serum_h v1.0 |
| `schema_contract.md` | Human-readable schema: required columns, analyte/LOD pairings, observed envelope, matrix-isolation rule, label-unit reconciliation (§3.2), refusal conditions, promotion gate | Lane ingestion contract (narrative) |
| `schema_contract.json` | Machine-readable mirror of `schema_contract.md` | Lane ingestion contract (machine) |
| `data_dictionary.md` | Per-column documentation in markdown: dtype, units, raw NHANES field, role, analyte, LOD pairing, nullability, reading rules | Reviewer-facing column reference (narrative) |
| `data_dictionary.csv` | Machine-readable mirror of `data_dictionary.md` | Reviewer-facing column reference (machine) |
| `limitations.md` | Explicit non-claims: not diagnostic, not clinical, not regulatory, not cross-matrix, not cross-cycle, not source-attribution, no admission of `SSPFAS_H.XPT` | Lane-level non-claim register |
| `provenance.md` | NHANES CDC source URLs, Docker / Ubuntu fetch+convert pipeline, SHA-256s of both raw XPTs and the derived anchor CSV, license, reproducibility recipe | Chain of custody for the serum_h v1.0 CSV |

## Anchor dataset

```text
Source:  https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/PFAS_H.xpt
Cycle:   H (NHANES 2013-2014)
n:       2,339 rows in the cycle-H PFAS subsample
         2,170 with at least one analyte value
Units:   ng/mL serum concentration (after label-unit reconciliation;
         the SAS labels read "(ug/L)" -- see schema_contract.md §3.2)
Panel:   8 analytes
         PFDeA, PFHxS, Me-PFOSA-AcOH, PFBS (cycle-H only),
         PFHpA (cycle-H only), PFNA, PFUnDA, PFDoA (cycle-H only)
LLOD:    constant 0.10 ng/mL across all 8 analytes
```

The repo-canonical location of the converted CSV is:

```text
data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv
SHA-256: 98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f
```

The raw NHANES XPT files live at:

```text
data/external/nhanes_serum_h/PFAS_H.XPT
SHA-256: ab062b2ecf99989b1731cb63588d8305409c2e554a76de7e05946f4877091652

data/external/nhanes_serum_h/SSPFAS_H.XPT       (isomer companion; recorded, not admitted)
SHA-256: 1e23688dfa6bdfdc14c0447f4d34032983271063a1a343c04338ae4258515c99
```

## Sibling lane (frozen, unaffected)

The cycle-J serum lane is governed separately:

```text
Governance dir:   validation/serum_v1/
Anchor CSV:       data/training/serum/nhanes_serum_pfas_2017_2018.csv
Anchor SHA-256:   dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f
```

Nothing in this directory modifies the cycle-J lane. The two
anchors are independent peer artifacts. Cross-cycle joins between
them require a documented harmonization artifact (not yet issued).

## Reproducibility recipe (Docker / Ubuntu)

```bash
docker run --rm \
  -v "$(pwd):/workspace" \
  -w /workspace \
  rocker/r-ver:4.4 \
  bash scripts/docker_fetch_pfas_h.sh
```

The script (`scripts/docker_fetch_pfas_h.sh`) is idempotent:
running it a second time produces the same hashes if the upstream
CDC files are unchanged. Detailed steps and verification commands
are in `provenance.md` §2–3.

An R-only peer of the same conversion (no Docker required) lives
at `scripts/convert_pfas_h_xpt_to_csv.R`.

## Matrix-isolation requirement

This dataset must **not** be combined with environmental-matrix
datasets (drinking water, biosolids/sludge, AFFF, methanol
standards, air emissions, soil/sediment, fish/tissue) without an
explicit, documented cross-matrix harmonization artifact. It must
also **not** be combined with the cycle-J serum lane on a per-row
basis without a documented cross-cycle harmonization artifact. The
enforcement is normative in `schema_contract.json`
(`matrix_isolation` block) and the refusal conditions in
`applicability_domain.txt`.

## Out-of-scope artifacts

- `SSPFAS_H.XPT` (surplus-serum isomer companion for cycle H) —
  recorded in `provenance.md` §3.1 but **not** admitted under this
  anchor. Admission requires a follow-up artifact (see
  `schema_contract.md` §7.1).
- `PFAS_J.XPT` (cycle J, 2017-2018) — governed separately by
  `validation/serum_v1/`. Cross-cycle merging requires its own
  artifact.
- `PFAS_I.XPT` (cycle I, 2015-2016) — requires its own
  `serum_i_v1` lane.
- `P_PFAS.XPT` (Pre-pandemic 2017-2020) — requires its own
  `serum_prepandemic_v1` lane.
- `L06AGE_C.XPT` (cycle C, 2003-2004, legacy panel) — requires its
  own `serum_c_v1` lane.

## Promotion

This directory is `draft` until:

1. A reviewer (the same reviewer-outreach packet under
   `validation/scope_freeze/`, or an equivalent independent check)
   signs off that the AD, the matrix-isolation statements, and the
   cycle-H specific label-unit reconciliation (§3.2 of
   `schema_contract.md`) are honest and defensible.
2. The converted CSV at
   `data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv` has
   its SHA-256 (recorded in `provenance.md` §3) added to a
   scope-freeze manifest entry for serum_h.

Until then, no model trained on this lane may be promoted to a
deployed prediction endpoint.

## Build-pipeline integration status (as of 2026-05-13)

This lane is **governance-only**. The anchor CSV is on disk and
the contract is locked, but the lane is **not** yet wired into:

- `data/config/matrix_pipeline_sop.csv` (no `serum_h` row).
- `scripts/run_matrix_pipeline.py` (the `_build_serum_h` helper
  and the `PHYSIOLOGICAL_LANE_STAMPS` extension do not exist
  yet).
- `LatestPFAS.R` (no `serum_h` entry in `PHYSIOLOGICAL_LANE_STAMPS`;
  the Shiny app does not yet offer a `serum_h` upload lane).
- `data/training/serum_h/manifest.json` (does not exist yet).
- `data/ad_models/serum_h/ad_model.json` (does not exist yet).

Wiring is a separate follow-up that must (a) update the SOP, (b)
emit a stamped training table, (c) build an AD model, and (d)
extend `PHYSIOLOGICAL_LANE_STAMPS` in both Python and R to include
`serum_h` with the stamp documented in
`schema_contract.md` §9.

## Read order (for a first-time external reviewer)

1. `intended_use.txt` — what this lane is for in one screen of text.
2. `limitations.md` — what this lane is **not** for (non-claims).
3. `applicability_domain.txt` — concrete inputs, envelope, refusals.
4. `schema_contract.md` — required columns, analyte panel, matrix
   isolation, label-unit reconciliation (§3.2), promotion gate.
5. `data_dictionary.md` — per-column reference.
6. `provenance.md` — source URLs, Docker/Ubuntu pipeline, SHA-256
   anchors.

The machine-readable mirrors (`schema_contract.json`,
`data_dictionary.csv`) carry the same content as
`schema_contract.md` and `data_dictionary.md` respectively, and
are consumed by code, not by humans. If the narrative and the
machine mirror disagree, the narrative is the contract.
