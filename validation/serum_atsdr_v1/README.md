# Serum lane ATSDR scaffold (v1)

This directory defines the governance contract for a future **ATSDR serum
external-validation lane**.

Status: **spec-only scaffold**. No ATSDR raw dataset has been ingested yet.

## Purpose

- Keep ATSDR cohort data in a **separate governed lane** from NHANES reference
  contextualization.
- Define acquisition controls before any download, transform, or merge.
- Preserve RUO and matrix-isolation discipline.

## Lane role

```text
NHANES = baseline U.S. population reference
ATSDR  = high-exposure community validation (this lane)
```

Official hub: [PFAS Exposure Assessments](https://www.atsdr.cdc.gov/pfas/exposure-assessments/index.html)

## Governance files

| File | Role |
|------|------|
| `ACQUISITION_TARGETS.md` | What to download (serum EA data, not toxicology docs) |
| `FIELD_CONTRACT.md` | Required/preferred fields and allowed analytical uses |
| `INTENDED_USE.txt` | Permitted and prohibited use statements |
| `limitations.md` | Binding non-claims and caveats |
| `scope.md` | Lane boundaries and output expectations |
| `INGEST_SOP.md` | Step-by-step ATSDR acquisition and ingest procedure |
| `EXTERNAL_REVIEWER_PACKET.md` | Who to contact, packet contents, and pass/fail gates for kickoff |

## Hard rules

1. Do **not** append ATSDR rows into NHANES reference tables.
2. Do **not** claim clinical or regulatory conclusions.
3. Do **not** ingest any ATSDR file without SHA-256 pinning in
   `data/reference/registry/reference_registry.csv`.
4. Keep raw, staged, and harmonized outputs separated:
   - `data/external/atsdr_pfas_ea/raw/`
   - `data/external/atsdr_pfas_ea/staging/`
   - `data/external/atsdr_pfas_ea/harmonized/`

## Relationship to existing serum lanes

- `validation/serum_v1/`: NHANES single-cycle contextualization.
- `validation/serum_v2/`: NHANES cross-cycle temporal contextualization.
- `validation/serum_atsdr_v1/` (this folder): non-NHANES external validation
  cohort lane.
