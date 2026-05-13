#!/usr/bin/env python3
"""Emit a single JSON governance roll-up for CI / operators (stdlib only).

Mirrors the Shiny tab **Governance & lineage** (LatestPFAS.R): matrix
inventory, per-lane manifest hints, registry summary, UCMR threshold
file hash, scope-freeze v1.0 manifest (if present), AD audit tail
aggregates, blind-validation index tail, recent ``results/`` files, and
SQLite ``audit_log`` / ``upload_validation_run`` tails when
``pfas_collection.sqlite`` exists.

Usage:
    python scripts/governance_operational_snapshot.py
    python scripts/governance_operational_snapshot.py --project-root /path/to/repo
    python scripts/governance_operational_snapshot.py --pretty
    python scripts/governance_operational_snapshot.py --strict      # CI / governed runs

Default mode is **non-blocking**: structural problems are reported in
the ``warnings`` array and the exit code is **0** so
``docker_verify_linux.sh`` can append this step without failing the
overall harness when optional assets are missing.

With ``--strict``, a non-empty ``warnings`` array causes exit code
**2** and a stderr summary listing each warning. Use this in CI for
release / governance promotion runs.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sqlite3
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


SCHEMA = "governance_operational_snapshot/v1"


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _load_sop(root: Path) -> tuple[List[Dict[str, str]], List[str]]:
    sop = root / "data" / "config" / "matrix_pipeline_sop.csv"
    if not sop.is_file():
        return [], [f"missing:{sop.as_posix()}"]
    warns: List[str] = []
    rows: List[Dict[str, str]] = []
    with sop.open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for r in reader:
            rows.append({k: (v or "").strip() for k, v in r.items()})
    return rows, warns


def _load_ad_index(root: Path) -> tuple[Optional[Dict[str, Dict[str, Any]]], List[str]]:
    idx = root / "data" / "ad_models" / "index.json"
    warns: List[str] = []
    if not idx.is_file():
        warns.append(f"missing:{idx.as_posix()}")
        return None, warns
    try:
        data = _read_json(idx)
    except (OSError, json.JSONDecodeError) as exc:
        warns.append(f"ad_index_parse_error:{exc}")
        return None, warns
    lanes = data.get("lanes") if isinstance(data, dict) else None
    if not isinstance(lanes, list):
        warns.append("ad_index_missing_lanes_array")
        return None, warns
    by_lane: Dict[str, Dict[str, Any]] = {}
    for item in lanes:
        if not isinstance(item, dict):
            continue
        pl = str(item.get("pipeline_lane") or "").strip()
        if pl:
            by_lane[pl] = item
    return by_lane, warns


def build_matrix_inventory(root: Path) -> tuple[List[Dict[str, Any]], List[str]]:
    sop_rows, warns = _load_sop(root)
    by_lane, w2 = _load_ad_index(root)
    warns.extend(w2)
    out: List[Dict[str, Any]] = []
    for r in sop_rows:
        pid = (r.get("pipeline_id") or r.get("Pipeline ID") or "").strip()
        mat = (r.get("matrix") or "").strip()
        cds = (r.get("canonical_datasets") or "").strip()
        ad = (by_lane or {}).get(pid, {})
        sha = str(ad.get("ad_model_sha256") or "")
        out.append(
            {
                "matrix": mat,
                "pipeline_id": pid,
                "canonical_datasets": cds,
                "ad_index_status": ad.get("status"),
                "ad_method": ad.get("ad_method"),
                "ad_model_version": ad.get("ad_model_version"),
                "ad_model_sha12": sha[:12] if sha else None,
            }
        )
    return out, warns


def _parse_training_manifest(man_path: Path) -> tuple[Optional[Dict[str, Any]], Optional[str]]:
    if not man_path.is_file():
        return None, None
    try:
        mj = _read_json(man_path)
    except (OSError, json.JSONDecodeError) as exc:
        return None, str(exc)
    if not isinstance(mj, dict):
        return None, "not_a_dict"
    notes = mj.get("notes")
    notes_str: Optional[str]
    if isinstance(notes, list):
        notes_str = " | ".join(str(x) for x in notes)
    elif notes is not None:
        notes_str = str(notes)
    else:
        notes_str = None
    return (
        {
            "rows_written": mj.get("rows_written"),
            "generated_at_utc": mj.get("generated_at_utc"),
            "notes": notes_str,
        },
        None,
    )


def build_manifest_status(root: Path) -> tuple[List[Dict[str, Any]], List[str]]:
    sop_rows, warns = _load_sop(root)
    out: List[Dict[str, Any]] = []
    for r in sop_rows:
        pid = (r.get("pipeline_id") or "").strip()
        if not pid:
            continue
        man_path = root / "data" / "training" / pid / "manifest.json"
        train_csv = root / "data" / "training" / pid / "training.csv"
        row: Dict[str, Any] = {
            "pipeline_id": pid,
            "matrix": (r.get("matrix") or "").strip(),
            "manifest_exists": man_path.is_file(),
            "training_csv_exists": train_csv.is_file(),
            "rows_written": None,
            "generated_at_utc": None,
            "notes": None,
        }
        parsed, err = _parse_training_manifest(man_path)
        if err:
            warns.append(f"manifest_unreadable:{pid}:{err}")
        elif parsed:
            row["rows_written"] = parsed["rows_written"]
            row["generated_at_utc"] = parsed["generated_at_utc"]
            row["notes"] = parsed["notes"]
        out.append(row)
    return out, warns


def registry_summary(root: Path) -> tuple[Dict[str, Any], List[str]]:
    reg = root / "data" / "reference" / "registry" / "reference_registry.csv"
    warns: List[str] = []
    if not reg.is_file():
        return {"row_count": 0, "path": None}, [f"missing:{reg.as_posix()}"]
    with reg.open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        fieldnames = reader.fieldnames or []
        rows = list(reader)
    keep = [
        c
        for c in (
            "source_org",
            "document_type",
            "document_id",
            "matrix_domain",
            "local_path",
            "sha256",
            "intended_use",
        )
        if c in fieldnames
    ]
    sample = []
    for r in rows[:5]:
        sample.append({k: (r.get(k) or "")[:200] for k in keep})
    return (
        {
            "path": reg.as_posix(),
            "row_count": len(rows),
            "columns": keep,
            "sample_rows": sample,
        },
        warns,
    )


def threshold_block(root: Path) -> tuple[Dict[str, Any], List[str]]:
    warns: List[str] = []
    ucmr = root / "data" / "config" / "ucmr_analyte_limits_ngl.csv"
    if not ucmr.is_file():
        return {"path": None, "sha256": None, "threshold_version_prefix": None}, [
            f"missing:{ucmr.as_posix()}"
        ]
    h = _sha256_file(ucmr)
    return (
        {
            "path": ucmr.as_posix(),
            "sha256": h,
            "threshold_version_prefix": h[:12],
        },
        warns,
    )


def scope_freeze_block(root: Path) -> tuple[Optional[Dict[str, Any]], List[str]]:
    mf = root / "validation" / "scope_freeze" / "v1.0" / "freeze_manifest.json"
    warns: List[str] = []
    if not mf.is_file():
        return None, warns
    try:
        data = _read_json(mf)
    except (OSError, json.JSONDecodeError) as exc:
        warns.append(f"scope_freeze_unreadable:{exc}")
        return None, warns
    if not isinstance(data, dict):
        return None, warns
    return (
        {
            "path": mf.as_posix(),
            "status": data.get("status"),
            "git_head_sha": data.get("git_head_sha"),
            "built_at_utc": data.get("built_at_utc"),
            "operator": data.get("operator"),
            "scientific_reviewer": data.get("scientific_reviewer"),
        },
        warns,
    )


def ad_audit_trends(root: Path, tail_n: int = 5000) -> tuple[Dict[str, Any], List[str]]:
    warns: List[str] = []
    path = root / "data" / "audit" / "ad_decisions.jsonl"
    if not path.is_file():
        return {"tail_lines_read": 0, "aggregate": []}, warns
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        warns.append(f"ad_audit_read_error:{exc}")
        return {"tail_lines_read": 0, "aggregate": []}, warns
    if len(lines) > tail_n:
        lines = lines[-tail_n:]
    ctr: Counter[tuple[str, str]] = Counter()
    bad = 0
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            bad += 1
            continue
        if not isinstance(rec, dict):
            bad += 1
            continue
        lane = str(rec.get("reference_lane") or rec.get("pipeline_lane") or "")
        st = str(rec.get("ad_status") or "")
        ctr[(lane, st)] += 1
    agg = [
        {"reference_lane": a, "ad_status": b, "n": n}
        for (a, b), n in sorted(ctr.items(), key=lambda x: (x[0][0], x[0][1]))
    ]
    out = {"tail_lines_read": len(lines), "json_parse_errors": bad, "aggregate": agg}
    if bad:
        warns.append(f"ad_audit_json_parse_errors:{bad}")
    return out, warns


def blind_tail(root: Path, n: int = 15) -> tuple[List[str], List[str]]:
    p = root / "validation" / "blind_external" / "manifests" / "submissions_index.jsonl"
    if not p.is_file():
        return [], []
    lines = p.read_text(encoding="utf-8").splitlines()
    return lines[-n:], []


def results_recent(root: Path, limit: int = 20) -> tuple[List[Dict[str, Any]], List[str]]:
    rd = root / "results"
    if not rd.is_dir():
        return [], []
    out: List[Dict[str, Any]] = []
    for p in sorted(rd.iterdir(), key=lambda x: x.stat().st_mtime, reverse=True):
        if not p.is_file():
            continue
        if p.suffix.lower() not in (".json", ".csv"):
            continue
        st = p.stat()
        out.append(
            {
                "file": p.name,
                "modified_utc": datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                ),
                "bytes": st.st_size,
            }
        )
        if len(out) >= limit:
            break
    return out, []


def sqlite_blocks(root: Path) -> tuple[Dict[str, Any], List[str]]:
    warns: List[str] = []
    db = root / "pfas_collection.sqlite"
    if not db.is_file():
        return {
            "database_path": None,
            "audit_log_tail": [],
            "upload_validation_tail": [],
            "ingestion_failures": [],
        }, warns
    out: Dict[str, Any] = {
        "database_path": db.as_posix(),
        "audit_log_tail": [],
        "upload_validation_tail": [],
        "ingestion_failures": [],
    }
    try:
        con = sqlite3.connect(str(db))
        con.row_factory = sqlite3.Row
    except sqlite3.Error as exc:
        warns.append(f"sqlite_connect_error:{exc}")
        return out, warns
    try:
        cur = con.cursor()
        cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
            "('audit_log','upload_validation_run')"
        )
        have = {row[0] for row in cur.fetchall()}
        if "audit_log" in have:
            cur.execute(
                "SELECT audit_id, entity_type, entity_id, action_type, changed_by, "
                "changed_at, change_notes FROM audit_log ORDER BY changed_at DESC LIMIT 80"
            )
            out["audit_log_tail"] = [dict(r) for r in cur.fetchall()]
        else:
            warns.append("sqlite_missing_table:audit_log")
        if "upload_validation_run" in have:
            cur.execute(
                "SELECT run_id, phase, status, validated_at, validated_by, file_name, "
                "row_count, rows_pass, rows_fail FROM upload_validation_run "
                "ORDER BY validated_at DESC LIMIT 40"
            )
            out["upload_validation_tail"] = [dict(r) for r in cur.fetchall()]
            cur.execute(
                "SELECT run_id, phase, status, validated_at, validated_by, file_name, "
                "row_count, rows_pass, rows_fail FROM upload_validation_run "
                "WHERE (LOWER(status) NOT IN ('ok','pass','passed','success')) "
                "OR (rows_fail IS NOT NULL AND rows_fail > 0) "
                "ORDER BY validated_at DESC LIMIT 30"
            )
            out["ingestion_failures"] = [dict(r) for r in cur.fetchall()]
        else:
            warns.append("sqlite_missing_table:upload_validation_run")
    except sqlite3.Error as exc:
        warns.append(f"sqlite_query_error:{exc}")
    finally:
        con.close()
    return out, warns


def build_snapshot(root: Path, ad_tail: int) -> Dict[str, Any]:
    warnings: List[str] = []
    mi, w1 = build_matrix_inventory(root)
    warnings.extend(w1)
    ms, w2 = build_manifest_status(root)
    warnings.extend(w2)
    reg, w3 = registry_summary(root)
    warnings.extend(w3)
    th, w4 = threshold_block(root)
    warnings.extend(w4)
    sf, w5 = scope_freeze_block(root)
    warnings.extend(w5)
    ad, w6 = ad_audit_trends(root, tail_n=ad_tail)
    warnings.extend(w6)
    lines, w7 = blind_tail(root)
    warnings.extend(w7)
    rr, w8 = results_recent(root)
    warnings.extend(w8)
    sql, w9 = sqlite_blocks(root)
    warnings.extend(w9)

    return {
        "schema": SCHEMA,
        "generated_at_utc": _utc_now(),
        "project_root": root.resolve().as_posix(),
        "matrix_inventory": mi,
        "manifest_status": ms,
        "registry": reg,
        "threshold_ucmr_limits": th,
        "scope_freeze_v1": sf,
        "ad_audit_trends": ad,
        "blind_submissions_index_tail": lines,
        "results_recent": rr,
        "sqlite": sql,
        "warnings": sorted(set(warnings)),
    }


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "--project-root",
        type=Path,
        default=Path.cwd(),
        help="Repository root (default: current working directory)",
    )
    ap.add_argument(
        "--ad-tail",
        type=int,
        default=5000,
        help="Max lines to read from ad_decisions.jsonl from end of file (default: 5000)",
    )
    ap.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print JSON (two-space indent)",
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help=(
            "Exit with code 2 when 'warnings' is non-empty. Use in CI / governance "
            "promotion runs. Default mode stays non-blocking (exit 0) so a bare "
            "checkout without optional assets still runs cleanly."
        ),
    )
    args = ap.parse_args(argv)
    root = args.project_root.resolve()
    snap = build_snapshot(root, ad_tail=args.ad_tail)
    indent = 2 if args.pretty else None
    print(json.dumps(snap, indent=indent) + ("\n" if indent is None else ""))
    warnings_list = snap.get("warnings") or []
    if args.strict and warnings_list:
        print(
            f"\nERROR: --strict mode and snapshot reports {len(warnings_list)} warning(s):",
            file=sys.stderr,
        )
        for w in warnings_list:
            print(f"  - {w}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
