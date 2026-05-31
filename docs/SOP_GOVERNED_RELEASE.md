# SOP: Governed Release (Manual Publish After Validation)

## Policy Lock

- No reusable-release automation yet.
- Validate first, then publish manually only after PASS.
- Audit clarity is prioritized over CI complexity.

## Scope

Use this SOP for governed PFAS Enterprise releases (for example `serum-v*`, `governed-v*`).

## Procedure

1. Confirm all required validation artifacts exist.
2. Run `governed-gate-full.yml`.
3. Confirm GitHub Actions status is `PASS`.
4. Create governed tag only after PASS.
5. Publish GitHub Release manually.
6. Attach evidence packet and model card to the release.
7. If gate fails, delete the tag, fix the issue, and rerun validation.

## Go / No-Go Criteria

- **GO** when:
  - governed gate is PASS
  - artifact set is complete
  - evidence manifest is present and consistent
  - reviewer signoff is present for governed mode

- **NO-GO** when:
  - any governed gate check fails
  - required artifacts are missing
  - threshold freeze / AD / provenance checks are inconsistent

## Rollback Rule

If a governed tag was created before a valid PASS state:

1. Delete local tag.
2. Delete remote tag.
3. Correct artifacts/configuration.
4. Rerun governed gate to PASS.
5. Recreate tag and proceed with manual release.

