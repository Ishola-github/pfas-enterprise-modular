# PFAS Enterprise 5.0 — Standard Operating Procedure (SOP)

| Field | Value |
| ----- | ----- |
| **Document ID** | PE5-SOP-SUITE |
| **Revision** | **2.1** |
| **Effective date** | 2026-05-17 |
| **Supersedes** | Rev 1.0 (2026-05-10) |
| **Git baseline** | `main` ≥ `6efc685`; serum tags per [RELEASES.md](../RELEASES.md) |
| **Status** | Active — RUO screening & contextualization platform |

---

## 1. Purpose

This SOP defines the operational procedures for the PFAS Enterprise 5.0 application used for PFAS screening workflows, exploratory machine learning, environmental occurrence analysis, threshold-governed screening review, validation reporting, evidence traceability, manifest generation, reproducibility tracking, screening prioritization, **governed serum PFOS/PFOA physiological contextualization**, and audit-oriented workflow governance.

## 2. Scope

This SOP applies to:

- PFAS Enterprise 5.0 Shiny application workflows (`PFAS_on_R_Studio` / `LatestPFAS.R`)
- Local RStudio execution, PowerShell-assisted execution, and Docker/Ubuntu verification
- Governed validation workflows (drinking-water v1, serum v1/v1.1/v2)
- Exploratory screening workflows (`results/screening/`)
- Evidence freeze procedures, threshold governance, reference-data governance
- Machine learning validation reporting and serum lane manifest provenance

## 3. Intended Use Statement

PFAS Enterprise 5.0 is intended for environmental screening support, PFAS prioritization workflows, exploratory analytical support, governed validation tracking, machine learning-assisted screening review, environmental occurrence screening, and **population-reference serum PFOS/PFOA contextualization (RUO)**.

The system is **not** intended to replace certified laboratory analysis, issue regulatory compliance determinations, function as a confirmatory analytical platform, or provide clinical diagnosis.

## 4. Regulatory Positioning

The application is positioned as a screening and prioritization platform and environmental informatics workflow system. It is **not** represented as ISO-certified software, EPA-approved analytical software, or a replacement for laboratory PFAS analysis.

## 5. Responsibilities

| Role | Responsibility |
| ---- | -------------- |
| **Technical owners** | Application maintenance, freeze governance, evidence retention, provenance preservation, ontology/reference pinning |
| **QA personnel** | Repeatability review, validation review, threshold-governance review, three-environment SHA confirmation |
| **Operators** | Preserve evidence integrity; follow SOP procedures; do not mix screening and governed outputs in claims |

## 6. System Requirements

| Component | Requirement |
| --------- | ------------- |
| **R** | RStudio; `shiny`, `DT`, `jsonlite` (R smoke / Shiny wrappers) |
| **Python** | 3.10+; `pandas`; repo `requirements.txt` (FastAPI smoke, V1/V2 CLI) |
| **Shell** | PowerShell (Windows); bash (WSL2/Docker/Ubuntu) |
| **Version control** | Git with serum release tags (see §31–35) |
| **Optional ML** | scikit-learn, xgboost, pyarrow (UCMR / occurrence lanes) |
| **Docker** | Docker Desktop + `Dockerfile.linux-verify` for Linux parity |

**Windows Python default (operator workstation):** `C:\pfasenv\Scripts\python.exe`  
Set `PFAS_PYTHON` when non-default.

## 7. Folder Structure

### Core (all lanes)

```text
PFAS_on_R_Studio/          # Shiny operational project (or canonical repo root)
├── LatestPFAS.R           # Shiny UI (Reports tab: serum V1.1 + V2)
├── scripts/               # R wrappers, smoke tests, sync, builders
├── data/
│   ├── config/            # matrix_pipeline_sop.csv
│   ├── reference_tables/  # pinned NHANES weighted tables (v1, v1_1)
│   ├── reference/registry/# reference_registry.csv
│   ├── v1/fixtures/       # governed serum input (e.g. nhanes_j_governed_v1_input.csv)
│   ├── v1/outputs/        # V1 report CSV, PDF stub, manifest JSON
│   ├── v2/outputs/        # V2 cross-cycle reports
│   ├── training/serum/    # NHANES serum anchor CSV
│   └── raw/nhanes/        # XPT sources (rebuild only via versioned scripts)
├── src/v1/                # V1 / V1.1 engine
├── src/v2/                # V2 temporal engine
├── validation/serum_v1/   # V1 governance contract
├── validation/serum_v2/   # V2 governance contract
├── validation/drinking_water_v1/
├── results/               # governed ML / screening outputs
├── results/screening/     # exploratory only — not governed evidence
├── models/                # joblib artifacts (UCMR, etc.)
└── docs/
    ├── RELEASES.md        # serum tag index + pinned SHAs
    ├── GOVERNANCE.md      # serum doctrine
    └── sop/               # this SOP (Rev 2.1)
```

