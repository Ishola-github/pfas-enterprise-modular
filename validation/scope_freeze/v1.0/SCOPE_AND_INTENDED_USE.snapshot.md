# PFAS Enterprise 5 — System Scope, Scientific Boundaries, and Intended Use

| Field | Value |
| --- | --- |
| Document ID | `SCOPE_AND_INTENDED_USE.md` |
| Companion documents | [`DISCLAIMER.md`](DISCLAIMER.md), [`api/README.md`](api/README.md), [`data/ad_models/README.md`](data/ad_models/README.md), [`validation/blind_external/README.md`](validation/blind_external/README.md), [`data/reference/registry/reference_registry_README.md`](data/reference/registry/reference_registry_README.md) |
| Version | 1.0 |
| Status | DRAFT — to be **frozen** before any pilot kickoff, SBIR submission, or external review |
| Audience | Pilot consultants, environmental laboratories, SBIR/STTR reviewers, investors, procurement, regulatory liaisons, internal operators |
| Review cadence | Re-review on every change to `data/config/matrix_pipeline_sop.csv`, on every new AD model, and quarterly otherwise |

This document is the **authoritative statement** of what the PFAS Enterprise 5
system **is**, what it **is not**, what it **may legitimately be used for**, and
what it **may not** be used for. The system's value depends on this scope
being public, conservative, and unchanged after freeze. Where this document
and a marketing claim conflict, **this document wins**.

A bullet labeled *"claim"* is something the operator may safely tell a
reviewer; a bullet labeled *"non-claim"* is something operators must
**not** assert, even informally.

---

## 1. System Purpose

**Claim.** PFAS Enterprise 5 is a **governed scientific screening and
prioritization platform** for per- and polyfluoroalkyl substances. Its
purpose is to:

- ingest curated PFAS datasets from authoritative public sources
  (EPA UCMR5, EPA ICIS-NPDES, EPA OTM-50, NHANES, NIST SRMs/RMs);
- separate those datasets into **matrix-specific pipeline lanes** so each
  lane has its own units, assumptions, and validation;
- enforce **applicability-domain (AD) refusal** so predictions outside
  validated training space are blocked at the network boundary, not just
  flagged in the UI;
- expose those decisions through (a) an analyst-facing Shiny console for
  exploration and (b) an operational FastAPI service for programmatic use;
- carry full provenance (SHA-256 manifests, an audit log of every refusal,
  and a sealed external blind-validation harness).

**Non-claim.** The system is **not** a PFAS compliance product, an
LC-MS/MS replacement, an automated decision-maker, a regulator-graded risk
calculator, or a substitute for accredited laboratory analysis. It does
not, today, ship a production-trained classifier; `/v1/predict` currently
returns AD status as the primary scoring signal and is honest about that.

---

## 2. Supported Matrices

The system supports **six** matrix lanes today, defined in
`data/config/matrix_pipeline_sop.csv` and enforced in code by
`scripts/run_matrix_pipeline.py` + `enforce_sop_single_pipeline()` in
`scripts/prepare_multisource_training.R`.

| Lane | Canonical sources | Unit domain | Scientific purpose | Concentration data? | AD method |
| --- | --- | --- | --- | --- | --- |
| `drinking_water` | EPA UCMR5 | ng/L | occurrence + screening | Yes | `per_analyte_envelope_v1` |
| `serum` | NHANES (lab + linked demographics), NIST SRM 1957 | ng/mL | biomonitoring | Yes | `per_analyte_envelope_v1` |
| `biosolids_sludge` | EPA NPDES biosolids permits + Method 1633 anchor | program metadata + method anchor (ng/g dry weight when concentrations are eventually available) | waste / environmental fate (governance only today) | **No — program metadata only** | `categorical_coverage_v1` |
| `afff` | NIST RM 8690 | formulation matrix | forensic / source characterization | reference-only | `per_analyte_envelope_v1` |
| `methanol_standards` | NIST RM 8446 | reference standards | calibration / benchmarking | reference-only | `per_analyte_envelope_v1` |
| `air_emissions` | EPA OTM-50 | ng/m³ (workbook source) | atmospheric emissions | Yes (when populated) | `per_analyte_envelope_v1` |

