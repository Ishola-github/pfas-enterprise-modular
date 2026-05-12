"""
Build per-lane applicability-domain (AD) models from each lane's training.csv.

Per-lane semantics (SOP §6 + AD enforcement design):

    Lane                 | AD method                      | What is enforced
    -------------------- | ------------------------------ | ---------------------------------
    drinking_water       | per_analyte_envelope_v1        | analyte ∈ training set; unit ng/L; |result_value_numeric| within
                         |                                |     log-space envelope around training median; method seen.
    serum                | per_analyte_envelope_v1        | same, per analyte; NHANES + SRM 1957 distributions.
    afff                 | per_analyte_envelope_v1        | per analyte; RM 8690 reference range.
    methanol_standards   | per_analyte_envelope_v1        | per analyte; RM 8446 reference range.
    air_emissions        | per_analyte_envelope_v1        | per analyte; OTM-50 stack distributions.
    biosolids_sludge     | categorical_coverage_v1        | matrix = 'biosolids/sludge'; state/method present in
                         |                                |     training categorical set; concentration-claim rows are
                         |                                |     REJECTED (this lane is governance/enrichment only).

Output:
    data/ad_models/<lane>/ad_model.json
    data/ad_models/index.json          (cross-lane catalog with hashes)

Each ad_model.json captures the full state needed to reproduce an AD decision:
training_csv_sha256, training_csv_rows, ad_method, ad_model_version,
ad_thresholds, training_range_version, and the per-analyte (or categorical)
envelopes. Distance is computed in log10 space for value-based lanes (PFAS
concentrations span orders of magnitude); the envelope mean/std are then
robust to outliers because we exclude non-detect rows from the training fit.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import statistics
import sys
from pathlib import Path
from typing import Any

AD_MODEL_VERSION = "1.0.0"

VALUE_BASED_LANES = {
    "drinking_water",
    "serum",
    "afff",
    "methanol_standards",
    "air_emissions",
}
CATEGORICAL_LANES = {"biosolids_sludge"}

LANE_AD_METHOD = {
    **{ln: "per_analyte_envelope_v1" for ln in VALUE_BASED_LANES},
    **{ln: "categorical_coverage_v1" for ln in CATEGORICAL_LANES},
}

DEFAULT_AD_THRESHOLDS = {
    ln: {"warning_z": 2.0, "reject_z": 3.0} for ln in VALUE_BASED_LANES
}
DEFAULT_AD_THRESHOLDS["biosolids_sludge"] = {"warning_z": 1.0, "reject_z": 1.0}

ANALYTICAL_VALUE_TYPES = {"field_measurement", "non-certified", "certified"}
METHOD_METADATA_VALUE_TYPES = {"method_metadata", "program_metadata"}


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _coerce_float(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        try:
            f = float(value)
        except (TypeError, ValueError):
            return None
        if math.isnan(f) or math.isinf(f):
            return None
        return f
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


def _percentiles(values: list[float], pcts: tuple[float, ...]) -> dict[str, float]:
    """Compute percentiles via linear interpolation; safe for tiny n."""
    if not values:
        return {f"p{int(p * 100):02d}": float("nan") for p in pcts}
    s = sorted(values)
    n = len(s)
    out: dict[str, float] = {}
    for p in pcts:
        if n == 1:
            out[f"p{int(p * 100):02d}"] = s[0]
            continue
        idx = p * (n - 1)
        lo = int(math.floor(idx))
        hi = int(math.ceil(idx))
        if lo == hi:
            out[f"p{int(p * 100):02d}"] = s[lo]
        else:
            frac = idx - lo
            out[f"p{int(p * 100):02d}"] = s[lo] * (1 - frac) + s[hi] * frac
    return out


def _summary_stats(values: list[float]) -> dict[str, Any]:
    if not values:
        return {"n": 0}
    out: dict[str, Any] = {"n": len(values)}
    out["min"] = min(values)
    out["max"] = max(values)
    out["mean"] = statistics.fmean(values)
    out["std"] = statistics.pstdev(values) if len(values) >= 2 else 0.0
    out.update(_percentiles(values, (0.05, 0.25, 0.50, 0.75, 0.95)))
    return out


def _read_training_rows(csv_path: Path) -> list[dict[str, str]]:
    with csv_path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def _build_value_lane_ad(lane: str, rows: list[dict[str, str]]) -> dict[str, Any]:
    analytical_rows = [
        r for r in rows
        if (r.get("value_type") or "").strip() in ANALYTICAL_VALUE_TYPES
    ]

    per_analyte: dict[str, dict[str, Any]] = {}
    unit_set: set[str] = set()
    method_set: set[str] = set()
    source_set: set[str] = set()
    cas_for_analyte: dict[str, str] = {}
    source_for_analyte: dict[str, str] = {}
    short_for_analyte: dict[str, str] = {}

    detect_rows = 0
    nd_rows = 0

    grouped: dict[str, list[tuple[float, str, str, str, str, str]]] = {}

    for r in analytical_rows:
        analyte = (r.get("analyte") or "").strip()
        if not analyte:
            continue
        unit = (r.get("result_unit") or "").strip()
        method = (r.get("method_id") or "").strip()
        source = (r.get("source") or "").strip()
        cas = (r.get("cas_rn") or "").strip()
        short = (r.get("analyte_short_name") or "").strip()
        if unit:
            unit_set.add(unit)
        if method:
            method_set.add(method)
        if source:
            source_set.add(source)
        if analyte not in cas_for_analyte and cas:
            cas_for_analyte[analyte] = cas
        if analyte not in source_for_analyte and source:
            source_for_analyte[analyte] = source
        if analyte not in short_for_analyte and short:
            short_for_analyte[analyte] = short

        qualifier = (r.get("qualifier") or "").strip().upper()
        rv = _coerce_float(r.get("result_value_numeric"))
        if rv is None or rv <= 0 or qualifier == "ND":
            nd_rows += 1
            continue
        detect_rows += 1
        grouped.setdefault(analyte, []).append(
            (rv, unit, method, source, cas, short)
        )

    for analyte, entries in grouped.items():
        vals = [e[0] for e in entries]
        log_vals = [math.log10(v) for v in vals if v > 0]

        per_analyte[analyte] = {
            "cas_rn": cas_for_analyte.get(analyte, ""),
            "analyte_short_name": short_for_analyte.get(analyte, ""),
            "primary_source": source_for_analyte.get(analyte, ""),
            "units": sorted({e[1] for e in entries if e[1]}),
            "methods": sorted({e[2] for e in entries if e[2]}),
            "linear": _summary_stats(vals),
            "log10": _summary_stats(log_vals),
        }

    return {
        "ad_method": LANE_AD_METHOD[lane],
        "value_lane": True,
        "thresholds": DEFAULT_AD_THRESHOLDS[lane],
        "global": {
            "n_training_rows": len(rows),
            "n_analytical_rows": len(analytical_rows),
            "n_detect_rows": detect_rows,
            "n_nondetect_rows": nd_rows,
            "n_analytes_with_envelope": len(per_analyte),
            "unit_set": sorted(unit_set),
            "method_set": sorted(method_set),
            "source_set": sorted(source_set),
        },
        "analytes": per_analyte,
        "refusal_rules": [
            "analyte not in training set -> reject (reason: analyte_unseen)",
            "unit not in training unit_set -> reject (reason: unit_mismatch)",
            "value <= 0 and not flagged ND -> reject (reason: invalid_value)",
            "log10 |z| > reject_z -> reject (reason: value_out_of_range)",
            "warning_z < log10 |z| <= reject_z -> warning (reason: value_warning)",
            "no envelope for analyte (n < 2 detects) -> warning (reason: sparse_training)",
        ],
    }


def _build_categorical_lane_ad(lane: str, rows: list[dict[str, str]]) -> dict[str, Any]:
    states: set[str] = set()
    counties: set[str] = set()
    matrices: set[str] = set()
    methods: set[str] = set()
    sources: set[str] = set()
    value_types: set[str] = set()
    facility_id_set: set[str] = set()

    n_metadata = 0
    for r in rows:
        vt = (r.get("value_type") or "").strip()
        value_types.add(vt)
        matrices.add((r.get("matrix") or "").strip())
        if (r.get("state") or "").strip():
            states.add(r["state"].strip().upper())
        if (r.get("county") or "").strip():
            counties.add(r["county"].strip())
        if (r.get("method_id") or "").strip():
            methods.add(r["method_id"].strip())
        if (r.get("source") or "").strip():
            sources.add(r["source"].strip())
        if (r.get("facility_id") or "").strip():
            facility_id_set.add(r["facility_id"].strip())
        if vt in METHOD_METADATA_VALUE_TYPES:
            n_metadata += 1

    return {
        "ad_method": LANE_AD_METHOD[lane],
        "value_lane": False,
        "thresholds": DEFAULT_AD_THRESHOLDS[lane],
        "global": {
            "n_training_rows": len(rows),
            "n_metadata_rows": n_metadata,
            "n_unique_facilities": len(facility_id_set),
        },
        "categorical": {
            "matrix_set": sorted(m for m in matrices if m),
            "state_set": sorted(states),
            "county_set": sorted(counties),
            "method_set": sorted(methods),
            "source_set": sorted(sources),
            "value_type_set": sorted(vt for vt in value_types if vt),
        },
        "refusal_rules": [
            "matrix != 'biosolids/sludge' -> reject (reason: matrix_mismatch)",
            "state not in training state_set -> reject (reason: state_unseen)",
            "method not in training method_set -> reject (reason: method_unseen)",
            "value_type indicates an analytical concentration (e.g. field_measurement) -> "
            "reject (reason: concentration_claim_in_metadata_lane) — this lane is governance "
            "and enrichment only; analytical PFAS sludge measurements must be submitted to a "
            "separate, validated biosolids analytical lane (not yet built).",
        ],
    }


def build_lane_ad(
    project_root: Path, lane: str, training_csv: Path
) -> dict[str, Any]:
    """Build a *deterministic* AD model for a single lane.

    The returned dict is reproducible from the same training.csv: it embeds
    the training CSV's SHA-256 prefix as the `training_range_version` anchor
    but NEVER the build timestamp. Build/run timestamps are recorded
    out-of-band in the per-decision audit log
    (data/audit/ad_decisions.jsonl), preserving registry-hash stability
    (registered SHA changes if and only if the training data changes).
    """
    rows = _read_training_rows(training_csv)
    csv_sha = _sha256_file(training_csv)
    training_range_version = csv_sha[:12]

    if lane in VALUE_BASED_LANES:
        body = _build_value_lane_ad(lane, rows)
    elif lane in CATEGORICAL_LANES:
        body = _build_categorical_lane_ad(lane, rows)
    else:
        raise SystemExit(f"ERROR: unknown lane '{lane}' (no AD method defined).")

    return {
        "pipeline_lane": lane,
        "ad_model_version": AD_MODEL_VERSION,
        "training_csv": str(training_csv.relative_to(project_root)).replace("\\", "/"),
        "training_csv_sha256": csv_sha,
        "training_csv_rows": len(rows),
        "training_range_version": training_range_version,
        "sop_separation_note": (
            "SOP §6: this AD model is bound to its lane. Do not use it to gate predictions "
            "for any other pipeline_lane. Predictions outside this envelope must be REFUSED "
            "(ad_status='reject'), not silently warned about."
        ),
        **body,
    }


def write_lane_ad(project_root: Path, lane: str) -> dict[str, Any]:
    training_csv = project_root / "data" / "training" / lane / "training.csv"
    if not training_csv.is_file():
        return {"pipeline_lane": lane, "status": "missing_training_csv",
                "path": str(training_csv)}

    out_dir = project_root / "data" / "ad_models" / lane
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "ad_model.json"

    payload = build_lane_ad(project_root, lane, training_csv)
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    sha = _sha256_file(out_path)
    return {
        "pipeline_lane": lane,
        "status": "ok",
        "ad_model_json": str(out_path.relative_to(project_root)).replace("\\", "/"),
        "ad_model_sha256": sha,
        "training_csv_sha256": payload["training_csv_sha256"],
        "training_csv_rows": payload["training_csv_rows"],
        "ad_model_version": AD_MODEL_VERSION,
        "ad_method": payload["ad_method"],
    }


def write_index(project_root: Path, results: list[dict[str, Any]]) -> Path:
    idx_path = project_root / "data" / "ad_models" / "index.json"
    idx_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "generated_at_utc": _now_iso(),
        "ad_framework_version": AD_MODEL_VERSION,
        "sop_separation_note": (
            "SOP §6: AD models are matrix-scoped. A drinking-water AD model "
            "MUST NOT be used to gate serum predictions, etc. Cross-lane reuse "
            "is forbidden by construction."
        ),
        "lanes": results,
    }
    idx_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return idx_path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--project-root", default=".", help="Project root (default '.').")
    ap.add_argument("--lane", default="all", help=(
        "Lane id or 'all'. Options: drinking_water, serum, biosolids_sludge, "
        "afff, methanol_standards, air_emissions, all."
    ))
    args = ap.parse_args()
    project_root = Path(args.project_root).resolve()

    if args.lane == "all":
        lanes = sorted(VALUE_BASED_LANES | CATEGORICAL_LANES)
    else:
        lanes = [args.lane]

    results: list[dict[str, Any]] = []
    for lane in lanes:
        r = write_lane_ad(project_root, lane)
        results.append(r)
        if r.get("status") == "ok":
            print(f"[ad] lane={lane:<22} method={r['ad_method']:<28} "
                  f"rows={r['training_csv_rows']:<6} sha256={r['training_csv_sha256'][:12]}...")
        else:
            print(f"[ad] lane={lane:<22} status={r.get('status')}: {r.get('path')}", file=sys.stderr)

    idx = write_index(project_root, results)
    print(f"\nIndex written: {idx}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
