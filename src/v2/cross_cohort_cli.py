"""CLI for manifest-backed cross-cohort comparison tables."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

from . import __version__
from .cross_cohort import build_overview, compare_cohort_summaries, to_csv_bytes


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def _sha256_file(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _git_head(repo_root: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(repo_root),
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    out = result.stdout.strip()
    return out if out else None


def run_pipeline(
    *,
    left_summary_csv: Path,
    right_summary_csv: Path,
    output_dir: Path,
    left_label: str = "left",
    right_label: str = "right",
    repo_root: Path | None = None,
) -> dict[str, object]:
    root = repo_root or _repo_root()
    out_dir = output_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    left_df = pd.read_csv(left_summary_csv)
    right_df = pd.read_csv(right_summary_csv)
    result = compare_cohort_summaries(left_df, right_df)
    out_csv = to_csv_bytes(result.comparison_df)

    left_hash = _sha256_file(left_summary_csv)
    right_hash = _sha256_file(right_summary_csv)
    out_hash = _sha256_bytes(out_csv)
    run_id = _sha256_bytes(
        (
            f"left={left_hash}|right={right_hash}|"
            f"code_version={__version__}|mode=v2_cross_cohort_compare_v1|"
            f"left_label={left_label}|right_label={right_label}"
        ).encode("utf-8")
    )[:16]

    csv_path = out_dir / f"v2_cross_cohort_comparison_{run_id}.csv"
    csv_path.write_bytes(out_csv)

    manifest = {
        "run_id": run_id,
        "timestamp_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "code_version": __version__,
        "mode": "v2_cross_cohort_compare_v1",
        "git_revision": _git_head(root),
        "left_label": left_label,
        "right_label": right_label,
        "left_summary_csv_path": str(left_summary_csv),
        "left_summary_csv_sha256": left_hash,
        "left_summary_csv_n_bytes": left_summary_csv.stat().st_size,
        "right_summary_csv_path": str(right_summary_csv),
        "right_summary_csv_sha256": right_hash,
        "right_summary_csv_n_bytes": right_summary_csv.stat().st_size,
        "output_csv_path": str(csv_path),
        "output_csv_sha256": out_hash,
        "output_csv_n_bytes": len(out_csv),
        "overview": build_overview(result),
    }
    manifest_path = out_dir / f"v2_cross_cohort_manifest_{run_id}.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        encoding="utf-8",
    )
    return {
        "run_id": run_id,
        "csv_path": str(csv_path),
        "manifest_path": str(manifest_path),
        "output_csv_sha256": out_hash,
        **manifest["overview"],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PFAS V2 cross-cohort comparator")
    parser.add_argument("--left-summary", required=True, type=Path, help="Path to left cohort summary CSV")
    parser.add_argument("--right-summary", required=True, type=Path, help="Path to right cohort summary CSV")
    parser.add_argument("--output-dir", required=True, type=Path, help="Directory for comparison CSV and manifest")
    parser.add_argument("--left-label", default="left", type=str, help="Display label for left cohort")
    parser.add_argument("--right-label", default="right", type=str, help="Display label for right cohort")
    args = parser.parse_args(argv)
    if not args.left_summary.is_file():
        print(f"ERROR: left summary not found: {args.left_summary}", file=sys.stderr)
        return 2
    if not args.right_summary.is_file():
        print(f"ERROR: right summary not found: {args.right_summary}", file=sys.stderr)
        return 2
    try:
        out = run_pipeline(
            left_summary_csv=args.left_summary,
            right_summary_csv=args.right_summary,
            output_dir=args.output_dir,
            left_label=args.left_label,
            right_label=args.right_label,
        )
    except Exception as exc:  # pragma: no cover
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
