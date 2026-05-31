# Changelog — PFAS Enterprise (repo governance & validation layer)

All notable changes to **this repository’s** controlled documentation index, validation tree, and governance scaffolding are recorded here. **Your full SOP suite** may maintain its own revision log per QMS; mirror major milestones here when they affect **code, validation artifacts, or release tags**.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) (simplified).

## [Unreleased]

### Added

- `docs/sop/README.md` — where to place controlled Word SOP master (`PFAS_Enterprise_5_SOP_Suite_Rev1_2026-05-10.docx`); optional Pandoc; `rstudio .` hint.  
- `docs/SOP_INDEX.md` — hub linking SOP freeze practice to `validation/drinking_water_v1/` and terminology guardrails.  
- `docs/CONTROLLED_DOCUMENTS.md` — register template for SOP ID, rev, effective date, git tag, linked freeze/manifest.  
- `docs/CHANGELOG.md` — this file.  
- `.gitignore` — `docs/sop/*.docx` (Word masters local by default).

### Notes

- **PE5-SOP-SUITE-R1** — Word master placed at `docs/sop/PFAS_Enterprise_5_SOP_Suite_Rev1_2026-05-10.docx`; SHA-256 recorded in `CONTROLLED_DOCUMENTS.md`. Formal QA approval and git tag **`sop-1.0`** (or equivalent) still pending.  
- Next evidence milestones: **repeatability 3×**, **external blind**, then **deployment pinning** (requirements/renv/Docker).

---

## Prior work (summary — not exhaustive)

Earlier commits introduced: drinking-water `VALIDATION_PLAN.md`, `FREEZE_v1.md`, artifact hashing (`write_run_hashes.cmd`), external blind and pilot review folders, `label_derivation_audit.json` emission from NHANES trainer (3.2.4), screening vs `results/` separation. See git history for detail.
