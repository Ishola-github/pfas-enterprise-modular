"""
Build a sealed external blind-validation pack.

This is the *submitter side* of the harness. An external party (a lab, a
collaborator, or a future-you) packages a candidate dataset and the
predictions a model produced on it, hashes everything, and submits the
sealed pack BEFORE seeing any scoring output.

Once sealed, the four ground rules apply:

    No retuning. No threshold change. No model change. No dataset editing
    after hash submission.

The seal is enforced by hash verification at score time: even if a sealed
file is edited (read-only flags are advisory on Windows), the recorded
dataset_sha256 / manifest_sha256 will fail to re-verify and the scorer
REFUSES to produce metrics.

Required submission inputs:

    --input        path to the dataset CSV (one row per record)
    --lane         matrix_lane (must match a pipeline_id in
                   data/config/matrix_pipeline_sop.csv)
    --truth-column name of the column carrying ground-truth binary labels
                   (0 / 1) — REQUIRED
    --submitted-by free-text identifier of who is submitting
                   (institution, lab, person)
    --model-version free-text identifier of the model that produced the
                   predictions in --predicted-* columns (semver + git
                   commit etc. — submitter is responsible for honesty here)

Optional:

    --predicted-score-column   continuous score column (used for ROC AUC)
    --predicted-label-column   binary 0/1 column (used for precision/recall/F1)
    --note                     free-text description
    --threshold-version-override   skip auto-resolution and supply a hash

Output (sealed pack):

    validation/blind_external/sealed/<submission_id>/
        dataset.csv          (verbatim copy of --input)
        submission.json      (manifest with all required + provenance fields)
        SEAL.txt             (human-readable summary of the seal)

The submission_id is `<lane>_<UTC>_<dataset_sha[:12]>` and is what the
scorer needs to unseal & evaluate. An entry is also appended to
validation/blind_external/manifests/submissions_index.jsonl for later
audit.

Required manifest fields (per user spec):

    submission_id
    dataset_sha256
    submitted_by
    submitted_at
    matrix_lane
    ad_policy_version
    model_version
    threshold_version
    manifest_sha256

Plus context fields for reproducibility:
    truth_column, predicted_score_column, predicted_label_column,
    n_rows, ad_framework_version, sop_revision, note, dataset_path_relative.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import shutil
import stat
import sys
from pathlib import Path
from typing import Any

VALID_LANES = (
    "drinking_water",
    "serum",
    "biosolids_sludge",
    "afff",
    "methanol_standards",
    "air_emissions",
)


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _sha256_bytes(data: bytes) -> str:
    h = hashlib.sha256()
    h.update(data)
    return h.hexdigest()


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _validate_lane(project_root: Path, lane: str) -> dict[str, str]:
    sop_path = project_root / "data" / "config" / "matrix_pipeline_sop.csv"
    if not sop_path.is_file():
        raise SystemExit(f"ERROR: missing SOP config: {sop_path}")
    with sop_path.open("r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            pid = (row.get("pipeline_id") or "").strip()
            if pid == lane:
                return {k: (v or "").strip() for k, v in row.items()}
    raise SystemExit(
        f"ERROR: lane '{lane}' is not a valid pipeline_id. "
        f"Allowed: {', '.join(VALID_LANES)}"
    )


def _resolve_ad_policy_version(project_root: Path, lane: str) -> dict[str, str]:
    """Hash the lane's ad_model.json. Returns dict for richer audit."""
    p = project_root / "data" / "ad_models" / lane / "ad_model.json"
    if not p.is_file():
        raise SystemExit(
            f"ERROR: missing AD model for lane '{lane}' at {p}. "
            "Run scripts/build_ad_models.py first."
        )
    sha = _sha256_file(p)
    try:
        model = json.loads(p.read_text(encoding="utf-8"))
        framework_version = model.get("ad_model_version", "")
        training_range = model.get("training_range_version", "")
    except Exception:
        framework_version = ""
        training_range = ""
    return {
        "ad_model_sha256": sha,
        "ad_model_path": str(p.relative_to(project_root)).replace("\\", "/"),
        "ad_framework_version": framework_version,
        "training_range_version": training_range,
    }


