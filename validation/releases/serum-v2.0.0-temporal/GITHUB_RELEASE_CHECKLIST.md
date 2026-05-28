# GitHub Release checklist — serum-v2.0.0-temporal (operator)

**Do this now.** Creates public frozen evidence before reviewer replies.

URL: https://github.com/Ishola-github/pfas-enterprise-modular/releases/new

---

## Release settings

| Field | Value |
|-------|-------|
| Tag | `serum-v2.0.0-temporal` (select existing) |
| Title | `PFAS Enterprise 5.0 — Serum v2.0.0 temporal reproducibility program` |
| Target | `main` or tag commit |

---

## Attach files

| File | Source path |
|------|-------------|
| Reviewer packet | `validation/releases/serum-v2.0.0-temporal/serum_demo_reviewer_packet.zip` |
| Freeze manifest | `validation/releases/serum-v2.0.0-temporal/REPRODUCIBILITY_RELEASE_FREEZE.json` |
| Canonical pins | `validation/releases/serum-v2.0.0-temporal/canonical_pins.json` |

---

## Description (paste)

Use body from `RELEASE_NOTES.md` in this folder.

Add link: `validation/public_reproducibility_summary.md` on `main` at `f95ebb4`.

---

## CI screenshots (required)

1. Open https://github.com/Ishola-github/pfas-enterprise-modular/actions
2. Screenshot latest green **Governance Checks** on `62377e1` or `f95ebb4`
3. Save as `screenshots/ci/governance_checks_green.png`
4. Attach to Release OR commit to repo and reference in notes

---

## After publish

1. Update `validation/public_reproducibility_summary.md` with Release URL
2. Zenodo: `docs/ZENODO_ARCHIVE.md`
3. Send **ONE** executor the minimal path: `ONE_COMMAND_REPRO.md` + ZIP

---

## Do NOT during pilot

- Change canonical hashes
- Add analytes / matrices / ML claims
- Re-tag without program note