### Governed model artifacts (examples)

- `models/ucmr_threshold_sweep.csv`, `ucmr_training_metrics.json`, `ucmr_training_provenance.json`
- `models/pfas_detect_sklearn.joblib`
- `data/ad_models/serum/ad_model.json` (applicability-domain; registry-pinned SHA)

## 8. Startup Procedure

1. Open PowerShell; navigate to the Shiny project root:

   ```powershell
   cd C:\Users\techj\OneDrive\Desktop\python_work\PFAS_on_R_Studio
   ```

2. Verify Python:

   ```powershell
   C:\pfasenv\Scripts\python.exe --version
   ```

3. **(After canonical repo updates)** Sync serum lane from `pfas-toxicology`:

   ```powershell
   cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
   powershell -ExecutionPolicy Bypass -File scripts\sync_serum_lane_to_rstudio.ps1
   ```

4. Open RStudio; set working directory to `PFAS_on_R_Studio`.

5. Launch Shiny:

   ```r
   shiny::runApp()
   ```

6. In the app: **Reports** tab → **V1.1** (default) or **V2 cross-cycle** sections.

## 9. PowerShell Verification

From project root:

```powershell
Get-Location
git branch
git tag -l "serum-*"

# Serum fixture
Test-Path data\v1\fixtures\nhanes_j_governed_v1_input.csv

# V1.1 reference table SHA (must match ontology pin)
(Get-FileHash -Algorithm SHA256 data\reference_tables\nhanes_pfas_weighted_reference_tables_v1_1.csv).Hash.ToLower()
# Expected: fe195d6206d98d1e2281213fdc937dace468b57f9f8518bfca0e3496d0ba8f19

# Drinking-water / ML governed artifacts (when applicable)
Test-Path results\label_derivation_audit.json
Test-Path validation\drinking_water_v1\runs\
Get-ChildItem models\ucmr_*.json -ErrorAction SilentlyContinue
```

Serum anchor confirmation:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\confirm_anchors_powershell.ps1
Get-Content validation\serum_h_v1\.confirm_powershell.txt
```

## 10. RStudio Verification

```r
getwd()  # must be PFAS_on_R_Studio
file.exists("LatestPFAS.R")
file.exists("scripts/run_v1_contextualization.R")
file.exists("scripts/run_v2_contextualization.R")
file.exists("data/v1/fixtures/nhanes_j_governed_v1_input.csv")
file.exists("src/v2/data/ontology/pfos_pfoa_v2.json")
list.files("validation/serum_v1")
```

## 11. Governed Workflow

Governed runs write auditable outputs including:

- Report CSV + provenance manifest JSON (`v1_manifest_<run_id>.json`, `v2_manifest_<run_id>.json`)
- Output SHA-256 in manifest (replay verification)
- Metrics JSONs, prediction CSVs, hashes, freeze declarations (lane-dependent)
- Drinking-water: `validation/drinking_water_v1/` bundle per `FREEZE_v1.md`

**Serum V1.1 CLI (production default):**

```powershell
python -m src.v1.cli --v1-1 `
  --input data\v1\fixtures\nhanes_j_governed_v1_input.csv `
  --output-dir data\v1\outputs
```

**Serum V2 CLI:**

```powershell
python -m src.v2.cli `
  --input data\v1\fixtures\nhanes_j_governed_v1_input.csv `
  --output-dir data\v2\outputs
