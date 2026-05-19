# Pilot scope freeze — blind reproducibility program

**Status:** ACTIVE until ≥2 independent blind PASS attestations are recorded.  
**Identity:** Governed infrastructure prototype with reproducibility-focused validation.

---

## What we claim

- Governed RUO PFAS serum contextualization (PFOS/PFOA isomers)
- Manifest-backed provenance (run_id + SHA-256)
- Docker-verifiable reproducibility pathway
- CI/schema-lock governance on frozen canonical outputs

## What we do NOT claim

- Validated scientific platform
- Commercial PFAS product
- Regulatory system
- Predictive toxicology / clinical utility engine
- Externally validated (until ≥2 blind PASS)

---

## Frozen until pilot closes

| Frozen item | Rule |
|-------------|------|
| Canonical hashes | No changes to `canonical_pins.json` gates |
| Input fixture | No edits to `nhanes_j_governed_v1_input.csv` |
| Reference v1.1 table | No rebuild without new release tag + program close |
| Git tag `serum-v2.0.0-temporal` | No retag; analytical pin stands |
| Manifest schema | No column removals/renames (schema-lock) |

## Prohibited during pilot

- New PFAS analytes
- New matrices (water, sludge, air, etc.)
- Schema redesign or ontology drift
- Shiny UI expansion
- New ML / disease / diagnostic claims
- Bulk outreach (target: **1** then **2** signed PASS only)
- Feature commits unrelated to repro fixes

## Allowed during pilot

- Bug fixes that restore frozen canonical outputs
- CI/registry verifier scope fixes (governance only)
- Reviewer friction reduction (docs/scripts for `repro_one_shot.sh`)
- GitHub Release + Zenodo (evidence packaging)
- Attestation logging in `reviewer_log.csv`

---

## Operator sequence (strict)

1. Reduce friction → `ONE_COMMAND_REPRO.md` + `repro_one_shot.sh`
2. **ONE** signed minimal attestation
3. GitHub Release (public frozen evidence)
4. Zenodo DOI
5. **Second** signed attestation
6. Whitepaper / abstract (claims match evidence only)
7. Pilot consulting / grants (repro infrastructure framing)

**Center of gravity:** independent reproducibility precedes everything else.

---

## Pilot close criteria

| Gate | Requirement |
|------|-------------|
| Close pilot | ≥2 rows in `reviewer_log.csv` with overall PASS |
| Then | Update `public_reproducibility_summary.md`; Zenodo; whitepaper claims |

Until close: describe project as **self-verified** infrastructure with reproducibility-focused validation in progress.
