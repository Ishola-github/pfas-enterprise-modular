#!/usr/bin/env python3
"""Verify reference_registry.csv: files exist and SHA-256 matches (stdlib only).

Modes:
  full (default) — every registry row must exist and match sha256.
  ci — only rows with ci_required=TRUE (for GitHub Actions / minimal checkout).

CI mode activates when --ci-mode is passed, or env CI=true / GITHUB_ACTIONS=true.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import subprocess
import sys
from pathlib import Path


def _default_project_root() -> Path:
    """Repository root when this file lives in <root>/scripts/."""
    return Path(__file__).resolve().parent.parent


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _sha256_git_head_blob(root: Path, rel: str) -> str | None:
    """SHA-256 of the committed git object at HEAD:rel, or None if unavailable."""
    try:
        blob = subprocess.check_output(
            ["git", "rev-parse", f"HEAD:{rel}"],
            cwd=root,
            stderr=subprocess.DEVNULL,
        ).decode().strip()
        data = subprocess.check_output(["git", "cat-file", "-p", blob], cwd=root)
        return hashlib.sha256(data).hexdigest()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def _read_registry_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    text = path.read_text(encoding="utf-8-sig")
    lines = text.splitlines()
    if not lines:
        return [], []
    reader = csv.DictReader(lines)
    fieldnames = reader.fieldnames or []
    rows = [dict(r) for r in reader]
    return list(fieldnames), rows


def _ci_mode_requested(args: argparse.Namespace) -> bool:
    if args.ci_mode:
        return True
    if args.full:
        return False
    ci = os.getenv("CI", "").strip().lower()
    if ci in ("1", "true", "yes"):
        return True
    if os.getenv("GITHUB_ACTIONS", "").strip().lower() == "true":
        return True
    return False


def _row_ci_required(row: dict[str, str]) -> bool:
    return (row.get("ci_required") or "").strip().upper() == "TRUE"


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify reference registry paths and hashes.")
    parser.add_argument(
        "--project-root",
        type=Path,
        default=None,
        help="Repository root (default: parent directory of scripts/)",
    )
    parser.add_argument(
        "--registry",
        type=Path,
        default=None,
        help="Default: <project-root>/data/reference/registry/reference_registry.csv",
    )
    parser.add_argument(
        "--ci-mode",
        action="store_true",
        help="Verify only rows with ci_required=TRUE",
    )
    parser.add_argument(
        "--full",
        action="store_true",
        help="Verify all rows (overrides CI env auto-detection)",
    )
    args = parser.parse_args()
    root = (args.project_root or _default_project_root()).resolve()
    reg_path = args.registry or (root / "data" / "reference" / "registry" / "reference_registry.csv")
    if not reg_path.is_file():
        print(f"ERROR: registry not found: {reg_path}", file=sys.stderr)
        return 2

    columns, rows = _read_registry_rows(reg_path)
    required = [
        "source_org",
        "document_type",
        "document_id",
        "local_path",
        "sha256",
    ]
    missing_cols = [c for c in required if c not in columns]
    if missing_cols:
        print(f"ERROR: registry missing columns: {missing_cols}", file=sys.stderr)
        return 3

    ci_mode = _ci_mode_requested(args)
    if ci_mode:
        if "ci_required" not in columns:
            print(
                "ERROR: ci_mode requires ci_required column in reference_registry.csv",
                file=sys.stderr,
            )
            return 5
        rows = [r for r in rows if _row_ci_required(r)]
        if not rows:
            print("ERROR: ci_mode selected but no ci_required=TRUE rows", file=sys.stderr)
            return 6

    errors: list[str] = []
    for i, row in enumerate(rows):
        line_no = i + 2  # 1-based; row 1 is header
        rel = (row.get("local_path") or "").strip()
        expect = (row.get("sha256") or "").strip().lower()
        doc = (row.get("document_id") or "").strip()
        if not rel:
            errors.append(f"row {line_no}: empty local_path for {doc!r}")
            continue
        path = (root / rel).resolve()
        if not path.is_file():
            errors.append(f"row {line_no}: missing file {doc!r} -> {path}")
            continue
        got_worktree = _sha256_file(path)
        got_git = _sha256_git_head_blob(root, rel) if ci_mode else None
        got = got_git if got_git is not None else got_worktree
        if expect and got.lower() != expect:
            detail = f"row {line_no}: sha256 mismatch {doc!r}\n  expected: {expect}\n  actual:   {got}"
            if got_git is not None and got_worktree.lower() != got_git.lower():
                detail += f"\n  worktree: {got_worktree}\n  git HEAD: {got_git}"
            errors.append(detail)

    mode_label = "ci" if ci_mode else "full"
    if errors:
        print(f"VERIFY FAILED ({mode_label}):\n", file=sys.stderr)
        for e in errors:
            print(e, file=sys.stderr)
        return 4

    print(
        f"OK ({mode_label}): {len(rows)} registry row(s) - paths exist and hashes match."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
