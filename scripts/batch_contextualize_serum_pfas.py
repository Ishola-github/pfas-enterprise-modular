from pathlib import Path
import pandas as pd
import json
from datetime import datetime, timezone

from contextualize_serum_pfas import contextualize_serum_pfas

INFILE = Path("data/contextualization_inputs/sample_serum_pfas_batch.csv")
OUTDIR = Path("data/contextualization_outputs")
OUTDIR.mkdir(parents=True, exist_ok=True)

if not INFILE.exists():
    INFILE.parent.mkdir(parents=True, exist_ok=True)

    sample = pd.DataFrame([
        {"sample_id": "S001", "analyte": "PFOS", "value": 8.2, "age": 35, "sex": "Male", "matrix": "serum", "units": "ng/mL"},
        {"sample_id": "S002", "analyte": "PFOA", "value": 2.1, "age": 42, "sex": "Female", "matrix": "serum", "units": "ng/mL"},
        {"sample_id": "S003", "analyte": "PFOS", "value": 8.2, "age": 35, "sex": "Male", "matrix": "water", "units": "ng/mL"},
    ])

    sample.to_csv(INFILE, index=False)
    print("Created sample input:", INFILE)

df = pd.read_csv(INFILE)

required = ["sample_id", "analyte", "value", "age", "sex", "matrix", "units"]
missing = [c for c in required if c not in df.columns]

if missing:
    raise ValueError(f"Missing required columns: {missing}")

rows = []
json_results = []

for _, row in df.iterrows():
    sample_id = row["sample_id"]

    try:
        result = contextualize_serum_pfas(
            analyte=row["analyte"],
            value=row["value"],
            age=row["age"],
            sex=row["sex"],
            matrix=row["matrix"],
            units=row["units"],
        )
    except Exception as e:
        result = {
            "status": "REJECTED",
            "reason": str(e),
        }

    result["sample_id"] = sample_id
    json_results.append(result)

    flat = {
        "sample_id": sample_id,
        "status": result.get("status"),
        "reason": result.get("reason"),
        "mode": result.get("mode"),
        "dataset_version": result.get("dataset_version"),
        "cycle": result.get("cycle"),
        "matrix": result.get("matrix"),
        "analyte": result.get("analyte"),
        "input_value": result.get("input_value"),
        "units": result.get("units"),
        "sex": result.get("sex"),
        "age": result.get("age"),
        "age_group": result.get("age_group"),
        "n_reference": result.get("n_reference"),
        "contextualization_band": result.get("contextualization_band"),
    }

    ref = result.get("reference_percentiles", {})
    for p in ["p50", "p75", "p90", "p95", "p99"]:
        flat[p] = ref.get(p)

    rows.append(flat)

out_csv = OUTDIR / "serum_pfas_batch_contextualized_v1.csv"
out_json = OUTDIR / "serum_pfas_batch_contextualized_v1.json"

pd.DataFrame(rows).to_csv(out_csv, index=False)

payload = {
    "generated_at_utc": datetime.now(timezone.utc).isoformat(),
    "engine_version": "batch_serum_contextualization_v1",
    "input_file": str(INFILE),
    "output_csv": str(out_csv),
    "results": json_results,
}

with open(out_json, "w") as f:
    json.dump(payload, f, indent=2)

print("Saved CSV:", out_csv)
print("Saved JSON:", out_json)
print(pd.DataFrame(rows))