def _resolve_threshold_version(project_root: Path, lane: str) -> dict[str, str]:
    """Locate any per-lane threshold config file and hash it.

    For drinking_water this is data/config/ucmr_analyte_limits_ngl.csv.
    Other lanes have no published threshold file today; threshold_version
    is then 'none'.
    """
    candidates = {
        "drinking_water": "data/config/ucmr_analyte_limits_ngl.csv",
    }
    rel = candidates.get(lane)
    if not rel:
        return {"threshold_version": "none", "threshold_path": ""}
    p = project_root / rel
    if not p.is_file():
        return {"threshold_version": "none", "threshold_path": rel + " (missing)"}
    sha = _sha256_file(p)
    return {
        "threshold_version": sha,
        "threshold_path": rel,
    }


def _validate_dataset(input_path: Path, args: argparse.Namespace) -> int:
    """Sanity-check the input CSV; return n_rows."""
    if not input_path.is_file():
        raise SystemExit(f"ERROR: --input not found: {input_path}")
    with input_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        cols = reader.fieldnames or []
        cols_set = set(cols)
        if args.truth_column not in cols_set:
            raise SystemExit(
                f"ERROR: --truth-column '{args.truth_column}' not in input columns: {cols}"
            )
        if args.predicted_score_column and args.predicted_score_column not in cols_set:
            raise SystemExit(
                f"ERROR: --predicted-score-column '{args.predicted_score_column}' not in input columns"
            )
        if args.predicted_label_column and args.predicted_label_column not in cols_set:
            raise SystemExit(
                f"ERROR: --predicted-label-column '{args.predicted_label_column}' not in input columns"
            )
        if not (args.predicted_score_column or args.predicted_label_column):
            raise SystemExit(
                "ERROR: at least one of --predicted-score-column or --predicted-label-column "
                "must be supplied (the dataset must carry the predictions being validated)."
            )
        n = 0
        for _ in reader:
            n += 1
        if n == 0:
            raise SystemExit("ERROR: input dataset is empty.")
        return n


