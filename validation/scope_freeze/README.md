# Scope Freeze Registry

This directory is the home for **hash-pinned snapshots** of
[`../../SCOPE_AND_INTENDED_USE.md`](../../SCOPE_AND_INTENDED_USE.md).

Each subdirectory (`v1.0/`, `v1.1/`, `v2.0/`, ...) contains one
freeze artifact, produced by
[`../../scripts/build_scope_freeze.py`](../../scripts/build_scope_freeze.py)
and verifiable by
[`../../scripts/verify_scope_freeze.py`](../../scripts/verify_scope_freeze.py).

## Why freeze the scope document

The scope document defines what the platform claims publicly. It must
be **immutable** once distributed alongside a pitch deck, an SBIR
narrative, a pilot agreement, or a partner conversation. A freeze
artifact gives any external reader a way to:

1. Recover the **exact** wording of the scope document at the moment
   of distribution.
2. Verify, via SHA-256, that the live `SCOPE_AND_INTENDED_USE.md` has
   not silently drifted since freeze.
3. Cross-check that the live SOP CSV, reference registry CSV, UCMR
   threshold CSV, and per-lane AD models still match what the scope
   document referenced.

## Build a new freeze

```
python scripts/build_scope_freeze.py --version vX.Y
```

For a final freeze (post-smoke, with operator sign-off):

```
python scripts/build_scope_freeze.py \
    --version v1.0 \
    --status frozen \
    --operator "Sunday Ishola" \
    --reviewer "<independent scientific reviewer>" \
    --smoke-windows pass \
    --smoke-rstudio pass \
    --smoke-docker-ubuntu pass \
    --smoke-wsl-ubuntu pass \
    --note "Pre-pilot freeze for SBIR submission"
```

## Verify an existing freeze

```
python scripts/verify_scope_freeze.py --version v1.0
```

Exits non-zero on any drift; safe to chain into the smoke harness.

## Freeze lifecycle

| Stage | `status` | What it means |
| --- | --- | --- |
| Build | `draft` | Snapshot taken, hashes recorded, smokes not yet declared green |
| Sign | `frozen` | Operator named, scientific reviewer named, all four smoke environments declared `pass`, git-tagged `scope-frozen-<version>` |

A `draft` freeze must not be cited externally as the basis of a public
claim. Use the wording "pre-pilot draft" until the freeze is signed.
