"""Smoke test for V2 cross-cohort comparator CLI stub."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def _run(cmd: list[str], cwd: Path) -> dict:
    proc = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        print(proc.stdout)
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(proc.returncode)
    return json.loads(proc.stdout)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    out = root / "data" / "v2" / "outputs" / "smoke_cross_cohort"
    out.mkdir(parents=True, exist_ok=True)

    # Build two governed cohort summaries from the same fixture for comparator smoke.
    v2 = _run(
        [
            sys.executable,
            "-m",
            "src.v2.cli",
            "--input",
            str(root / "data" / "v1" / "fixtures" / "nhanes_j_governed_v1_input.csv"),
            "--output-dir",
            str(out / "v2"),
        ],
        root,
    )
    c1 = _run(
        [
            sys.executable,
            "-m",
            "src.v2.cohort_cli",
            "--input-report",
            str(v2["csv_path"]),
            "--output-dir",
            str(out / "cohort_left"),
        ],
        root,
    )
    c2 = _run(
        [
            sys.executable,
            "-m",
            "src.v2.cohort_cli",
            "--input-report",
            str(v2["csv_path"]),
            "--output-dir",
            str(out / "cohort_right"),
        ],
        root,
    )
    cmp_out = _run(
        [
            sys.executable,
            "-m",
            "src.v2.cross_cohort_cli",
            "--left-summary",
            str(c1["csv_path"]),
            "--right-summary",
            str(c2["csv_path"]),
            "--left-label",
            "NHANES",
            "--right-label",
            "NHANES_clone",
            "--output-dir",
            str(out / "comparison"),
        ],
        root,
    )
    print(
        json.dumps(
            {
                "run_id": cmp_out["run_id"],
                "output_csv_sha256": cmp_out["output_csv_sha256"],
                "n_rows_out": cmp_out["n_rows_out"],
                "n_matched_rows": cmp_out["n_matched_rows"],
                "n_left_only_rows": cmp_out["n_left_only_rows"],
                "n_right_only_rows": cmp_out["n_right_only_rows"],
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
