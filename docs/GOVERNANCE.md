# PFAS Enterprise 5.0 — Governance doctrine (serum lane)

This document describes how the **governed serum PFOS/PFOA contextualization lane** is
intended to operate. It is the credibility layer above code: what we claim, what we refuse,
and how reproducibility is enforced.

**Status:** RUO (research use only). **Not** a medical device, diagnostic, or regulatory product.

---

## 1. Governed scope

| In scope | Out of scope |
|----------|----------------|
| Human serum / plasma, NHANES-style PFOS/PFOA isomers (`n_pfoa`, `sb_pfoa`, `n_pfos`, `sm_pfos`) | Environmental matrices (water, sludge, air, AFFF, etc.) without explicit harmonization |
| Population-reference percentiles (weighted NHANES) | Individual clinical diagnosis or treatment decisions |
| Demographic strata: sex, age group, race/ethnicity (V1.1+) | Source attribution or causation |
| Cross-cycle **population** comparison (V2: cycles I, J, P) | Individual longitudinal follow-up |
| ng/mL concentrations, CDC NHANES source program | Cross-matrix training or prediction |

Matrix isolation is **normative**. Serum rows must not silently merge with environmental occurrence data.

---

## 2. Layered releases

| Layer | Package | Governance dir | Default |
|-------|---------|------------------|---------|
| V1.0 | `src/v1/` + `pfos_pfoa_v1.json` | `validation/serum_v1/` | Legacy only |
| **V1.1** | `src/v1/` + `pfos_pfoa_v1_1.json` | `validation/serum_v1/` | **Shiny + production default** |
| V2.0 | `src/v2/` + `pfos_pfoa_v2.json` | `validation/serum_v2/` | Temporal add-on (requires V1.1 input schema) |

Release tags and pinned hashes: [RELEASES.md](RELEASES.md).

---

## 3. Ontology pinning

Each run loads a **frozen ontology JSON** that specifies:

- required and optional input columns,
- allowed analytes and units,
- reference table path and **documented SHA-256**,
- applicability-domain rules.

At runtime the engine **hashes the reference table on disk** and **refuses** if it does not match the ontology pin (`ReferenceTableDrifted`). This prevents silent drift after rebuilds.

**Policy:** Never change `reference_table_sha256` in the ontology without a version bump, tag, and three-environment SHA confirmation.

---

## 4. Applicability domain (AD)

Rows outside the validated envelope are **refused** (`ad_status=refused`), not coerced:

- wrong matrix, unit, or source program,
- unsupported analyte,
- missing required fields,
- values outside training/reference envelope (per-lane AD models where enabled).

Refused rows have analytical outputs blanked. Decisions are auditable via manifests and optional `data/audit/ad_decisions.jsonl`.

---

## 5. Demographic harmonization (V1.1)

| Input | Stratum behavior |
|-------|------------------|
| `sex` (1=male, 2=female) | `sex_stratum` or `all` if missing |
| `age_years` | NHANES age groups via `normalize_age_group` |
| `race_ethnicity` | Collapsed categories; `MIN_N_RACE_STRATUM=20` with documented fallback |
| `lod_code` | LOD flags on report; no silent imputation beyond documented policy |

Hispanic collapse (`mexican_american` + `other_hispanic` → `hispanic`) is implemented in `src/v1/race_strata_policy.py`.

---

## 6. Temporal contextualization (V2)

V2 compares **weighted population percentiles** for the same demographic stratum across NHANES cycles **I, J, P**:

- `percentile_cycle_I/J/P`, anchor cycle, deltas,
- `temporal_context_flag` (e.g. `cross_cycle_percentile_shift_ge_15`),
- cycle P labeled pre-pandemic (WTSBAPRP caveat).

**Not** within-person longitudinal tracking. Do not narrate V2 outputs as individual trajectories.

---

## 7. Manifest provenance

Every CLI run writes `v1_manifest_<run_id>.json` or `v2_manifest_<run_id>.json` containing:

- input CSV SHA-256,
- ontology path and SHA-256,
- reference table SHA-256 (actual vs documented),
- output report SHA-256,
- code/ontology version,
- git revision when available.

Manifests are the **scientific audit trail** for demos, grants, and institutional review.

---

## 8. Reproducibility policy

| Environment | Verification |
|-------------|----------------|
| Windows PowerShell | `Get-FileHash`; `scripts/confirm_anchors_powershell.ps1`; `scripts/smoke_v*_shiny_integration.R` |
| Docker/Ubuntu | `Dockerfile.linux-verify`; `scripts/docker_verify_linux.sh`; `scripts/docker_recheck_v2.sh`; `scripts/confirm_reference_tables_docker.sh` |
| RStudio Shiny | `PFAS_on_R_Studio` synced via `scripts/sync_serum_lane_to_rstudio.ps1` |

**Expectation:** Same fixture + pinned reference table → same `run_id` and output CSV SHA across environments (see [RELEASES.md](RELEASES.md)).

---

## 9. Reference table governance

| Table | Rows (current) | SHA-256 | Builder |
|-------|----------------|---------|---------|
| `nhanes_pfas_weighted_reference_tables_v1.csv` | v1.0 | `715cd896…` | v1 builder |
| `nhanes_pfas_weighted_reference_tables_v1_1.csv` | 988 | `fe195d62…` | `scripts/build_nhanes_weighted_reference_tables_v1_1.py` |

Rebuild procedure:

1. Run builder from repo root with raw NHANES XPTs present under `data/raw/nhanes/`.
2. Confirm SHA in PowerShell and Docker (`confirm_reference_tables_docker.sh` includes v1_1).
3. Update ontology pin + [RELEASES.md](RELEASES.md) + new git tag if material.

**Warning:** Stale or nested-copy tables in RStudio (wrong SHA, row count 1040) indicate sync error — re-run sync script, do not use for governed runs.

---

## 10. RUO restrictions (non-claims)

Do **not** state or imply:

- clinical diagnosis, risk classification for individuals, or medical action,
- EPA/regulatory compliance or legal defensibility,
- PFAS source identification from serum alone,
- diagnostic-grade precision or LOQ certification beyond NHANES reference context.

Permitted framing: population-reference contextualization, research analytics, exposure intelligence, pilot environmental-health decision support with human review.

---

## 11. Architectural discipline (anti-patterns)

| Do | Do not |
|----|--------|
| Add datasets through versioned builders + ontology bumps | Drop CSVs into `data/` without pins |
| Keep serum lane isolated from environmental ML | Mix serum rows into occurrence training |
| Tag releases; update RELEASES.md | Run production Shiny on unversioned `main` without tags |
| Extend V2 from governed report CSVs for cohort work | Re-implement NHANES joins in Shiny server |
| Document limitations in `validation/serum_*` | Expand UI claims faster than governance docs |

---

## 12. Key paths

```text
src/v1/                          V1/V1.1 engine
src/v2/                          V2 temporal engine
validation/serum_v1/             V1 governance contract
validation/serum_v2/             V2 governance contract
data/v1/fixtures/                Governed input examples
data/reference_tables/           Pinned NHANES reference tables
docs/RELEASES.md                 Tag index and reproduction
scripts/sync_serum_lane_to_rstudio.ps1   Deploy to Shiny project
```

---

## 13. Contact / change control

Ontology or reference-table changes require: version increment, validation doc update, smoke + Docker recheck, new release tag, and RELEASES.md entry.
