# Release: serum-v2.0.0-temporal — Reproducibility Program (frozen)

**Frozen:** 2026-05-19 · **Do not change canonical pins during active pilot.**

## Checkout

```bash
git fetch --tags
git checkout serum-v2.0.0-temporal
```

Program documentation and CI fixes are recorded at commit `62377e1` on `main`; analytical
canonical `run_id` / CSV SHA values are unchanged from this tag.

## Package contents

| Asset | Path |
|-------|------|
| Reviewer ZIP | `validation/serum_demo_v1/serum_demo_reviewer_packet.zip` |
| 5-minute path | `validation/serum_demo_v1/QUICKSTART_5MIN.md` |
| Pilot program | `validation/serum_demo_v1/REPRODUCIBILITY_PROGRAM.md` |
| Canonical hashes | `validation/serum_demo_v1/canonical_pins.json` |
| Freeze record | `validation/releases/serum-v2.0.0-temporal/REPRODUCIBILITY_RELEASE_FREEZE.json` |
| Public evidence | `validation/public_reproducibility_summary.md` |
| Whitepaper draft | `docs/whitepapers/PFAS_Enterprise_5_Reproducibility_Whitepaper.md` |
| Zenodo guide | `docs/ZENODO_ARCHIVE.md` |

## GitHub Release checklist (operator)

1. Tag already exists: `serum-v2.0.0-temporal`
2. Attach `serum_demo_reviewer_packet.zip`
3. Attach `REPRODUCIBILITY_RELEASE_FREEZE.json`
4. Add CI screenshot(s) from Actions → `screenshots/ci/`
5. Paste `RELEASE_NOTES.md` body into GitHub Release description
6. Trigger Zenodo sync per `docs/ZENODO_ARCHIVE.md`

## PASS criteria (reviewers)

See `QUICKSTART_5MIN.md` — Docker ends with `=== Linux verify: ALL PASS ===`.
