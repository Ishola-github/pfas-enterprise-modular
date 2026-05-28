from pathlib import Path
import pandas as pd
import numpy as np

RAW_PFAS = Path("data/raw/nhanes_pfas/PFAS_J_2017_2018.XPT")
OUT = Path("data/reference_tables")
OUT.mkdir(parents=True, exist_ok=True)

df = pd.read_sas(RAW_PFAS, format="xport")

df["PFOA_TOTAL"] = df["LBXNFOA"] + df["LBXBFOA"]
df["PFOS_TOTAL"] = df["LBXNFOS"] + df["LBXMFOS"]

records = []

for analyte in ["PFOA_TOTAL", "PFOS_TOTAL"]:
    values = pd.to_numeric(df[analyte], errors="coerce").dropna()

    records.append({
        "dataset_version": "NHANES_2017_2018_PFAS_J_total_v1",
        "cycle": "2017_2018",
        "matrix": "serum",
        "analyte": analyte,
        "units": "ng/mL",
        "n": int(values.shape[0]),
        "p50": float(np.percentile(values, 50)),
        "p75": float(np.percentile(values, 75)),
        "p90": float(np.percentile(values, 90)),
        "p95": float(np.percentile(values, 95)),
        "p99": float(np.percentile(values, 99)),
    })

out = pd.DataFrame(records)
out.to_csv(OUT / "nhanes_j_total_pfas_reference_v1.csv", index=False)

print(out)
print("Saved:", OUT / "nhanes_j_total_pfas_reference_v1.csv")
