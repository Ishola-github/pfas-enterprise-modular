<<<<<<< Updated upstream
# Public reproducibility evidence summary — PFAS Enterprise 5.0 (serum lane)

**Last updated:** 2026-05-25 (UTC)  
**Program:** Independent Reproducibility Pilot · **RUO only**

This document is **operator-maintained public evidence**. It does not claim external
validation until independent attestations are recorded below.

---

## Frozen release

| Field | Value |
|-------|-------|
| Analytical tag | `serum-v2.0.0-temporal` |
| CI-verified commit | `8ce2492` |
| Canonical pins | `validation/serum_demo_v1/canonical_pins.json` |
| GitHub Release | https://github.com/Ishola-github/pfas-enterprise-modular/releases/tag/serum-v2.0.0-temporal |
| Zenodo DOI | https://doi.org/10.5281/zenodo.20348369 |
| One-command path | `bash scripts/repro_one_shot.sh` |
| Grant positioning (17025-style, not certification) | `docs/grants/ISO_17025_WORKFLOW_SUPPORT_BLURB.md` |

---

## Grant-safe summary (ISO/IEC 17025 workflow support)

**PFAS Enterprise 5.0** is an **RUO** serum PFOS/PFOA contextualization scaffold with **17025-aligned workflow elements** (provenance, registry verification, schema locks, human review, applicability-domain gating)—**not** ISO accreditation or regulatory certification. Full grant-safe text: **`docs/grants/ISO_17025_WORKFLOW_SUPPORT_BLURB.md`**.

---

## Operator evidence note (2026-05-25)

**Gate result:** Smoke API `24/24 PASS`; Linux verify `ALL PASS`.  
The `422` fake-analyte response confirms the applicability-domain reject path is working.  
The `429` burst response confirms rate limiting is working.  
Structured JSON logs were captured as expected.

Environments: Windows PowerShell, Docker/Linux (`pfas-linux-verify`), WSL (`.venv`).  
Operator precondition for Docker/WSL bind mounts: `python scripts/materialize_governed_pins_from_git.py` before verify when worktree bytes drift from registry pins.  
**Do not retag. Do not change canonical hashes.**

---

## Environment verification matrix

