# Failure-case validation (bad inputs)

Software validation for a screening product often matters **more** than small AUC deltas. Intentionally run these tests; record pass/fail and UI or log text in `runs/<run_id>/manifest.json` (e.g. under `metrics.software_checks`).

| Test | Expected behavior |
| ----- | ------------------- |
| Missing PFAS / required column | Clear error naming **exact** missing fields |
| Wrong units | Block or convert with **audit-visible** note |
| Empty file | Reject with clear message |
| Non–drinking-water matrix | Applicability warning or block (see `applicability_domain.txt`) |
| Duplicate sample IDs | Flag duplicates |
| Corrupt / truncated upload | Fail gracefully; no silent partial load |

## Record

- Date, operator, app version, screenshot or log URI per row.
