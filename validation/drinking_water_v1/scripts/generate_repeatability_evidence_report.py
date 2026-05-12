#!/usr/bin/env python3
"""Generate repeatability evidence report (hash stability + metric availability)."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    p = argparse.ArgumentParser(description="Generate repeatability evidence report.")
    p.add_argument("--repeatability-dir", type=Path, required=True)
    p.add_argument("--out-md", type=Path, required=True)
    p.add_argument("--out-json", type=Path, required=True)
    args = p.parse_args()

    rep_dir = args.repeatability_dir.resolve()
    run_dirs = sorted([d for d in rep_dir.iterdir() if d.is_dir() and "-repro-" in d.name])
    if len(run_dirs) != 3:
        raise SystemExit(f"Expected 3 repro dirs in {rep_dir}, found {len(run_dirs)}")

    rows = []
    hash_groups: dict[str, list[str]] = {"manifest.json": [], "hashes.txt": []}
    metrics_available = []
    for d in run_dirs:
        mf = d / "manifest.json"
        hf = d / "hashes.txt"
        mjson = d / "metrics.json"
        rec = {
            "run_dir": d.name,
            "manifest_exists": mf.exists(),
            "hashes_exists": hf.exists(),
            "metrics_json_exists": mjson.exists(),
        }
        if mf.exists():
            rec["manifest_sha256"] = sha256_file(mf)
            hash_groups["manifest.json"].append(rec["manifest_sha256"])
        if hf.exists():
            rec["hashes_sha256"] = sha256_file(hf)
            hash_groups["hashes.txt"].append(rec["hashes_sha256"])
        rows.append(rec)
        metrics_available.append(mjson.exists())

    manifest_stable = len(set(hash_groups["manifest.json"])) == 1 if hash_groups["manifest.json"] else False
    hashes_stable = len(set(hash_groups["hashes.txt"])) == 1 if hash_groups["hashes.txt"] else False
    metrics_ready = all(metrics_available)

    verdict = "PASS" if (manifest_stable and hashes_stable and metrics_ready) else "REVIEW"
    verdict_reason = []
    if not manifest_stable:
        verdict_reason.append("manifest hashes differ across repeats")
    if not hashes_stable:
        verdict_reason.append("hashes.txt differs across repeats")
    if not metrics_ready:
        verdict_reason.append("metrics.json missing in one or more repeats")

    payload = {
        "repeatability_dir": str(rep_dir),
        "runs": rows,
        "checks": {
            "manifest_hash_stability": manifest_stable,
            "hashes_file_stability": hashes_stable,
            "metrics_available_all_runs": metrics_ready,
        },
        "verdict": verdict,
        "verdict_reason": verdict_reason or ["all checks passed"],
        "scope_note": "screening / prioritization / governance repeatability evidence only",
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    lines = [
        "# Repeatability 3-Run Evidence Report (v1)",
        "",
        f"Repeatability folder: `{rep_dir}`",
        "",
        "Scope: screening / prioritization / governance platform evidence.",
        "",
        "## Hash Comparison",
        "",
        "| Run | manifest.json SHA256 | hashes.txt SHA256 | metrics.json present |",
        "|---|---|---|---|",
    ]
    for r in rows:
        lines.append(
            f"| {r['run_dir']} | {r.get('manifest_sha256', 'NA')} | {r.get('hashes_sha256', 'NA')} | "
            f"{'Yes' if r.get('metrics_json_exists') else 'No'} |"
        )
    lines += [
        "",
        "## Stability Checks",
        "",
        f"- manifest hash stability: **{'PASS' if manifest_stable else 'REVIEW'}**",
        f"- hashes.txt stability: **{'PASS' if hashes_stable else 'REVIEW'}**",
        f"- metrics availability (all 3 runs): **{'PASS' if metrics_ready else 'REVIEW'}**",
        "",
        f"## Verdict: **{verdict}**",
        "",
        "Reason(s):",
        *[f"- {x}" for x in (verdict_reason or ["all checks passed"])],
        "",
        "Conservative note: this evidence does not imply accreditation, certification, regulatory approval, or compliance automation.",
    ]
    args.out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(str(args.out_md))
    print(str(args.out_json))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
