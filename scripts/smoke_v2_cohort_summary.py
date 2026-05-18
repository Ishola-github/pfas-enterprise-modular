"""Smoke test for V2 cohort summary CLI."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    out_dir = root / "data" / "v2" / "outputs" / "smoke_cohort"
    out_dir.mkdir(parents=True, exist_ok=True)

    # First produce a deterministic V2 report fixture.
    v2 = subprocess.run(
        [
            sys.executable,
            "-m",
            "src.v2.cli",
            "--input",
            str(root / "data" / "v1" / "fixtures" / "nhanes_j_governed_v1_input.csv"),
            "--output-dir",
            str(out_dir),
        ],
        cwd=str(root),
        capture_output=True,
        text=True,
        check=False,
    )
    if v2.returncode != 0:
        print(v2.stdout)
        print(v2.stderr, file=sys.stderr)
        raise SystemExit(v2.returncode)
    v2_summary = json.loads(v2.stdout)

    cohort = subprocess.run(
        [
            sys.executable,
            "-m",
            "src.v2.cohort_cli",
            "--input-report",
            str(v2_summary["csv_path"]),
            "--output-dir",
            str(out_dir),
        ],
        cwd=str(root),
        capture_output=True,
        text=True,
        check=False,
    )
    if cohort.returncode != 0:
        print(cohort.stdout)
        print(cohort.stderr, file=sys.stderr)
        raise SystemExit(cohort.returncode)
    cs = json.loads(cohort.stdout)
    print(
        json.dumps(
            {
                "cohort_run_id": cs["run_id"],
                "output_csv_sha256": cs["output_csv_sha256"],
                "n_rows_input_report": cs["n_rows_input_report"],
                "n_rows_in_domain": cs["n_rows_in_domain"],
                "n_groups": cs["n_groups"],
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
