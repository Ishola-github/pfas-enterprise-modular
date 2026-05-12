# External blind validation — drinking water v1

**Goal:** Show whether the **frozen** screening model generalizes to **unseen, independent** PFAS environmental data — without retraining and **without** tuning threshold **τ** on that data.

## Rules (integrity)

| Rule | Detail |
| ---- | ------ |
| **Train** | On your primary source only (already done for v1.0). |
| **Threshold** | Use **`reports/FREEZE_v1.md`** value only (**τ = 0.25** for current freeze). **No** sweep, **no** optimization on the blind set. |
| **Blind set** | Not used for feature selection, model selection, or threshold tuning. |
| **App** | Use **prediction / scoring** only (e.g. “Run PFAS Prediction” / equivalent). **Do not** run full **train** on the external CSV to “fit” the blind set. |

Breaking any of the above invalidates “external blind” claims.

## Suggested independent source (v1)

**California PFAS / GAMA-style groundwater data** (or similar state public releases): independent geography and sampling context vs typical UCMR training mixes; document exact file, download date, and license.

- Confirm the dataset’s **public use terms** before redistribution or screenshots of raw tables in commercial materials.
- Prefer files that align with **drinking-water / groundwater monitoring** narrative in **`../reports/applicability_domain.txt`**; document any **matrix or method mismatch** honestly in **`results/EXTERNAL_BLIND_RESULTS_v1.md`**.

**Finding data:** Search California Water Boards and related **GAMA / PFAS** program pages for downloadable PFAS results (analytes, results, units, sample dates, site IDs). Replace bookmarks in your run notes when URLs change.

## Folder layout

| Path | Purpose |
| ---- | ------- |
| **`data/`** | Raw external downloads + a short **`README.md`** listing filenames and hashes. |
| **`results/`** | Predictions CSV, exported metrics, **`EXTERNAL_BLIND_RESULTS_v1.md`** summary. |
| **`screenshots/`** | UI / applicability-domain / error-handling captures for this phase. |
| **`forms/`** | Governance documents: **`BLINDED_EVALUATION_CHECKLIST_v1.md`** and **`BLIND_DATA_CONTRACT_v1.md`**. |

## Workflow (PowerShell bootstrap)

From project root:

```powershell
mkdir .\validation\drinking_water_v1\external_blind\data\ -Force
mkdir .\validation\drinking_water_v1\external_blind\results\ -Force
mkdir .\validation\drinking_water_v1\external_blind\screenshots\ -Force
```

Place downloads under **`data/`**. After prediction, copy artifacts into **`results/`** and complete **`results/EXTERNAL_BLIND_RESULTS_v1.md`**.

## Cross-references

- Protocol: **`../reports/EXTERNAL_BLIND_PROTOCOL_v1.md`**
- Freeze (τ and internal metrics): **`../reports/FREEZE_v1.md`**
- Applicability: **`../reports/applicability_domain.txt`**
- Checklist: **`forms/BLINDED_EVALUATION_CHECKLIST_v1.md`**
- Data contract: **`forms/BLIND_DATA_CONTRACT_v1.md`**
