"""
Apply per-lane applicability-domain (AD) guard to a candidate prediction or
upload CSV.

Hard-refusal contract (per SOP §6 + AD enforcement design):

    Annotated output columns (always added):
        ad_status                 in_domain | warning | reject
        ad_distance               log10 |z| for value lanes; categorical match score for biosolids
        ad_reason                 human-readable explanation (e.g. value_out_of_range:z=3.4)
        reference_lane            the governing pipeline_lane
        training_range_version    matches the lane's ad_model.training_range_version
        ad_model_version          semver of the AD framework
        ad_threshold              the reject threshold that was applied (z for values; 1.0 for categorical)
        nearest_training_source   primary source organization for the matched analyte / lane
        ad_method                 per_analyte_envelope_v1 | categorical_coverage_v1

Strict mode (default): rows with ad_status='reject' have their analytical
result columns (result_value_raw, result_value_numeric, result_unit, qualifier,
mdl, rl) **blanked**. The refusal is propagated downstream and to the audit
log; this is intentional — predictions outside the validated applicability
domain are not silently warned about, they are refused.

Audit log: every decision is appended to data/audit/ad_decisions.jsonl as a
JSON object with row hash, decision fields, and lane reference. This makes AD
decisions reproducible and auditable post-hoc.

Examples:
    # Annotate a candidate upload (drinking water occurrence):
    python scripts/apply_ad_guard.py --lane drinking_water \
        --input my_water_samples.csv --output annotated.csv

    # Annotate only (do not blank reject rows):
    python scripts/apply_ad_guard.py --lane serum --input nhanes_like.csv \
        --output annotated.csv --mode annotate

    # Pipe a single-row decision (auto-routes by pipeline_lane if --lane omitted):
    python scripts/apply_ad_guard.py --input my_records.csv
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any

AD_FRAMEWORK_VERSION = "1.0.0"

AD_OUTPUT_COLUMNS = [
    "ad_status",
    "ad_distance",
    "ad_reason",
    "reference_lane",
    "training_range_version",
    "ad_model_version",
    "ad_threshold",
    "nearest_training_source",
    "ad_method",
]

ANALYTICAL_VALUE_TYPES = {"field_measurement", "non-certified", "certified"}
RESULT_COLS_TO_BLANK = {
    "result_value_raw",
    "result_value_numeric",
    "result_unit",
    "qualifier",
    "mdl",
    "rl",
}


def _coerce_float(value: Any) -> float | None:
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        f = float(s.replace(",", ""))
    except ValueError:
        return None
    if math.isnan(f) or math.isinf(f):
        return None
    return f


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _hash_row(row: dict[str, Any]) -> str:
    payload = json.dumps(
        {k: ("" if v is None else str(v)) for k, v in sorted(row.items())},
        ensure_ascii=False, sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _load_ad_model(project_root: Path, lane: str) -> dict[str, Any]:
    p = project_root / "data" / "ad_models" / lane / "ad_model.json"
    if not p.is_file():
        raise SystemExit(
            f"ERROR: missing AD model for lane '{lane}' at {p}. "
            "Run scripts/build_ad_models.py first."
        )
    return json.loads(p.read_text(encoding="utf-8"))


# -------------------------------------------------------------------- #
# Per-lane decision functions                                          #
# -------------------------------------------------------------------- #


def _decide_value_lane(
    model: dict[str, Any], row: dict[str, str]
) -> tuple[str, float, str, str]:
    """Return (ad_status, ad_distance, ad_reason, nearest_training_source)."""

    thresholds = model["thresholds"]
    reject_z = float(thresholds["reject_z"])
    warning_z = float(thresholds["warning_z"])
    g = model["global"]
    unit_set = set(g["unit_set"])
    source_set = sorted(g["source_set"])
    primary_source = source_set[0] if source_set else ""

    analyte = (row.get("analyte") or "").strip()
    if not analyte:
        return "reject", float("inf"), "analyte_missing", primary_source

    env = model["analytes"].get(analyte)
    if env is None:
        return "reject", float("inf"), "analyte_unseen", primary_source

    unit = (row.get("result_unit") or "").strip()
    if unit and unit_set and unit not in unit_set:
        return "reject", float("inf"), f"unit_mismatch:{unit}", env.get("primary_source", primary_source)

    qualifier = (row.get("qualifier") or "").strip().upper()
    rv_str = (row.get("result_value_numeric") or row.get("result_value_raw") or "").strip()

    if qualifier == "ND" and not rv_str:
        return "in_domain", 0.0, "non_detect_no_concentration_claim", env.get("primary_source", primary_source)

    rv = _coerce_float(rv_str)
    if rv is None:
        return "reject", float("inf"), "invalid_value", env.get("primary_source", primary_source)
    if rv <= 0:
        return "reject", float("inf"), f"non_positive_value:{rv}", env.get("primary_source", primary_source)

    log_env = env.get("log10", {})
    n = int(log_env.get("n", 0))
    if n < 2:
        return "warning", float("nan"), f"sparse_training:n={n}", env.get("primary_source", primary_source)

    log_mean = float(log_env["mean"])
    log_std = float(log_env["std"])
    if log_std <= 0:
        log_min = float(log_env.get("min", log_mean))
        log_max = float(log_env.get("max", log_mean))
        if math.log10(rv) < log_min or math.log10(rv) > log_max:
            return "reject", float("inf"), "zero_std_out_of_range", env.get("primary_source", primary_source)
        return "in_domain", 0.0, "zero_std_match", env.get("primary_source", primary_source)

    z = abs((math.log10(rv) - log_mean) / log_std)
    if z > reject_z:
        return "reject", z, f"value_out_of_range:log10_z={z:.2f}", env.get("primary_source", primary_source)
    if z > warning_z:
        return "warning", z, f"value_warning:log10_z={z:.2f}", env.get("primary_source", primary_source)
    return "in_domain", z, f"value_in_envelope:log10_z={z:.2f}", env.get("primary_source", primary_source)


def _decide_categorical_lane(
    model: dict[str, Any], row: dict[str, str]
) -> tuple[str, float, str, str]:
    cat = model["categorical"]
    matrix_set = set(cat["matrix_set"])
    state_set = set(cat["state_set"])
    method_set = set(cat["method_set"])
    source_set = sorted(cat["source_set"])
    primary_source = source_set[0] if source_set else ""

    matrix = (row.get("matrix") or "").strip()
    if matrix and matrix_set and matrix not in matrix_set:
        return "reject", float("inf"), f"matrix_mismatch:{matrix}", primary_source

    vt = (row.get("value_type") or "").strip()
    if vt in ANALYTICAL_VALUE_TYPES:
        return ("reject", float("inf"),
                "concentration_claim_in_metadata_lane:biosolids_sludge_is_governance_only",
                primary_source)

    state = (row.get("state") or "").strip().upper()
    if state and state_set and state not in state_set:
        return "reject", float("inf"), f"state_unseen:{state}", primary_source

    method = (row.get("method_id") or "").strip()
    if method and method_set and method not in method_set:
        return "reject", float("inf"), f"method_unseen:{method}", primary_source

    return "in_domain", 0.0, "metadata_in_coverage", primary_source


def decide(model: dict[str, Any], row: dict[str, str]) -> dict[str, Any]:
    if model.get("value_lane", False):
        status, dist, reason, nearest = _decide_value_lane(model, row)
    else:
        status, dist, reason, nearest = _decide_categorical_lane(model, row)

    threshold = model["thresholds"]["reject_z"]
    dist_str = ""
    if isinstance(dist, float):
        if math.isinf(dist):
            dist_str = "inf"
        elif math.isnan(dist):
            dist_str = "nan"
        else:
            dist_str = f"{dist:.4f}"

    return {
        "ad_status": status,
        "ad_distance": dist_str,
        "ad_reason": reason,
        "reference_lane": model["pipeline_lane"],
        "training_range_version": model["training_range_version"],
        "ad_model_version": model["ad_model_version"],
        "ad_threshold": str(threshold),
        "nearest_training_source": nearest,
        "ad_method": model["ad_method"],
    }


# -------------------------------------------------------------------- #
# CLI                                                                  #
# -------------------------------------------------------------------- #


def _audit_append(project_root: Path, payload: dict[str, Any]) -> None:
    audit_path = project_root / "data" / "audit" / "ad_decisions.jsonl"
    audit_path.parent.mkdir(parents=True, exist_ok=True)
    with audit_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__.splitlines()[1] if __doc__ else "Apply AD guard."
    )
    ap.add_argument("--project-root", default=".")
    ap.add_argument("--lane", default=None, help=(
        "Force a specific lane id. If omitted, the per-row 'pipeline_lane' "
        "column is used."
    ))
    ap.add_argument("--input", required=True, help="Input CSV path.")
    ap.add_argument("--output", default=None, help=(
        "Output CSV (default: <input>.ad_annotated.csv next to input)."
    ))
    ap.add_argument("--mode", choices=["strict", "annotate"], default="strict",
                    help="strict (default) blanks result columns on reject; "
                         "annotate keeps original values and only adds AD columns.")
    ap.add_argument("--no-audit", action="store_true",
                    help="Skip writing data/audit/ad_decisions.jsonl entries.")
    args = ap.parse_args()

    project_root = Path(args.project_root).resolve()
    in_path = Path(args.input).resolve()
    if not in_path.is_file():
        print(f"ERROR: input not found: {in_path}", file=sys.stderr)
        return 2
    out_path = Path(args.output).resolve() if args.output else (
        in_path.with_name(in_path.stem + ".ad_annotated.csv")
    )

    models_cache: dict[str, dict[str, Any]] = {}

    def _model_for(lane: str) -> dict[str, Any]:
        if lane not in models_cache:
            models_cache[lane] = _load_ad_model(project_root, lane)
        return models_cache[lane]

    if args.lane:
        _model_for(args.lane)

    counts = {"in_domain": 0, "warning": 0, "reject": 0, "no_lane": 0}

    with in_path.open("r", encoding="utf-8", newline="") as fin:
        reader = csv.DictReader(fin)
        in_cols = list(reader.fieldnames or [])
        extra_cols = [c for c in AD_OUTPUT_COLUMNS if c not in in_cols]
        out_cols = in_cols + extra_cols
        rows_out: list[dict[str, str]] = []
        for raw_row in reader:
            lane = (args.lane or (raw_row.get("pipeline_lane") or "")).strip()
            if not lane:
                ann = {
                    "ad_status": "reject",
                    "ad_distance": "inf",
                    "ad_reason": "no_lane_specified",
                    "reference_lane": "",
                    "training_range_version": "",
                    "ad_model_version": AD_FRAMEWORK_VERSION,
                    "ad_threshold": "",
                    "nearest_training_source": "",
                    "ad_method": "",
                }
                counts["no_lane"] += 1
            else:
                model = _model_for(lane)
                ann = decide(model, raw_row)
                counts[ann["ad_status"]] = counts.get(ann["ad_status"], 0) + 1

            new_row = dict(raw_row)
            for k, v in ann.items():
                new_row[k] = v

            if args.mode == "strict" and ann["ad_status"] == "reject":
                for col in RESULT_COLS_TO_BLANK:
                    if col in new_row:
                        new_row[col] = ""

            rows_out.append(new_row)

            if not args.no_audit:
                _audit_append(project_root, {
                    "timestamp_utc": _now_iso(),
                    "input": str(in_path),
                    "row_sha256": _hash_row(raw_row),
                    "reference_lane": ann["reference_lane"],
                    "ad_status": ann["ad_status"],
                    "ad_distance": ann["ad_distance"],
                    "ad_reason": ann["ad_reason"],
                    "training_range_version": ann["training_range_version"],
                    "ad_model_version": ann["ad_model_version"],
                    "ad_method": ann["ad_method"],
                    "mode": args.mode,
                })

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="") as fout:
        writer = csv.DictWriter(fout, fieldnames=out_cols)
        writer.writeheader()
        for r in rows_out:
            writer.writerow({c: r.get(c, "") for c in out_cols})

    print(json.dumps({
        "input": str(in_path),
        "output": str(out_path),
        "mode": args.mode,
        "ad_framework_version": AD_FRAMEWORK_VERSION,
        "counts": counts,
        "audit_log": (
            str((project_root / "data/audit/ad_decisions.jsonl").resolve())
            if not args.no_audit else None
        ),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