The matrix-distinguishing axes that make this separation **scientifically
required** (not stylistic) are: analytical methods, extraction chemistry,
concentration units, background distributions, detection limits,
contamination mechanisms, toxicokinetics, sampling bias, regulatory
interpretation, and uncertainty structure. Collapsing any two of the rows
above into a single "PFAS dataset" creates label leakage, artificial
correlations, unstable thresholds, invalid calibration, misleading
ROC/AUC behavior, broken applicability domains, and outputs that are
scientifically indefensible. The architecture refuses that collapse at
three code-level checkpoints — see Section 6.

**Non-claim.** Soil/sediment and fish/tissue lanes are **not in scope**
in this document. They are future work and must not be referenced as
supported until they exist in `matrix_pipeline_sop.csv`.

**Non-claim.** Bulk **EPA ICIS-AIR** (the program-listing CSV) is **not** a
supported analytical matrix. It is governance metadata only. The Shiny
upload path enforces this at three layers (signature detection, mapper
hard-block, action-handler refusal — see `scripts/smoke_icis_air_upload_banner.R`).

---

## 3. Supported Analytical Contexts

The system supports the following uses **per supported lane**:

- **Triage and prioritization** of samples / facilities / analytes ahead
  of confirmatory analytical work.
- **Occurrence exploration** within a single lane's validated unit
  domain (`ng/L`, `ng/mL`, `ng/m³`, ...).
- **AD-gated screening predictions** with explicit refusal of rows
  outside the lane's training envelope.
- **Threshold context** for drinking water using
  `data/config/ucmr_analyte_limits_ngl.csv` (versioned by SHA-256
  prefix in every API response).
- **Provenance review** via `data/reference/registry/reference_registry.csv`
  with hash verification (`python scripts/verify_reference_registry.py`).
- **Sealed external blind validation** via
  `scripts/build_blind_validation_pack.py` and
  `scripts/score_blind_validation.py` — hash-locked submission, single-shot
  scoring, immutable revealed metrics.

---

## 4. Unsupported Use Cases

The system **must not** be presented or used for:

1. **Regulatory compliance determinations** of any kind (drinking-water MCL
   compliance, biosolids land-application decisions, NPDES permit decisions,
   stack-emission compliance, etc.).
2. **Replacement of an accredited laboratory measurement** (e.g. EPA
   Methods 533 / 537.1 / 1633 / OTM-50 instrumental analysis, or
   isotope-dilution LC-MS/MS).
3. **Autonomous decision-making** without a competent human reviewer.
4. **Cross-matrix prediction** — predicting a serum outcome from a
   drinking-water row, or vice-versa.
5. **Forensic source attribution at the legal-evidence level.** AFFF and
   methanol standards lanes are reference / formulation lanes, not
   chain-of-custody forensic tooling.
6. **Universal "one PFAS model"** that pools matrices. The architecture
   actively refuses this (see Section 6).
7. **Quantitative inference from program-metadata lanes**
   (`biosolids_sludge`, ICIS-AIR program reference). Counts and listings
   are governance data; they are not analytical concentrations.
8. **Operator-facing risk advice to end consumers**
   (e.g. drinking-water consumer advisories) without independent
   regulator review.

A use that is not listed under Sections 1–3 and is not listed here is
**not supported by default**. The operator must obtain a written scope
exception before extending use.

---

## 5. Screening vs Confirmatory Separation

PFAS Enterprise 5 is a **screening** system. The boundary is enforced
both linguistically and programmatically:

- All `/v1/predict` responses carry an `intended_use` field with the
  literal text **"Screening decision-support only. Not EPA-approved,
  ISO-accredited, or a certified laboratory method."**
- The Shiny screening-mode buttons (`btn_external_train_screening`)
  write `workflow_mode: screening`, `iso_governed: false` into the
  audit trail.
- The strict ISO-style validation gate (`load_external_upload_schema`)
  is invoked by the **evidence-governed** train path, not by screening.
