from pathlib import Path
import pandas as pd
import numpy as np

PFAS_PATH = "data/raw/nhanes_pfas/PFAS_J_2017_2018.XPT"
DEMO_PATH = "data/raw/nhanes/2017_2018/DEMO_J.XPT"

OUT = Path("data/reference_tables")
OUT.mkdir(parents=True, exist_ok=True)

pfas = pd.read_sas(PFAS_PATH, format="xport")
demo = pd.read_sas(DEMO_PATH, format="xport")

df = pfas.merge(
    demo[["SEQN", "RIDAGEYR", "RIAGENDR"]],
    on="SEQN",
    how="left"
)

df["PFOA_TOTAL"] = df["LBXNFOA"] + df["LBXBFOA"]
df["PFOS_TOTAL"] = df["LBXNFOS"] + df["LBXMFOS"]

df["weight"] = df["WTSB2YR"]

def sex_label(x):
    if x == 1:
        return "Male"
    if x == 2:
        return "Female"
    return "Unknown"

def age_group(age):
    if pd.isna(age):
        return "Unknown"

    age = int(age)

    if age < 20:
        return "<20"
    if age <= 39:
        return "20-39"
    if age <= 59:
        return "40-59"
    return "60+"

df["sex"] = df["RIAGENDR"].apply(sex_label)
df["age_group"] = df["RIDAGEYR"].apply(age_group)

def weighted_percentile(values, weights, percentile):
    values = np.asarray(values, dtype=float)
    weights = np.asarray(weights, dtype=float)

    valid = np.isfinite(values) & np.isfinite(weights) & (weights > 0)

    values = values[valid]
    weights = weights[valid]

    if len(values) == 0:
        return np.nan

    sorter = np.argsort(values)
    values = values[sorter]
    weights = weights[sorter]

    cumulative = np.cumsum(weights)
    cutoff = percentile / 100.0 * cumulative[-1]

    return float(np.interp(cutoff, cumulative, values))

records = []

for analyte in ["PFOA_TOTAL", "PFOS_TOTAL"]:
    for (sex, agegrp), sub in df.groupby(["sex", "age_group"]):
        vals = pd.to_numeric(sub[analyte], errors="coerce")
        wts = pd.to_numeric(sub["weight"], errors="coerce")

        valid = vals.notna() & wts.notna() & (wts > 0)

        vals = vals[valid].to_numpy()
        wts = wts[valid].to_numpy()

        if len(vals) < 20:
            continue

        records.append({
            "dataset_version": "NHANES_J_WEIGHTED_STRATIFIED_V1",
            "cycle": "2017_2018",
            "matrix": "serum",
            "analyte": analyte,
            "sex": sex,
            "age_group": agegrp,
            "units": "ng/mL",
            "weight_column": "WTSB2YR",
            "n": int(len(vals)),
            "p50": weighted_percentile(vals, wts, 50),
            "p75": weighted_percentile(vals, wts, 75),
            "p90": weighted_percentile(vals, wts, 90),
            "p95": weighted_percentile(vals, wts, 95),
            "p99": weighted_percentile(vals, wts, 99),
        })

out = pd.DataFrame(records)

outfile = OUT / "nhanes_j_weighted_stratified_reference_v1.csv"
out.to_csv(outfile, index=False)

print(out)
print()
print("Saved:", outfile)
