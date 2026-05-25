# Governance index — PFAS Enterprise 5.0

**Identity:** governed, reproducible environmental toxicology **infrastructure** (RUO decision-support)—not a certified laboratory system, clinical diagnostic, or “ISO-certified AI.”

**Frozen serum release:** tag `serum-v2.0.0-temporal` · commit `8ce2492` · [Zenodo 10.5281/zenodo.20348369](https://doi.org/10.5281/zenodo.20348369) · [GitHub Release](https://github.com/Ishola-github/pfas-enterprise-modular/releases/tag/serum-v2.0.0-temporal)

External executors: use the **tag only** — not branch `main`.

---

## Start here

| Document | Purpose |
|----------|---------|
| [DISCLAIMER.md](../DISCLAIMER.md) | Honest scope, limitations, safe positioning |
| [validation/public_reproducibility_summary.md](../validation/public_reproducibility_summary.md) | Public evidence matrix (CI, Docker, canonical pins) |
| [validation/serum_demo_v1/ONE_COMMAND_REPRO.md](../validation/serum_demo_v1/ONE_COMMAND_REPRO.md) | Blind reviewer path: `bash scripts/repro_one_shot.sh` |
| [validation/serum_demo_v1/PILOT_SCOPE_FREEZE.md](../validation/serum_demo_v1/PILOT_SCOPE_FREEZE.md) | Active pilot freeze (no scope expansion) |

---

## Reproducibility and releases

| Document | Purpose |
|----------|---------|
| [ONE_COMMAND_REPRO.md](../ONE_COMMAND_REPRO.md) | Root pointer (Mode A vs Mode B API) |
| [scripts/repro_one_shot.sh](../scripts/repro_one_shot.sh) | One-shot Docker verify + canonical V2 SHA gate |
| [docs/ZENODO_ARCHIVE.md](ZENODO_ARCHIVE.md) | Archival and DOI operator guide |
| [docs/RELEASES.md](RELEASES.md) | Release tagging discipline |
| [validation/releases/serum-v2.0.0-temporal/](../validation/releases/serum-v2.0.0-temporal/) | Freeze manifest, checklist, canonical pins copy |

---

## Doctrine and validation

| Document | Purpose |
|----------|---------|
| [docs/GOVERNANCE.md](GOVERNANCE.md) | Program doctrine (pins, CI, promotion gates) |
| [validation/serum_demo_v1/REPRODUCIBILITY_PROGRAM.md](../validation/serum_demo_v1/REPRODUCIBILITY_PROGRAM.md) | Independent reproducibility pilot |
| [validation/serum_demo_v1/BLIND_EXTERNAL_REPRO_PROTOCOL.md](../validation/serum_demo_v1/BLIND_EXTERNAL_REPRO_PROTOCOL.md) | Full blind protocol (optional) |
| [validation/serum_demo_v1/REVIEWER_ATTESTATION_MINIMAL.txt](../validation/serum_demo_v1/REVIEWER_ATTESTATION_MINIMAL.txt) | Signed attestation template |
| [validation/serum_demo_v1/reviewer_log.csv](../validation/serum_demo_v1/reviewer_log.csv) | External PASS/FAIL log (≥2 PASS → promotion) |
| [validation/serum_demo_v1/canonical_pins.json](../validation/serum_demo_v1/canonical_pins.json) | Frozen analytical hashes |

---

## Grants and public narrative

| Document | Purpose |
|----------|---------|
| [docs/blog/POST_01_REPRODUCIBILITY_PFAS_WORKFLOWS.md](blog/POST_01_REPRODUCIBILITY_PFAS_WORKFLOWS.md) | Draft: Why reproducibility matters (publish externally) |
| [docs/grants/ISO_17025_WORKFLOW_SUPPORT_BLURB.md](grants/ISO_17025_WORKFLOW_SUPPORT_BLURB.md) | Grant-safe 17025-*aligned* wording (not certification) |
| [docs/whitepapers/PFAS_Enterprise_5_Reproducibility_Whitepaper.md](whitepapers/PFAS_Enterprise_5_Reproducibility_Whitepaper.md) | Long-form reproducibility narrative |

---

## Technical contracts (selected)

| Document | Purpose |
|----------|---------|
| [docs/PIPELINE_CONTRACT_V1.md](PIPELINE_CONTRACT_V1.md) | Pipeline I/O contract |
| [docs/CONTROLLED_DOCUMENTS.md](CONTROLLED_DOCUMENTS.md) | Controlled doc index |
| [SCOPE_AND_INTENDED_USE.md](../SCOPE_AND_INTENDED_USE.md) | Scope boundaries |

---

## What we do not claim

- ISO/IEC 17025 **accreditation** or EPA **certification**
- Clinical diagnosis or automated regulatory compliance
- Replacement for accredited analytical methods (EPA 533 / 537.1 / 1633)

**Safe framing:** decision-support · screening · contextualization · workflow governance · human-reviewed outputs.

---

## Changing frozen artifacts

Never silently overwrite canonical hashes or the analytical tag `serum-v2.0.0-temporal`. If behavior must change, publish a **new tag** (e.g. `serum-v2.0.1-demo`) and a new Zenodo version; preserve the original deposit permanently.
