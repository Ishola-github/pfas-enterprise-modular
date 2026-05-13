# Reviewer Scope Checklist — PFAS Enterprise 5.0 Scope Document v1.0

> **Instructions:** Save a copy of this file as `<your-last-name>.md`
> in this directory. Fill in the header, mark each of the six numbered
> questions with `pass`, `concern`, or `reject` (and a one-sentence
> note), then complete the sign-off block at the bottom. Submit the
> filled-in file by email reply or as a pull request to the public
> repository.

**Document under review:** `SCOPE_AND_INTENDED_USE.md`
**Frozen at:** git tag `scope-frozen-v1.0` (see
[`../freeze_manifest.json`](../freeze_manifest.json))
**Snapshot copy:**
[`../SCOPE_AND_INTENDED_USE.snapshot.md`](../SCOPE_AND_INTENDED_USE.snapshot.md)

---

## Reviewer

| Field | Value |
| --- | --- |
| Name | _(your full name)_ |
| Affiliation (optional) | _(institution / firm / "independent")_ |
| Email (not published) | _(for operator follow-up only)_ |
| Date reviewed (YYYY-MM-DD) | _(date)_ |
| Document SHA-256 read | _(paste `files.scope_document.sha256` from `../freeze_manifest.json`; confirms which version your review applies to)_ |

---

## Six scoped questions

### Q1. Are the scope boundaries honest? (Sections 1, 4)

Specifically: does **Section 1 (System Purpose)** describe the
platform without overstating capability? Does **Section 4 (Unsupported
Use Cases)** cover the categories you would expect a screening
prototype to refuse? Are there capabilities implied but not delivered?

- [ ] pass
- [ ] concern
- [ ] reject

**Notes (one or two sentences):**

```
_(your note)_
```

---

### Q2. Is matrix separation defensible? (Sections 2, 6, 14)

Specifically: **Section 2 (Supported Matrices)** lists six lanes with
unit domains and scientific purposes. **Section 6 (Matrix Isolation
Requirements)** describes three code-level checkpoints and includes
subsection 6.4 (Shared infrastructure vs. matrix-isolated science).
**Section 14 (Environmental vs Physiological Separation)** keeps
serum apart from environmental occurrence lanes. Is the separation
defensible on analytical / matrix / unit / detection-limit /
contamination-mechanism grounds? Are any two lanes implicitly
comparable when they should not be?

- [ ] pass
- [ ] concern
- [ ] reject

**Notes (one or two sentences):**

```
_(your note)_
```

---

### Q3. Are the governance claims reasonable? (Sections 7, 8, 13)

Specifically: **Section 7 (AD Policy)** describes per-lane
applicability-domain models with hard refusal. **Section 8 (Governance
and Provenance)** describes SHA-256 manifests, the reference registry
verifier, and audit logs — with an explicit non-claim that provenance
is tamper-evident, not cryptographically signed for non-repudiation.
**Section 13 (Threshold Governance)** versions the UCMR thresholds by
SHA-256 prefix. Are the governance claims at the level the platform
actually supports today, or do they overstate? Is the Section 8
"tamper-evident, not non-repudiation" caveat strong enough?

- [ ] pass
- [ ] concern
- [ ] reject

**Notes (one or two sentences):**

```
_(your note)_
```

---

### Q4. Are the limitations stated clearly? (Sections 9, 10, 16)

Specifically: **Section 9 (External Validation Status)** declares no
independent published study, no interlaboratory study, no
regulator-conducted evaluation. **Section 10 (Regulatory and
Accreditation Limitations)** lists explicit "Not" statements (EPA,
ELAP, NELAP, ISO 17025, SOC 2, GLP, GMP, 21 CFR Part 11, FedRAMP,
IL-4/5). **Section 16 (SaaS Operational Limitations)** lists what the
API ships and explicitly what it does not. Are the limitations clear
enough that a procurement reviewer or regulatory liaison would
understand them on first read?

- [ ] pass
- [ ] concern
- [ ] reject

**Notes (one or two sentences):**

```
_(your note)_
```

---

### Q5. Are the prohibited-use statements sufficient? (Section 4)

**Section 4** lists eight categories of unsupported use (regulatory
compliance, LC-MS/MS replacement, autonomous decision-making,
cross-matrix prediction, forensic source attribution, "one PFAS model",
quantitative inference from program-metadata lanes, consumer
advisories). Are there obvious prohibitions missing? In particular:
can you imagine a way an operator could use this platform that the
document does **not** explicitly prohibit but **should**?

- [ ] pass
- [ ] concern
- [ ] reject

**Notes (one or two sentences):**

```
_(your note)_
```

---

### Q6. Are there obvious scientific overclaims? (whole document)

Across all 17 sections, are there statements that go beyond what the
technical artifacts support — language like "validated," "accredited,"
"regulator-grade," "production-ready," "compliance," "certified," or
similar — that should be softened, qualified, or removed?

- [ ] pass
- [ ] concern
- [ ] reject

**Notes (one or two sentences):**

```
_(your note)_
```

---

## Free-text comments (optional)

Anything that doesn't fit one of the six questions: section-level
copy-edits, structural suggestions, things the document does not
currently address that you think it should.

```
_(free text — as much or as little as you like)_
```

---

## Reviewer sign-off

### Overall verdict (pick exactly one)

- [ ] **OK to cite v1.0 as independently reviewed** with no required changes.
- [ ] **OK once Q[#]–Q[#] concerns above are addressed** in the next revision (v1.1).
- [ ] **NOT OK as written.** Major rework needed before this document is fit for the stated purpose.

### Public attribution consent

- [ ] **Yes.** My name and (optional) affiliation may appear in the
      public [`../freeze_manifest.json`](../freeze_manifest.json) as
      `scientific_reviewer` for the version of the document I
      reviewed.
- [ ] **No.** My review may stay in this directory only; do **not**
      add my name to the public manifest.

### Conflict of interest disclosure

- [ ] **None.**
- [ ] **Disclosed:** _(brief description — e.g. former employer,
      research funding source, prior collaboration with the platform
      operator, equity / consulting relationships in PFAS-adjacent
      companies)_

### Signature

```
Name (typed):       _(your name)_
Date (YYYY-MM-DD):  _(date)_
```

---

*This checklist is governance evidence, not legal or regulatory
certification. Operators of the platform remain responsible for their
public claims, jurisdictions, and use contexts. Your review applies
only to the version of the document identified by the SHA-256 in your
header; later versions require re-review.*
