# Reviewer Brief — PFAS Enterprise 5.0 Scope Document (v1.0)

## What the ask is, in one table

| Field | Value |
| --- | --- |
| What you are reviewing | `SCOPE_AND_INTENDED_USE.md` — a single 17-section document, ~10 pages |
| What you are **not** reviewing | The codebase, the predictions, the deployed API, the AD models themselves, the training data |
| What you are **not** endorsing | The platform's predictions, accuracy, fitness for any specific use, regulatory acceptance, or commercial readiness |
| Time commitment | 2-4 hours of reading and structured feedback |
| Honorarium | None. Pro-bono review with public attribution. |
| Attribution | Your name and (optional) affiliation are placed in this directory in the public GitHub repository |
| Right to decline attribution | Yes. You may complete the review with your name kept private. |
| Deliverable | A filled-in copy of `reviewer_scope_checklist.md` named `<your-last-name>.md`, returned by email or pull request |

## One-paragraph context

PFAS Enterprise 5.0 is a multi-matrix screening prototype for per- and
polyfluoroalkyl substances in environmental and biomonitoring matrices.
It separates each supported matrix into its own pipeline lane
(`drinking_water`, `serum`, `biosolids_sludge`, `afff`,
`methanol_standards`, `air_emissions`), each anchored to a documented
public source (US EPA UCMR5, NHANES, NIST SRM 1957, EPA Method 1633
anchor + EPA ICIS-NPDES biosolids permits, NIST RM 8690, NIST RM 8446,
EPA OTM-50). Each lane carries its own applicability-domain (AD) model
and refusal logic. The platform ships with a public AD-gated FastAPI
service, a Shiny analyst console, a sealed external blind-validation
harness, and a reproducible scope-freeze artifact. It is **not** a
regulatory product, **not** a laboratory replacement, and **not** an
autonomous decision-maker.

## Specifically what I am asking

Read `SCOPE_AND_INTENDED_USE.md` and fill in
`reviewer_scope_checklist.md`. The six scoped questions you will
answer are:

1. **Are the scope boundaries honest?** (Sections 1, 4)
2. **Is matrix separation defensible?** (Sections 2, 6, 14)
3. **Are the governance claims reasonable?** (Sections 7, 8, 13)
4. **Are the limitations stated clearly?** (Sections 9, 10, 16)
5. **Are the prohibited-use statements sufficient?** (Section 4)
6. **Are there obvious scientific overclaims?** (whole document)

For each, mark `pass` / `concern` / `reject` and add a one-sentence
note. The structured form makes the review easy to skim, easy to
action, and easy to attribute.

You are **not** being asked: "Is the platform scientifically correct
overall?" That is too large a question for a 2-4 hour review and would
require examining the codebase, training data, and model outputs —
none of which are in scope here.

## Access the document

The frozen v1.0 scope document is available at the git tag
`scope-frozen-v1.0`:

- Live document (current `main` branch):
  https://github.com/Ishola-github/pfas-enterprise-modular/blob/main/SCOPE_AND_INTENDED_USE.md
- Snapshot at the v1.0 freeze (immutable, at git tag `scope-frozen-v1.0`):
  https://github.com/Ishola-github/pfas-enterprise-modular/blob/scope-frozen-v1.0/validation/scope_freeze/v1.0/SCOPE_AND_INTENDED_USE.snapshot.md
- Freeze manifest with SHA-256 of every governance-critical file (immutable, at tag):
  https://github.com/Ishola-github/pfas-enterprise-modular/blob/scope-frozen-v1.0/validation/scope_freeze/v1.0/freeze_manifest.json
- This review packet directory (added to `main` after the tag was issued, so use the `main` URL):
  https://github.com/Ishola-github/pfas-enterprise-modular/tree/main/validation/scope_freeze/v1.0/reviews

The tag `scope-frozen-v1.0` is intentionally preserved as the
immutable record of the v1.0 governance state. The reviewer packet
was added on `main` afterwards and lives there until it is folded
into a future freeze version (v1.1 or v2.0).

If you want to verify that the document you read matches the version
the operator is citing, copy the `sha256` from
`freeze_manifest.json → files.scope_document.sha256` into the header
of your checklist. That short hash uniquely identifies which version
your review applies to.

## What happens after your review

1. Your filled-in checklist is added to this directory as
   `<your-last-name>.md`.
2. If you marked any items `concern` or `reject`, those become tasks
   for the next scope-document revision (v1.1). The fixes are made,
   the document is rebuilt, and a new freeze artifact (v1.1) is
   issued.
3. **Your sign-off applies only to the version you reviewed.** A
   later v1.1 or v2.0 does not inherit your attribution unless you
   re-review.
4. With your explicit consent (a checkbox in the checklist), your name
   is added to the public `freeze_manifest.json` as
   `scientific_reviewer`. Without consent, your review stays in this
   directory only.

## What your review does and does not confer

| Your review **does** | Your review **does not** |
| --- | --- |
| Establish that v1.0 was independently scrutinized for honesty | Endorse the predictions or the AD models |
| Document any concerns or rejections per section | Confer regulatory acceptance |
| Inform the v1.1 revision priorities | Make the platform validated for compliance use |
| Become a citable governance artifact | Imply an ongoing advisory relationship |
| Sit in the public GitHub repo (with your consent) | Bind you to future versions |

That distinction is preserved in every artifact your name appears in.

## Why this packet exists

Mature scientific platforms are defined as much by **controlled
claims** as by **technical capability**. A scope document that no one
outside the build team has read is not a controlled claim; it is a
self-issued promise. This review is the smallest credible action that
converts the promise into a documented external check.
