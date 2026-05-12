# Clean-Machine Reproduction Runbook (v1)

This runbook verifies that PFAS Enterprise 5.0 can be reproduced on an independent machine as a screening / prioritization / governance platform.

## Scope

- Reproduce deployment from repository + lock artifacts.
- Verify governed files and hashes.
- Do not retrain or tune during this check.
- Do not claim accreditation, certification, or regulatory approval.

## Required Inputs

- Repository checkout at the target commit/tag.
- `validation/drinking_water_v1/reports/FREEZE_v1.md`
- `validation/drinking_water_v1/runs/v1-dw-20260510-freeze/manifest.json`
- `validation/drinking_water_v1/runs/v1-dw-20260510-freeze/hashes.txt`
- `validation/drinking_water_v1/reports/DEPLOYMENT_VERIFICATION_v1.md`
- Docker Desktop (Windows) or equivalent Docker runtime.

## Procedure

1. **Clone and enter repo**
   - `git clone <repo-url>`
   - `cd pfas-toxicology`
2. **Checkout governed commit/tag**
   - `git checkout <commit-or-tag>`
3. **Confirm required files exist**
   - `Test-Path` checks for FREEZE, manifest, hashes, deployment verification.
4. **Build and run container**
   - `docker compose build`
   - `docker compose up`
5. **Runtime check**
   - Confirm app endpoint loads (current deployment note may indicate `http://localhost:8000`).
6. **Governance check**
   - Verify run manifest + hashes still present and readable.
7. **Record evidence**
   - Screenshot compose logs and app landing page.
   - Record machine metadata (OS, Docker version, timestamp, operator).
8. **Hash refresh (if documentation changed)**
   - `.\scripts\write_run_hashes.cmd -RunId v1-dw-20260510-freeze -UpdateManifest`

## Acceptance Criteria

- Compose build and up complete without unresolved package errors.
- App endpoint opens from localhost.
- Required governance files exist.
- No undocumented modifications to frozen run artifacts.

## Evidence to Capture

- Docker build log snippet.
- Container runtime log snippet.
- App endpoint screenshot.
- Output of:
  - `docker version`
  - `docker compose version`
  - `git rev-parse HEAD`
- Signed operator note in:
  - `validation/drinking_water_v1/reports/DEPLOYMENT_VERIFICATION_v1.md`

## Reporting Statement (Conservative)

Use wording like:

`Independent clean-machine reproduction completed for screening / prioritization / governance workflow.`

Avoid wording like:

`accredited`, `certified`, `regulatory-approved`, `compliance automation`.
