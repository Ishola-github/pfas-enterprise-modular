"""
Score a sealed blind-validation submission.

This is the *scorer side* of the harness. The scorer is single-shot: once
score_blind_validation.py writes validation/blind_external/revealed/<id>/score.json,
that file is the immutable result.

Workflow:

    1. Locate sealed/<submission_id>/{dataset.csv, submission.json}.
    2. Re-verify dataset_sha256 == sha256(sealed_dataset). REFUSE if mismatch.
    3. Re-verify manifest_sha256 by re-canonicalizing the manifest minus the
       manifest_sha256 field. REFUSE if mismatch.
    4. Re-resolve ad_policy_version from data/ad_models/<lane>/ad_model.json.
       If different from sealed value, flag "freeze_drift_ad_policy" in the
       reveal (does not refuse — scoring still runs, but the drift is
       recorded so the result cannot silently misrepresent the freeze).
    5. Re-resolve threshold_version similarly; flag drift if different.
    6. AD-gate the dataset (scripts/apply_ad_guard.py --mode annotate, so we
       can compute metrics on in-domain rows without permanently mutating the
       sealed file).
    7. Compute the nine metrics required by the harness:
           roc_auc, precision, recall, f1, flags_per_10k, FP_per_TP,
           ad_reject_count, ad_warning_count, ad_in_domain_count
    8. Write revealed/<id>/score.json (immutable). Append to
       reveals_index.jsonl.

Re-running the scorer on the same submission produces byte-identical results
(scoring is deterministic for a fixed (dataset, model_version, ad_policy_version,
threshold_version) tuple).

A reveal can be overwritten only by passing --force, which is recorded in the
audit log; in practice this should only be used to re-score after a documented
freeze drift, and the prior reveal is preserved in revealed/<id>/score_prior_*.json.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

REQUIRED_METRICS = (
    "roc_auc",
    "precision",
    "recall",
    "f1",
    "flags_per_10k",
    "FP_per_TP",
    "ad_reject_count",
    "ad_warning_count",
    "ad_in_domain_count",
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


def _coerce_binary_label(value: Any) -> int | None:
    f = _coerce_float(value)
    if f is None:
        return None
    if f in (0.0, 1.0):
        return int(f)
    return None


def _make_readonly(path: Path) -> None:
    try:
        mode = path.stat().st_mode
        path.chmod(mode & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)
        if os.name == "nt":
            os.system(f'attrib +R "{path}" >NUL 2>&1')
    except Exception:
        pass


def _roc_auc(y_true: list[int], y_score: list[float]) -> float | None:
    """Pairwise AUC (Mann-Whitney U). O(n^2) but stable; OK for blind-val sizes."""
    pos = [s for t, s in zip(y_true, y_score) if t == 1]
    neg = [s for t, s in zip(y_true, y_score) if t == 0]
    if not pos or not neg:
        return None
    total = 0.0
    for p in pos:
        for n in neg:
            if p > n:
                total += 1.0
            elif p == n:
                total += 0.5
    return total / (len(pos) * len(neg))


def _confusion(y_true: list[int], y_pred: list[int]) -> dict[str, int]:
    tp = fp = tn = fn = 0
    for t, p in zip(y_true, y_pred):
        if t == 1 and p == 1:
            tp += 1
        elif t == 0 and p == 1:
            fp += 1
        elif t == 0 and p == 0:
            tn += 1
        elif t == 1 and p == 0:
            fn += 1
    return {"tp": tp, "fp": fp, "tn": tn, "fn": fn}


def _verify_manifest_sha(manifest: dict[str, Any]) -> tuple[bool, str, str]:
    """Recompute manifest_sha256 by canonicalizing the manifest minus that
    field. Returns (ok, expected, actual)."""
    expected = manifest.get("manifest_sha256", "")
    body = {k: v for k, v in manifest.items() if k != "manifest_sha256"}
    actual = _sha256_bytes(json.dumps(body, indent=2, sort_keys=True).encode("utf-8"))
    return (expected == actual, expected, actual)


def _resolve_ad_policy_now(project_root: Path, lane: str) -> str:
    p = project_root / "data" / "ad_models" / lane / "ad_model.json"
    if not p.is_file():
        return ""
    return _sha256_file(p)


def _resolve_threshold_now(project_root: Path, lane: str) -> str:
    candidates = {"drinking_water": "data/config/ucmr_analyte_limits_ngl.csv"}
    rel = candidates.get(lane)
    if not rel:
        return "none"
    p = project_root / rel
    if not p.is_file():
        return "none"
    return _sha256_file(p)


def _run_ad_guard(project_root: Path, dataset: Path, lane: str) -> tuple[Path, dict[str, int]]:
    """Run scripts/apply_ad_guard.py in annotate mode against a temp output."""
    tmp = Path(tempfile.mkdtemp(prefix="pfas_blind_ad_"))
    out_csv = tmp / "ad_annotated.csv"
    cmd = [
        sys.executable,
        str(project_root / "scripts" / "apply_ad_guard.py"),
        "--project-root", str(project_root),
        "--lane", lane,
        "--input", str(dataset),
        "--output", str(out_csv),
        "--mode", "annotate",
        "--no-audit",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise SystemExit(
            "ERROR: AD guard subprocess failed during scoring.\n"
            f"  stdout: {proc.stdout}\n  stderr: {proc.stderr}"
        )
    counts = {"in_domain": 0, "warning": 0, "reject": 0, "no_lane": 0}
    try:
        first = proc.stdout.find("{")
        if first >= 0:
            summary = json.loads(proc.stdout[first:])
            for k, v in (summary.get("counts") or {}).items():
                counts[k] = int(v)
    except Exception:
        pass
    return out_csv, counts


def _score_rows(
    annotated_csv: Path,
    truth_col: str,
    score_col: str | None,
    label_col: str | None,
) -> dict[str, Any]:
    y_true_all: list[int] = []
    y_score_all: list[float | None] = []
    y_pred_all: list[int | None] = []
    ad_status_all: list[str] = []

    with annotated_csv.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            t = _coerce_binary_label(row.get(truth_col))
            if t is None:
                continue
            y_true_all.append(t)

            s = _coerce_float(row.get(score_col)) if score_col else None
            y_score_all.append(s)

            if label_col:
                p_lab = _coerce_binary_label(row.get(label_col))
            elif s is not None:
                p_lab = 1 if s >= 0.5 else 0
            else:
                p_lab = None
            y_pred_all.append(p_lab)

            ad_status_all.append((row.get("ad_status") or "").strip())

    in_dom_idx = [i for i, s in enumerate(ad_status_all) if s == "in_domain"]
    y_true = [y_true_all[i] for i in in_dom_idx]
    y_score_in = [y_score_all[i] for i in in_dom_idx]
    y_pred = [y_pred_all[i] for i in in_dom_idx]

    auc = None
    if score_col and any(s is not None for s in y_score_in):
        y_score_clean = [(t, s) for t, s in zip(y_true, y_score_in) if s is not None]
        if y_score_clean:
            yt = [t for t, _ in y_score_clean]
            ys = [s for _, s in y_score_clean]
            auc = _roc_auc(yt, ys)

    valid_pairs = [(t, p) for t, p in zip(y_true, y_pred) if p is not None]
    confusion: dict[str, int] = {"tp": 0, "fp": 0, "tn": 0, "fn": 0}
    if valid_pairs:
        yt = [t for t, _ in valid_pairs]
        yp = [p for _, p in valid_pairs]
        confusion = _confusion(yt, yp)

    tp, fp, fn = confusion["tp"], confusion["fp"], confusion["fn"]
    precision = tp / (tp + fp) if (tp + fp) > 0 else None
    recall    = tp / (tp + fn) if (tp + fn) > 0 else None
    f1 = (2 * precision * recall / (precision + recall)
          if precision is not None and recall is not None and (precision + recall) > 0
          else None)

    n_scored = len(valid_pairs)
    flags = tp + fp
    flags_per_10k = (flags * 10000.0 / n_scored) if n_scored > 0 else None
    fp_per_tp = (fp / tp) if tp > 0 else (float("inf") if fp > 0 else None)

    return {
        "n_rows_total": len(y_true_all),
        "n_rows_in_domain": len(in_dom_idx),
        "n_rows_scored": n_scored,
        "confusion": confusion,
        "metrics": {
            "roc_auc": auc,
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "flags_per_10k": flags_per_10k,
            "FP_per_TP": fp_per_tp,
        },
    }


def _list_submissions(project_root: Path) -> int:
    sealed_root = project_root / "validation" / "blind_external" / "sealed"
    if not sealed_root.is_dir():
        print("No sealed submissions yet.")
        return 0
    items = sorted(p.name for p in sealed_root.iterdir() if p.is_dir())
    print(json.dumps({"sealed_submissions": items, "count": len(items)}, indent=2))
    return 0


def _archive_prior_reveal(reveal_dir: Path) -> Path | None:
    prior = reveal_dir / "score.json"
    if not prior.is_file():
        return None
    archived = reveal_dir / f"score_prior_{_now_iso().replace(':', '').replace('-', '')}.json"
    prior.replace(archived)
    return archived


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1] if __doc__ else "Score blind validation")
    ap.add_argument("--project-root", default=".")
    ap.add_argument("--submission-id", default=None,
                    help="Submission identifier (sealed folder name). Required unless --list.")
    ap.add_argument("--list", action="store_true",
                    help="List sealed submissions and exit.")
    ap.add_argument("--force", action="store_true",
                    help="Overwrite an existing reveal (prior reveal is archived alongside).")
    args = ap.parse_args()

    project_root = Path(args.project_root).resolve()
    if args.list:
        return _list_submissions(project_root)
    if not args.submission_id:
        print("ERROR: --submission-id is required (or pass --list).", file=sys.stderr)
        return 2

    sealed_dir = project_root / "validation" / "blind_external" / "sealed" / args.submission_id
    dataset = sealed_dir / "dataset.csv"
    manifest_path = sealed_dir / "submission.json"
    if not sealed_dir.is_dir() or not dataset.is_file() or not manifest_path.is_file():
        print(f"ERROR: sealed submission not found / incomplete: {sealed_dir}", file=sys.stderr)
        return 2

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    actual_data_sha = _sha256_file(dataset)
    expected_data_sha = manifest.get("dataset_sha256", "")
    if actual_data_sha != expected_data_sha:
        print(json.dumps({
            "status": "REFUSED",
            "reason": "dataset_sha256_mismatch",
            "expected": expected_data_sha,
            "actual": actual_data_sha,
            "note": "Sealed dataset has been altered; reveal refused.",
        }, indent=2))
        return 3

    ok, exp_m, act_m = _verify_manifest_sha(manifest)
    if not ok:
        print(json.dumps({
            "status": "REFUSED",
            "reason": "manifest_sha256_mismatch",
            "expected": exp_m,
            "actual": act_m,
            "note": "Sealed manifest has been altered; reveal refused.",
        }, indent=2))
        return 3

    lane = manifest["matrix_lane"]
    truth_col = manifest["truth_column"]
    score_col = manifest.get("predicted_score_column") or None
    label_col = manifest.get("predicted_label_column") or None

    ad_now = _resolve_ad_policy_now(project_root, lane)
    ad_drift = ad_now != manifest.get("ad_policy_version", "")
    thr_now = _resolve_threshold_now(project_root, lane)
    thr_drift = thr_now != manifest.get("threshold_version", "")

    annotated_csv, ad_counts = _run_ad_guard(project_root, dataset, lane)
    score_block = _score_rows(annotated_csv, truth_col, score_col, label_col)

    metrics_payload: dict[str, Any] = {
        **score_block["metrics"],
        "flags_per_10k": score_block["metrics"]["flags_per_10k"],
        "FP_per_TP": score_block["metrics"]["FP_per_TP"],
        "ad_reject_count": int(ad_counts.get("reject", 0)),
        "ad_warning_count": int(ad_counts.get("warning", 0)),
        "ad_in_domain_count": int(ad_counts.get("in_domain", 0)),
    }

    reveal_dir = project_root / "validation" / "blind_external" / "revealed" / args.submission_id
    reveal_dir.mkdir(parents=True, exist_ok=True)
    if (reveal_dir / "score.json").is_file() and not args.force:
        print(json.dumps({
            "status": "ALREADY_REVEALED",
            "submission_id": args.submission_id,
            "reveal_path": str((reveal_dir / "score.json").relative_to(project_root)).replace("\\", "/"),
            "note": ("This submission has already been scored. Reveals are single-shot. "
                     "Pass --force to re-score (the prior reveal is archived alongside)."),
        }, indent=2))
        return 0

    archived_path = _archive_prior_reveal(reveal_dir) if args.force else None

    reveal_payload = {
        "status": "REVEALED",
        "submission_id": args.submission_id,
        "revealed_at_utc": _now_iso(),
        "sealed_manifest": manifest,
        "seal_verification": {
            "dataset_sha256_match": True,
            "manifest_sha256_match": True,
            "ad_policy_version_at_reveal": ad_now,
            "ad_policy_drift": ad_drift,
            "threshold_version_at_reveal": thr_now,
            "threshold_drift": thr_drift,
        },
        "ad_counts": ad_counts,
        "score_block": score_block,
        "metrics": metrics_payload,
        "required_metric_fields_present": sorted(
            [k for k in REQUIRED_METRICS if k in metrics_payload]
        ),
        "ground_rules": [
            "No retuning. No threshold change. No model change. No dataset editing after hash submission.",
        ],
        "forced_overwrite": bool(args.force),
        "prior_reveal_archived": (
            str(archived_path.relative_to(project_root)).replace("\\", "/") if archived_path else None
        ),
    }
    if ad_drift or thr_drift:
        drift_reasons = []
        if ad_drift:
            drift_reasons.append(f"ad_policy drifted: sealed={manifest.get('ad_policy_version','')[:12]} now={ad_now[:12]}")
        if thr_drift:
            drift_reasons.append(f"threshold drifted: sealed={manifest.get('threshold_version','')[:12]} now={thr_now[:12]}")
        reveal_payload["freeze_drift_warnings"] = drift_reasons

    out_path = reveal_dir / "score.json"
    out_path.write_text(json.dumps(reveal_payload, indent=2, sort_keys=True), encoding="utf-8")
    _make_readonly(out_path)

    idx_path = project_root / "validation" / "blind_external" / "manifests" / "reveals_index.jsonl"
    idx_path.parent.mkdir(parents=True, exist_ok=True)
    with idx_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps({
            "submission_id": args.submission_id,
            "revealed_at_utc": reveal_payload["revealed_at_utc"],
            "matrix_lane": lane,
            "metrics": metrics_payload,
            "ad_policy_drift": ad_drift,
            "threshold_drift": thr_drift,
            "forced_overwrite": bool(args.force),
            "dataset_sha256": manifest.get("dataset_sha256", ""),
            "manifest_sha256": manifest.get("manifest_sha256", ""),
        }, ensure_ascii=False) + "\n")

    try:
        annotated_csv.parent.rmdir() if not any(annotated_csv.parent.iterdir()) else None
    except Exception:
        pass
    try:
        annotated_csv.unlink()
    except Exception:
        pass

    print(json.dumps({
        "status": "REVEALED",
        "submission_id": args.submission_id,
        "reveal_path": str(out_path.relative_to(project_root)).replace("\\", "/"),
        "metrics": metrics_payload,
        "ad_policy_drift": ad_drift,
        "threshold_drift": thr_drift,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
