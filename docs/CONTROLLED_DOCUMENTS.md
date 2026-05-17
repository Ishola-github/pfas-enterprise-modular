# Controlled documents register — PFAS Enterprise 5.0

**Purpose:** Single table linking **document IDs**, **revisions**, **effective dates**, **superseded** versions, and **links to technical freezes** (git tag, manifest, validation bundle).  
Update this file when a document is **approved**, **revised**, or **withdrawn**.

*Full SOP narrative (Word/PDF)* — store per your QMS; record metadata here only.

---

## Register

| Document ID | Title / description | Rev | Effective date | Supersedes | Git tag / commit | Linked freeze / manifest | Status |
| ----------- | -------------------- | --- | -------------- | ---------- | ---------------- | ------------------------- | ------ |
| PE5-SOP-SUITE-R1 | PFAS Enterprise 5.0 SOP suite (Word master) | 1.0 | 2026-05-10 | — | *Pending QA: tag e.g. `sop-1.0`* | `FREEZE_v1.md` + `runs/v1-dw-20260510-freeze/` | Superseded by Rev 2.1 (serum) |
| PE5-SOP-SUITE | PFAS Enterprise 5.0 SOP (markdown master) | **2.1** | **2026-05-17** | 1.0 | `6efc685` + serum tags | `docs/RELEASES.md`, `docs/GOVERNANCE.md`, `validation/serum_v1/`, `validation/serum_v2/` | **Active** |
| PE5-VAL-PLAN-DW1 | Drinking-water validation plan (repo) | *as committed* | *see git* | — | *branch/SHA* | `validation/drinking_water_v1/VALIDATION_PLAN.md` | Active |
| PE5-FREEZE-DW1 | Drinking-water screening freeze v1.0 | *1.0* | *per FREEZE* | — | *tie to same tag as SOP when locked* | `validation/drinking_water_v1/reports/FREEZE_v1.md` | Active |
| PE5-INTENDED-USE-1 | Intended use statement | *1.0* | *per sign-off* | — | *optional* | `validation/drinking_water_v1/reports/intended_use.txt` | Active |

---

## Superseded / archived

| Document ID | Rev withdrawn | Date | Replaced by |
| ----------- | ------------- | ---- | ----------- |
| — | — | — | — |

---

## SOP Word file (Rev 1.0) — integrity

| Field | Value |
| ----- | ----- |
| Path | `docs/sop/PFAS_Enterprise_5_SOP_Suite_Rev1_2026-05-10.docx` |
| Source copy | `C:\Users\techj\Downloads\PFAS_Enterprise_5_SOP.docx` |
| SHA-256 | `3175e8ef86d91bbd937506bac103afa908313478b4c2c02d017318b3f07fcd87` |

Recompute after any edit to the Word file; update this table and **`CHANGELOG.md`**.

---

## Notes

- **One approved SOP revision** should map to **one** git tag (or tagged release) and to **one** primary validation run manifest when you lock a product snapshot. After QA signs **Rev 1.0**, create tag **`sop-1.0`** (or your naming standard) and replace the *pending* commit note in the **PE5-SOP-SUITE-R1** row with that tag’s SHA.  
- Do not claim **ISO certification** of software in this register; use **aligned** / **traceability-oriented** wording.  
- For **screening** trains, state clearly when artifacts under `results/screening/` are copied into `validation/.../artifacts/` for the frozen bundle.