```

## 12. Exploratory Screening Workflow

Exploratory workflows write under `results/screening/`. Outputs **must remain separated** from governed evidence runs and **must not** be represented as regulated laboratory validation evidence or serum RUO contextualization.

## 13. Matrix Separation Policy

PFAS reference materials, environmental occurrence datasets, **serum biomonitoring (NHANES)**, methanol standards, and AFFF reference materials **must remain separated** by matrix and intended use.

- Serum rows (`sample_matrix=human_serum`) **must not** merge with environmental occurrence training without a documented harmonization artifact.
- Cross-matrix interpretation without documented justification is **prohibited**.
- Enforced in upload mapper, AD models, and `validation/serum_v1/schema_contract.json`.

## 14. Threshold Governance

Screening thresholds must be frozen during governed validation and external blind evaluation. Threshold selection should consider recall, precision, false-positive burden, flags-per-10k, and operational workload metrics.

## 15. Applicability Domain

Predictions or contextualization rows outside validated matrix, analyte, unit, or dataset domains are **refused** (`ad_status=refused`) or flagged exploratory — excluded from governed validation claims. Serum AD: `data/ad_models/serum/ad_model.json`.

## 16. Provenance Governance

Governed runs must preserve:

- Source dataset identity and input CSV SHA-256
- Ontology path and SHA-256
- Reference table actual vs documented SHA-256
- Output report SHA-256, `run_id`, timestamp, code version, git revision (when available)

## 17. Synthetic Data Restriction

Synthetic or demonstration datasets must not be represented as environmental occurrence validation evidence, external validation evidence, regulatory screening evidence, or NHANES population-reference evidence.

## 18. External Running Route SOP

External workflows must preserve frozen thresholds, avoid retraining during blind validation, document reviewer information, preserve hashes and manifests for all evidence bundles, and retain provenance metadata.

## 19. Validation Workflow

Generate audit-oriented validation reports, ML validation reports, prediction CSVs, provenance artifacts, threshold sweeps, and governed evidence artifacts per lane (`validation/drinking_water_v1/`, `validation/serum_v1/`, `validation/serum_v2/`).

## 20. Freeze Procedure

### Drinking water

Copy required files into `validation/drinking_water_v1/artifacts/` and document in `FREEZE_v1.md`.

### Serum lane (git tags — primary freeze mechanism)

| Tag | Purpose |
| --- | ------- |
| `serum-v1.0-governed` | Sex/age strata; v1 weighted reference |
| `serum-v1.1-demographics` / `serum-v1.1-race-aware` | Race-aware strata; v1_1 reference (988 rows) |
| `serum-v2.0.0-temporal` | Cross-cycle I/J/P population comparison |

Full pin table: `docs/RELEASES.md`. Do not move or force-push serum tags.

## 21. Hashing and Manifest Procedure

### Drinking water (legacy route)

Generate hashes using `scripts/write_run_hashes.cmd` and update `manifest.json` using the `-UpdateManifest` flag.

### Serum lane

Each CLI run emits `v1_manifest_<run_id>.json` or `v2_manifest_<run_id>.json` with embedded SHA-256 values. Three-environment reference confirmation:

```powershell
# PowerShell
(Get-FileHash -Algorithm SHA256 data\reference_tables\nhanes_pfas_weighted_reference_tables_v1_1.csv).Hash

# Docker/Ubuntu
docker run --rm -v "${PWD}:/app" -w /app ubuntu:22.04 bash -c `
  "sed -i 's/\r$//' scripts/confirm_reference_tables_docker.sh && bash scripts/confirm_reference_tables_docker.sh"
```

## 22. Repeatability Procedure

Execute three identical runs using the same inputs, seed (where applicable), threshold, and model configuration. For serum contextualization, identical fixture + pinned reference table must yield identical `run_id` and `output_csv_sha256` (see `docs/RELEASES.md` exemplar: `run_id=2bda057f5ab18ff6`, output `87c8b97e…`).

## 23. External Blind Validation

Perform blind evaluation without threshold tuning using the frozen governed configuration. Preserve all provenance and evidence artifacts.

## 24. Pilot Reviewer Validation

Collect reviewer feedback on trust, usability, interpretability, operational burden, and screening workflow utility using pilot review forms and anonymized summaries.

## 25. Approved Public PFAS Data Sources

Approved public sources include EPA UCMR5, EPA CompTox, California GAMA, **CDC NHANES PFAS serum** (cycles H/I/J/P per governed builders), EPA ICIS-NPDES, EPA OTM-50, EPA Method 1633 validation datasets, and NIST PFAS reference materials (e.g. SRM 1957 for serum lane notes).

## 26. ISO/IEC 17025:2017 Alignment Notes

