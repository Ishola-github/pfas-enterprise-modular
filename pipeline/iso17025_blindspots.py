"""
ISO/IEC 17025-aligned readiness support — scoring and reporting only.
Not laboratory accreditation and not a claim of ISO compliance.
"""
from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

import pandas as pd

PENALTIES = {
    "CRITICAL": 20,
    "HIGH": 10,
    "MEDIUM": 5,
    "LOW": 2,
    "INFO": 0,
}

# Canonical labels (display). Input status is matched case-insensitively.
STATUS_OPEN = "open"
STATUS_IN_PROGRESS = "in_progress"
STATUS_MITIGATED = "mitigated"
STATUS_CLOSED = "closed"
STATUS_NOT_APPLICABLE = "not_applicable"


def _norm_status(raw: object) -> str:
    if raw is None or (isinstance(raw, str) is False and pd.isna(raw)):
        return STATUS_OPEN
    s = str(raw).strip().lower()
    s = re.sub(r"[\s_]+", " ", s)
    if not s or s in ("open",):
        return STATUS_OPEN
    if s in ("in progress", "in-progress", "inprogress"):
        return STATUS_IN_PROGRESS
    if s in ("mitigated", "partially mitigated"):
        return STATUS_MITIGATED
    if s in ("closed", "complete", "completed"):
        return STATUS_CLOSED
    if s in ("not applicable", "not-applicable", "n/a", "na", "none"):
        return STATUS_NOT_APPLICABLE
    return s or STATUS_OPEN


def _display_status(canonical: str) -> str:
    return {
        STATUS_OPEN: "Open",
        STATUS_IN_PROGRESS: "In Progress",
        STATUS_MITIGATED: "Mitigated",
        STATUS_CLOSED: "Closed",
        STATUS_NOT_APPLICABLE: "Not Applicable",
    }.get(canonical, canonical.replace("_", " ").title())


def _base_penalty(severity: str) -> int:
    return int(PENALTIES.get(str(severity).upper().strip(), 0))


def _penalty_for_status(canonical_status: str, base: int) -> float:
    """Strict scoring: Open full; In Progress half; Mitigated small; Closed / N/A base 0."""
    if base <= 0:
        return 0.0
    if canonical_status == STATUS_OPEN:
        return float(base)
    if canonical_status == STATUS_IN_PROGRESS:
        return float(base) / 2.0
    if canonical_status == STATUS_MITIGATED:
        # Small but non-zero when severity had a positive weight
        return max(1.0, float(base) / 4.0)
    if canonical_status in (STATUS_CLOSED, STATUS_NOT_APPLICABLE):
        return 0.0
    # Unknown status: treat conservatively as fully open
    return float(base)


def _cell_str(row: pd.Series, key: str) -> str:
    try:
        v = row[key]
    except (KeyError, IndexError):
        return ""
    if pd.isna(v):
        return ""
    s = str(v).strip()
    return "" if s.lower() == "nan" else s


def _has_evidence_note(row: pd.Series) -> bool:
    return bool(_cell_str(row, "evidence_path") or _cell_str(row, "evidence_status"))


def _resolve_evidence_path(run_path: Path, raw: object) -> str:
    """Prefer path under run_dir when relative; otherwise return trimmed string."""
    s = str(raw if raw is not None else "").strip()
    if not s:
        return ""
    p = Path(s)
    if p.is_absolute():
        return s.replace("\\", "/")
    candidate = (run_path / s).resolve()
    if candidate.exists():
        return candidate.as_posix()
    return s.replace("\\", "/")


