# Reference data registry

This folder holds `reference_registry.csv`, the authoritative index of curated reference files shipped with the PFAS screening and prioritization package.

## Columns

| Column | Meaning |
|--------|---------|
| `source_org` | Issuer of the reference (e.g. NIST). |
| `document_type` | `SRM`, `RM`, `method`, or other controlled type. |
| `document_id` | Catalog identifier (e.g. `SRM 1957`, `RM 8446`). |
| `url` | Human-facing source pointer (verify current CoA / fact sheet on the issuer site). |
| `local_path` | Path relative to the project root (`pfas-toxicology/`). |
| `sha256` | SHA-256 of file bytes at registration time. |
| `matrix_domain` | High-level matrix or use domain (for separation logic — not a substitute for row-level `matrix` in data files). |
| `intended_use` | Governance: why the file exists in this app. |
| `limitations` | Conservative scope; prohibited mis-use. |
| `registry_status` | `active`, `pending`, `external_large`, `generated`, or `local_only`. |
| `ci_required` | `TRUE` only for git-tracked governed core artifacts required in GitHub Actions. |

## CI vs full verification

| Mode | Command | Scope |
|------|---------|-------|
| **CI** (GitHub Actions) | `CI=true python scripts/verify_reference_registry.py` | Rows with `ci_required=TRUE` only |
| **Full** (local release) | `python scripts/verify_reference_registry.py --full` | All registry rows |

CI must **not** require large or gitignored assets (`external_large`, `generated`, `local_only`).
Run full verification on a machine with optional datasets before tagging releases.

## Update rules

1. **Never change bytes without updating `sha256`.** After editing any registered file, recompute the hash and update the registry row in the same commit.
2. **Prefer additive changes.** New analytes or rows should be documented in commit messages; breaking renames need a manifest or changelog note.
3. **Keep matrices logically separate.** Do not merge serum, methanol calibration, and AFFF tables into one “environmental” dataset.
4. **NIST bundle layout.** Curated matrix-separated CSVs live under `data/reference/nist/<catalog>/` (e.g. `nist/srm1957/serum_pfas.csv`). After changing any of those files, run `python scripts/build_nist_reference_bundle.py --project-root .` to refresh `nist/manifest.json` and `nist/hashes.txt`, then update `sha256` in this registry for each changed CSV row.
5. **Run the verifier** before tagging a release:

   ```bash
   python scripts/verify_reference_registry.py --project-root . --full
   ```

6. **URLs** are pointers for auditors; the controlled scientific content is the issuer’s current certificate or reference report. Replace generic landing-page URLs with document-specific links when you have stable NIST (or EPA) citations.

## Official external datasets (by matrix)

Use these for **enrichment**, **benchmarking**, or **separate workflows**. They are **not** interchangeable with UCMR drinking-water occurrence rows, and they are **not** registered in `reference_registry.csv` until you ingest a specific file with a hash.

| Matrix | Primary sources | Method context | Typical use in this app |
| ------ | --------------- | -------------- | ------------------------ |
| Drinking water | EPA UCMR5 (e.g. occurrence files under `data/external/epa_ucmr5/`) | EPA Methods **533**, **537.1** | Environmental occurrence / screening priors |
| Serum / biomonitoring | CDC NHANES PFAS cycles; NIST SRM 1957 (this repo) | CDC laboratory methods (per cycle docs) | Physiological benchmarks; reference QC — not MCL exceedance |
| Sludge / biosolids / NPDES context | EPA ECHO / ICIS-NPDES biosolids downloads; EPA PFAS in sewage sludge program | EPA Method **1633** (solids), DMR governance | Facility linkage; sludge matrix governance — **not** UCMR substitutes |
| AFFF / foam | NIST RM 8690 (this repo) | NIST certificate / reference report | Foam / forensic lane — separate from distribution water |
| Methanol / calibration-style RM | NIST RM 8446 (this repo) | NIST certificate / reference report | Certificate-style reference — not field environmental occurrence |
| Air / stack | EPA OTM-50 published dataset (Data.gov, `data/external/epa_otm50/`) | EPA **OTM-50** (Other Test Method) | Industrial air / source characterization — separate head from water |
| Air program reference | EPA ICIS-AIR pollutant catalog (`data/processed/epa_icis_air/`) | ECHO bulk `ICIS-AIR_POLLUTANTS.csv` | Facility-linkage / regulatory context — **program reporting metadata, not concentrations**; near-zero PFAS coverage |

