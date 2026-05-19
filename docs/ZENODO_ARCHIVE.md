# Zenodo archive and DOI — serum reproducibility program

Archive a **frozen** reproducibility release before citing in grants, pilots, or papers.

**Do not** mint a DOI on moving `main` without a tag or release snapshot.

---

## What to archive

| Artifact | Path |
|----------|------|
| Git tag snapshot | `serum-v2.0.0-temporal` (+ program commit `62377e1` notes in README) |
| Reviewer packet | `validation/serum_demo_v1/serum_demo_reviewer_packet.zip` |
| Canonical pins | `validation/serum_demo_v1/canonical_pins.json` |
| Freeze manifest | `validation/releases/serum-v2.0.0-temporal/REPRODUCIBILITY_RELEASE_FREEZE.json` |
| Public evidence | `validation/public_reproducibility_summary.md` |
| Whitepaper | `docs/whitepapers/PFAS_Enterprise_5_Reproducibility_Whitepaper.md` |
| Example manifests | `validation/serum_demo_v1/evidence_bundle/manifests/` (if included in release zip) |

---

## GitHub → Zenodo (recommended)

1. Create account: https://zenodo.org/
2. Link GitHub: https://zenodo.org/account/settings/github/
3. Enable repository: `Ishola-github/pfas-enterprise-modular`
4. On GitHub: **Releases → Draft new release**
   - Tag: `serum-v2.0.0-temporal` (existing) or new `serum-v2.0.0-temporal-repro-1` if you need program commit pinned
   - Attach: `serum_demo_reviewer_packet.zip`, `REPRODUCIBILITY_RELEASE_FREEZE.json`, optional evidence zip
   - Title: `PFAS Enterprise 5.0 — Serum v2.0.0 temporal reproducibility program`
5. Zenodo will ingest the GitHub release and assign a **DOI**
6. Add `CITATION.cff` or README badge with the DOI

---

## Metadata (suggested)

- **Title:** Governed RUO PFAS Serum Contextualization — Docker-Verifiable Reproducibility Package
- **Creators:** [your name, ORCID if available]
- **Description:** Frozen NHANES serum PFOS/PFOA contextualization demo with manifest provenance, schema-lock CI, and blind external reproducibility protocol. RUO only.
- **Keywords:** PFAS, NHANES, biomonitoring, reproducibility, provenance, Docker
- **License:** Match repository license
- **Version:** serum-v2.0.0-temporal

---

## After DOI

1. Add DOI to `validation/public_reproducibility_summary.md`
2. Add DOI to whitepaper front matter
3. Cite in grant / pilot materials as **citable reproducibility artifact**, not as regulatory validation

---

## Optional: OSF / arXiv

- **OSF:** upload same zip + whitepaper PDF for project management visibility
- **arXiv:** submit whitepaper after ≥2 blind PASS attestations (methods + reproducibility focus)