- Refusal of a prediction (`ad_status="reject"`) is always **HTTP 422**
  by default (`PFAS_API_AD_STRICT_REFUSAL=true`), making it indisputable
  to a downstream system that the screening engine declined to answer.

A confirmatory result requires **an accredited laboratory measurement**
under EPA Methods 533 / 537.1 / 1633 / OTM-50 or equivalent. This system
does not, under any configuration, produce a confirmatory result.

---

## 6. Matrix Isolation Requirements

Matrix isolation is **not a convention**; it is a code-level enforcement
boundary with three independent checkpoints. Operators must respect all
three when adding data:

1. **Pipeline layer.** `prepare_multisource_training.R` runs
   `enforce_sop_single_pipeline()` on the merged training CSV. If two
   matrix lanes' rows enter the same file, the build **halts**. The
   escape hatch (`PFAS_ALLOW_MULTISOURCE_MERGE=1`) is exploratory only
   and is logged in the audit trail. Smoke: `scripts/smoke_sop_matrix_separation.R`.
2. **AD layer.** Each lane has its own
   `data/ad_models/<lane>/ad_model.json`. A row tagged with lane X
   cannot be scored against lane Y's model. Smoke:
   `scripts/smoke_ad_enforcement.R` (24/24 PASS).
3. **API layer.** `/v1/predict` requires `matrix_lane` in the body;
   an unknown lane returns HTTP 400 `ad_lane_unknown`. There is no
   default lane fallback. Smoke: `scripts/smoke_api.py` and
   `scripts/smoke_docker_compose.py`.

The Shiny upload path additionally classifies uploads by **semantic
type** (`UPLOAD_SEMANTIC_TYPES` in `LatestPFAS.R`). Metadata-only types
(`air_program_metadata`, `biosolids_program_metadata`) are blocked from
the PFAS occurrence mapper — Validate / Normalize / Save / Train / Train
Screening all refuse. Smoke: `scripts/smoke_icis_air_upload_banner.R`
(14/14 PASS, including five `grep`-style wiring contracts).

### 6.4 Shared infrastructure vs. matrix-isolated science

Matrix separation does **not** mean "everything must be duplicated". The
platform deliberately shares **infrastructure** across lanes while
isolating **scientific content**. The boundary between the two is
explicit and enforced.

**Shared safely across all lanes (infrastructure layer):**

- PFAS analyte ontology and CAS normalization (`scripts/normalize_external_pfas.py`, analyte registry).
- Provenance framework (SHA-256 manifests, `reference_registry.csv` verifier).
- Audit logging conventions (JSONL append-only access log, `ad_decisions.jsonl`).
- Governance infrastructure (SOP CSV, freeze procedure, blind-validation harness layout).
- UI framework (`LatestPFAS.R` Shiny shell, navigation, role-aware components).
- Authentication and rate-limiting middleware (`api/security.py`, `api/rate_limit.py`, `api/middleware.py`).
- Deployment layer (`Dockerfile`, `docker-compose.yml`, `.dockerignore`, `requirements.txt` pinning).

**Must NOT be shared across lanes (scientific layer):**

- Calibration thresholds — `data/config/ucmr_analyte_limits_ngl.csv` governs `drinking_water` only; no other lane inherits it.
- Prediction distributions — each lane carries its own training CSV and its own model artifact (today: AD; later: classifier).
- Concentration normalization — log-space envelope statistics are computed per analyte **inside** a lane, never pooled across lanes.
- Training targets — a lane's label semantics (occurrence flag, biomonitoring exposure, program-metadata presence, formulation reference, calibration anchor) do not transfer.
- Detection assumptions (MDL, RL, qualifier handling) — these are method-specific and lane-specific.
- Matrix-specific QC logic — sample-volume checks, dilution flags, freezer holding-time rules, fate-process assumptions, and biomonitoring exposure controls are lane-local.

The single biggest scientific failure pattern that this architecture
exists to prevent is the collapse of all PFAS measurements into one
"universal PFAS AI model." That collapse is **structurally impossible**
in the system as built: the API requires `matrix_lane`, the AD models
are per-lane, the SOP enforcement halts cross-lane merges, and the
Shiny semantic-type detector refuses cross-class uploads.

---

