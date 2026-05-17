# V2 — Cross-cycle temporal contextualization

V2 compares **population-referenced percentiles** for the same serum PFOS/PFOA
measurement across NHANES cycles **I**, **J**, and **P**.

## Run

```powershell
cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
C:\pfasenv\Scripts\python.exe -m src.v2.cli `
  --input data\v1\fixtures\nhanes_j_governed_v1_input.csv `
  --output-dir data\v2\outputs
```

Requires V1.1 governed input (`reference_cycle` on every row) and
`nhanes_pfas_weighted_reference_tables_v1_1.csv`.

## Governance

See `validation/serum_v2/` for intended use, limitations, and applicability.

## Architecture

```text
V1.1 ReferenceEngine  ×  cycles I, J, P
        ↓
percentile_cycle_* + deltas + p50 ratios
        ↓
v2_report_<run_id>.csv / manifest / PDF
```

V2 does **not** follow individuals over time; it compares cross-sectional NHANES references.
