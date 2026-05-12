# Scope Freeze v1.0

This directory will hold the **first** hash-pinned snapshot of
[`../../../SCOPE_AND_INTENDED_USE.md`](../../../SCOPE_AND_INTENDED_USE.md)
once `scripts/build_scope_freeze.py --version v1.0` is run.

## Status

**Pre-build.** The build script has not yet been run on this checkout.
After the first successful build, this directory will additionally
contain:

- `SCOPE_AND_INTENDED_USE.snapshot.md` — byte-identical copy of the
  live scope document at freeze build time.
- `freeze_manifest.json` — machine-readable manifest with SHA-256 of
  every governance-critical file (scope doc, SOP CSV, reference
  registry, UCMR limits CSV, every per-lane AD model JSON), plus lane
  inventory, smoke status, freeze metadata, and `git_head_sha`.
- `CHANGELOG.md` — append-only log of every build performed against
  this freeze version.

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

After re-running the full regression suite in all four target
environments and obtaining an independent scientific reviewer sign-off:

```
python scripts/build_scope_freeze.py \
    --version v1.0 \
    --status frozen \
    --operator "Sunday Ishola" \
    --reviewer "<independent scientific reviewer name>" \
    --regulatory-liaison "<optional>" \
    --smoke-windows pass \
    --smoke-rstudio pass \
    --smoke-docker-ubuntu pass \
    --smoke-wsl-ubuntu pass \
    --note "Pre-pilot freeze for SBIR submission"
```

Then tag the repository:

```
git tag scope-frozen-v1.0
git push --tags
```

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
