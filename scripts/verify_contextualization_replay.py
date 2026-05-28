from pathlib import Path
import pandas as pd
import hashlib
import json
from datetime import datetime, timezone

INPUT = Path("data/contextualization_inputs/sample_serum_pfas_batch.csv")
OUTPUT = Path("data/contextualization_outputs/serum_pfas_batch_contextualized_v1.csv")
REPORT = Path("data/contextualization_outputs/replay_verification_v1.json")

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()

if not INPUT.exists():
    raise FileNotFoundError(f"Missing input file: {INPUT}")

if not OUTPUT.exists():
    raise FileNotFoundError(f"Missing output file: {OUTPUT}")

input_hash = sha256_file(INPUT)
output_hash = sha256_file(OUTPUT)

df = pd.read_csv(OUTPUT)

required_cols = [
    "sample_id",
    "status",
    "analyte",
    "input_value",
    "units",
    "sex",
    "age",
    "age_group",
    "contextualization_band",
]

missing_cols = [c for c in required_cols if c not in df.columns]

valid_count = int((df["status"] == "VALID").sum())
rejected_count = int((df["status"] == "REJECTED").sum())

report = {
    "verification_status": "PASS" if not missing_cols else "FAIL",
    "generated_at_utc": datetime.now(timezone.utc).isoformat(),
    "engine": "contextualization_replay_verification_v1",
    "input_file": str(INPUT),
    "output_file": str(OUTPUT),
    "input_sha256": input_hash,
    "output_sha256": output_hash,
    "row_count": int(len(df)),
    "valid_count": valid_count,
    "rejected_count": rejected_count,
    "missing_required_columns": missing_cols,
    "governance_checks": {
        "has_valid_rows": valid_count > 0,
        "has_rejected_rows": rejected_count > 0,
        "matrix_refusal_present": bool(
            df["reason"].fillna("").str.contains("serum matrix only", case=False).any()
        ),
    },
}

with open(REPORT, "w") as f:
    json.dump(report, f, indent=2)

print(json.dumps(report, indent=2))
print("Saved:", REPORT)
