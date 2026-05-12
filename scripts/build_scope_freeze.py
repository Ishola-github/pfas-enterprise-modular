"""Build a reproducible scope-freeze artifact.

Usage:
    python scripts/build_scope_freeze.py --version v1.0
    python scripts/build_scope_freeze.py --version v1.0 --status frozen \
        --operator "Sunday Ishola" --reviewer "Pending"

The artifact lives at ``validation/scope_freeze/<version>/`` and contains:

- ``SCOPE_AND_INTENDED_USE.snapshot.md`` — byte-identical copy of the
  live scope document at freeze time. The snapshot's SHA-256 is recorded
  in ``freeze_manifest.json`` and can be re-verified at any time with
  ``scripts/verify_scope_freeze.py``.
- ``freeze_manifest.json`` — hashes of governance-critical files
  (scope doc, SOP CSV, reference registry CSV, UCMR limits CSV, each AD
  model JSON), plus lane inventory, AD methods, smoke-suite status,
  and freeze metadata (operator, reviewer, status, timestamp, git SHA).
- ``README.md`` and ``CHANGELOG.md`` are written on first freeze and
  hand-maintained thereafter — this script does not overwrite them.

Design notes
------------

* The script is **idempotent**: re-running with the same inputs writes
  the same bytes (no embedded timestamps inside the snapshot; the
  freeze build time is in the manifest only).
* ``--status draft`` and ``--status frozen`` are the only allowed
  status values. ``frozen`` requires the operator name to be present.
* The script never modifies the live ``SCOPE_AND_INTENDED_USE.md``.
* Smoke-suite status is **declared** by the operator via flags
  (``--smoke-windows pass``, etc.); the script does not run the smokes
  itself. Truthfulness of those flags is the operator's responsibility.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional


REPO_ROOT = Path(__file__).resolve().parent.parent
SCOPE_DOC = REPO_ROOT / "SCOPE_AND_INTENDED_USE.md"
SOP_CSV = REPO_ROOT / "data" / "config" / "matrix_pipeline_sop.csv"
REGISTRY_CSV = REPO_ROOT / "data" / "reference" / "registry" / "reference_registry.csv"
UCMR_LIMITS_CSV = REPO_ROOT / "data" / "config" / "ucmr_analyte_limits_ngl.csv"
AD_MODELS_DIR = REPO_ROOT / "data" / "ad_models"
AD_MODELS_INDEX = AD_MODELS_DIR / "index.json"
FREEZE_ROOT = REPO_ROOT / "validation" / "scope_freeze"


VALID_STATUSES = {"draft", "frozen"}
VALID_SMOKE = {"pass", "fail", "skipped", "pending"}


def sha256_file(path: Path) -> str:
    """Return the hex SHA-256 of ``path``, reading in 1 MiB chunks."""
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def count_csv_rows(path: Path) -> int:
    """Return the data-row count (header excluded) of a CSV file."""
    with path.open("r", encoding="utf-8", newline="") as fh:
        return max(0, sum(1 for _ in fh) - 1)


def git_head_sha() -> Optional[str]:
    """Return the current git HEAD SHA, or ``None`` if git is unavailable."""
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=str(REPO_ROOT),
            stderr=subprocess.DEVNULL,
        )
        return out.decode("utf-8").strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def collect_ad_models() -> List[Dict[str, object]]:
    """Enumerate per-lane AD models and report hash + method.

    The returned list is sorted by lane name for deterministic output.
    """
    if not AD_MODELS_DIR.is_dir():
        return []
    entries: List[Dict[str, object]] = []
    for lane_dir in sorted(p for p in AD_MODELS_DIR.iterdir() if p.is_dir()):
        model_path = lane_dir / "ad_model.json"
        if not model_path.is_file():
            continue
        try:
            model = json.loads(model_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            model = {}
        entries.append(
            {
                "lane": lane_dir.name,
                "path": str(model_path.relative_to(REPO_ROOT)).replace("\\", "/"),
                "ad_method": model.get("ad_method"),
                "sha256": sha256_file(model_path),
            }
        )
    return entries


def parse_sop_lanes() -> List[Dict[str, str]]:
    """Parse the SOP CSV and return ``[{matrix, datasets, pipeline_id}, ...]``."""
    import csv

    if not SOP_CSV.is_file():
        return []
    rows: List[Dict[str, str]] = []
    with SOP_CSV.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            rows.append(
                {
                    "matrix": (row.get("matrix") or "").strip(),
                    "canonical_datasets": (row.get("canonical_datasets") or "").strip(),
                    "pipeline_id": (row.get("pipeline_id") or "").strip(),
                }
            )
    return rows


def build_manifest(
    version: str,
    status: str,
    operator: Optional[str],
    reviewer: Optional[str],
    regulatory_liaison: Optional[str],
    note: Optional[str],
    smoke_status: Dict[str, str],
) -> Dict[str, object]:
    """Construct the freeze manifest dictionary."""
    sop_lanes = parse_sop_lanes()
    ad_models = collect_ad_models()

    manifest: Dict[str, object] = {
        "schema": "scope_freeze_manifest/v1",
        "freeze_version": version,
        "status": status,
        "built_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "git_head_sha": git_head_sha(),
        "operator": operator,
        "scientific_reviewer": reviewer,
        "regulatory_liaison": regulatory_liaison,
        "note": note,
        "files": {
            "scope_document": {
                "path": str(SCOPE_DOC.relative_to(REPO_ROOT)).replace("\\", "/"),
                "sha256": sha256_file(SCOPE_DOC),
                "bytes": SCOPE_DOC.stat().st_size,
            },
            "matrix_pipeline_sop_csv": {
                "path": str(SOP_CSV.relative_to(REPO_ROOT)).replace("\\", "/"),
                "sha256": sha256_file(SOP_CSV),
                "rows": count_csv_rows(SOP_CSV),
            },
            "reference_registry_csv": {
                "path": str(REGISTRY_CSV.relative_to(REPO_ROOT)).replace("\\", "/"),
                "sha256": sha256_file(REGISTRY_CSV),
                "rows": count_csv_rows(REGISTRY_CSV),
            },
            "ucmr_analyte_limits_csv": {
                "path": str(UCMR_LIMITS_CSV.relative_to(REPO_ROOT)).replace("\\", "/"),
                "sha256": sha256_file(UCMR_LIMITS_CSV),
                "rows": count_csv_rows(UCMR_LIMITS_CSV),
            },
        },
        "supported_matrix_lanes": sop_lanes,
        "ad_models": ad_models,
        "smoke_status": smoke_status,
        "scope_doc_sections": {
            "count": 17,
            "list": [
                "1. System Purpose",
                "2. Supported Matrices",
                "3. Supported Analytical Contexts",
                "4. Unsupported Use Cases",
                "5. Screening vs Confirmatory Separation",
                "6. Matrix Isolation Requirements",
                "7. Applicability Domain (AD) Policy",
                "8. Governance and Provenance",
                "9. External Validation Status",
                "10. Regulatory and Accreditation Limitations",
                "11. Human Review Requirements",
                "12. Data Source Lineage",
                "13. Threshold Governance",
                "14. Environmental vs Physiological Separation",
                "15. Air / Biosolids Metadata Limitation Statements",
                "16. SaaS Operational Limitations",
                "17. Future Validation Roadmap",
            ],
        },
    }

    if AD_MODELS_INDEX.is_file():
        manifest["ad_models_index_sha256"] = sha256_file(AD_MODELS_INDEX)

    return manifest


def parse_smoke_flags(args: argparse.Namespace) -> Dict[str, str]:
    """Translate ``--smoke-*`` CLI flags into a smoke_status dictionary."""
    out: Dict[str, str] = {}
    for env in ("windows", "rstudio", "docker_ubuntu", "wsl_ubuntu"):
        value = getattr(args, f"smoke_{env}", "pending") or "pending"
        value = value.lower()
        if value not in VALID_SMOKE:
            raise SystemExit(
                f"--smoke-{env.replace('_', '-')}: must be one of {sorted(VALID_SMOKE)}"
            )
        out[env] = value
    return out


def ensure_static_files(target_dir: Path, version: str) -> None:
    """Create README/CHANGELOG only if they do not already exist."""
    readme = target_dir / "README.md"
    if not readme.exists():
        readme.write_text(
            (
                f"# Scope Freeze {version}\n\n"
                "This directory is a hash-pinned snapshot of "
                "[`../../SCOPE_AND_INTENDED_USE.md`](../../../SCOPE_AND_INTENDED_USE.md) "
                "as of the freeze build time recorded in "
                "[`freeze_manifest.json`](freeze_manifest.json).\n\n"
                "## Files\n\n"
                "- `SCOPE_AND_INTENDED_USE.snapshot.md` — byte-identical "
                "snapshot of the live scope document at freeze time.\n"
                "- `freeze_manifest.json` — machine-readable manifest "
                "with SHA-256 of every governance-critical file, lane "
                "inventory, AD methods, smoke status, and signature "
                "metadata.\n"
                "- `CHANGELOG.md` — append-only log of why this freeze "
                "was issued.\n\n"
                "## Rebuild this freeze\n\n"
                "```\n"
                f"python scripts/build_scope_freeze.py --version {version}\n"
                "```\n\n"
                "## Verify this freeze against the live repository\n\n"
                "```\n"
                f"python scripts/verify_scope_freeze.py --version {version}\n"
                "```\n\n"
                "`verify_scope_freeze.py` re-hashes the live files and "
                "compares to the recorded SHA-256s in `freeze_manifest.json`. "
                "Any drift is reported and the script exits non-zero, so "
                "this check belongs in the regression suite alongside "
                "`verify_reference_registry.py`.\n\n"
                "## What completes the freeze\n\n"
                "A freeze is **final** when:\n\n"
                "1. `status` in `freeze_manifest.json` is `frozen` (not `draft`).\n"
                "2. All four `smoke_status` entries are `pass`.\n"
                "3. `operator` is populated; `scientific_reviewer` is populated\n"
                "   and is independent of the platform builder.\n"
                "4. A git tag `scope-frozen-{version}` exists at the commit\n"
                "   whose SHA is recorded in `git_head_sha`.\n\n"
                "Until all four conditions hold, any external claim derived\n"
                "from this snapshot must include the word *draft*.\n"
            ).replace("{version}", version),
            encoding="utf-8",
        )

    changelog = target_dir / "CHANGELOG.md"
    if not changelog.exists():
        changelog.write_text(
            (
                f"# Scope Freeze {version} — Change Log\n\n"
                "| Build time (UTC) | Status | Operator | Note |\n"
                "| --- | --- | --- | --- |\n"
                "| _(first build will append here)_ | | | |\n\n"
                "Append-only. Do not edit historical rows.\n"
            ),
            encoding="utf-8",
        )


def append_changelog(target_dir: Path, manifest: Dict[str, object]) -> None:
    """Append a single row to ``CHANGELOG.md`` recording this build."""
    changelog = target_dir / "CHANGELOG.md"
    line = "| {built_at_utc} | {status} | {operator} | {note} |\n".format(
        built_at_utc=manifest["built_at_utc"],
        status=manifest["status"],
        operator=manifest.get("operator") or "_(unset)_",
        note=manifest.get("note") or "",
    )
    with changelog.open("a", encoding="utf-8") as fh:
        fh.write(line)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", required=True, help="Freeze version, e.g. v1.0")
    parser.add_argument(
        "--status",
        default="draft",
        choices=sorted(VALID_STATUSES),
        help="draft (default) or frozen. 'frozen' requires --operator.",
    )
    parser.add_argument("--operator", default=None)
    parser.add_argument("--reviewer", default=None)
    parser.add_argument("--regulatory-liaison", default=None)
    parser.add_argument("--note", default=None)
    parser.add_argument("--smoke-windows", default="pending")
    parser.add_argument("--smoke-rstudio", default="pending")
    parser.add_argument("--smoke-docker-ubuntu", default="pending")
    parser.add_argument("--smoke-wsl-ubuntu", default="pending")

    args = parser.parse_args(argv)

    if not SCOPE_DOC.is_file():
        print(f"ERROR: scope document not found at {SCOPE_DOC}", file=sys.stderr)
        return 2

    if args.status == "frozen" and not args.operator:
        print(
            "ERROR: --status frozen requires --operator to be supplied.",
            file=sys.stderr,
        )
        return 2

    smoke_status = parse_smoke_flags(args)

    target_dir = FREEZE_ROOT / args.version
    target_dir.mkdir(parents=True, exist_ok=True)

    snapshot_path = target_dir / "SCOPE_AND_INTENDED_USE.snapshot.md"
    shutil.copyfile(SCOPE_DOC, snapshot_path)

    manifest = build_manifest(
        version=args.version,
        status=args.status,
        operator=args.operator,
        reviewer=args.reviewer,
        regulatory_liaison=args.regulatory_liaison,
        note=args.note,
        smoke_status=smoke_status,
    )

    snapshot_hash = sha256_file(snapshot_path)
    if snapshot_hash != manifest["files"]["scope_document"]["sha256"]:
        print(
            "ERROR: snapshot SHA-256 disagrees with live document. "
            "Refusing to write an inconsistent manifest.",
            file=sys.stderr,
        )
        return 3

    manifest_path = target_dir / "freeze_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )

    ensure_static_files(target_dir, args.version)
    append_changelog(target_dir, manifest)

    rel = os.path.relpath(target_dir, REPO_ROOT).replace("\\", "/")
    print(f"OK  scope-freeze artifact written to {rel}/")
    print(f"OK  scope doc SHA-256 = {snapshot_hash}")
    print(f"OK  status = {args.status}")
    if args.status == "draft":
        print(
            "INFO  status=draft: complete the freeze by re-running with "
            "--status frozen --operator <name> and verified smoke flags."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
