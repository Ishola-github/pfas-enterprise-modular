# Ingest SOP — ATSDR serum acquisition (v1 scaffold)

This SOP defines the acquisition and ingest control path for ATSDR serum cohort
data into PFAS Enterprise 5.0.

Status: scaffold. Execute only when ATSDR downloadable artifacts are confirmed.

## 1) Source confirmation

Use **Exposure Assessment** biomonitoring sources only (not generic toxicology docs).
See `ACQUISITION_TARGETS.md` for the full download list.

1. Confirm source URL(s):
   - https://www.atsdr.cdc.gov/pfas/exposure-assessments/index.html
   - https://www.atsdr.cdc.gov/pfas/final-report/index.html
   - https://www.atsdr.cdc.gov/pfas/docs/PFAS-EA-Final-Report-508.pdf
   - https://www.atsdr.cdc.gov/pfas/docs/PFAS-EA-Final-Report-Appendices-508.pdf
   - https://www.atsdr.cdc.gov/pfas/docs/pfas-exposure-assessment-protocol-508.pdf
   - Per-site pages under `…/pfas/exposure-assessments/<site>.html`
2. Record acquisition date and downloader identity.
3. Capture license/use terms at time of download.
4. Classify each file: row-level serum (P0), summary table (P1), narrative only (P3).

## 2) Raw staging structure

Use lane-separated directories:

```text
data/external/atsdr_pfas_ea/raw/
data/external/atsdr_pfas_ea/staging/
data/external/atsdr_pfas_ea/harmonized/
```

Do not store transformed files in `raw/`.

## 3) Integrity pinning

For every downloaded file:

1. Compute SHA-256 (`Get-FileHash` / `sha256sum`).
2. Add or update `data/reference/registry/reference_registry.csv` row.
3. Commit hash + path before writing harmonization scripts.

If the upstream file changes, create a new row/version; never overwrite history.

## 4) Schema triage

Before code ingestion, classify each file:

- row-level serum records,
- summary tables,
- metadata only,
- narrative report only.

Only row-level serum records may enter harmonization flow.

## 5) Harmonization contract (staging -> harmonized)

Map input columns per `FIELD_CONTRACT.md` (required + preferred fields).

Minimum governed fields:

- `analyte`, `result_value`, `result_unit`, `sample_matrix`
- `source_program` (set to `ATSDR PFAS EA`)
- `cohort_id` / `source_site`, collection year/window, LOD flags
- optional demographics (`sex`, `age_years`, `race_ethnicity`)
- optional drinking-water linkage fields (env metadata; not serum AD)

Explicitly document:

- unit conversions,
- non-detect handling/LOD conventions,
- analyte-name crosswalk decisions (PFOS, PFOA, PFHxS, PFNA priority).

## 6) Separation and non-pooling rule

ATSDR data must remain in a separate lane:

- no appending into NHANES weighted reference tables,
- no direct pooling into `src/v1` reference builders,
- no combined modeling without a separate harmonization artifact and ontology.

## 7) Manifest and evidence

For each ingest run, preserve:

- input file list + SHA-256,
- transform script version/commit,
- output artifact SHA-256,
- row counts (input/staging/harmonized),
- refusal/filtered row counts with reasons.

Store under:

```text
validation/serum_atsdr_v1/evidence/
```

## 8) Promotion gate (scaffold -> active lane)

Do not mark this lane active until all are true:

1. `INTENDED_USE.txt`, `scope.md`, and `limitations.md` approved.
2. At least one pinned raw dataset row exists in registry.
3. Reproducible ingest script passes on two environments (PowerShell + Docker).
4. Sample output manifests are generated and reviewed.

## 9) RUO and communication guardrails

All outputs must include RUO language and must not claim:

- clinical diagnosis,
- regulatory compliance determination,
- EPA or ISO software certification.
