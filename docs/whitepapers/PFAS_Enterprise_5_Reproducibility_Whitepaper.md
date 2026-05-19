# Governed RUO PFAS Serum Contextualization Workflow with Docker-Verifiable Reproducibility

**PFAS Enterprise 5.0 — Technical whitepaper (draft)**  
**Version:** 0.1 · **Date:** 2026-05-19  
**Status:** RUO · Not peer-reviewed · Not regulatory

**DOI:** *(pending Zenodo archive)*

---

## Abstract

We describe a governed research-use-only (RUO) workflow for serum PFOS/PFOA
contextualization against weighted NHANES population references, with cross-cycle
temporal comparison (cycles I/J/P), manifest provenance (SHA-256), applicability-domain
refusal, schema-lock regression tests, and Docker-verifiable multi-environment parity.
The system prioritizes **exposure contextualization infrastructure** over disease
prediction or black-box machine learning. Independent blind reproducibility is structured
as a formal pilot program with frozen canonical outputs.

---

## 1. Introduction

PFAS biomonitoring interpretation requires population-referenced context, not isolated
concentrations. Most tools lack reproducible provenance, schema stability, and
environment-parity checks. PFAS Enterprise 5.0 implements a **layered governance model**
for serum PFOS/PFOA isomers with explicit non-claims (RUO).

---

## 2. Architecture

```text
Governed input (CSV) → ontology pin → reference table SHA check → AD gate
        → contextualization engine (V1.1 / V2) → manifest + report CSV/PDF
```

**Reference-layer roadmap (separate lanes, no pooling):**

| Layer | Role |
|-------|------|
| NHANES | U.S. baseline population percentiles (operational) |
| ATSDR Exposure Assessments | Exposed-community validation (scaffold) |
| HBM4EU | International comparison (scaffold) |

---

## 3. Provenance and manifests

Each run emits JSON manifest: input SHA, reference table SHA, ontology version,
output CSV SHA, `run_id`, git revision when available. Canonical demo fixture
(7,716 rows) produces deterministic `run_id` values across Windows, Docker, and CI.

---

## 4. Schema-lock and CI governance

- V1.1: race-aware columns locked (`race_ethnicity_*`, `race_stratum_fallback`)
- V2 cohort summary: subgroup metric columns locked
- GitHub Actions: Docker full verify + schema-lock tests
- Reference registry: `ci_required` scope for CI vs full local audit

---

## 5. NHANES contextualization (operational)

- **V1.1:** weighted percentiles with sex, age, race/ethnicity strata
- **V2:** cross-cycle population percentile comparison (I/J/P); not individual longitudinal

Canonical pins documented in `validation/serum_demo_v1/canonical_pins.json`.

---

## 6. Reproducibility evidence

| Check | Result (operator / CI) |
|-------|------------------------|
| CI Governance Checks | PASS on `62377e1` |
| Schema-lock pytest | 2/2 PASS |
| CI registry (13 rows) | PASS |
| Canonical CLI outputs | PASS (`LOCAL_REPRO_VERIFICATION.json`) |
| Independent blind repro | *In progress* (≥2 required) |

Public summary: `validation/public_reproducibility_summary.md`

---

## 7. Limitations (binding)

- Not diagnostic, clinical, or regulatory
- No PFAS source attribution from serum alone
- No disease-outcome inference
- ATSDR/HBM4EU lanes not active in v0.1 whitepaper results

---

## 8. Conclusion

PFAS Enterprise 5.0 demonstrates **governed scientific platform engineering** for serum
PFAS contextualization: frozen releases, manifest audit trails, schema locks, and
Docker-verifiable parity. Citable reproducibility (Zenodo DOI) and independent pilot
attestations are the intended credibility path — not feature sprawl or unfounded ML claims.

---

## References (selected)

- CDC NHANES laboratory data
- ATSDR PFAS Exposure Assessments: https://www.atsdr.cdc.gov/pfas/exposure-assessments/
- Repository: https://github.com/Ishola-github/pfas-enterprise-modular

---

## Author / contact

*[Add name, affiliation, email]*
