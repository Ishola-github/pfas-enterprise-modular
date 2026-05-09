from pathlib import Path
import json
import pandas as pd

PENALTIES = {
    "CRITICAL": 20,
    "HIGH": 10,
    "MEDIUM": 5,
    "LOW": 2,
    "INFO": 0,
}


def generate_iso17025_outputs(run_dir: str, reference_csv: str = "data/reference/iso17025_blindspots.csv"):
    run_path = Path(run_dir)
    ref = Path(reference_csv)

    if not run_path.exists():
        raise FileNotFoundError(run_path)
    if not ref.exists():
        raise FileNotFoundError(ref)

    df = pd.read_csv(ref)

    required_artifacts = [
        "clean_dataset.csv",
        "qc_report.json",
        "priority_report.csv",
        "provenance.json",
        "summary_report.pdf",
    ]

    missing = [x for x in required_artifacts if not (run_path / x).exists()]

    score = 100
    evidence_notes = []

    if missing:
        score -= 25
        evidence_notes.append("Missing required pipeline artifacts: " + ", ".join(missing))

    for _, row in df.iterrows():
        severity = str(row.get("severity", "")).upper().strip()
        status = str(row.get("status", "")).lower().strip()
        if status == "open":
            score -= PENALTIES.get(severity, 0)

    score = max(0, min(100, score))

    if score >= 90:
        rating = "Strong ISO-readiness support"
    elif score >= 70:
        rating = "Acceptable but needs review"
    elif score >= 40:
        rating = "Weak audit defensibility"
    else:
        rating = "Serious ISO-readiness risk"

    out_csv = run_path / "iso_blind_spots_report.csv"
    out_json = run_path / "iso_readiness_score.json"

    df.to_csv(out_csv, index=False)

    payload = {
        "score": score,
        "rating": rating,
        "missing_required_artifacts": missing,
        "open_critical": int(((df["severity"].str.upper() == "CRITICAL") & (df["status"].str.lower() == "open")).sum()),
        "open_high": int(((df["severity"].str.upper() == "HIGH") & (df["status"].str.lower() == "open")).sum()),
        "open_medium": int(((df["severity"].str.upper() == "MEDIUM") & (df["status"].str.lower() == "open")).sum()),
        "notes": evidence_notes,
        "disclaimer": "ISO/IEC 17025-aligned readiness support only. This does not certify accreditation or prove laboratory compliance."
    }

    out_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    return {
        "iso_blind_spots_report": str(out_csv),
        "iso_readiness_score": str(out_json),
        "score": score,
        "rating": rating,
    }


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir")
    args = parser.parse_args()
    print(json.dumps(generate_iso17025_outputs(args.run_dir), indent=2))
