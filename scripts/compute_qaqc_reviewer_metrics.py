"""
Compute blinded reviewer-vs-engine QA/QC validation metrics.

Inputs:
  - reviewer comparison CSV with columns:
      study_id,batch_id,reviewer_a_decision,reviewer_b_decision,
      engine_decision,consensus_decision,escalated_to_human

Outputs:
  - agreement_pct
  - cohens_kappa (engine vs consensus)
  - false_positive_rate (fail class)
  - false_negative_rate (fail class)
  - escalation_rate
  - missed_failure_rate
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
from pathlib import Path
from typing import Any

ALLOWED_DECISIONS = {"pass", "warning", "fail"}


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _norm_decision(value: Any) -> str:
    return str(value or "").strip().lower()


def _norm_bool(value: Any) -> bool:
    s = str(value or "").strip().lower()
    return s in {"1", "true", "yes", "y"}


def _safe_rate(numer: int, denom: int) -> float | None:
    if denom <= 0:
        return None
    return numer / denom


def _cohens_kappa(labels_a: list[str], labels_b: list[str]) -> float | None:
    if not labels_a or not labels_b or len(labels_a) != len(labels_b):
        return None
    n = len(labels_a)
    if n == 0:
        return None

    categories = sorted(set(labels_a) | set(labels_b))
    if not categories:
        return None

    observed_matches = sum(1 for a, b in zip(labels_a, labels_b) if a == b)
    p_o = observed_matches / n

    p_e = 0.0
    for c in categories:
        p_a = sum(1 for x in labels_a if x == c) / n
        p_b = sum(1 for x in labels_b if x == c) / n
        p_e += p_a * p_b

    if p_e >= 1.0:
        return None
    return (p_o - p_e) / (1.0 - p_e)


def _load_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        return [{str(k): (v or "") for k, v in row.items()} for row in reader]


def _derive_consensus(row: dict[str, str]) -> str:
    explicit = _norm_decision(row.get("consensus_decision"))
    if explicit in ALLOWED_DECISIONS:
        return explicit

    a = _norm_decision(row.get("reviewer_a_decision"))
    b = _norm_decision(row.get("reviewer_b_decision"))
    if a in ALLOWED_DECISIONS and b in ALLOWED_DECISIONS and a == b:
        return a
    return ""


def compute_metrics(rows: list[dict[str, str]]) -> dict[str, Any]:
    engine_vs_consensus_pairs: list[tuple[str, str]] = []
    escalation_count = 0
    fp_count = 0
    fn_count = 0
    missed_failure_count = 0
    consensus_fail_count = 0
    consensus_non_fail_count = 0

    for row in rows:
        engine = _norm_decision(row.get("engine_decision"))
        consensus = _derive_consensus(row)
        escalated = _norm_bool(row.get("escalated_to_human"))
        if escalated:
            escalation_count += 1

        if engine in ALLOWED_DECISIONS and consensus in ALLOWED_DECISIONS:
            engine_vs_consensus_pairs.append((engine, consensus))

            if consensus == "fail":
                consensus_fail_count += 1
                if engine != "fail":
                    fn_count += 1
                if engine == "pass":
                    missed_failure_count += 1
            else:
                consensus_non_fail_count += 1
                if engine == "fail":
                    fp_count += 1

    compared_n = len(engine_vs_consensus_pairs)
    agreement_matches = sum(1 for e, c in engine_vs_consensus_pairs if e == c)
    agreement_pct = _safe_rate(agreement_matches, compared_n)

    labels_engine = [e for e, _ in engine_vs_consensus_pairs]
    labels_consensus = [c for _, c in engine_vs_consensus_pairs]
    kappa = _cohens_kappa(labels_engine, labels_consensus)

    out = {
        "generated_utc": _now_iso(),
        "rows_total": len(rows),
        "rows_compared": compared_n,
        "agreement_pct": (agreement_pct * 100.0) if agreement_pct is not None else None,
        "cohens_kappa": kappa,
        "false_positive_rate": _safe_rate(fp_count, consensus_non_fail_count),
        "false_negative_rate": _safe_rate(fn_count, consensus_fail_count),
        "escalation_rate": _safe_rate(escalation_count, len(rows)),
        "missed_failure_rate": _safe_rate(missed_failure_count, consensus_fail_count),
        "counts": {
            "agreement_matches": agreement_matches,
            "consensus_fail_count": consensus_fail_count,
            "consensus_non_fail_count": consensus_non_fail_count,
            "false_positives": fp_count,
            "false_negatives": fn_count,
            "missed_failures": missed_failure_count,
            "escalations": escalation_count,
        },
    }
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Compute EPA1633 QA/QC reviewer metrics.")
    ap.add_argument(
        "--input-csv",
        default="validation/studies/epa1633_qaqc_v1/reviewer_comparison_template.csv",
        help="Path to reviewer comparison CSV.",
    )
    ap.add_argument(
        "--out-json",
        default="validation/studies/epa1633_qaqc_v1/reviewer_metrics_summary.json",
        help="Output JSON metrics path.",
    )
    args = ap.parse_args()

    input_csv = Path(args.input_csv).resolve()
    out_json = Path(args.out_json).resolve()
    if not input_csv.is_file():
        raise SystemExit(f"ERROR: input CSV not found: {input_csv}")

    rows = _load_rows(input_csv)
    metrics = compute_metrics(rows)

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(metrics, indent=2, sort_keys=True))
    print(f"WROTE {out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
