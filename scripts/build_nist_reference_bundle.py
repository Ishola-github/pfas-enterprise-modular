#!/usr/bin/env python3
"""Write data/reference/nist/hashes.txt and manifest.json for all bundled NIST CSVs."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _default_project_root() -> Path:
    return Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(description="Build NIST reference bundle manifest + hashes.")
    parser.add_argument(
        "--project-root",
        type=Path,
        default=None,
        help="Repository root (default: parent of scripts/)",
    )
    args = parser.parse_args()
    root = (args.project_root or _default_project_root()).resolve()
    nist_dir = root / "data" / "reference" / "nist"
    if not nist_dir.is_dir():
        print(f"ERROR: {nist_dir} not found", flush=True)
        return 2

    csv_paths = sorted(nist_dir.rglob("*.csv"))
    lines = []
    files_meta = []
    for p in csv_paths:
        rel = p.relative_to(root).as_posix()
        hx = _sha256_file(p)
        lines.append(f"{rel}\t{hx}")
        try:
            nlines = sum(1 for _ in p.open("rb")) - 1
        except OSError:
            nlines = -1
        files_meta.append({"path": rel, "sha256": hx, "data_rows_estimate": max(0, nlines)})

    (nist_dir / "hashes.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    manifest = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "nist_root": nist_dir.as_posix(),
        "disclaimer": (
            "Bundled extracts for software benchmarking; not ISO 17025 evidence. "
            "Matrices (serum / methanol / AFFF) must stay separate. "
            "Pin official NIST PDFs into sibling folders when permitted; update source_pdf in CSVs when you do."
        ),
        "files": files_meta,
    }
    (nist_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print((nist_dir / "manifest.json").read_text(encoding="utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