## 7. Applicability Domain (AD) Policy

The AD framework is the system's **scientific refusal layer**. It is
the single most important governance mechanism the platform provides.

- **Per-lane models.** One AD model per supported lane, built from that
  lane's training CSV by `scripts/build_ad_models.py`.
- **Method per lane.** Value-based lanes use `per_analyte_envelope_v1`
  (log-space z-score against per-analyte mean/std);
  `biosolids_sludge` uses `categorical_coverage_v1`.
- **Determinism.** AD JSON SHA-256 changes **iff** the training data
  changes; the build timestamp is in the audit log, not in the model
  body.
- **Refusal is hard.** `ad_status="reject"` propagates simultaneously to
  HTTP status (422), JSON body (`prediction_refused: true`), response
  header (`X-Request-Id`), and structured access log on the same
  `request_id`. There is no soft-warning bypass for production. The
  optional soft mode (`PFAS_API_AD_STRICT_REFUSAL=false`) still returns
  `prediction_refused=true` in the body and is intended for diagnostic
  use only.
- **Refusal is auditable.** Every decision is appended to
  `data/audit/ad_decisions.jsonl` (offline guard) and emitted as one
  structured JSON line per `/v1/predict` request (API guard) with
  `lane`, `ad_status`, `threshold_version`, `model_version`.

**Non-claim.** AD refusal does not certify that an in-domain prediction
is *correct*; it certifies only that the row falls within the validated
chemical/measurement space the lane was trained on. Human review
remains required (Section 11).

---

## 8. Governance and Provenance

- **Reference registry.** `data/reference/registry/reference_registry.csv`
  lists every authoritative artifact (currently 17 rows) with its
  `local_path`, `source_org`, `document_id`, and **SHA-256**. The
  verifier `scripts/verify_reference_registry.py` re-hashes each file
  and reports drift — `OK` only when every hash matches.
- **Manifests.** Each training lane has a `data/training/<lane>/manifest.json`
  carrying source file hashes, row counts, and governance notes
  (e.g. `biosolids_sludge` carries the explicit caveat that the lane is
  *program metadata + method metadata*, not nationwide PFAS-in-biosolids
  concentrations).
- **Audit logs.**
  - `data/audit/ad_decisions.jsonl` — every AD decision from the offline
    guard.
  - `validation/blind_external/manifests/{submissions,reveals}_index.jsonl`
    — every sealed/revealed blind validation event.
  - API access log — one JSON record per HTTP request with `request_id`,
    `lane`, `ad_status`, `prediction_refused`, `threshold_version`,
    `model_version`.
- **Image immutability.** The operational image is tagged
  `pfas-enterprise/api:5.0.0` and is reproducible from
  `requirements.txt` (pinned versions), the project `Dockerfile`, and
  the contents of `.dockerignore`. A pilot operator can re-build and
  re-run `scripts/smoke_docker_compose.py` to obtain the same 21/21 PASS
  signature against the same image.

**Non-claim.** Provenance is **hash-based**, not cryptographically
signed. The system does not provide non-repudiation of records, only
tamper-evidence (any mutation changes the SHA-256). A regulator who
requires digital signatures, time-stamping authority, or chain-of-custody
custody under 21 CFR Part 11 / GLP / GMP rules **must layer those
controls externally**; the platform does not implement them.

---

## 9. External Validation Status

- **Internal regression tests:** `smoke_api.py` (24/24), `smoke_docker_compose.py`
  (21/21), `smoke_ad_enforcement.R` (24/24), `smoke_blind_validation.R`
  (PASS), `smoke_sop_matrix_separation.R` (3/3), `verify_reference_registry.py`
  (17/17), `smoke_icis_air_upload_banner.R` (14/14), all reproducible
  in Windows + RStudio + Docker Ubuntu + native WSL Ubuntu.
- **Sealed external blind-validation harness:** **implemented** at
  `scripts/build_blind_validation_pack.py` + `scripts/score_blind_validation.py`
  with hash-protected single-shot scoring. The harness is **ready**;
  the first external submission has **not yet occurred**.
- **Independent published study:** **none**.
- **Interlaboratory study:** **none**.
- **Regulator-conducted evaluation:** **none**.

