#!/usr/bin/env python3
"""Add sex / age_years to a governed V1 input CSV from a sidecar file.

Use when your concentration file has row_index (or sample_id) but no demographics.
V1 will then emit sex/age-specific percentiles instead of all / all_ages.

Sidecar CSV must include row_index OR sample_id plus sex and/or age_years.

Example:
  python scripts/enrich_v1_input_demographics.py \\
    --input data/v1/uploads/my_batch.csv \\
    --demographics data/v1/fixtures/demo_sex_age.csv \\
    --output data/v1/fixtures/my_batch_with_demographics.csv

sex coding: 1=male, 2=female (NHANES); also accepts Male/Female/M/F.
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


def _read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            raise ValueError(f"No header in {path}")
        rows = [dict(r) for r in reader]
        return list(reader.fieldnames), rows


def _write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def _norm_sex(raw: str) -> str:
    s = (raw or "").strip().lower()
    if s in {"1", "male", "m"}:
        return "1"
    if s in {"2", "female", "f"}:
        return "2"
    return (raw or "").strip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Enrich governed V1 CSV with sex/age_years.")
    parser.add_argument("--input", "-i", type=Path, required=True)
    parser.add_argument("--demographics", "-d", type=Path, required=True)
    parser.add_argument("--output", "-o", type=Path, required=True)
    parser.add_argument(
        "--join-key",
        default="row_index",
        help="Join key present in both files (row_index or sample_id). Default: row_index",
    )
    args = parser.parse_args(argv)

    in_fields, in_rows = _read_csv(args.input)
    demo_fields, demo_rows = _read_csv(args.demographics)
    key = args.join_key

    if key not in in_fields:
        if key == "row_index":
            in_fields = ["row_index", *in_fields]
            for i, row in enumerate(in_rows):
                row["row_index"] = str(i)
            print(f"Note: added row_index 0..{len(in_rows) - 1} to input (was missing).")
        else:
            raise SystemExit(f"Input missing join key {key!r}; columns: {in_fields}")
    if key not in demo_fields:
        raise SystemExit(f"Demographics missing join key {key!r}; columns: {demo_fields}")

    lookup: dict[str, dict[str, str]] = {}
    for row in demo_rows:
        k = (row.get(key) or "").strip()
        if k:
            lookup[k] = row

    out_fields = list(in_fields)
    if "row_index" in out_fields:
        out_fields = ["row_index"] + [c for c in out_fields if c != "row_index"]
    for col in ("sex", "age_years"):
        if col not in out_fields:
            out_fields.append(col)

    filled_sex = 0
    filled_age = 0
    for i, row in enumerate(in_rows):
        if key == "row_index" and not (row.get(key) or "").strip():
            row[key] = str(i)
        elif not (row.get(key) or "").strip():
            raise SystemExit(f"Row {i}: missing join key {key!r}")
        demo = lookup.get(row[key].strip())
        if not demo:
            continue
        if demo.get("sex") and not (row.get("sex") or "").strip():
            row["sex"] = _norm_sex(demo["sex"])
            filled_sex += 1
        if demo.get("age_years") and not (row.get("age_years") or "").strip():
            row["age_years"] = str(demo["age_years"]).strip()
            filled_age += 1

    _write_csv(args.output, out_fields, in_rows)
    print(f"Wrote {args.output} ({len(in_rows)} rows)")
    print(f"Filled sex: {filled_sex}  age_years: {filled_age}  (join={key})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
