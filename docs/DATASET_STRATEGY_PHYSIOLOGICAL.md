# PFAS Enterprise 5.0 — Physiological dataset strategy (governed)

**Revision:** 1.2 · **Date:** 2026-05-18  
**Status:** RUO planning document — not a data catalog commit  
**Related:** [GOVERNANCE.md](GOVERNANCE.md), [RELEASES.md](RELEASES.md), `validation/serum_demo_v1/`

---

## Why this document exists

Most public PFAS datasets online are **not** suitable for governed physiological ML because they are too small, poorly harmonized, missing demographics or weights, missing units, non-reproducible, or environmentally scoped without body-burden meaning.

PFAS Enterprise 5.0 prioritizes datasets that support **population-reference contextualization** with audit trails — not “more CSVs.”

---

## Minimum requirements (serum / physiological lane)

| Requirement | Why |
|-------------|-----|
| Human biomonitoring | Physiological interpretation |
| Serum or plasma PFAS | Body-burden matrix |
| Demographics (sex, age, race/ethnicity where available) | V1.1 strata |
| Survey weights (population surveys) | Weighted percentiles |
| Public raw files (XPT, documented exports) | Reproducibility + SHA governance |
| Large N | Stable reference distributions |
| Repeated cycles (optional) | V2 temporal contextualization |

---

## Reference-layer architecture (core design)

```text
NHANES  = baseline U.S. population (weighted percentiles)
ATSDR   = exposed-community validation (PFAS Exposure Assessments)
HBM4EU  = international harmonized comparison
UCMR5   = environmental exposure linkage (separate matrix lane)
```

**Product direction:** governed PFAS **exposure contextualization infrastructure** — not PFAS disease-prediction AI.

**Next technical capability (planned):** multi-reference percentile comparison — one cohort scored against each pinned reference layer without pooling distributions. See `validation/serum_multi_reference_v1/SPEC.md`.

## Tier architecture (recommended)

| Layer | Role | Primary dataset(s) | PFAS Enterprise status |
|-------|------|-------------------|------------------------|
| **Reference contextualization** | Weighted population percentiles | **NHANES** (cycles I, J, P; PFOS/PFOA isomers) | **Operational** — V1.1 + V2, pinned ref table |
| **Temporal contextualization** | Cross-cycle population comparison | **NHANES** repeated cycles | **Operational** — V2 |
| **External validation** | Exposed communities vs NHANES | **ATSDR PFAS Exposure Assessments** | **Scaffolded** — `validation/serum_atsdr_v1/` |
| **International validation** | Cross-country harmonized HBM | **HBM4EU / IPCHEM / VITO dashboard** | **Scaffolded** — `validation/serum_hbm4eu_v1/` |
| **Environmental linkage** | Drinking-water occurrence context | **UCMR5** | **Separate matrix lane** — not serum AD |
| **High-burden cohorts** | Exposure-gradient / litigation-adjacent RUO | **C8**, **Pease (NH)** | **Future** — ontology per cohort |
| **Reference framing (non-ML)** | Context thresholds, not training | **National Academies** | **Citation only** |

**Do not** merge tiers into one training table without a documented harmonization artifact, ontology version bump, and new release tag.

## Strict ML / analytics policy (physiological lane)

| Allowed | Forbidden |
|---------|-----------|
| Cohort contextualization, percentile shift | Disease / outcome prediction |
| NHANES deviation scoring, exposure clustering | Black-box ML on pooled multi-source tables |
| Hotspot profiling, demographic-normalized contrast | Health-outcome inference |
| Cross-cohort and multi-reference comparison (RUO) | Using ATSDR as NHANES reference replacement |

---

## Tier 1 — NHANES (foundation — in production)

**Why it is the moat:** U.S. gold-standard biomonitoring, survey weights, demographics, public XPTs, repeated cycles, massive literature.

### Official sources