The workflow supports traceability, reproducibility, evidence integrity, documentation control, threshold governance, and provenance preservation. It does **not** constitute laboratory accreditation, ISO certification of software, or regulatory certification.

## 27. Machine Learning Limitations

Model outputs are screening indicators only — not confirmatory analytical determinations. False positives are expected in high-recall screening configurations. Regulatory or compliance decisions require certified laboratory confirmation.

## 28. Troubleshooting

| Issue | Action |
| ----- | ------ |
| RStudio cannot find validation files | `getwd()` / `setwd()` to `PFAS_on_R_Studio` |
| V1 shows `sex_stratum=all` for all rows | Input missing `sex`/`age_years`/`race_ethnicity`; use `nhanes_j_governed_v1_input.csv` or `enrich_v1_input_demographics.py` |
| V2 fails preflight | Input missing `reference_cycle` (I/J/P) |
| Reference table drift error | Rebuild with `build_nhanes_weighted_reference_tables_v1_1.py`; update ontology pin + tag; re-confirm SHA |
| Stale RStudio `src/v1` nested paths | Re-run `sync_serum_lane_to_rstudio.ps1` |
| Docker R smoke fails (jsonlite) | Rebuild `pfas-linux-verify` image (`r-cran-jsonlite` in Dockerfile) |
| `label_derivation_audit.json` missing | Check `results/screening/` for exploratory runs |

## 29. Appendix A — PowerShell Commands

```powershell
cd C:\Users\techj\OneDrive\Desktop\python_work\PFAS_on_R_Studio
Test-Path data\v1\fixtures\nhanes_j_governed_v1_input.csv
git fetch --tags
git show serum-v2.0.0-temporal --no-patch

# Full Docker verify (from canonical repo root)
cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
docker build -f Dockerfile.linux-verify -t pfas-linux-verify .
docker run --rm -v "${PWD}:/app" -w /app pfas-linux-verify

# V2-only recheck
docker run --rm --entrypoint bash -v "${PWD}:/app" -w /app pfas-linux-verify scripts/docker_recheck_v2.sh
```

## 30. Appendix B — RStudio Commands

```r
getwd()
setwd("C:/Users/techj/OneDrive/Desktop/python_work/PFAS_on_R_Studio")
file.exists("data/reference_tables/nhanes_pfas_weighted_reference_tables_v1_1.csv")

# Shiny
shiny::runApp()

# R smoke (serum)
Sys.setenv(PFAS_SMOKE_PROJECT_ROOT = getwd())
system2("Rscript", c("scripts/smoke_v1_shiny_integration.R"))
system2("Rscript", c("scripts/smoke_v2_shiny_integration.R"))
```

---

## 31. V1.1 Demographic Contextualization Governance

PFAS Enterprise 5.0 **V1.1** is the **default production serum mode** (Shiny and `run_v1_contextualization.R` pass `--v1-1` unless legacy V1.0 is explicitly selected).

V1.1 provides demographic-aware physiological contextualization using weighted NHANES reference distributions stratified by:

- **sex** → `sex_stratum`
- **age_years** → `age_group_stratum`
- **race_ethnicity** → `race_ethnicity_stratum` (with minimum-n fallback policy)

**Ontology:** `src/v1/data/ontology/pfos_pfoa_v1_1.json` (v1.1.1)  
**Reference table:** `data/reference_tables/nhanes_pfas_weighted_reference_tables_v1_1.csv`  
**Pinned SHA-256:** `fe195d6206d98d1e2281213fdc937dace468b57f9f8518bfca0e3496d0ba8f19` (988 rows)

Missing demographic fields must be documented in manifest outputs and preflight logs; blank fields widen strata (`all`, `all_ages`, race fallback).

**Legacy V1.0:** Shiny checkbox *“Use legacy V1.0 ontology”* — uses `pfos_pfoa_v1.json` and v1 weighted table only.

## 32. Race-Stratified Reference Workflow

Weighted subgroup contextualization uses controlled demographic mappings:

- `nh_white`, `nh_black`, `nh_asian`, `hispanic` (Mexican American + Other Hispanic collapsed), `other`

Policy implementation: `src/v1/race_strata_policy.py` (`MIN_N_RACE_STRATUM=20`).

Cross-strata interpretation without documented justification is **prohibited**. Report columns include `race_ethnicity_requested`, `race_ethnicity_lookup`, `race_ethnicity_stratum`, `race_stratum_fallback`, `input_lod_code`.

