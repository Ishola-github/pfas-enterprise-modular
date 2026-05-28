#!/usr/bin/env python3
"""Convert legacy serum batch CSV to V1 governed input schema.

Legacy layout (batch contextualization era)::

    sample_id, analyte, value, age, sex, matrix, units

V1 governed layout::

    sample_matrix, result_unit, source_program, analyte, result_value,
    sex, age_years, reference_cycle, lod_code

Rows that cannot be scored after conversion are still emitted so V1 can
refuse them with the correct ontology codes (e.g. non-serum matrix).
A sidecar manifest records mapping decisions and expected outcomes.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any, Mapping

V1_COLUMNS = (
    "sample_matrix",
    "result_unit",
    "source_program",
    "analyte",
    "result_value",
    "sex",
    "age_years",
    "reference_cycle",
    "lod_code",
)

DEFAULT_SOURCE_PROGRAM = "CDC NHANES"
DEFAULT_MATRIX = "human_serum"
DEFAULT_UNIT = "ng/mL"

# Legacy total names -> linear isomer stand-ins (RUO only; not a lab split).
LEGACY_ANALYTE_MAP: dict[str, str] = {
    "pfos": "n_pfos",
    "pfoa": "n_pfoa",
    "n-pfos": "n_pfos",
    "n-pfoa": "n_pfoa",
    "branched pfos": "sm_pfos",
    "branched pfoa": "sb_pfoa",
    "sm-pfos": "sm_pfos",
    "sb-pfoa": "sb_pfoa",
}

MATRIX_MAP: dict[str, str] = {
    "serum": DEFAULT_MATRIX,
    "human serum": DEFAULT_MATRIX,
    "human_serum": DEFAULT_MATRIX,
    "blood serum": DEFAULT_MATRIX,
    "plasma": DEFAULT_MATRIX,
    "whole blood": DEFAULT_MATRIX,
}

V1_ANALYTE_IDS = frozenset({"n_pfoa", "sb_pfoa", "n_pfos", "sm_pfos"})

_FIELD_ALIASES: dict[str, tuple[str, ...]] = {
    "sample_id": ("sample_id", "sample", "id"),
    "analyte": ("analyte", "compound", "chemical"),
    "value": ("value", "result", "concentration", "result_value"),
    "age": ("age", "age_years", "ridageyr"),
    "sex": ("sex", "gender", "riagendr"),
    "matrix": ("matrix", "sample_matrix", "specimen_matrix"),
    "units": ("units", "unit", "result_unit"),
}


def _norm_header(name: str) -> str:
    return name.strip().lower().replace(" ", "_")


def _resolve_column(headers: list[str], aliases: tuple[str, ...]) -> str | None:
    norm = {_norm_header(h): h for h in headers}
    for alias in aliases:
        key = _norm_header(alias)
        if key in norm:
            return norm[key]
    return None


def _pick(row: Mapping[str, str], col: str | None) -> str:
    if col is None:
        return ""
    return (row.get(col) or "").strip()


def _sex_to_nhanes_code(raw: str) -> str:
    s = raw.strip().lower()
    if s in {"1", "male", "m"}:
        return "1"
    if s in {"2", "female", "f"}:
        return "2"
    try:
        code = int(float(s))
        if code in (1, 2):
            return str(code)
    except (TypeError, ValueError):
        pass
    return ""


def _map_matrix(raw: str) -> tuple[str, list[str]]:
    notes: list[str] = []
    if not raw:
        notes.append("matrix_missing_defaults_to_human_serum")
        return DEFAULT_MATRIX, notes
    key = raw.strip().lower()
    if key in MATRIX_MAP:
        if key != "human_serum":
            notes.append(f"matrix_mapped:{raw!r}->{MATRIX_MAP[key]!r}")
        return MATRIX_MAP[key], notes
    notes.append(f"matrix_passthrough:{raw!r} (V1 may refuse if not human_serum)")
    return raw.strip(), notes


def _map_analyte(raw: str) -> tuple[str, list[str]]:
    notes: list[str] = []
    if not raw:
        return "", ["analyte_missing"]
    aid = raw.strip()
    if aid in V1_ANALYTE_IDS:
        return aid, notes
    key = aid.lower().replace(" ", "")
    key_sp = aid.lower()
    if key in LEGACY_ANALYTE_MAP:
        mapped = LEGACY_ANALYTE_MAP[key]
        notes.append(
            f"legacy_total_analyte_mapped:{aid!r}->{mapped!r} "
            "(linear isomer stand-in; not a lab isomer split)"
        )
        return mapped, notes
    if key_sp in LEGACY_ANALYTE_MAP:
        mapped = LEGACY_ANALYTE_MAP[key_sp]
        notes.append(
            f"legacy_total_analyte_mapped:{aid!r}->{mapped!r} "
            "(linear isomer stand-in; not a lab isomer split)"
        )
        return mapped, notes
    notes.append(f"analyte_unmapped:{aid!r} (V1 will refuse)")
    return aid, notes


def _expected_v1_status(
    sample_matrix: str,
    result_unit: str,
    analyte: str,
) -> str:
    if sample_matrix != DEFAULT_MATRIX:
        return "refused:matrix_not_serum"
    if result_unit != DEFAULT_UNIT:
        return "refused:units"
    if analyte not in V1_ANALYTE_IDS:
        return "refused:analyte_not_in_pfos_pfoa_scope"
    return "in_domain:candidate"


def _is_governed_input(headers: list[str]) -> bool:
    norm = {_norm_header(h) for h in headers}
    return "sample_matrix" in norm and "result_value" in norm


def convert_row(
    row: Mapping[str, str],
    *,
    row_index: int,
    colmap: Mapping[str, str | None],
    default_cycle: str,
    source_program: str,
) -> tuple[dict[str, str], dict[str, Any]]:
    notes: list[str] = []
    sample_id = _pick(row, colmap.get("sample_id"))

    if _is_governed_input(list(row.keys())):
        out = {c: _pick(row, c) or "" for c in V1_COLUMNS}
        if not out["reference_cycle"]:
            out["reference_cycle"] = default_cycle.upper()
        if not out["lod_code"]:
            out["lod_code"] = "0"
        notes.append("already_governed_passthrough")
    else:
        raw_matrix = _pick(row, colmap.get("matrix"))
        raw_units = _pick(row, colmap.get("units")) or DEFAULT_UNIT
        raw_analyte = _pick(row, colmap.get("analyte"))
        raw_value = _pick(row, colmap.get("value"))
        raw_sex = _pick(row, colmap.get("sex"))
        raw_age = _pick(row, colmap.get("age"))

        sample_matrix, m_notes = _map_matrix(raw_matrix)
        notes.extend(m_notes)

        if raw_units and raw_units != DEFAULT_UNIT:
            notes.append(f"units_passthrough:{raw_units!r}")
        elif not raw_units:
            notes.append("units_missing_defaulted_to_ng_per_mL")

        analyte, a_notes = _map_analyte(raw_analyte)
        notes.extend(a_notes)

        sex_code = _sex_to_nhanes_code(raw_sex)
        if raw_sex and not sex_code:
            notes.append(f"sex_unmapped:{raw_sex!r} (left blank; V1 uses all)")

        out = {
            "sample_matrix": sample_matrix,
            "result_unit": raw_units if raw_units else DEFAULT_UNIT,
            "source_program": source_program,
            "analyte": analyte,
            "result_value": raw_value,
            "sex": sex_code,
            "age_years": raw_age,
            "reference_cycle": default_cycle.upper(),
            "lod_code": "0",
        }

    manifest_row: dict[str, Any] = {
        "row_index": row_index,
        "legacy_sample_id": sample_id,
        "conversion_notes": notes,
        "expected_v1_status": _expected_v1_status(
            out["sample_matrix"],
            out["result_unit"],
            out["analyte"],
        ),
    }
    return out, manifest_row


def convert_file(
    inpath: Path,
    outpath: Path,
    *,
    manifest_path: Path | None,
    default_cycle: str,
    source_program: str,
) -> dict[str, Any]:
    with inpath.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            raise ValueError(f"No header row in {inpath}")
        headers = list(reader.fieldnames)
        colmap = {k: _resolve_column(headers, v) for k, v in _FIELD_ALIASES.items()}
        rows = list(reader)

    out_rows: list[dict[str, str]] = []
    manifest_rows: list[dict[str, Any]] = []
    for i, row in enumerate(rows):
        converted, meta = convert_row(
            row,
            row_index=i,
            colmap=colmap,
            default_cycle=default_cycle,
            source_program=source_program,
        )
        out_rows.append(converted)
        manifest_rows.append(meta)

    outpath.parent.mkdir(parents=True, exist_ok=True)
    with outpath.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=V1_COLUMNS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(out_rows)

    summary = {
        "input": str(inpath.resolve()),
        "output": str(outpath.resolve()),
        "n_rows": len(out_rows),
        "n_expected_in_domain": sum(
            1 for m in manifest_rows if m["expected_v1_status"].startswith("in_domain")
        ),
        "n_expected_refused": sum(
            1 for m in manifest_rows if m["expected_v1_status"].startswith("refused")
        ),
        "default_reference_cycle": default_cycle.upper(),
        "rows": manifest_rows,
    }

    if manifest_path is not None:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert legacy serum PFAS batch CSV to V1 governed input.",
    )
    parser.add_argument(
        "--input",
        "-i",
        type=Path,
        required=True,
        help="Legacy batch CSV (sample_id, analyte, value, matrix, units, ...).",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        help="Governed V1 CSV path (default: <input_stem>_v1.csv beside input).",
    )
    parser.add_argument(
        "--manifest",
        "-m",
        type=Path,
        help="JSON manifest of mapping notes (default: <output_stem>.manifest.json).",
    )
    parser.add_argument(
        "--default-cycle",
        default="J",
        help="NHANES reference cycle letter when not in input (default: J).",
    )
    parser.add_argument(
        "--source-program",
        default=DEFAULT_SOURCE_PROGRAM,
        help=f"source_program value (default: {DEFAULT_SOURCE_PROGRAM!r}).",
    )
    args = parser.parse_args(argv)

    inpath: Path = args.input
    if not inpath.is_file():
        print(f"error: input not found: {inpath}", file=sys.stderr)
        return 1

    outpath = args.output or inpath.with_name(inpath.stem + "_v1.csv")
    manifest_path = args.manifest
    if manifest_path is None and args.manifest is not False:
        manifest_path = outpath.with_suffix(".manifest.json")

    summary = convert_file(
        inpath,
        outpath,
        manifest_path=manifest_path,
        default_cycle=args.default_cycle,
        source_program=args.source_program,
    )

    print(f"Wrote {outpath} ({summary['n_rows']} rows)")
    print(
        f"Expected after V1 run: in_domain~={summary['n_expected_in_domain']} "
        f"refused~={summary['n_expected_refused']}"
    )
    if manifest_path:
        print(f"Manifest: {manifest_path}")
    for row in summary["rows"]:
        sid = row.get("legacy_sample_id") or row["row_index"]
        print(f"  [{sid}] {row['expected_v1_status']}: {', '.join(row['conversion_notes']) or 'ok'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