**SOP matrix → dataset table (versioned, do not merge lanes):** `data/config/matrix_pipeline_sop.csv` — matches PFAS Enterprise 5 SOP §6; enforced when building `pfas_multisource_training.csv` (see `scripts/prepare_multisource_training.R`).

**Per-lane applicability-domain (AD) enforcement:** `data/ad_models/<lane>/ad_model.json` — built by `scripts/build_ad_models.py`, applied by `scripts/apply_ad_guard.py` (or the R wrapper `scripts/run_ad_guard.R`). Hard refusal contract: predictions / uploads outside the validated per-lane envelope are *refused* (analytical result columns blanked in strict mode) and every decision is appended to `data/audit/ad_decisions.jsonl`. Each lane's AD model and method (per-analyte log10 envelope for value lanes; categorical coverage for `biosolids_sludge`) is documented in `data/ad_models/README.md`. AD model JSONs are registered in this `reference_registry.csv` under `document_type=ad_model` and verified by `scripts/verify_reference_registry.py`.

**Sealed external blind validation:** `validation/blind_external/` — submissions are hash-sealed by `scripts/build_blind_validation_pack.py` and scored single-shot by `scripts/score_blind_validation.py` (R wrapper: `scripts/run_blind_validation.R`). Ground rules ("no retuning / no threshold change / no model change / no dataset editing after hash submission") are enforced by SHA-256 re-verification at reveal time: tampered sealed bytes cause hard refusal with exit code 3. AD-policy and threshold drift between seal and reveal is captured in `seal_verification` / `freeze_drift_warnings`. Required metric fields per reveal: `roc_auc`, `precision`, `recall`, `f1`, `flags_per_10k`, `FP_per_TP`, `ad_reject_count`, `ad_warning_count`, `ad_in_domain_count`. Audit logs: `validation/blind_external/manifests/{submissions_index,reveals_index}.jsonl`. Full design in `validation/blind_external/README.md`; regression: `Rscript scripts/smoke_blind_validation.R`.

**UCMR scope note:** UCMR is a **drinking-water monitoring** program; it does **not** provide biosolids or sewage-sludge occurrence measurements. Keep sludge/biosolids lines of evidence on EPA biosolids / NPDES paths, not by relabeling UCMR rows.

### Pointers (verify current pages before citing)