## 33. V2 Cross-Cycle Temporal Contextualization

V2 (`src/v2/`, ontology `pfos_pfoa_v2.json` v2.0.0) compares **population-reference weighted percentiles** across NHANES cycles:

| Cycle | Label |
| ----- | ----- |
| **I** | 2015–2016 |
| **J** | 2017–2018 (anchor default) |
| **P** | 2017–2020 pre-pandemic (WTSBAPRP caveat) |

Outputs include `percentile_cycle_I/J/P`, deltas, and `temporal_context_flag` (e.g. `cross_cycle_percentile_shift_ge_15`).

**Not** individual longitudinal follow-up. Requires `reference_cycle` on every input row. Uses V1.1 reference engine internally.

**Shiny:** Reports tab → teal **V2** panel; fixture `data/v1/fixtures/nhanes_j_governed_v1_input.csv`.

## 34. Docker and Ubuntu Reproducibility

Governed workflows must maintain parity across Windows PowerShell, Docker (WSL2), and Ubuntu.

| Check | Command / artifact |
| ----- | ------------------ |
| Full verify | `docker run --rm -v "${PWD}:/app" -w /app pfas-linux-verify` |
| V2 recheck | `scripts/docker_recheck_v2.sh` |
| Reference SHA | `scripts/confirm_reference_tables_docker.sh` (includes v1_1) |
| Anchor SHA | `scripts/confirm_anchors_docker.sh` |

**Exemplar parity (NHANES J fixture, V2):** `run_id=2bda057f5ab18ff6`, output CSV SHA `87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67`, 7716 in-domain, 1189 cross-cycle shifts ≥15.

Windows checkouts: strip CRLF before running bash scripts in plain `ubuntu:22.04` (see script headers).

## 35. Ontology Pinning and Reference Governance

Reference tables and ontology files are **version-pinned**. Runtime engines refuse drift when on-disk SHA ≠ ontology `reference_table_sha256`.

**Rebuild procedure (intentional change only):**

1. Run `scripts/build_nhanes_weighted_reference_tables_v1_1.py` with raw XPTs under `data/raw/nhanes/`.
2. Confirm SHA in PowerShell and Docker.
3. Update ontology pin, `docs/RELEASES.md`, and issue new git tag.
4. Never edit pins without version bump.

Doctrine: `docs/GOVERNANCE.md`.

## 36. RUO and Non-Diagnostic Positioning

All serum physiological contextualization outputs are **Research Use Only (RUO)**.

The platform shall **not** be represented as:

- a clinical diagnostic or exposure diagnosis engine,
- a regulatory compliance determination platform,
- EPA-approved or ISO-certified analytical software.

Shiny PDF downloads are **RUO stubs**; governed artifacts are CSV + manifest JSON.

## 37. Cohort-Level Exposure Intelligence

**Planned** governed capability (next release slice): cohort-level summaries derived from governed report CSVs — not re-querying raw NHANES.

Examples:

- median percentile by race/age stratum,
- cross-cycle shift counts by subgroup,
- PFOS vs PFOA burden distributions,
- occupational or custom cohort aggregates (with documented AD boundaries).

Institutional reporting must preserve demographic applicability boundaries and RUO framing. Row-level V1.1/V2 remains the authoritative input to cohort roll-ups.

## 38. Commercial Positioning Restrictions

PFAS Enterprise 5.0 may be positioned as a **governed environmental and physiological contextualization platform** for screening, prioritization, and exposure intelligence (RUO).

**Prohibited marketing claims:**

- laboratory certification or accreditation of the software,
- direct clinical diagnosis or treatment guidance,
- EPA approval or regulatory defensibility without independent legal review,
- consumer “PFAS health app” diagnostic framing.

---

## Document control

| Revision | Date | Summary |
| -------- | ---- | ------- |
| 1.0 | 2026-05-10 | Initial SOP suite; drinking-water validation focus |
| **2.1** | **2026-05-17** | Serum V1.1 default, V2 temporal, Docker parity, release tags, GOVERNANCE/RELEASES linkage |

**Related controlled docs:** `docs/GOVERNANCE.md`, `docs/RELEASES.md`, `docs/CONTROLLED_DOCUMENTS.md`, `docs/SOP_INDEX.md`

---

*End of SOP Rev 2.1*
