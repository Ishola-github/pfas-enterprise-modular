#!/usr/bin/env python3
"""Verify reference_registry.csv: files exist and SHA-256 matches (stdlib only)."""

from __future__ import annotations

import argparse
import csv
import hashlib
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


def _read_registry_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    text = path.read_text(encoding="utf-8-sig")
    lines = text.splitlines()
    if not lines:
        return [], []
    reader = csv.DictReader(lines)
    fieldnames = reader.fieldnames or []
    rows = [dict(r) for r in reader]
    return list(fieldnames), rows


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
        got = _sha256_file(path)
        if expect and got.lower() != expect:
            errors.append(
                f"row {line_no}: sha256 mismatch {doc!r}\n  expected: {expect}\n  actual:   {got}"
            )

    if errors:
        print("VERIFY FAILED:\n", file=sys.stderr)
        for e in errors:
            print(e, file=sys.stderr)
        return 4

    print(f"OK: {len(rows)} registry row(s) - paths exist and hashes match.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
