# Serum PFAS contextualization — frozen demo package v1

**Flagship governed workflow** for external technical validation (Phase 1).  
**RUO only** — not diagnostic, clinical, or regulatory.

## Reproducibility program (start here)

| Doc | Purpose |
|-----|---------|
| `QUICKSTART_5MIN.md` | Docker-only 5-minute PASS path |
| `REPRODUCIBILITY_PROGRAM.md` | Independent Reproducibility Pilot Program |
| `../public_reproducibility_summary.md` | Public evidence matrix |
| `../releases/serum-v2.0.0-temporal/` | Frozen release + screenshots |

## Validation status language (use precisely)

| State | Meaning |
|-------|---------|
| Self-verified | Operator pre-flight passed (`evidence_bundle/LOCAL_REPRO_VERIFICATION.json`) |
| Externally reproducible | ≥2 independent blind reviewers pass `BLIND_EXTERNAL_REPRO_PROTOCOL.md` |

Do not claim external validation until the second row is true.

## What this demo proves

| Capability | Evidence |
|------------|----------|
| Weighted NHANES reference percentiles | V1.1 engine + `nhanes_pfas_weighted_reference_tables_v1_1.csv` |
| Sex / age / race contextualization | 7,716-row NHANES J fixture with full demographics |
| Cross-cycle temporal comparison (I/J/P) | V2 engine; population-level, not longitudinal |
| Manifest provenance | JSON per run (`run_id`, SHA-256 pins) |
| Multi-environment parity | PowerShell + Docker reproducibility |

## Frozen release baseline

```text
Git tag:     serum-v2.0.0-temporal (V2) + serum-v1.1-race-aware (V1.1 default)
SOP:         docs/sop/PFAS_Enterprise_5_SOP_Rev2.1.md
Doctrine:    docs/GOVERNANCE.md
Release pins: docs/RELEASES.md
```

## Canonical exemplar run (external reviewers must match)

| Lane | run_id | output_csv_sha256 |
|------|--------|-------------------|
| V2 temporal | `2bda057f5ab18ff6` | `87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67` |
| V1.1 race-aware | `583780b861049800` | `ebb3daf421c291292b7c0c891d9fdf75313bd57fb8011f0aa1c8451ddd4057fa` |

Input fixture SHA: `73b5b5da3faec469a05a082c53060b1b6bca2a9bb0900acab448e7b4cded96ee`  
Reference v1.1 SHA: `fe195d6206d98d1e2281213fdc937dace468b57f9f8518bfca0e3496d0ba8f19`

## Quick start (reviewer)

See **[EXTERNAL_REPRO_RUNBOOK.md](EXTERNAL_REPRO_RUNBOOK.md)**.

## Evidence bundle

After a local repro run, build:

```powershell
cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
powershell -ExecutionPolicy Bypass -File scripts\build_serum_validation_evidence_bundle.ps1
```

Output: `validation/serum_demo_v1/evidence_bundle/`

## Files in this directory

| File | Purpose |
|------|---------|
| `README.md` | This overview |
| `EXTERNAL_REPRO_RUNBOOK.md` | Step-by-step for 2–5 external reviewers |
| `BLIND_EXTERNAL_REPRO_PROTOCOL.md` | Blind review rules (Docker-only preferred), divergence handling |
| `REVIEWER_ATTESTATION_TEMPLATE.txt` | Signed/dated return template |
| `EXTERNAL_REVIEWER_PACKET.md` | Outreach script, pass gates, 30-day cadence |
| `EVIDENCE_CHECKLIST.md` | Screenshots and artifacts to collect |
| `reviewer_log.csv` | Track reviewer returns (operator-maintained) |
| `INTENDED_USE.txt` | RUO positioning (external-facing) |
| `evidence_bundle/` | Generated audit package (gitignored contents optional) |

## What we do NOT claim in this demo

- Clinical diagnosis or individual medical decisions  
- EPA approval or regulatory compliance  
- ISO certification of software  
- Automated litigation outcomes  

Sell **governed PFAS exposure contextualization**, not “AI PFAS platform.”