def generate_iso17025_outputs(run_dir: str, reference_csv: str = "data/reference/iso17025_blindspots.csv"):
    run_path = Path(run_dir).resolve()
    ref = Path(reference_csv)
    if not ref.is_absolute():
        ref = (Path.cwd() / ref).resolve()

    if not run_path.exists():
        raise FileNotFoundError(run_path)
    if not ref.exists():
        raise FileNotFoundError(ref)

    df = pd.read_csv(ref, encoding="utf-8-sig")

    for col in ("evidence_path", "evidence_status", "reviewer", "review_date"):
        if col not in df.columns:
            df[col] = ""
        df[col] = df[col].fillna("")

    required_artifacts = [
        "clean_dataset.csv",
        "qc_report.json",
        "priority_report.csv",
        "provenance.json",
        "summary_report.pdf",
    ]

    missing = [x for x in required_artifacts if not (run_path / x).exists()]

    score = 100.0
    evidence_notes: list[str] = []

    if missing:
        score -= 25.0
        evidence_notes.append("Missing required pipeline artifacts: " + ", ".join(missing))

    canonical_statuses: list[str] = []
    penalty_applied: list[float] = []

    for _, row in df.iterrows():
        sev = str(row.get("severity", "")).upper().strip()
        canon = _norm_status(row.get("status", ""))
        canonical_statuses.append(canon)

        base = _base_penalty(sev)
        pen = _penalty_for_status(canon, base)
        penalty_applied.append(pen)

        if canon == STATUS_NOT_APPLICABLE and not _has_evidence_note(row):
            label = _cell_str(row, "blind_spot") or "(unnamed blind spot)"
            evidence_notes.append(
                "Not Applicable requires an evidence note (evidence_path and/or evidence_status): " + label
            )

        score -= pen

    score_i = int(max(0, min(100, math.floor(score + 0.5))))

    if score_i >= 90:
        rating = "Strong ISO/IEC 17025-aligned readiness support"
    elif score_i >= 70:
        rating = "Acceptable ISO/IEC 17025-aligned readiness support (needs review)"
    elif score_i >= 40:
        rating = "Weak ISO/IEC 17025-aligned readiness support (audit defensibility)"
    else:
        rating = "Serious ISO/IEC 17025-aligned readiness support risk"

    df = df.copy()
    df["_canonical_status"] = canonical_statuses
    df["_penalty_applied"] = penalty_applied

    blind_spots_ui: list[dict] = []
    for idx, row in df.iterrows():
        canon = row["_canonical_status"]
        disp = _display_status(canon)
        ev_path = _resolve_evidence_path(run_path, _cell_str(row, "evidence_path"))
        ev_stat = _cell_str(row, "evidence_status")
        rev = _cell_str(row, "reviewer")
        rdate = _cell_str(row, "review_date")
        title = _cell_str(row, "blind_spot")
        lines = [f"{title}: {disp}"]
        if ev_path:
            lines.append(f"Evidence: {ev_path}")
        if ev_stat:
            lines.append(f"Evidence status: {ev_stat}")
        if rev:
            lines.append(f"Reviewer: {rev}")
        if rdate:
            lines.append(f"Review date: {rdate}")
        blind_spots_ui.append(
            {
                "blind_spot": title,
                "status": disp,
                "canonical_status": canon,
                "evidence_path": ev_path,
                "evidence_status": ev_stat,
                "reviewer": rev,
                "review_date": rdate,
                "summary_text": "\n".join(lines),
            }
        )

    out_df = df.drop(columns=["_canonical_status", "_penalty_applied"], errors="ignore")
    out_csv = run_path / "iso_blind_spots_report.csv"
    out_json = run_path / "iso_readiness_score.json"

    out_df.to_csv(out_csv, index=False)

    st = df["_canonical_status"].astype(str)
    payload = {
        "score": score_i,
        "rating": rating,
        "missing_required_artifacts": missing,
        "open_critical": int(((df["severity"].str.upper() == "CRITICAL") & (st == STATUS_OPEN)).sum()),
        "open_high": int(((df["severity"].str.upper() == "HIGH") & (st == STATUS_OPEN)).sum()),
        "open_medium": int(((df["severity"].str.upper() == "MEDIUM") & (st == STATUS_OPEN)).sum()),
        "count_in_progress": int((st == STATUS_IN_PROGRESS).sum()),
        "count_mitigated": int((st == STATUS_MITIGATED).sum()),
        "count_closed": int((st == STATUS_CLOSED).sum()),
        "count_not_applicable": int((st == STATUS_NOT_APPLICABLE).sum()),
        "na_missing_evidence_note": int(
            sum(
                1
                for i, row in df.iterrows()
                if row["_canonical_status"] == STATUS_NOT_APPLICABLE and not _has_evidence_note(row)
            )
        ),
        "notes": evidence_notes,
        "blind_spots": blind_spots_ui,
        "disclaimer": (
            "ISO/IEC 17025-aligned readiness support only. "
            "This does not certify accreditation, claim ISO compliance, or prove laboratory conformity."
        ),
    }

    out_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    return {
        "iso_blind_spots_report": str(out_csv),
        "iso_readiness_score": str(out_json),
        "score": score_i,
        "rating": rating,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir")
    args = parser.parse_args()
    print(json.dumps(generate_iso17025_outputs(args.run_dir), indent=2))
