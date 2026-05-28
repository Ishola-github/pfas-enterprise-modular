# PFAS Enterprise 5.0 — V1

Governed serum PFOS/PFOA contextualization against CDC NHANES reference
distributions with deterministic replay, provenance logging, and
refusal-first applicability enforcement.

## What V1 is

V1 accepts a CSV of serum PFOS/PFOA results (four isomer-resolved analytes),
validates each row against a frozen ontology, and—for in-domain rows—returns
**percentile context** from a hash-pinned, precomputed **weighted NHANES**
reference table (cycles I, J, P). Outputs are an RUO CSV report, a one-page
PDF summary, and a provenance manifest JSON.

## What V1 is NOT

- Not diagnostic, not clinical, not regulatory
- Not exposure-risk prediction, not toxicology AI
- Not a temporal-trend or cross-cycle comparison tool

See `validation/serum_v1/limitations.md` and the ontology `non_claims` list.

## Build order (components)

| # | Module | Role |
|---|--------|------|
| 1 | `ontology.py` | Load/hash frozen `data/ontology/pfos_pfoa_v1.json` |
| 2 | `reference.py` | Lookup precomputed weighted percentiles |
| 3 | `applicability.py` | Refusal-first row validation |
| 4 | `provenance.py` | Deterministic `run_id` + manifest |
| 5 | `report.py` | RUO CSV + PDF stub |
| 6 | `cli.py` | End-to-end orchestrator |

## Quick start

From the repo root:

```bash
python -m src.v1.cli \
  --input data/v1/fixtures/sample_input.csv \
  --output-dir data/v1/outputs
```

Governed input template (for Shiny or CLI):

`data/v1/templates/governed_serum_pfos_pfoa_input_template.csv`

Legacy batch CSV (`sample_id`, `analyte`, `value`, `matrix`, `units`, …) must be
converted first:

```bash
python scripts/convert_legacy_serum_batch_to_v1.py \
  --input data/contextualization_inputs/sample_serum_pfas_batch.csv \
  --output data/v1/fixtures/sample_serum_pfas_batch_v1.csv
```

Then upload the `*_v1.csv` in Shiny and run V1 contextualization.

## Shiny app integration

In **Reports / Export → PFAS External Data + Training Pipeline Runner**, the
**V1 serum PFOS/PFOA contextualization** panel (below the serum lane build
button) provides:

- Template download
- CSV upload
- Run → report preview + download (CSV, optional PDF, manifest JSON)

Backed by `scripts/run_v1_contextualization.R` calling `python -m src.v1.cli`.
PDF requires `reportlab`; CSV + manifest always emit.

Required input columns: `sample_matrix`, `result_unit`, `source_program`,
`analyte`, `result_value`.

Optional: `sex`, `age_years` (or `ridageyr`) for stratified reference lookup;
defaults to `all` / `all_ages` when omitted.

## Reference artifacts

| Artifact | Path | Role |
|----------|------|------|
| Weighted table (runtime) | `data/reference_tables/nhanes_pfas_weighted_reference_tables_v1.csv` | Official percentiles |
| Unweighted table (peer) | `data/reference_tables/nhanes_pfas_reference_tables_v1.csv` | Replay-diff only |
| Cycle-J anchor (provenance) | `data/training/serum/nhanes_serum_pfas_2017_2018.csv` | Frozen chain-of-custody; not queried at runtime |

Rebuild reference tables:

```bash
python scripts/build_nhanes_weighted_reference_tables.py
```

## Replay invariants

```bash
pytest src/v1/tests/test_replay.py -q
```

1. Same input → same output CSV hash and `run_id`
2. Changed ontology → changed `run_id`
3. Unsupported analyte / non-serum matrix → refusal

## Reproducibility recipe

`run_id` = SHA-256 (truncated) of:

`input_hash | reference_table_hash | ontology_hash | code_version | ontology_version`

The report CSV contains **no timestamps**. Timestamps appear only in the
manifest JSON metadata.
