# Blind external reproducibility protocol — serum demo v1

**Purpose:** Transition from self-verified infrastructure to **externally reproducible**
infrastructure with auditable evidence — not internal claims.

**RUO only.** Not diagnostic, regulatory, or certification validation.

---

## What “blind” means here

| Requirement | Rule |
|-------------|------|
| Clean clone | Fresh `git clone`; no operator handoff of pre-built outputs |
| Frozen pin | Checkout tag `serum-v2.0.0-temporal` (or commit recorded in `canonical_pins.json` era) |
| No privileged setup | Reviewer uses only repo + Docker (+ Git); no shared `data/*/outputs` from sponsor |
| Regenerate outputs | All manifests/reports produced during review session |
| Compare to canonical | Match `run_id` + `output_csv_sha256` in `canonical_pins.json` |
| Document divergence | Any mismatch → structured note; do not silently “fix” inputs |

---

## Execution modes

### Mode A — Docker-only (preferred for blind review)

**Strongest evidence.** Single environment; matches CI governance checks.

```powershell
git clone https://github.com/Ishola-github/pfas-enterprise-modular.git pfas-blind-repro
cd pfas-blind-repro
git fetch --tags
git checkout serum-v2.0.0-temporal
git rev-parse HEAD   # record in attestation

docker build -f Dockerfile.linux-verify -t pfas-linux-verify .
docker run --rm -v "${PWD}:/app" -w /app pfas-linux-verify
```

**Pass:** terminal ends with `=== Linux verify: ALL PASS ===`

This run includes V1.1 race-aware column assertion, V2 recheck, and schema-lock-related guards in `scripts/docker_verify_linux.sh`.

Then regenerate governed CLI outputs inside the same container:

```powershell
docker run --rm -v "${PWD}:/app" -w /app pfas-linux-verify bash -c "
  export PYTHONPATH=/app PFAS_V2_SKIP_R_PARSE=1
  python -m src.v2.cli --input data/v1/fixtures/nhanes_j_governed_v1_input.csv --output-dir data/v2/outputs/blind_repro
  python -m src.v1.cli --v1-1 --input data/v1/fixtures/nhanes_j_governed_v1_input.csv --output-dir data/v1/outputs/blind_repro
"
```

Record stdout JSON `run_id` and `output_csv_sha256` for both runs.

### Mode B — Host Python (acceptable if Docker unavailable)

Follow [EXTERNAL_REPRO_RUNBOOK.md](EXTERNAL_REPRO_RUNBOOK.md) steps 1–4.  
Still require reference-table SHA check and manifest files.  
Note `execution_mode=host_python` on attestation.

---

## Canonical pass gates

| Gate | Expected |
|------|----------|
| Input fixture SHA | `73b5b5da3faec469a05a082c53060b1b6bca2a9bb0900acab448e7b4cded96ee` |
| Reference v1.1 SHA | `fe195d6206d98d1e2281213fdc937dace468b57f9f8518bfca0e3496d0ba8f19` |
| V2 `run_id` | `2bda057f5ab18ff6` |
| V2 `output_csv_sha256` | `87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67` |
| V1.1 `run_id` | `583780b861049800` |
| V1.1 `output_csv_sha256` | `ebb3daf421c291292b7c0c891d9fdf75313bd57fb8011f0aa1c8451ddd4057fa` |
| Docker verify | `ALL PASS` (Mode A) |
| V1.1 race columns | Present in CSV header (Docker guard or manual check) |

---

## Manifest verification (reviewer)

For each manifest under `data/v1/outputs/blind_repro/` and `data/v2/outputs/blind_repro/`:

1. Confirm `output_csv_sha256` matches stdout and file hash.
2. Confirm `input` / reference table SHA fields match `canonical_pins.json`.
3. Attach manifest paths to attestation (do not redact SHA fields).

```powershell
(Get-FileHash -Algorithm SHA256 data\v2\outputs\blind_repro\v2_report_2bda057f5ab18ff6.csv).Hash.ToLower()
```

---

## Schema-lock confirmation

If reviewer has Python env:

```powershell
$env:PYTHONPATH = (Get-Location).Path
python -c "from src.v1.tests.test_schema_lock import test_v1_1_report_includes_race_aware_columns; test_v1_1_report_includes_race_aware_columns(); print('V1.1_SCHEMA_LOCK_PASS')"
python -c "from src.v2.tests.test_schema_lock import test_v2_cohort_summary_columns_locked; test_v2_cohort_summary_columns_locked(); print('V2_COHORT_SCHEMA_LOCK_PASS')"
```

Mode A reviewers: Docker full verify already exercises race-column assertion; cohort schema-lock is CI `schema-lock` job equivalent.

---

## Evidence bundle (optional but recommended)

Sponsor does **not** send pre-built reports. Reviewer may build a minimal evidence folder:

```powershell
# After successful repro only
powershell -ExecutionPolicy Bypass -File scripts\build_serum_validation_evidence_bundle.ps1
```

Copy `validation/serum_demo_v1/evidence_bundle/` + completed attestation into a zip for return.  
Large CSVs/PDFs may stay local; return manifests + `hashes.txt` + attestation if size limits apply.

---

## Divergence handling

| Situation | Action |
|-----------|--------|
| SHA mismatch, same `run_id` | STOP — document fixture/reference drift; open issue with manifest JSON |
| Different `run_id` | STOP — verify input fixture SHA first |
| Docker fail, host pass | Record both; classify as environment-specific divergence |
| Partial pass (V2 only) | FAIL overall; do not mark blind repro complete |

**Never** change pinned files to force a pass during blind review.

---

## Return package (required)

1. Completed [REVIEWER_ATTESTATION_TEMPLATE.txt](REVIEWER_ATTESTATION_TEMPLATE.txt) (signed/dated)
2. Row in sponsor-maintained [reviewer_log.csv](reviewer_log.csv) (sponsor enters from attestation)
3. `git rev-parse HEAD` + execution mode
4. V2 and V1.1 stdout JSON or manifest paths
5. Docker log excerpt showing `ALL PASS` (Mode A)
6. One-paragraph usability notes (1–5 scale)

**Do not** return patient-identifiable data.

---

## Sponsor promotion rule

Blind repro is **complete** when ≥2 independent reviewers pass all canonical gates on Mode A or documented equivalent.

Until then: claim “self-verified with operator pre-flight (`LOCAL_REPRO_VERIFICATION.json`)” only — not “externally validated.”
