"""CLI for cohort-level summaries from V2 report CSV outputs."""
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
from .cohort import build_overview, summarize_v2_report, to_csv_bytes


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


def run_pipeline(*, input_report_csv: Path, output_dir: Path, repo_root: Path | None = None) -> dict[str, object]:
    root = repo_root or _repo_root()
    out_dir = output_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(input_report_csv)
    summary = summarize_v2_report(df)
    summary_csv = to_csv_bytes(summary.summary_df)

    input_hash = _sha256_file(input_report_csv)
    output_hash = _sha256_bytes(summary_csv)
    run_id = _sha256_bytes(
        (
            f"input={input_hash}|output={output_hash}|"
            f"code_version={__version__}|mode=v2_cohort_summary_v1"
        ).encode("utf-8")
    )[:16]

    csv_path = out_dir / f"v2_cohort_summary_{run_id}.csv"
    csv_path.write_bytes(summary_csv)

    manifest = {
        "run_id": run_id,
        "timestamp_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "code_version": __version__,
        "mode": "v2_cohort_summary_v1",
        "git_revision": _git_head(root),
        "input_report_csv_path": str(input_report_csv),
        "input_report_csv_sha256": input_hash,
        "input_report_csv_n_bytes": input_report_csv.stat().st_size,
        "output_summary_csv_path": str(csv_path),
        "output_summary_csv_sha256": output_hash,
        "output_summary_csv_n_bytes": len(summary_csv),
        "overview": build_overview(summary),
    }
    manifest_path = out_dir / f"v2_cohort_manifest_{run_id}.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        encoding="utf-8",
    )
    return {
        "run_id": run_id,
        "csv_path": str(csv_path),
        "manifest_path": str(manifest_path),
        "output_csv_sha256": output_hash,
        **manifest["overview"],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PFAS V2 cohort summary from report CSV")
    parser.add_argument("--input-report", required=True, type=Path, help="Path to v2_report_<run_id>.csv")
    parser.add_argument("--output-dir", required=True, type=Path, help="Directory for cohort summary CSV + manifest")
    args = parser.parse_args(argv)
    if not args.input_report.is_file():
        print(f"ERROR: input report not found: {args.input_report}", file=sys.stderr)
        return 2
    try:
        out = run_pipeline(input_report_csv=args.input_report, output_dir=args.output_dir)
    except Exception as exc:  # pragma: no cover
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
