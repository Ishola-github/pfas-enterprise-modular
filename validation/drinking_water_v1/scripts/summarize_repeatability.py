#!/usr/bin/env python3
"""Summarize 3-run repeatability from metrics JSON files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import mean


METRIC_KEYS = ("recall", "precision", "specificity", "npv", "false_positive_rate_negative")

ISO_METRIC_ALIASES = {
    "recall": "recall_positive",
    "precision": "precision_positive",
    "specificity": "specificity",
    "npv": "npv",
    "false_positive_rate_negative": "false_positive_rate_negative",
}


def read_metrics(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object in {path}")
    return data


def pull_metric(payload: dict, key: str):
    if key in payload and payload.get(key) is not None:
        return payload.get(key)
    iso = payload.get("iso_holdout_metrics")
    if isinstance(iso, dict):
        alias = ISO_METRIC_ALIASES.get(key)
        if alias and iso.get(alias) is not None:
            return iso.get(alias)
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize repeatability metrics across 3 runs.")
    parser.add_argument("--run1", type=Path, required=True, help="metrics JSON for run 1")
    parser.add_argument("--run2", type=Path, required=True, help="metrics JSON for run 2")
    parser.add_argument("--run3", type=Path, required=True, help="metrics JSON for run 3")
    parser.add_argument("--out", type=Path, required=True, help="output markdown path")
    parser.add_argument("--tolerance", type=float, default=1e-9, help="absolute tolerance for exact-match flag")
    args = parser.parse_args()

    runs = [args.run1, args.run2, args.run3]
    payloads = [read_metrics(p) for p in runs]

    rows = []
    for k in METRIC_KEYS:
        vals = []
        for p in payloads:
            v = pull_metric(p, k)
            if v is None:
                vals.append(None)
            else:
                vals.append(float(v))
        present = [v for v in vals if v is not None]
        same = len(present) == 3 and max(present) - min(present) <= args.tolerance
        rows.append((k, vals, same, (max(present) - min(present)) if present else None, mean(present) if present else None))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Repeatability Summary (Executed)",
        "",
        "Scope: screening / prioritization / governance workflow only.",
        "",
        "## Inputs",
        f"- run1: `{args.run1}`",
        f"- run2: `{args.run2}`",
        f"- run3: `{args.run3}`",
        "",
        "## Metric Stability",
        "",
        "| Metric | Run1 | Run2 | Run3 | Exact-Match (tol) | Range | Mean |",
        "|---|---:|---:|---:|---|---:|---:|",
    ]
    for metric, vals, same, rng, avg in rows:
        vtxt = [("NA" if v is None else f"{v:.6g}") for v in vals]
        lines.append(
            f"| {metric} | {vtxt[0]} | {vtxt[1]} | {vtxt[2]} | {'PASS' if same else 'REVIEW'} | "
            f"{'NA' if rng is None else f'{rng:.6g}'} | {'NA' if avg is None else f'{avg:.6g}'} |"
        )

    overall = all(r[2] for r in rows if all(v is not None for v in r[1]))
    lines += [
        "",
        f"Overall stability: **{'PASS' if overall else 'REVIEW'}**",
        "",
        "Interpretation note: this report does not establish accreditation, certification, or regulatory approval.",
    ]
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(str(args.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
