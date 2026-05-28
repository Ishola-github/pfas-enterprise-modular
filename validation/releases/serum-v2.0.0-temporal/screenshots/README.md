# Release screenshots — serum-v2.0.0-temporal reproducibility

Place evidence images here before publishing GitHub Release / Zenodo archive.

## Required (operator)

| File | Source |
|------|--------|
| `ci/governance_checks_green.png` | GitHub Actions — Governance Checks on `62377e1` (both jobs green) |
| `ci/schema_lock_pass.png` | Schema Lock Tests log (optional) |

## Recommended

| File | Source |
|------|--------|
| `docker/all_pass_terminal.png` | Local or CI Docker verify last line |
| `powershell/registry_ci_ok.png` | `CI=true python scripts/verify_reference_registry.py` |
| `pytest/schema_lock_2of2.png` | pytest 2 passed |

## Do not commit

- Patient-identifiable data
- Unrelated matrix-lane outputs
