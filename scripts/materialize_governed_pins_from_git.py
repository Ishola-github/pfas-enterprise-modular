#!/usr/bin/env python3
"""Rewrite ci_required registry files from git HEAD blobs (exact bytes).

Used in GitHub Actions after checkout so working-tree hashes match committed
objects and reference_registry pins (avoids CRLF / smudge drift on runners).
"""

from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path


def _project_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _ci_required_paths(registry: Path) -> list[str]:
    text = registry.read_text(encoding="utf-8-sig")
    reader = csv.DictReader(text.splitlines())
    paths: list[str] = []
    for row in reader:
        if (row.get("ci_required") or "").strip().upper() != "TRUE":
            continue
        rel = (row.get("local_path") or "").strip()
        if rel:
            paths.append(rel)
    return paths


def main() -> int:
    root = _project_root()
    registry = root / "data" / "reference" / "registry" / "reference_registry.csv"
    if not registry.is_file():
        print(f"ERROR: registry not found: {registry}", file=sys.stderr)
        return 2

    paths = _ci_required_paths(registry)
    if not paths:
        print("ERROR: no ci_required paths in registry", file=sys.stderr)
        return 3

    for rel in paths:
        dest = root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            blob = subprocess.check_output(
                ["git", "rev-parse", f"HEAD:{rel}"],
                cwd=root,
                stderr=subprocess.STDOUT,
            ).decode().strip()
            data = subprocess.check_output(["git", "cat-file", "-p", blob], cwd=root)
        except subprocess.CalledProcessError as exc:
            print(f"ERROR: cannot read HEAD:{rel}\n{exc.output.decode()}", file=sys.stderr)
            return 4
        dest.write_bytes(data)
        print(f"materialized {rel} ({len(data)} bytes)")

    print(f"OK: materialized {len(paths)} governed pin(s) from git HEAD")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