| Environment | Check | Result | Evidence |
|-------------|-------|--------|----------|
| GitHub Actions CI | Governance Checks workflow | **PASS** on `8ce2492` (run #24) | https://github.com/Ishola-github/pfas-enterprise-modular/actions |
| GitHub Actions | Schema lock tests (V1.1 + V2 cohort) | **PASS** | Job: Schema Lock Tests |
| GitHub Actions | Docker verify | **PASS** | Job: Docker Verify — ends `ALL PASS` |
| Windows PowerShell | CI registry + smoke + pytest | **PASS** | Operator recheck 2026-05-25 |
| WSL / Docker Desktop | `docker_verify_linux.sh` + smoke | **PASS** | Operator recheck 2026-05-25 — `ALL PASS` |
| Docker/Ubuntu | Full `docker_verify_linux.sh` | **PASS** (operator) | `EXTERNAL_REPRO_DOCKER_20260522_080853.log` on release |
| Windows PowerShell | External repro log | **PASS** | `EXTERNAL_REPRO_PS_20260522_080851.log` on release |
| RStudio Shiny | V1.1 + V2 smoke | **PASS** (operator) | Optional screenshot |

---

## Canonical output pins (must match for PASS)

| Lane | run_id | output_csv_sha256 |
|------|--------|-------------------|
| V2 temporal | `2bda057f5ab18ff6` | `87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67` |
| V1.1 race-aware | `583780b861049800` | `ebb3daf421c291292b7c0c891d9fdf75313bd57fb8011f0aa1c8451ddd4057fa` |

Input fixture SHA: `73b5b5da3faec469a05a082c53060b1b6bca2a9bb0900acab448e7b4cded96ee`  
Reference v1.1 SHA: `fe195d6206d98d1e2281213fdc937dace468b57f9f8518bfca0e3496d0ba8f19`

---

## Independent blind reproduction (external)

| reviewer_id | date | Mode | V2 SHA match | V1.1 SHA match | Docker ALL PASS | Status |
|-------------|------|------|--------------|----------------|-----------------|--------|
| *(pending)* | | | | | | |

**Promotion:** ≥2 rows with all gates YES → update status to **Externally reproducible**.

Source log: `validation/serum_demo_v1/reviewer_log.csv`

---

## Governance artifacts (versioned in git)

- Schema-lock tests: `src/v1/tests/test_schema_lock.py`, `src/v2/tests/test_schema_lock.py`
- CI registry scope: `ci_required` column in `data/reference/registry/reference_registry.csv`
- Blind protocol: `validation/serum_demo_v1/BLIND_EXTERNAL_REPRO_PROTOCOL.md`
- Doctrine: `docs/GOVERNANCE.md`

---

## What this does NOT claim

- Clinical diagnosis or individual medical risk
- EPA/regulatory compliance or ISO certification
- PFAS disease prediction or litigation automation
- Enterprise SaaS readiness

**Intended use:** governed PFAS exposure contextualization infrastructure (RUO).
=======
# Public reproducibility evidence summary — PFAS Enterprise 5.0 (serum lane)

**Last updated:** 2026-05-19 (UTC)  
**Program:** Independent Reproducibility Pilot · **RUO only**

This document is **operator-maintained public evidence**. It does not claim external
validation until independent attestations are recorded below.

---

## Frozen release

| Field | Value |
|-------|-------|
| Analytical tag | `serum-v2.0.0-temporal` |
| Program commit | `f95ebb4` (repro program) · CI base `62377e1` |
| Canonical pins | `validation/serum_demo_v1/canonical_pins.json` |
| GitHub Release | *(operator: publish per `validation/releases/serum-v2.0.0-temporal/GITHUB_RELEASE_CHECKLIST.md`)* |
| One-command path | `bash scripts/repro_one_shot.sh` |

---

## Environment verification matrix

| Environment | Check | Result | Evidence |
|-------------|-------|--------|----------|
| GitHub Actions CI | Governance Checks workflow | **PASS** (expected on `62377e1`) | https://github.com/Ishola-github/pfas-enterprise-modular/actions |
| GitHub Actions | Schema lock tests (V1.1 + V2 cohort) | **PASS** | Job: Schema Lock Tests |
| GitHub Actions | Docker verify | **PASS** | Job: Docker Verify — ends `ALL PASS` |
| Windows PowerShell | CI registry (`CI=true`) | **PASS** — 13 rows | Operator log 2026-05-18 |
| Windows PowerShell | Full registry (`--full`) | **PASS** — 29 rows | Operator log 2026-05-18 |
| Windows PowerShell | `pytest` schema-lock | **PASS** — 2/2 | Operator log 2026-05-18 |
| Windows PowerShell | Canonical V1.1 + V2 CLI | **PASS** | `LOCAL_REPRO_VERIFICATION.json` |
| Docker/Ubuntu | Full `docker_verify_linux.sh` | **PASS** (operator) | Add screenshot to `validation/releases/serum-v2.0.0-temporal/screenshots/` |
| RStudio Shiny | V1.1 + V2 smoke | **PASS** (operator) | Optional screenshot |

**CI screenshots:** place under `validation/releases/serum-v2.0.0-temporal/screenshots/ci/` before GitHub Release publish.

---

## Canonical output pins (must match for PASS)

| Lane | run_id | output_csv_sha256 |
|------|--------|-------------------|
| V2 temporal | `2bda057f5ab18ff6` | `87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67` |
| V1.1 race-aware | `583780b861049800` | `ebb3daf421c291292b7c0c891d9fdf75313bd57fb8011f0aa1c8451ddd4057fa` |

Input fixture SHA: `73b5b5da3faec469a05a082c53060b1b6bca2a9bb0900acab448e7b4cded96ee`  
Reference v1.1 SHA: `fe195d6206d98d1e2281213fdc937dace468b57f9f8518bfca0e3496d0ba8f19`

---

## Independent blind reproduction (external)

| reviewer_id | date | Mode | V2 SHA match | V1.1 SHA match | Docker ALL PASS | Status |
|-------------|------|------|--------------|----------------|-----------------|--------|
| *(pending)* | | | | | | |

**Promotion:** ≥2 rows with all gates YES → update status to **Externally reproducible**.

Source log: `validation/serum_demo_v1/reviewer_log.csv`

---

## Governance artifacts (versioned in git)

- Schema-lock tests: `src/v1/tests/test_schema_lock.py`, `src/v2/tests/test_schema_lock.py`
- CI registry scope: `ci_required` column in `data/reference/registry/reference_registry.csv`
- Blind protocol: `validation/serum_demo_v1/BLIND_EXTERNAL_REPRO_PROTOCOL.md`
- Doctrine: `docs/GOVERNANCE.md`

---

## What this does NOT claim

- Clinical diagnosis or individual medical risk
- EPA/regulatory compliance or ISO certification
- PFAS disease prediction or litigation automation
- Enterprise SaaS readiness

**Intended use:** governed PFAS exposure contextualization infrastructure (RUO).
>>>>>>> Stashed changes