- **EPA ECHO data downloads:** [ECHO tools — data downloads](https://echo.epa.gov/tools/data-downloads) — includes facility/permit/compliance-style exports relevant to wastewater governance.
- **ICIS-NPDES biosolids (summary page):** [Biosolids download summary](https://echo.epa.gov/tools/data-downloads/biosolids-download-summary). The biosolids ZIP (`npdes_biosolids_downloads.zip`) is pulled by `download_epa_icis_npdes_ml.ps1` **by default**; pass `-SkipBiosolids` only when you have a reason. To fetch just biosolids + reference tables (skip the large DMR and outfall ZIPs):

  ```powershell
  .\download_epa_icis_npdes_ml.ps1 -SkipDmr -SkipOutfalls
  ```

  Files land in `data/raw/epa_icis_npdes/`. Tag rows with `matrix = "biosolids"` (or `"npdes_dmr"` for discharge monitoring) and `source = "EPA_ICIS_NPDES"`.

  The `biosolids_sludge` lane builder (`scripts/run_matrix_pipeline.py --lane biosolids_sludge`) reads this ZIP and emits one canonical training row per `BIOSOLIDS_FLAG='Y'` permit, with per-facility compliance counts (inspections / severe violations / formal & informal enforcement actions) carried in `matrix_governance_note`, plus one anchor row from `data/reference/epa_1633a_method_metadata.csv`. **Scope:** these rows are **program metadata + method metadata**, not PFAS sludge concentrations — EPA does not publish a nationwide PFAS-in-biosolids bulk export. Use this lane as the biosolids matrix label space and compliance context; pair with EPA Method 1633(A) PFAS solids measurements (state programs, EPA studies, lab reports) when ingesting analytical data later.
- **EPA PFAS in sewage sludge (program context):** [PFAS in sewage sludge](https://www.epa.gov/biosolids/and-polyfluoroalkyl-substances-pfas-sewage-sludge) — pair with **EPA Method 1633** for solids analytical chemistry context.
- **EPA ICIS-AIR pollutant catalog (program reference):** ECHO bulk `ICIS-AIR_downloads.zip` (contains `ICIS-AIR_POLLUTANTS.csv`, ~976k rows). Pull with `download_epa_icis_air.ps1`, filter with `scripts/filter_icis_air_pfas.py`. Outputs land in `data/processed/epa_icis_air/` with the `pfas_class_note` caveat preserved per row. **Coverage finding:** only the EPA aggregate `PERFLUOROCARBONS` code (CAS `308069-13-8`, a fluorinated-GHG umbrella) hits the PFAS filter — it is **not** a drinking-water-class PFAS. Use OTM-50 for actual PFAS air measurements. See `data/processed/epa_icis_air/README.md` before using in the Shiny "environmental occurrence" panel.
- **NHANES PFAS (examples):** [2017–2018 `P_PFAS`](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_PFAS.htm) · [2015–2016 `PFAS_I`](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2015/DataFiles/PFAS_I.htm) · [NHANES portal](https://www.cdc.gov/nchs/nhanes/index.html) — formats are often **SAS transport (XPT)**; convert to CSV in R/Python with documented scripts.
- **CDC National Exposure Report tables:** [Biomonitoring data tables](https://www.cdc.gov/exposurereport/data_tables.html)
- **EPA OTM-50 PFAS air dataset (DOI [10.23719/1531897](https://doi.org/10.23719/1531897)):** [Data.gov landing page](https://catalog.data.gov/dataset/otm-50-data-from-air-pollution-controls-at-a-fluoropolymer-manufacturer-2024) · [Data.gov beta mirror](https://catalog-beta.data.gov/dataset/otm-50-data-from-air-pollution-controls-at-a-fluoropolymer-manufacturer-2024) — three **XLSX** workbooks (`FW_TO_*`, `FW_VEN_*`, `FW_VES_*`); treat as **air matrix** (stack / process emissions at a single fluoropolymer facility), not water. Use `download_epa_otm50.ps1` at the repo root; data lands in `data/external/epa_otm50/` (see that folder's `README.md` for governance).
- **EPA PFAS air methods context:** [PFAS air emissions measurement methods (webinar archive)](https://www.epa.gov/research-states/pfas-air-emissions-measurement-methods-webinar-archive)
- **NIST PFAS reference materials:** curated CSVs under `data/reference/nist/` per `document_id` — use certificates / PDFs on NIST for authoritative values; in-repo tables are for **software traceability**, not wet-lab proof.

For **solids / biosolids chemistry** lines of evidence, pair program metadata with methods appropriate to the matrix (e.g. **EPA Method 1633** and related solids guidance where applicable); always record matrix, method, and units in the same row-level governance fields you use elsewhere.

## Non-claims

Registry entries support traceability and software benchmarking. They do **not** establish ISO/IEC 17025 accreditation, EPA certification, or regulatory approval of this application.
