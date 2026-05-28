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

## Cohort summary CLI (v2 report -> subgroup aggregates)

Build governed subgroup summaries from a V2 report CSV:

```powershell
C:\pfasenv\Scripts\python.exe -m src.v2.cohort_cli `
  --input-report data\v2\outputs\v2_report_2bda057f5ab18ff6.csv `
  --output-dir data\v2\outputs\cohort
```

Outputs:

- `v2_cohort_summary_<run_id>.csv` (analyte x sex x age x race strata)
- `v2_cohort_manifest_<run_id>.json` (input/output SHA + overview counts)

## Cross-cohort comparator CLI (summary -> comparison table)

Compare two governed cohort summary CSVs:

```powershell
C:\pfasenv\Scripts\python.exe -m src.v2.cross_cohort_cli `
  --left-summary  data\v2\outputs\cohort\left_summary.csv `
  --right-summary data\v2\outputs\cohort\right_summary.csv `
  --left-label NHANES `
  --right-label ATSDR `
  --output-dir data\v2\outputs\cross_cohort
```

Outputs:

- `v2_cross_cohort_comparison_<run_id>.csv`
- `v2_cross_cohort_manifest_<run_id>.json`
