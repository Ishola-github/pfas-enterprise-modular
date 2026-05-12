#!/usr/bin/env python3
"""
PFAS Enterprise / Shiny entrypoint: absorbs CLI flags the dashboard passes through and runs the
NHANES serum high-burden model (`train_nhanes_serum_pfas.py`), which writes metrics under `results/`
or, when the dashboard sets `PFAS_TRAIN_RESULTS_SUBDIR=screening`, under `results/screening/`.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERUM = ROOT / "scripts" / "train_nhanes_serum_pfas.py"


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--strict", action="store_true", help="Accepted for UI parity; serum trainer ignores.")
    ap.add_argument("-v", "--verbose", action="store_true", help="Accepted for UI parity.")
    ap.add_argument("--min-recall-positive", type=float, default=None, help="Reserved; not enforced here.")
    ap.add_argument("--holdout-threshold", type=float, default=None)
    args, forwarded = ap.parse_known_args()

    cmd = [sys.executable, str(SERUM)]
    cmd.extend(forwarded)

    if args.holdout_threshold is not None and "--holdout-threshold" not in forwarded:
        cmd.extend(["--holdout-threshold", str(args.holdout_threshold)])

    return int(subprocess.call(cmd, cwd=str(ROOT)))


if __name__ == "__main__":
    raise SystemExit(main())
