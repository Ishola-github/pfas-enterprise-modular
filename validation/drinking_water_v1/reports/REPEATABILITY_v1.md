# Repeatability validation (v1)

## Procedure

1. After **FREEZE_v1.md** is satisfied for a configuration, run the **same** training / evaluation workflow **three times** with:
   - identical inputs (same file hashes),
   - same documented **seed** and split,
   - same **model** and **threshold**.
2. Save after each run:
   - confusion matrix (from metrics JSON),
   - full metrics JSON,
   - feature importance CSV (or equivalent).

## Pass criterion

```text
same input + same seed + same model version = same metrics
```

Material drift without a documented cause → **reproducibility gap**; treat the build as **not validation-ready** until resolved or variance is bounded and documented.

## Where to store outputs

Use three sibling folders or repeat indices under `runs/` (e.g. `v1-dw-YYYYMMDD-repro-1`, `...-repro-2`, `...-repro-3`) and set `reproducibility` fields in each `manifest.json`.

## Automation helpers (v1)

From project root:

```powershell
.\validation\drinking_water_v1\scripts\launch_repeatability_3run.ps1 -BaseRunId v1-dw-20260510-freeze -Seed 42 -Threshold 0.25
```

After you execute the three frozen runs and collect their metrics JSON files:

```powershell
python .\validation\drinking_water_v1\scripts\summarize_repeatability.py `
  --run1 <metrics_run1.json> `
  --run2 <metrics_run2.json> `
  --run3 <metrics_run3.json> `
  --out .\validation\drinking_water_v1\runs\<repeatability_folder>\REPEATABILITY_SUMMARY_EXECUTED_v1.md
```

Conservative interpretation only: this is repeatability evidence for a screening / prioritization / governance platform, not accreditation or regulatory validation.
