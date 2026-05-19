# Independent Reproducibility Pilot Program — PFAS Enterprise 5.0 (serum demo v1)

**Status:** Active · **RUO only** · Not diagnostic, regulatory, or certification validation.

This is a **structured reproducibility program**, not an informal code review request.

---

## Program objective

Demonstrate that an independent technical executor can reproduce frozen canonical outputs
(`run_id` + output CSV SHA-256) from a clean clone using Docker-verifiable governance checks.

**Success criterion:** ≥2 independent blind PASS attestations (Mode A: Docker preferred).

---

## Frozen release (do not change during pilot)

| Item | Value |
|------|-------|
| Analytical tag | `serum-v2.0.0-temporal` |
| Program manifest commit | `62377e1` (CI registry scope + schema-lock deps) |
| Canonical pins | `validation/serum_demo_v1/canonical_pins.json` |
| Freeze record | `validation/releases/serum-v2.0.0-temporal/REPRODUCIBILITY_RELEASE_FREEZE.json` |

**Rule:** Do not modify canonical hashes, fixtures, or reference tables during active reviewer rounds.

---

## Participant profile (recruit these first)

| Priority | Role |
|----------|------|
| 1 | Research software engineers |
| 2 | Computational toxicology postdocs |
| 3 | Bioinformatics engineers |
| 4 | Exposure-science programmers |
| 5 | Docker/Linux scientific platform engineers |

Professors and executives are **not** first-wave executors — they are credibility amplifiers after PASS evidence exists.

---

## Participant packet

1. `QUICKSTART_5MIN.md` — primary entry (Docker → ALL PASS)
2. `BLIND_EXTERNAL_REPRO_PROTOCOL.md` — full gates + divergence rules
3. `canonical_pins.json` — expected hashes
4. `REVIEWER_ATTESTATION_TEMPLATE.txt` — signed return
5. `serum_demo_reviewer_packet.zip` — bundled send

**Do not** receive sponsor pre-built report CSVs (defeats blind repro).

---

## Operator workflow

| Week | Action |
|------|--------|
| 1 | Enroll 5–8 executors; send packet; log `reviewer_log.csv` as `sent` |
| 2 | Office hours (30 min) for Docker blockers only |
| 3 | Collect attestations; mark `pass` / `fail` |
| 4 | If ≥2 PASS → publish `validation/public_reproducibility_summary.md` update; Zenodo archive; whitepaper |

---

## Evidence ladder (language discipline)

| Stage | Claim allowed |
|-------|----------------|
| Operator pre-flight + CI green | **Self-verified** infrastructure |
| 1 blind PASS | **Single external reproduction** (provisional) |
| ≥2 blind PASS | **Externally reproducible** (Phase 1 demo) |
| Zenodo DOI + whitepaper | **Citable reproducibility artifact** |

---

## After pilot (strict order)

1. Mint Zenodo DOI (`docs/ZENODO_ARCHIVE.md`)
2. Publish technical whitepaper (not marketing)
3. Conference abstract / grant collaboration outreach
4. Pilot consulting conversations (governed contextualization — not SaaS/diagnostics)

---

## Contacts

Program operator maintains `validation/serum_demo_v1/reviewer_log.csv`.  
Public evidence: `validation/public_reproducibility_summary.md`
