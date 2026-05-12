# Independent Clean-Machine Execution Log (Template v1)

Use this log for an operator other than the primary developer to reproduce deployment and governance checks.

Workflow framing: screening / prioritization / governance platform.

## Run Metadata

- Template created: 2026-05-11 01:01:34 -07:00
- Repository path: `C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology`
- Governing run id: `v1-dw-20260510-freeze`
- Governing commit SHA: `9b3bb7c0a9f17c3eb87655c4352f4fd03935ed78`
- Operator (independent): ____________________
- Machine ID / hostname: ____________________
- OS: ____________________
- Timezone: ____________________

## Runtime Snapshot (from template machine)

- Docker Compose: `Docker Compose version v2.38.2-desktop.1`
- Docker CLI client: `28.3.2`
- Docker server at capture time: `not reachable from PowerShell pipe (desktop engine offline in this shell context)`
- Python: `Python 3.10.11`
- R: `R version 4.6.0 (2026-04-24 ucrt)`

## Required Inputs

- `validation/drinking_water_v1/reports/FREEZE_v1.md`
- `validation/drinking_water_v1/reports/DEPLOYMENT_VERIFICATION_v1.md`
- `validation/drinking_water_v1/runs/v1-dw-20260510-freeze/manifest.json`
- `validation/drinking_water_v1/runs/v1-dw-20260510-freeze/hashes.txt`
- `validation/drinking_water_v1/reports/CLEAN_MACHINE_RUNBOOK_v1.md`

## Execution Checklist

| Step | Status | Notes |
|---|---|---|
| Clone/open repo on clean machine | Pending | |
| Checkout governed commit SHA | Pending | |
| Confirm required governance files exist | Pending | |
| `docker compose build` completes | Pending | |
| `docker compose up` completes | Pending | |
| App endpoint opens (`localhost` mapped port) | Pending | Record exact URL |
| FREEZE / manifest / hashes visible post-run | Pending | |
| No unresolved package/runtime error | Pending | |

## Command Evidence

Record outputs (copy/paste or attach screenshots):

- `git rev-parse HEAD`
- `docker version`
- `docker compose version`
- `python --version`
- `Rscript -e "cat(R.version.string)"`

## Outcome

- Independent clean-machine reproduction: Pending
- Reproducibility statement: _______________________________________________

## Conservative Wording Guardrail

Allowed wording:

`screening / prioritization / governance platform`

Disallowed wording:

`accredited`, `certified`, `regulatory-approved`, `compliance automation`

## Sign-off

- Independent operator: ____________________
- Reviewer / technical owner: ____________________
- Date (local): ____________________
