# Why Reproducibility Matters in PFAS Decision-Support Workflows

**Author:** Sunday Ishola  
**Status:** Draft for ResearchHub / dev.to / GitHub Discussions  
**Frozen artifact:** [Zenodo 10.5281/zenodo.20348369](https://doi.org/10.5281/zenodo.20348369) · tag `serum-v2.0.0-temporal` · commit `8ce2492`

---

Environmental PFAS workflows sit at an uncomfortable intersection: high public stakes, heterogeneous matrices, fast-moving methods literature, and increasing use of software for screening and contextualization. In that setting, **reproducibility is not a nice-to-have**—it is how you show that a decision-support tool is **governed infrastructure**, not a black-box claim machine.

This note explains what we froze, why we froze it, and how independent reviewers can verify it—without pretending the system is a certified laboratory or clinical product.

---

## The problem: self-asserted “AI” is weak evidence

Many PFAS tools report impressive outputs but leave critical questions unanswered:

- Which **exact inputs** and reference tables were used?
- Which **software version** and configuration produced the result?
- Can a third party **re-run** the workflow and obtain the same governed outputs?
- What happens when a sample is **outside applicability domain**?

Without answers, reviewers, collaborators, and funders correctly treat outputs as **demos**, not infrastructure.

---

## What we did instead: layered trust architecture

For PFAS Enterprise 5.0 (serum pilot lane), we separated **analytical freeze** from **documentation polish**:

| Layer | What it pins | Why it matters |
|-------|----------------|----------------|
| Git tag `serum-v2.0.0-temporal` | Commit `8ce2492` | Immutable code snapshot for reviewers |
| Canonical pins (JSON) | SHA-256 of fixtures, ontology, outputs | Tamper-evident analytical artifacts |
| CI governance workflow | Registry, schema lock, Docker verify, smoke API | Automated guards on every `main` push |
| GitHub Release + assets | Reviewer packet, repro logs, freeze manifest | Human-auditable bundle |
| Zenodo DOI | Citable deposit independent of GitHub | Long-term archival identity |

**Critical discipline:** after issuing the DOI and tagging the release, we did **not** silently rewrite canonical hashes or move the analytical tag to chase a “prettier” demo. Documentation on `main` may evolve; the **frozen reproducibility record stays at `8ce2492`**.

That is the difference between **reproducible research** and **retroactive storytelling**.

---

## One command for independent reviewers

Blind executors should not need to understand container orchestration. They need a **single auditable path**:

```bash
git clone https://github.com/Ishola-github/pfas-enterprise-modular.git
cd pfas-enterprise-modular
git checkout serum-v2.0.0-temporal
bash scripts/repro_one_shot.sh
```

**PASS** requires:

```text
=== Linux verify: ALL PASS ===
ONE_SHOT_REPRO: PASS
V2 output_csv_sha256: 87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67
```

`docker compose up` runs the operational API stack; it is **not** the blind reproducibility gate. Public narrative should emphasize **frozen workflow + hash match**, not orchestration trivia.

---

## What PASS does—and does not—mean

**PASS means:**

- Governed registry rows verify under CI scope
- Schema-lock tests succeed
- Linux Docker verification completes
- Canonical V2 output hash matches the frozen pin

**PASS does not mean:**

- ISO/IEC 17025 accreditation
- EPA method certification
- Clinical diagnostic validity
- “AI replaces the laboratory”

We describe the system as **research-use-only (RUO) decision-support**: screening, contextualization, provenance, and human review—not automated compliance or diagnosis.

---

## Why this framing wins in environmental toxicology

Labs and regulators are not allergic to software—they are allergic to **unverifiable software**. Governance-heavy design (applicability-domain refusal, audit logs, manifest provenance, frozen releases) reduces perceived compliance risk and makes collaboration psychologically safer.

The goal is not to prove “ultimate PFAS AI.” It is to prove:

> **Scientifically governed, reproducible environmental toxicology infrastructure.**

---

## Next proof point: external attestation

Internal CI and operator logs are necessary but not sufficient. The pilot promotes **independent blind reproduction** with a minimal signed attestation. **One** clean external PASS materially strengthens the story; **two** PASS rows support promotion to “externally reproducible” in the public evidence summary.

If you are reviewing this work: use the GitHub Release assets or reviewer packet, run only `repro_one_shot.sh` on the tag above, and return the attestation template without modifying schemas, hashes, or reference tables.

---

## Citation

```
Ishola SA (2026). PFAS Enterprise 5.0 — Serum v2.0.0 temporal reproducibility program.
Zenodo. https://doi.org/10.5281/zenodo.20348369
(tag: serum-v2.0.0-temporal; commit: 8ce2492)
```

**Repository:** https://github.com/Ishola-github/pfas-enterprise-modular  
**Governance index:** `docs/GOVERNANCE_INDEX.md` on `main` (executors: use the tag, not `main`, for verification)

---

*RUO only. Not ISO-certified. Not a replacement for accredited laboratories.*