- [CDC NHANES laboratory data](https://wwwn.cdc.gov/nchs/nhanes/search/datapage.aspx?Component=Laboratory)
- [CDC NHANES demographics](https://wwwn.cdc.gov/nchs/nhanes/search/datapage.aspx?Component=Demographics)
- Cycle examples:
  - [PFAS_I (2015–2016)](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2015/DataFiles/PFAS_I.htm)
  - [PFAS_J (2017–2018)](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/PFAS_J.htm)
  - [P_PFAS (2017–2020)](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_PFAS.htm)

### Repo integration (current)

| Artifact | Path |
|----------|------|
| Raw XPTs | `data/raw/nhanes/{cycle}/` |
| Governed input fixture | `data/v1/fixtures/nhanes_j_governed_v1_input.csv` |
| Weighted reference v1.1 | `data/reference_tables/nhanes_pfas_weighted_reference_tables_v1_1.csv` |
| Builder | `scripts/build_nhanes_weighted_reference_tables_v1_1.py` |
| Engines | `src/v1/`, `src/v2/` |

### ATSDR context (narrative only — not acquisition target)

- [ATSDR PFAS facts & stats](https://www.atsdr.cdc.gov/pfas/data-research/facts-stats/index.html) — summary narrative; **not** row-level serum for ML.

---

## Tier 2 — ATSDR PFAS Exposure Assessments (next external-validation priority)

**Why:** Real human serum PFAS in exposed communities; drinking-water-linked exposure; demographics; ATSDR already contrasts to NHANES in published EA analyses.

**Lane role:** high-exposure cohort validation — **not** baseline population reference.

### Sources (acquire these — not generic toxicology pages)

- [PFAS Exposure Assessments](https://www.atsdr.cdc.gov/pfas/exposure-assessments/index.html)
- [Final report — ten sites](https://www.atsdr.cdc.gov/pfas/final-report/index.html)
- [Final report PDF](https://www.atsdr.cdc.gov/pfas/docs/PFAS-EA-Final-Report-508.pdf)
- [Appendices PDF](https://www.atsdr.cdc.gov/pfas/docs/PFAS-EA-Final-Report-Appendices-508.pdf)
- [EA protocol PDF](https://www.atsdr.cdc.gov/pfas/docs/pfas-exposure-assessment-protocol-508.pdf)

Governance: `validation/serum_atsdr_v1/ACQUISITION_TARGETS.md`, `FIELD_CONTRACT.md`

### Integration policy (before any ingest)

1. Define **separate lane** (`validation/serum_atsdr_v1/`) — not mixed into NHANES reference engine. ✅ scaffold created
2. Document units, LOD policy, matrix (serum), and cohort ID per site.
3. Map to governed input schema or publish ATSDR-specific ontology.
4. SHA-pin raw downloads; no silent updates.
5. Compare distributions **against NHANES percentiles** (contextualization), not pooled training by default.

**Commercial use:** External validation cohorts for reports (“exposed community vs NHANES reference”).

---

## Tier 3 — HBM4EU (European harmonized HBM)

**Why:** Harmonized European biomonitoring; occupational and multi-country serum PFAS distributions.

### Sources

- [HBM4EU portal](https://www.hbm4eu.eu/)
- [HBM4EU PFAS substances](https://www.hbm4eu.eu/hbm4eu-substances/per-polyfluorinated-compounds/)
- [European HBM Dashboard (VITO)](https://hbm.vito.be/eu-hbm-dashboard)
- [IPCHEM HBM4EU portal](https://ipchem.jrc.ec.europa.eu/hbm4eu_overview.html)

Scaffold: `validation/serum_hbm4eu_v1/`

### Integration policy

- Treat as **international validation** layer only until harmonization spec is frozen.
- Do not assume U.S. NHANES strata map 1:1 to EU race/ethnicity categories.
- Requires explicit cross-walk document before ontology pin.

---

## Tier 4 — High-burden epidemiology cohorts (high value, high friction)

### C8 Health Project

- [C8 Science Panel data](https://www.c8sciencepanel.org/prob_link.html)
- Large PFOA-era cohort; exposure–response literature; **non-standard** vs NHANES.
- Use for: high-burden distribution context, external validation, **not** default reference percentiles.

### Pease Study (New Hampshire)

- [ATSDR Pease-related materials](https://www.atsdr.cdc.gov/pfas/pfas/progress-newsletter/february-2024.html)
- Community contamination; useful exposure-gradient validation vs NHANES.

**Policy:** Each cohort gets its own governance folder before code ingest. Expect weeks of harmonization — not a weekend CSV drop.

---

## Tier 5 — National Academies (reference framing only)

- [Guidance on PFAS testing and concentrations (NASEM)](https://www.nationalacademies.org/read/26156/chapter/7)
- Use for **RUO narrative context** and threshold discussion — not ML training rows without explicit extraction governance.

---

## Strict avoid list (do not invest engineering months)

| Source type | Reason |
|-------------|--------|
| Tiny papers (n ≪ 100) | Unstable ML / percentiles |
| Non-public hospital extracts | No reproducibility |
| Random Kaggle PFAS CSVs | Unknown provenance |
| Environmental-only (water/soil) without physiology | Wrong applicability domain |
| Synthetic / AI-generated PFAS data | Invalid validation evidence |
| Unweighted summary tables | Cannot reproduce weighted NHANES logic |

---

## Dataset ranking for governed contextualization (now)

| Rank | Dataset | Best use |
|------|---------|----------|
| 1 | NHANES | Baseline physiological contextualization |
| 2 | ATSDR EA | Exposed-cohort comparison |
| 3 | HBM4EU | International comparison |
| 4 | C8 | Longitudinal exposure research |
| 5 | UCMR5 | Environmental linkage |

## Best public ecosystem (strict summary)

```text
NHANES  +  ATSDR Exposure Assessments  +  HBM4EU  (+ UCMR5 for env linkage)
```

That triad is suitable for **governed contextualization** only in **separate lanes** with pinned provenance.

NHANES is operational (V1.1 + V2). Next disciplined steps: **ATSDR P0 row-level acquisition**, then **multi-reference percentile engine** (`validation/serum_multi_reference_v1/`).

---

## Acquisition discipline (anti-drift)

Before adding any new physiological dataset:

1. Write `validation/<lane>/intended_use.txt` + `limitations.md`
2. Pin raw file SHA-256 in `data/reference/registry/reference_registry.csv`
3. Add row to this document’s status table
4. **Do not** merge into `src/v1` reference table without version bump + tag
5. Run three-environment SHA confirm (PowerShell + Docker + manifest)

---

## What NOT to do next (commercial discipline)

- Download HBM4EU + C8 + ATSDR simultaneously “for ML”
- Train one random forest on a pooled mega-table
- Add dashboards before first **paid** NHANES contextualization report
- Claim clinical utility from exposed-community cohorts

**Next monetizable step:** Sell NHANES-governed contextualization reports using `validation/serum_demo_v1/` — then fund ATSDR lane ingest from pilot revenue.

---

## Document control

| Rev | Date | Change |
|-----|------|--------|
| 1.0 | 2026-05-17 | Initial physiological dataset tier strategy |
| 1.1 | 2026-05-18 | Added ATSDR lane scaffold + ingest SOP + registry protocol row |
| 1.2 | 2026-05-18 | Multi-reference architecture; ATSDR EA acquisition targets; HBM4EU scaffold; ML policy |
