# PFAS Enterprise 5.0 — SOP & controlled documentation index

This file is the **navigation hub** for quality and engineering. The **full SOP suite** (operational procedures, Word/PDF masters) may live outside this repository; this index records **how repo artifacts tie to that suite** without duplicating controlled text.

## Governance stance (language)

- Prefer: **ISO/IEC 17025–aligned** governance, **evidence-governed** vs **screening** workflows, **traceability-oriented** design, **screening and prioritization** decision-support.  
- Avoid product claims of **ISO certification**, **regulatory compliance** for the model, or **substitution** for accredited laboratory validation.  
- See `.cursor/rules/pfas-terminology.mdc` and `validation/drinking_water_v1/reports/intended_use.txt`.

## Active SOP revision

| Rev | Markdown master | Status |
| --- | --------------- | ------ |
| **2.1** | [`docs/sop/PFAS_Enterprise_5_SOP_Rev2.1.md`](sop/PFAS_Enterprise_5_SOP_Rev2.1.md) | **Current** — serum V1.1/V2, Docker parity, release tags |
| 1.0 | `docs/sop/PFAS_Enterprise_5_SOP_Suite_Rev1_2026-05-10.docx` (Word; gitignored) | Superseded by 2.1 for serum lane |

Serum doctrine: [`GOVERNANCE.md`](GOVERNANCE.md) · Release pins: [`RELEASES.md`](RELEASES.md)

## Freezing SOP Revision 1.0 (historical baseline)

When QA approved **SOP Rev 1.0**, record in **`CONTROLLED_DOCUMENTS.md`**:

| Field | Example |
| ----- | ------- |
| SOP document ID | *Assign (e.g. PE5-SOP-001 suite)* |
| Revision | **1.0** |
| Effective date | *YYYY-MM-DD* |
| Git tag | *e.g. `sop-1.0` or `v5.0-sop-1.0`* |
| Commit SHA | *full or short SHA of tag target* |

**Tie the same tag/SHA** to:

- `validation/drinking_water_v1/reports/FREEZE_v1.md` (product/threshold freeze)  
- `validation/drinking_water_v1/runs/<run_id>/manifest.json` + `hashes.txt`  
- Validation artifact bundle under `validation/drinking_water_v1/artifacts/`  
- Controlled Word master (example): `docs/sop/PFAS_Enterprise_5_SOP_Suite_Rev1_2026-05-10.docx` — see `docs/sop/README.md`

## In-repo validation & evidence (drinking-water v1)

| Artifact | Path |
| -------- | ---- |
| Master validation plan | `validation/drinking_water_v1/VALIDATION_PLAN.md` |
| Product freeze declaration | `validation/drinking_water_v1/reports/FREEZE_v1.md` |
| Intended use | `validation/drinking_water_v1/reports/intended_use.txt` |
| Acceptance criteria | `validation/drinking_water_v1/reports/acceptance_criteria_v1.md` |
| Evidence copy checklist | `validation/drinking_water_v1/reports/EVIDENCE_COPY_CHECKLIST.md` |
| Repeatability | `validation/drinking_water_v1/reports/REPEATABILITY_v1.md` |
| External blind | `validation/drinking_water_v1/external_blind/` + `reports/EXTERNAL_BLIND_PROTOCOL_v1.md` |
| Pilot reviewers | `validation/drinking_water_v1/pilot_review/` + `reports/PILOT_REVIEW_PROTOCOL_v1.md` |
| Run manifests & hashes | `validation/drinking_water_v1/runs/` + `scripts/write_run_hashes.cmd` |

## Operational routes (conceptual)

- **Internal Shiny workflow** — primary integrated path; align with SOP “internal runner.”  
- **External runner / training route** — scripts, env vars (`PFAS_TRAIN_RESULTS_SUBDIR`, UCMR pipeline); separate SOP section as you documented.  
- **Screening vs evidence-governed** — `results/` vs `results/screening/`; must not be mixed silently in claims or exports.

## Serum lane (Rev 2.1)

| Topic | Path |
| ----- | ---- |
| SOP sections 31–38 | `docs/sop/PFAS_Enterprise_5_SOP_Rev2.1.md` |
| Shiny V1.1 + V2 | `LatestPFAS.R` → Reports tab |
| Sync to RStudio | `scripts/sync_serum_lane_to_rstudio.ps1` |
| V1.1 CLI | `python -m src.v1.cli --v1-1` |
| V2 CLI | `python -m src.v2.cli` |
| Tags | `serum-v1.0-governed`, `serum-v1.1-race-aware`, `serum-v2.0.0-temporal` |

## Related registry

- **Controlled document register:** `CONTROLLED_DOCUMENTS.md`  
- **Revision history (this layer):** `CHANGELOG.md`

## Next discipline (no scope creep)

1. Execute **repeatability** (3× identical) before expanding model complexity.  
2. Complete **external blind** with frozen **τ**.  
3. Add **deployment reproducibility** (pinned env, Docker/`renv`) only after evidence steps advance.
