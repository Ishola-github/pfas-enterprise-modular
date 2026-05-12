"""Verify a scope-freeze artifact against the live repository.

Re-hashes every file referenced by
``validation/scope_freeze/<version>/freeze_manifest.json`` and reports
drift. Exits non-zero on any mismatch so the script is safe to chain
into a regression smoke (e.g. ``scripts/docker_verify_linux.sh``).

Usage:
    python scripts/verify_scope_freeze.py --version v1.0

Exit codes:
    0  all hashes match, lane list intact, AD methods intact
    1  drift detected (any hash, row count, or method mismatch)
    2  manifest missing or unreadable
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


REPO_ROOT = Path(__file__).resolve().parent.parent
FREEZE_ROOT = REPO_ROOT / "validation" / "scope_freeze"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def count_csv_rows(path: Path) -> int:
    with path.open("r", encoding="utf-8", newline="") as fh:
        return max(0, sum(1 for _ in fh) - 1)


def check_file(label: str, entry: Dict[str, object]) -> Tuple[bool, str]:
    """Re-hash one file and compare to the manifest record."""
    rel_path = str(entry.get("path") or "")
    if not rel_path:
        return False, f"{label}: manifest entry missing 'path'"
    full = REPO_ROOT / rel_path
    if not full.is_file():
        return False, f"{label}: live file missing at {rel_path}"

    expected_hash = entry.get("sha256")
    actual_hash = sha256_file(full)
    if actual_hash != expected_hash:
        return False, (
            f"{label}: SHA-256 drift\n"
            f"        expected {expected_hash}\n"
            f"        actual   {actual_hash}\n"
            f"        path     {rel_path}"
        )

    expected_bytes = entry.get("bytes")
    if expected_bytes is not None and full.stat().st_size != int(expected_bytes):
        return False, (
            f"{label}: byte length drift "
            f"(manifest={expected_bytes}, live={full.stat().st_size})"
        )

    expected_rows = entry.get("rows")
    if expected_rows is not None:
        actual_rows = count_csv_rows(full)
        if actual_rows != int(expected_rows):
            return False, (
                f"{label}: row-count drift "
                f"(manifest={expected_rows}, live={actual_rows})"
            )

    return True, f"{label}: OK"


def check_ad_models(records: List[Dict[str, object]]) -> List[Tuple[bool, str]]:
    """Re-hash each AD model JSON listed in the manifest."""
    results: List[Tuple[bool, str]] = []
    for rec in records or []:
        lane = rec.get("lane") or "?"
        rel_path = str(rec.get("path") or "")
        if not rel_path:
            results.append((False, f"ad_model[{lane}]: manifest record missing 'path'"))
            continue
        full = REPO_ROOT / rel_path
        if not full.is_file():
            results.append((False, f"ad_model[{lane}]: missing at {rel_path}"))
            continue
        actual_hash = sha256_file(full)
        if actual_hash != rec.get("sha256"):
            results.append(
                (
                    False,
                    (
                        f"ad_model[{lane}]: SHA-256 drift\n"
                        f"        expected {rec.get('sha256')}\n"
                        f"        actual   {actual_hash}"
                    ),
                )
            )
            continue
        try:
            model = json.loads(full.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            results.append((False, f"ad_model[{lane}]: cannot parse JSON ({exc})"))
            continue
        if model.get("ad_method") != rec.get("ad_method"):
            results.append(
                (
                    False,
                    (
                        f"ad_model[{lane}]: ad_method drift "
                        f"(manifest={rec.get('ad_method')}, live={model.get('ad_method')})"
                    ),
                )
            )
            continue
        results.append((True, f"ad_model[{lane}]: OK ({rec.get('ad_method')})"))
    return results


def check_snapshot(target_dir: Path, manifest: Dict[str, object]) -> Tuple[bool, str]:
    """Verify the snapshot copy still matches the manifest's scope-doc hash."""
    snapshot = target_dir / "SCOPE_AND_INTENDED_USE.snapshot.md"
    if not snapshot.is_file():
        return False, "snapshot: SCOPE_AND_INTENDED_USE.snapshot.md missing"
    expected = manifest.get("files", {}).get("scope_document", {}).get("sha256")
    actual = sha256_file(snapshot)
    if actual != expected:
        return False, (
            "snapshot: SHA-256 disagrees with manifest.files.scope_document.sha256\n"
            f"        manifest expected {expected}\n"
            f"        snapshot actual   {actual}"
        )
    return True, "snapshot: OK (matches live scope document hash)"


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", required=True, help="Freeze version, e.g. v1.0")
    args = parser.parse_args(argv)

    target_dir = FREEZE_ROOT / args.version
    manifest_path = target_dir / "freeze_manifest.json"
    if not manifest_path.is_file():
        print(f"ERROR: freeze manifest not found at {manifest_path}", file=sys.stderr)
        return 2

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: cannot read manifest: {exc}", file=sys.stderr)
        return 2

    print(f"=== Verifying scope freeze {args.version} ===")
    print(f"  manifest        : {manifest_path.relative_to(REPO_ROOT)}")
    print(f"  freeze status   : {manifest.get('status')}")
    print(f"  git_head_sha    : {manifest.get('git_head_sha')}")
    print(f"  built_at_utc    : {manifest.get('built_at_utc')}")
    print()

    results: List[Tuple[bool, str]] = []

    files_block = manifest.get("files") or {}
    for key, entry in files_block.items():
        results.append(check_file(f"file[{key}]", entry))

    results.extend(check_ad_models(manifest.get("ad_models") or []))
    results.append(check_snapshot(target_dir, manifest))

    print("-- per-check results --")
    failures = 0
    for ok, msg in results:
        marker = "PASS" if ok else "FAIL"
        print(f"  {marker}  {msg}")
        if not ok:
            failures += 1
    print()

    smoke_status = manifest.get("smoke_status") or {}
    if smoke_status:
        print("-- smoke status declared in manifest --")
        for env, status in smoke_status.items():
            print(f"  {status:8s}  {env}")
        print()

    total = len(results)
    print(f"Overall: {total - failures}/{total} checks PASS, {failures} FAIL")
    if failures:
        print(
            "scope-freeze verification FAILED. Treat any external claim "
            "derived from this freeze as invalid until drift is investigated."
        )
        return 1
    print("scope-freeze verification OK.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
