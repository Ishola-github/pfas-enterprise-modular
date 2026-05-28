from pathlib import Path
import pandas as pd
import numpy as np
import json
from datetime import datetime, timezone

REF_PATH = Path("data/reference_tables/nhanes_j_weighted_stratified_reference_v1.csv")
OUT_DIR = Path("data/contextualization_outputs")
OUT_DIR.mkdir(parents=True, exist_ok=True)

SUPPORTED_ANALYTES = {
    "PFOA": "PFOA_TOTAL",
    "PFOS": "PFOS_TOTAL",
    "PFOA_TOTAL": "PFOA_TOTAL",
    "PFOS_TOTAL": "PFOS_TOTAL",
}

def age_group(age):
    age = int(age)
    if age < 20:
        return "<20"
    if age <= 39:
        return "20-39"
    if age <= 59:
        return "40-59"
    return "60+"

def normalize_sex(sex):
    s = str(sex).strip().lower()
    if s in ["m", "male", "1"]:
        return "Male"
    if s in ["f", "female", "2"]:
        return "Female"
    raise ValueError("Unsupported sex. Use Male/Female.")

def normalize_analyte(analyte):
    key = str(analyte).strip().upper()
    if key not in SUPPORTED_ANALYTES:
        raise ValueError("Unsupported analyte. V1 supports PFOS and PFOA only.")
    return SUPPORTED_ANALYTES[key]

def contextualize_serum_pfas(analyte, value, age, sex, matrix="serum", units="ng/mL"):
    if str(matrix).strip().lower() != "serum":
        return {
            "status": "REJECTED",
            "reason": "V1 supports serum matrix only. Cross-matrix contextualization is blocked."
        }

    if str(units).strip() != "ng/mL":
        return {
            "status": "REJECTED",
            "reason": "V1 supports ng/mL only. Unit conversion is not silently applied."
        }

    analyte_norm = normalize_analyte(analyte)
    sex_norm = normalize_sex(sex)
    agegrp = age_group(age)
    value = float(value)

    ref = pd.read_csv(REF_PATH)

    row = ref[
        (ref["analyte"] == analyte_norm) &
        (ref["sex"] == sex_norm) &
        (ref["age_group"] == agegrp)
    ]

    if row.empty:
        return {
            "status": "REJECTED",
            "reason": "No matching NHANES reference bucket found.",
            "analyte": analyte_norm,
            "sex": sex_norm,
            "age_group": agegrp
        }

    r = row.iloc[0]

    percentiles = {
        "p50": float(r["p50"]),
        "p75": float(r["p75"]),
        "p90": float(r["p90"]),
        "p95": float(r["p95"]),
        "p99": float(r["p99"]),
    }

    if value < percentiles["p50"]:
        band = "below_p50"
    elif value < percentiles["p75"]:
        band = "p50_to_p75"
    elif value < percentiles["p90"]:
        band = "p75_to_p90"
    elif value < percentiles["p95"]:
        band = "p90_to_p95"
    elif value < percentiles["p99"]:
        band = "p95_to_p99"
    else:
        band = "above_p99"

    result = {
        "status": "VALID",
        "mode": "RUO_CONTEXTUALIZATION_ONLY",
        "dataset_version": str(r["dataset_version"]),
        "cycle": str(r["cycle"]),
        "matrix": "serum",
        "analyte": analyte_norm,
        "input_value": value,
        "units": "ng/mL",
        "sex": sex_norm,
        "age": int(age),
        "age_group": agegrp,
        "n_reference": int(r["n"]),
        "weight_column": str(r["weight_column"]),
        "reference_percentiles": percentiles,
        "contextualization_band": band,
        "disclaimer": (
            "Research Use Only. This is population-reference contextualization, "
            "not diagnosis, treatment guidance, toxicity interpretation, or medical advice."
        ),
        "provenance": {
            "reference_table": str(REF_PATH),
            "engine_version": "serum_contextualization_v1",
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "governance_rules": [
                "serum_only",
                "ng_per_mL_only",
                "PFOS_PFOA_only",
                "no_cross_matrix_contextualization",
                "no_clinical_interpretation"
            ]
        }
    }

    return result

if __name__ == "__main__":
    examples = [
        {"analyte": "PFOS", "value": 8.2, "age": 35, "sex": "Male"},
        {"analyte": "PFOA", "value": 2.1, "age": 42, "sex": "Female"},
        {"analyte": "PFOS", "value": 8.2, "age": 35, "sex": "Male", "matrix": "water"},
    ]

    outputs = []

    for ex in examples:
        res = contextualize_serum_pfas(**ex)
        outputs.append(res)
        print(json.dumps(res, indent=2))
        print("-" * 80)

    out_file = OUT_DIR / "serum_pfas_contextualization_examples_v1.json"
    with open(out_file, "w") as f:
        json.dump(outputs, f, indent=2)

    print("Saved:", out_file)