def _make_readonly(path: Path) -> None:
    """Set read-only bits on a file. Advisory on Windows but documents intent."""
    try:
        mode = path.stat().st_mode
        path.chmod(mode & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)
        if os.name == "nt":
            os.system(f'attrib +R "{path}" >NUL 2>&1')
    except Exception:
        pass


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1] if __doc__ else "Seal blind validation pack")
    ap.add_argument("--project-root", default=".")
    ap.add_argument("--input", required=True, help="Path to candidate dataset CSV.")
    ap.add_argument("--lane", required=True, choices=VALID_LANES)
    ap.add_argument("--truth-column", required=True)
    ap.add_argument("--predicted-score-column", default=None)
    ap.add_argument("--predicted-label-column", default=None)
    ap.add_argument("--submitted-by", required=True)
    ap.add_argument("--model-version", required=True,
                    help="Identifier of the model that produced the predictions "
                         "(submitter-supplied; e.g. 'lab_rf_v2.3+commit_abc1234').")
    ap.add_argument("--threshold-version-override", default=None,
                    help="Override auto-resolution (e.g. for non-drinking_water lanes).")
    ap.add_argument("--note", default="")
    args = ap.parse_args()

    project_root = Path(args.project_root).resolve()
    input_path = Path(args.input).resolve()

    sop_row = _validate_lane(project_root, args.lane)
    n_rows = _validate_dataset(input_path, args)
    dataset_sha = _sha256_file(input_path)

    ad_info = _resolve_ad_policy_version(project_root, args.lane)
    thr_info = _resolve_threshold_version(project_root, args.lane)
    if args.threshold_version_override:
        thr_info = {
            "threshold_version": args.threshold_version_override,
            "threshold_path": "override",
        }

    submitted_at = _now_iso()
    submission_id = f"{args.lane}_{submitted_at.replace(':', '').replace('-', '')}_{dataset_sha[:12]}"

    sealed_dir = project_root / "validation" / "blind_external" / "sealed" / submission_id
    if sealed_dir.exists():
        raise SystemExit(
            f"ERROR: sealed directory already exists: {sealed_dir}. "
            "Submissions are immutable — delete only via documented procedure."
        )
    sealed_dir.mkdir(parents=True, exist_ok=False)
    sealed_dataset = sealed_dir / "dataset.csv"
    shutil.copyfile(input_path, sealed_dataset)

    sealed_dataset_sha = _sha256_file(sealed_dataset)
    if sealed_dataset_sha != dataset_sha:
        raise SystemExit(
            "ERROR: dataset hash mismatch after copy; refusing to seal "
            f"(expected {dataset_sha}, got {sealed_dataset_sha})."
        )

    manifest_body = {
        "submission_id": submission_id,
        "dataset_sha256": dataset_sha,
        "submitted_by": args.submitted_by,
        "submitted_at": submitted_at,
        "matrix_lane": args.lane,
        "ad_policy_version": ad_info["ad_model_sha256"],
        "model_version": args.model_version,
        "threshold_version": thr_info["threshold_version"],

        "ad_framework_version": ad_info["ad_framework_version"],
        "training_range_version": ad_info["training_range_version"],
        "ad_model_path": ad_info["ad_model_path"],
        "threshold_path": thr_info["threshold_path"],

        "sop_row": sop_row,
        "n_rows": n_rows,
        "truth_column": args.truth_column,
        "predicted_score_column": args.predicted_score_column or "",
        "predicted_label_column": args.predicted_label_column or "",
        "dataset_path_relative": str(sealed_dataset.relative_to(project_root)).replace("\\", "/"),

        "submission_rules": [
            "No retuning. No threshold change. No model change. No dataset editing after hash submission.",
            "AD enforcement is part of the freeze: ad_policy_version is captured at submit time. "
            "If the AD model changes before reveal, the scorer flags the freeze drift.",
            "The reveal is single-shot: once score_blind_validation.py writes revealed/<id>/score.json, "
            "the result is immutable and registered in reveals_index.jsonl.",
        ],
        "note": args.note,
    }

    payload_no_self = dict(manifest_body)
    payload_bytes = json.dumps(payload_no_self, indent=2, sort_keys=True).encode("utf-8")
    manifest_sha = _sha256_bytes(payload_bytes)
    manifest_body["manifest_sha256"] = manifest_sha

    manifest_path = sealed_dir / "submission.json"
    manifest_path.write_text(json.dumps(manifest_body, indent=2, sort_keys=True), encoding="utf-8")

    seal_lines = [
        f"PFAS blind-validation seal",
        f"=" * 64,
        f"submission_id        : {submission_id}",
        f"submitted_at_utc     : {submitted_at}",
        f"submitted_by         : {args.submitted_by}",
        f"matrix_lane          : {args.lane}",
        f"n_rows               : {n_rows}",
        f"dataset_sha256       : {dataset_sha}",
        f"manifest_sha256      : {manifest_sha}",
        f"ad_policy_version    : {ad_info['ad_model_sha256']}",
        f"model_version        : {args.model_version}",
        f"threshold_version    : {thr_info['threshold_version']}",
        f"truth_column         : {args.truth_column}",
        f"predicted_score_col  : {args.predicted_score_column or '(none)'}",
        f"predicted_label_col  : {args.predicted_label_column or '(none)'}",
        "",
        "Sealed contents are integrity-checked at score time. Editing the",
        "dataset or manifest will cause score_blind_validation.py to refuse.",
        "",
        "To score this submission (must run AFTER any freeze interval):",
        f"  python scripts/score_blind_validation.py --submission-id {submission_id}",
    ]
    (sealed_dir / "SEAL.txt").write_text("\n".join(seal_lines) + "\n", encoding="utf-8")

    for f in (sealed_dataset, manifest_path, sealed_dir / "SEAL.txt"):
        _make_readonly(f)

    idx_path = project_root / "validation" / "blind_external" / "manifests" / "submissions_index.jsonl"
    idx_path.parent.mkdir(parents=True, exist_ok=True)
    with idx_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps({
            "submission_id": submission_id,
            "submitted_at": submitted_at,
            "submitted_by": args.submitted_by,
            "matrix_lane": args.lane,
            "dataset_sha256": dataset_sha,
            "manifest_sha256": manifest_sha,
            "ad_policy_version": ad_info["ad_model_sha256"],
            "model_version": args.model_version,
            "threshold_version": thr_info["threshold_version"],
            "n_rows": n_rows,
        }, ensure_ascii=False) + "\n")

    print(json.dumps({
        "status": "sealed",
        "submission_id": submission_id,
        "sealed_dir": str(sealed_dir.relative_to(project_root)).replace("\\", "/"),
        "dataset_sha256": dataset_sha,
        "manifest_sha256": manifest_sha,
        "n_rows": n_rows,
        "matrix_lane": args.lane,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
