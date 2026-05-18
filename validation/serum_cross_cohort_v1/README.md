# Serum cross-cohort contextualization scaffold (v1)

This folder defines governance for comparison of two governed cohort summary
CSV outputs (for example NHANES baseline vs exposed cohort summary).

Status: scaffold and comparator CLI stub only. No new cohort ingestion is
performed by this lane.

## Files

| File | Role |
|------|------|
| `SPEC.md` | Cross-cohort comparison spec and operating model |
| `schema_contract.md` | Human-readable input/output schema contract |
| `schema_contract.json` | Machine-readable schema contract |
| `intended_use.txt` | RUO intended use |
| `limitations.md` | Non-claims and guardrails |

## Comparator CLI

```powershell
python -m src.v2.cross_cohort_cli `
  --left-summary  data\v2\outputs\cohort\left.csv `
  --right-summary data\v2\outputs\cohort\right.csv `
  --left-label NHANES `
  --right-label ATSDR `
  --output-dir data\v2\outputs\cross_cohort
```
