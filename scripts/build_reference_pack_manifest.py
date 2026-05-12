#!/usr/bin/env python3
"""Summarize data/reference/* pack files for audit manifests (row counts, columns)."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd


def _default_project_root() -> Path:
    """Repository root when this file lives in <root>/scripts/."""
    return Path(__file__).resolve().parent.parent


EXPECTED_FILES = [
    "nist/srm1957/serum_pfas.csv",
    "nist/rm8446/methanol_pfas.csv",
    "nist/rm8690/afff_pfas.csv",
    "nist/manifest.json",
    "nist/hashes.txt",
    "registry/reference_registry.csv",
    "nist_srm1957_pfas_reference.csv",
    "nist_srm1957_pfas.csv",
    "nist_srm1957_pfas_noncertified.csv",
    "epa_1633a_method_metadata.csv",
    "epa_1633a_qc_limits.csv",
    "epa_1633a_qc_batch_schema.csv",
    "holding_times.csv",
    "pfas_matrix_registry.csv",
    "contamination_control_rules.csv",
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Build reference pack manifest JSON.")
    parser.add_argument(
        "--project-root",
        type=Path,
        default=None,
        help="Repository root (default: parent directory of scripts/)",
    )
    args = parser.parse_args()
    root = (args.project_root or _default_project_root()).resolve()
    ref_dir = root / "data" / "reference"
    out_path = root / "results" / "reference_pack_manifest.json"

    entries = []
    for name in EXPECTED_FILES:
        path = ref_dir / name
        if not path.is_file():
            entries.append({"file": name, "present": False})
            continue
        df = pd.read_csv(path, dtype=str)
        entries.append(
            {
                "file": name,
                "present": True,
                "rows": int(len(df)),
                "columns": [str(c) for c in df.columns.tolist()],
            }
        )

    manifest = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "reference_dir": str(ref_dir.resolve()),
        "disclaimer": (
            "Manifest describes bundled reference tables for app logic and benchmarking. "
            "Numeric QC limits in epa_1633a_qc_limits.csv are placeholders until loaded from a controlled Method 1633A PDF. "
            "epa_1633a_qc_batch_schema.csv is a LIMS-oriented row template (TEMPLATE_* ids) — replace with real batch data. "
            "NIST Table A2 concentrations are non-certified consensus values. "
            "RM 8446 / RM 8690 tables are separate matrices (methanol calibration vs AFFF foam) — do not merge with serum. "
            "reference_registry.csv records SHA-256 for curated files; run scripts/verify_reference_registry.py in CI or before release. "
            "This is not EPA certification, ISO 17025 accreditation, or wet-lab validation evidence."
        ),
        "files": entries,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(out_path.read_text(encoding="utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
