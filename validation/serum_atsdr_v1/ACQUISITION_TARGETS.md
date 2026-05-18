# ATSDR PFAS Exposure Assessments — acquisition targets (v1)

**Status:** specification only — no raw serum files ingested yet.

This document lists the **structured biomonitoring artifacts** PFAS Enterprise 5.0 needs.
It does **not** cover generic ATSDR toxicology documentation pages.

---

## Primary official entry points

| Resource | URL | Use in Enterprise 5.0 |
|----------|-----|------------------------|
| **Exposure Assessments hub** | https://www.atsdr.cdc.gov/pfas/exposure-assessments/index.html | Program scope, site list, EA methodology |
| **Final report (ten sites)** | https://www.atsdr.cdc.gov/pfas/final-report/index.html | Cross-site findings; NHANES contrast narrative |
| **Final report PDF** | https://www.atsdr.cdc.gov/pfas/docs/PFAS-EA-Final-Report-508.pdf | Methods, tables, age-adjusted NHANES comparisons |
| **Appendices A–C PDF** | https://www.atsdr.cdc.gov/pfas/docs/PFAS-EA-Final-Report-Appendices-508.pdf | Supplementary tables / site detail |
| **EA protocol PDF** | https://www.atsdr.cdc.gov/pfas/docs/pfas-exposure-assessment-protocol-508.pdf | Field definitions, sampling design |
| **Per-site EA pages** | e.g. `…/exposure-assessments/<site>.html` | Site-specific serum summaries and methods |

**Deprecated for acquisition:** `pfas/activities/assessments/` redirects conceptually to Exposure Assessments; pin downloads from `exposure-assessments` and `final-report` paths only.

---

## Lane role (architecture)

```text
NHANES  = baseline U.S. population reference (weighted percentiles)
ATSDR   = high-exposure community validation (exposed cohorts)
HBM4EU  = international comparison (future lane)
UCMR5   = environmental exposure linkage (separate matrix lane)
```

ATSDR is **not** a replacement NHANES reference table. Use ATSDR for:

- elevated-exposure cohort contextualization,
- percentile shift vs NHANES,
- demographic-normalized contrast,
- hotspot / community profiling,
- manifest-backed external validation.

**Do not** use ATSDR first for disease prediction, black-box ML, or health-outcome inference.

---

## Download priority (when acquisition starts)

| Priority | Artifact type | Expected content | Ingest? |
|----------|---------------|------------------|---------|
| P0 | Row-level serum PFAS + demographics (if published per site) | analyte, concentration, unit, sex, age, race/ethnicity, site ID | **Yes** — harmonized lane only |
| P1 | Site-level summary tables with serum statistics | medians, percentiles, N by analyte/site | **Maybe** — summary-only lane; no row-level AD |
| P1 | Final report / appendix tables (machine-readable if extracted) | age-adjusted community vs NHANES | **Maybe** — validation cross-check only |
| P2 | Drinking-water PFAS linkage tables | water source, concentration, household | **Separate** env linkage artifact; not merged into serum AD |
| P3 | Narrative PDFs only | methods, charts | **No** for ML — citation and manual QA only |

Before any P0 ingest: SHA-pin each file in `data/reference/registry/reference_registry.csv`.

---

## Staging layout (raw → harmonized)

```text
data/external/atsdr_pfas_ea/raw/<site_or_bundle>/
data/external/atsdr_pfas_ea/staging/
data/external/atsdr_pfas_ea/harmonized/
validation/serum_atsdr_v1/evidence/
```

---

## Per-site pages (ATSDR-led + pilots)

Collect links and download manifests per site when row-level files are identified:

- Westhampton / Quogue, NY (pilot)
- Montgomery / Bucks, PA (pilot)
- Hampden County, MA (Westfield)
- Berkeley County, WV
- New Castle County, DE
- Spokane County, WA (Airway Heights)
- Lubbock County, TX
- Fairbanks North Star Borough, AK (Moose Creek)
- El Paso County, CO (Security-Widefield)
- Orange County, NY

**Note:** ATSDR combined blood data from pilot EAs with ATSDR-led EAs in final-report analyses; document provenance when harmonizing.

---

## Promotion gate

Replace `PENDING_DATASET_NOTICE.txt` registry row with **one registry row per pinned raw file** only after:

1. P0 row-level serum file confirmed (not summary-only),
2. `FIELD_CONTRACT.md` mapping completed,
3. ingest script reproducible on PowerShell + Docker,
4. sample contextualization manifest reviewed.

See `INGEST_SOP.md` and `FIELD_CONTRACT.md`.
