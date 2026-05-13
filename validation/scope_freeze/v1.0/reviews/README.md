# Scope Review Packet — PFAS Enterprise 5.0 v1.0

This directory contains the **reviewer outreach packet** and **completed
reviews** for the v1.0 scope document
([`../SCOPE_AND_INTENDED_USE.snapshot.md`](../SCOPE_AND_INTENDED_USE.snapshot.md)).

## What's here

| File | Purpose | Audience |
| --- | --- | --- |
| `reviewer_brief.md` | One-page brief: what the review is and isn't | Candidate reviewers |
| `reviewer_request_email.md` | Three outreach email variants + follow-up | Platform operator (you) |
| `reviewer_scope_checklist.md` | Structured review form (template) | Reviewers fill in and return |
| `<last-name>.md` | A single completed review, named after the reviewer | (added as reviews come in) |

## How a review lands here

1. Operator sends outreach (a variant from `reviewer_request_email.md`)
   with a link to this directory.
2. Reviewer reads `reviewer_brief.md` and decides whether to accept.
3. Reviewer copies `reviewer_scope_checklist.md` to
   `<their-last-name>.md`, fills it in, and submits the file by email
   or pull request.
4. With explicit attribution consent (a checkbox inside the checklist),
   the reviewer's name and affiliation are added to
   [`../freeze_manifest.json`](../freeze_manifest.json) as
   `scientific_reviewer` in the next freeze build
   (`python scripts/build_scope_freeze.py --version v1.0 --status frozen
   --operator "<name>" --reviewer "<reviewer name>"`).
5. Without consent, the file stays in this directory only and is
   never promoted to the manifest.

## Scope discipline

This packet asks for **scope-document review**, not platform
endorsement. Concretely:

- The reviewer is **not** endorsing predictions or accuracy.
- The reviewer is **not** endorsing the codebase or the deployment.
- The reviewer is **not** signing a regulatory or compliance attestation.
- The reviewer **is** confirming that the v1.0 scope document is
  honest, internally consistent, and defensible.

That distinction is preserved in every artifact in this directory.

## Open invitation

If you reached this directory by browsing the public GitHub repository
and you have relevant PFAS analytical chemistry, environmental
consulting, environmental QA, or environmental informatics expertise,
[`reviewer_brief.md`](reviewer_brief.md) describes how to participate.