The fact that the validation **infrastructure** is hash-sealed and
auditable does **not** imply that the system has been externally
validated. Section 17 lists the steps that would change this status.

---

## 10. Regulatory and Accreditation Limitations

The platform is, as of this document:

- **Not** EPA-approved as a method.
- **Not** ELAP-certified.
- **Not** NELAP-certified.
- **Not** ISO/IEC 17025 accredited.
- **Not** SOC 2 Type I or Type II audited.
- **Not** HIPAA, GLP, GMP, FDA 21 CFR Part 11, FedRAMP, or DOD IL-4/IL-5
  compliant.
- **Not** registered with any state drinking-water regulator as an
  approved laboratory or method.

The Shiny app refers to "ISO-aligned" workflow hooks; that language is
deliberate and means *structurally consistent with ISO patterns*. It
does **not** mean accredited (see `DISCLAIMER.md`, "Schema & folder
readiness (not lab validation)" alert).

Any text that suggests otherwise — in a sales deck, grant narrative,
investor pitch, web page, or partner deck — is a **scope violation**
and must be corrected before this document is invoked.

---

## 11. Human Review Requirements

A competent human reviewer **must** be in the loop for every operational
use that influences a decision external to the platform. Specifically:

- **Every screening prediction** intended to inform sampling, testing,
  or risk-communication decisions must be reviewed by a person with
  expertise in the relevant matrix and analytical method.
- **Every AD refusal** is a positive governance signal; the reviewer
  must treat refusal as a halt, not as a curiosity to be overridden.
- **Every upload of new external data** must pass strict-schema
  validation (`load_external_upload_schema`) before being merged into a
  training lane. The strict gate is in addition to, not a replacement
  for, reviewer judgement.
- **Every blind-validation result** must be reviewed for drift in
  `ad_policy_version`, `threshold_version`, and `model_version`. A
  drift report is not a re-tune authorization.

The platform supports human review; it does not substitute for it.

---

## 12. Data Source Lineage

Every supported lane is anchored to a documented public source. The
authoritative inventory is `data/reference/registry/reference_registry.csv`;
the operator-readable narrative is
`data/reference/registry/reference_registry_README.md`.

Summary:

| Source | Provider | Used by |
| --- | --- | --- |
| UCMR5 (occurrence + analyte limits) | US EPA | `drinking_water` |
| NHANES (PFAS lab + demographics) | US CDC / NCHS | `serum` |
| NIST SRM 1957 (serum reference) | NIST | `serum` (anchor) |
| EPA Method 1633 anchor | US EPA | `biosolids_sludge` (method metadata) |
| EPA ICIS-NPDES biosolids permits (bulk) | US EPA / ECHO | `biosolids_sludge` (program metadata) |
| EPA OTM-50 PFAS air emissions workbooks | US EPA | `air_emissions` |
| EPA ICIS-AIR pollutant program listing (curated PFAS extract) | US EPA / ECHO | `air_program_reference` (governance only — **not** a training lane) |
| NIST RM 8690 (AFFF) | NIST | `afff` |
| NIST RM 8446 (methanol standards) | NIST | `methanol_standards` |

**Non-claim.** Inclusion of a public source does **not** mean the
source provider endorses or has reviewed this platform.

---

## 13. Threshold Governance

Thresholds are **not generic.** They are governed per lane:

- **`drinking_water`** — uses `data/config/ucmr_analyte_limits_ngl.csv`
  (UCMR-listed analyte action levels) and exposes
  `threshold_version=<SHA-256 prefix>` in every API response and access
  log. Any change to the CSV produces a new `threshold_version` value
  visible to downstream consumers.
- **All other lanes** — return `threshold_version="none"`. The
  platform does **not** invent thresholds for matrices that lack a
  consensus regulatory analytical limit.

The blind-validation harness captures `threshold_version` at seal time
and refuses to score if the value drifts before reveal. No human can
move a threshold mid-evaluation.

**Non-claim.** Use of UCMR analyte limits as a screening threshold
**is not** a regulatory MCL compliance decision. UCMR limits are
investigative levels; they are used here for screening prioritization
only.

---

## 14. Environmental vs Physiological Separation

The system **distinguishes** environmental occurrence lanes
(`drinking_water`, `biosolids_sludge`, `air_emissions`) from
physiological body-burden lanes (`serum`). They share **no** model,
**no** threshold, **no** AD envelope, and **no** training target.

A NHANES serum row cannot be scored against a UCMR drinking-water AD;
a UCMR drinking-water row cannot be scored against a NHANES serum AD.
The API enforces this by requiring `matrix_lane` on every prediction;
no lane has a default.

`afff` and `methanol_standards` are **reference / formulation** lanes,
not occurrence lanes; they exist to support analytical bench work and
must not be conflated with environmental occurrence or human
biomonitoring.

---

## 15. Air / Biosolids Metadata Limitation Statements

Two lanes carry explicit non-claim language because the underlying
public data is governance metadata, not concentrations:

### 15.1 Air program reference (`air_program_reference` matrix, ICIS-AIR-derived)

- **What it is:** a curated PFAS-relevant slice of the EPA ICIS-AIR
  pollutant program listing (`scripts/filter_icis_air_pfas.py` →
  `data/processed/epa_icis_air/icis_air_pfas_pollutants.csv`).
- **What it is not:** a PFAS-in-air concentration dataset. Each row is
  the fact that a facility reports or permits a pollutant; there is no
  ng/m³ value, no detection limit, no sampling event.
- **Enforcement:** the Shiny upload path refuses to map ICIS-AIR bulk
  files into the PFAS occurrence mapper (semantic type
  `air_program_metadata`), see Section 6.

### 15.2 Biosolids/sludge (`biosolids_sludge` lane)

- **What it is:** EPA NPDES biosolids permits + Method 1633 method
  anchor, structured as a *governance enrichment* lane for facilities
  and analytical method context.
- **What it is not:** a nationwide PFAS-in-biosolids occurrence dataset.
  The manifest at `data/training/biosolids_sludge/manifest.json`
  explicitly states this. The lane carries facility compliance counts
  in `matrix_governance_note`, **not** concentrations.
- **Enforcement:** AD method for this lane is `categorical_coverage_v1`,
  not `per_analyte_envelope_v1`; concentration-style envelope
  predictions are structurally unavailable for this lane.

These limitation statements **must be reproduced verbatim** in any
public material derived from the biosolids or air-program data sets.

---

## 16. SaaS Operational Limitations

The operational FastAPI service (`api/`) ships **only the controls
explicitly listed below**. Anything not listed is **out of scope** for
the current phase and must not be claimed.

In scope today:

- API-key authentication (constant-time compare, `api/security.py`).
- In-process per-key token-bucket rate limiting (`api/rate_limit.py`).
- Structured JSON access logs with `request_id`, `lane`, `ad_status`,
  `prediction_refused`, `model_version`, `threshold_version`
  (`api/logging_setup.py`, `api/middleware.py`).
- AD-gated `/v1/predict` with hard refusal (HTTP 422 by default).
- `/health` with AD lane inventory, manifest availability booleans, and
  registry verification status.
- Pinned, non-root Docker image with healthcheck.
- `docker compose up` runbook with secret loaded from `.env` (not from
  the image).

Out of scope today (not built, not claimed):

- Enterprise RBAC, per-tenant key scoping, JWT issuer, OAuth, SSO.
- Multi-tenant data isolation; the service has no per-tenant database.
- Distributed rate limiting (Redis / Memcached).
- Billing, metering, quota enforcement.
- Kubernetes manifests, autoscaling configuration, blue/green
  deployment automation.
- SOC 2 / FedRAMP / IL-4 / IL-5 control inheritance.
- Encryption at rest; the operator is responsible for disk encryption
  on the host.
- TLS termination; expected to be handled by the reverse proxy in front
  of the API.
- Web Application Firewall, DDoS protection.
- mTLS client certificates.
- WebAuthn / hardware-token MFA.

These are not roadmap items in this document — they are explicit
non-claims. They are added only when a pilot user surfaces a concrete
workflow need.

---

## 17. Future Validation Roadmap

The following items are **prerequisite to changing claims** in Sections
9, 10, or 16:

| Step | Effect on scope |
| --- | --- |
| First successful **external blind-validation submission** scored through `scripts/score_blind_validation.py` | Section 9 line "first external submission has not yet occurred" can be replaced with the revealed metrics |
| First **pilot deployment** with at least one external environmental consultant or laboratory | Section 16 may add narrow controls actually exercised in the pilot |
| **Independent reviewer** (analytical chemistry expert, not internal) signs off on per-lane AD methodology | Section 7 may upgrade language from "validated training envelope" to "externally reviewed AD methodology" |
| **Soil/Sediment** lane built (EPA Method 1633 source, `ng/g` unit domain, environmental-transport scientific purpose) with manifest + per-analyte envelope AD model + lane smoke test | Section 2 gains a `soil_sediment` row; matrix isolation checkpoints (Section 6) extend to seven lanes |
| **Fish/Tissue** lane built (EPA National Lakes Assessment fish-tissue source, `ng/g wet weight` unit domain, bioaccumulation scientific purpose) with manifest + per-analyte envelope AD model + lane smoke test | Section 2 gains a `fish_tissue` row; matrix isolation extends to eight lanes |
| Structured **audit database** replaces / supplements the JSONL audit log | Section 8 may reference queryable audit retention rather than append-only files |
| **External published evaluation** (preprint or peer review) of at least one lane | Section 9 may add the citation; Section 10 remains unchanged unless the evaluation is conducted by a regulator |

Each step requires this document to be **re-issued** with an incremented
version. No claim in the deck, pitch, or web copy may move ahead of
this document.

---

## Glossary (for non-specialist reviewers)

| Term | Meaning in this document |
| --- | --- |
| Matrix lane | A code-level pipeline for one PFAS sample type (drinking water, serum, biosolids, etc.) |
| AD / Applicability Domain | The chemical and measurement space within which a model's predictions are considered valid |
| Refusal | A formal "I will not predict on this row" outcome, propagated to HTTP status + body + log |
| Provenance | The set of hashes, manifests, and audit records that allow an external reviewer to reproduce or verify a result |
| Threshold version | A short SHA-256 prefix that identifies which threshold table was in force when a prediction was made |
| Blind validation | A workflow where an external party submits a dataset (sealed by hash) and the operator scores it exactly once, without retuning |
| Screening | A prioritization output that informs further analytical work, never replaces it |
| Confirmatory | An accredited laboratory measurement performed under an approved method |

---

## Change Control

| Version | Date | Author | Change | Re-verification |
| --- | --- | --- | --- | --- |
| 1.0 (DRAFT) | 2026-05-12 | Sunday Ishola (operator), platform engineering | Initial scope statement for pre-pilot freeze. | All six smoke suites + Docker compose smoke green on Windows + RStudio + Docker Ubuntu + WSL Ubuntu. |

**Freeze procedure** (to be performed once before first pilot or SBIR submission):

1. Verify all six regression smokes still PASS in the four environments
   listed above.
2. Confirm `reference_registry.csv` rows still equal 17 with all hashes
   matching.
3. Confirm `data/config/matrix_pipeline_sop.csv` has not been modified
   since the last review.
4. Add a signature row to this table with the freeze date.
5. Tag the repository (`git tag scope-frozen-v1.0`).
6. Distribute this file as a PDF render alongside the pitch / proposal.

Until that signature row exists, this document is **DRAFT** and any
public claim derived from it must include the word "draft" or "pre-pilot".

---

## Signature Block (to be populated at freeze)

| Role | Name | Date | Signature / commit |
| --- | --- | --- | --- |
| Platform operator | _(pending)_ | _(pending)_ | _(git tag)_ |
| Scientific reviewer (matrix expert) | _(pending — must be independent)_ | _(pending)_ | _(pending)_ |
| Regulatory liaison (if applicable) | _(pending)_ | _(pending)_ | _(pending)_ |

---

*This document is project governance, not legal advice. It states what
the system supports today and what it does not. Operators remain
responsible for their public claims, jurisdictions, and use contexts.*
