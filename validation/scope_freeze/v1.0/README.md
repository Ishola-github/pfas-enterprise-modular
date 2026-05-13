# Scope Freeze v1.0

This directory will hold the **first** hash-pinned snapshot of
[`../../../SCOPE_AND_INTENDED_USE.md`](../../../SCOPE_AND_INTENDED_USE.md)
once `scripts/build_scope_freeze.py --version v1.0` is run.

## Status

**Built. Status `draft`.** The build script has been run on this
checkout (see `CHANGELOG.md` row for the build timestamp). The
manifest reports `status: "draft"` with `scientific_reviewer: null`
because the independent review packet
([`reviews/`](reviews/)) has been published but no completed review
has been returned and consented to public attribution yet.

This directory contains:

- `SCOPE_AND_INTENDED_USE.snapshot.md` — byte-identical copy of the
  live scope document at freeze build time.
- `freeze_manifest.json` — machine-readable manifest with SHA-256 of
  every governance-critical file (scope doc, SOP CSV, reference
  registry, UCMR limits CSV, every per-lane AD model JSON), plus lane
  inventory, smoke status, freeze metadata, and `git_head_sha`.
- `CHANGELOG.md` — append-only log of every build performed against
  this freeze version.
- [`reviews/`](reviews/) — the independent reviewer outreach packet
  (`reviewer_brief.md`, `reviewer_request_email.md`,
  `reviewer_scope_checklist.md`) and the directory where completed
  reviews land as `<reviewer-last-name>.md`.

## Produce the v1.0 freeze

```
python scripts/build_scope_freeze.py --version v1.0
```

That single command:

1. Copies `SCOPE_AND_INTENDED_USE.md` to
   `SCOPE_AND_INTENDED_USE.snapshot.md` here.
2. Computes SHA-256 of every governance-critical file.
3. Walks `data/ad_models/<lane>/ad_model.json` for every supported
   lane and records each model's hash and `ad_method`.
4. Writes `freeze_manifest.json` with `status: "draft"`.
5. Appends one row to `CHANGELOG.md`.

## Promote v1.0 from draft to frozen

Two conditions must hold before promoting:

1. The four-environment regression suite (Windows / RStudio / Docker
   Ubuntu / WSL Ubuntu) has been re-run on this commit and is green.
2. At least one returned [`reviews/<last-name>.md`](reviews/) file
   exists with a "OK to cite v1.0 as independently reviewed" verdict
   **and** the reviewer's explicit public-attribution consent
   (checkbox in the checklist).

Then:

```
python scripts/build_scope_freeze.py \
    --version v1.0 \
    --status frozen \
    --operator "Sunday Ishola" \
    --reviewer "<real reviewer name from reviews/<last-name>.md>" \
    --regulatory-liaison "<optional>" \
    --smoke-windows pass \
    --smoke-rstudio pass \
    --smoke-docker-ubuntu pass \
    --smoke-wsl-ubuntu pass \
    --note "Pre-pilot freeze for SBIR submission; reviewed by <name>"
```

Then tag the repository:

```
git tag -d scope-frozen-v1.0     # the draft tag, if it exists
git tag -a scope-frozen-v1.0 -m "Scope freeze v1.0 (frozen, reviewed by <name>)"
git push origin :refs/tags/scope-frozen-v1.0    # delete on remote
git push origin scope-frozen-v1.0               # re-create on remote
```

Do **not** use a placeholder string like `"<independent reviewer>"`
for `--reviewer`. The build script accepts any string, but a
placeholder makes the manifest internally contradictory (claiming
`frozen` while not having a real reviewer) and is treated as a scope
violation by this directory's own discipline.

## Verify v1.0 at any time

```
python scripts/verify_scope_freeze.py --version v1.0
```

Re-hashes every file referenced by `freeze_manifest.json` and reports
drift. Exits non-zero on any mismatch — safe to chain into the smoke
harness alongside `scripts/verify_reference_registry.py`.

## What this freeze must capture (per current live state)

When you run the build, the manifest should record:

- **Six** supported matrix lanes (`drinking_water`, `serum`,
  `biosolids_sludge`, `afff`, `methanol_standards`, `air_emissions`).
- **Seventeen** reference-registry rows.
- AD methods: five lanes use `per_analyte_envelope_v1`,
  `biosolids_sludge` uses `categorical_coverage_v1`.
- **Seventeen** numbered scope-document sections.

If any of these counts disagree at build time, the live repository has
drifted from the scope statement and the build should be aborted until
the discrepancy is investigated.
