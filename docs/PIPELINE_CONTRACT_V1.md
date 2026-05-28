# Pipeline contract v1 — UCMR5 PFAS triage

This document defines the **v1 contract** for `pipeline/process_ucmr5.py`: inputs, outputs, and scope. It aligns with **[DISCLAIMER.md](../DISCLAIMER.md)** — **screening and workflow support only**, not regulatory or lab certification.

## Entry point

```bash
python pipeline/process_ucmr5.py <path-to-UCMR5-tab-or-csv-file> [--output-root runs] [--run-id my_run]
```

- **Input:** EPA-style UCMR occurrence extract (tab-delimited `latin1` typical for Method 533 text exports).
- **Output root:** Default `runs/` under the current working directory (gitignored).

## Run directory

Each run writes to:

```text
runs/<run_id>/
```

`run_id` defaults to `ucmr5_YYYYMMDD_HHMMSS` UTC if `--run-id` is omitted.

## Required outputs (v1)

All of the following **must** exist after a successful run:

| File | Purpose |
|------|---------|
| `clean_dataset.csv` | Normalized long-style table (canonical columns, ng/L-oriented). |
| `qc_report.json` | Row counts, structural/analytical/metadata QC flags, heuristic `qc_score`. |
| `priority_report.csv` | Ranked screening triage (v1 thresholds: high if detected and ≥ 10 ng/L). |
| `provenance.json` | Run id, timestamps, input path, SHA-256 of input, pipeline version strings. |
| `summary_report.pdf` | Short summary (ReportLab PDF if available; else plain text written to the same path for contract compliance). |

## QC score

`qc_score` is a **heuristic** (0–100) for internal triage only. It is **not** an EPA, ISO, or lab score.

## Priority rules (v1)

- **high:** `detect_flag` and `result_ng_l` ≥ 10  
- **medium:** detected, numeric result &gt; 0, below 10  
- **low:** non-detect or non-numeric  

Replace thresholds and logic with validated rules when a single workflow is frozen for production study.

## Versioning

- **Pipeline:** `ucmr5_pipeline_v1` (see `provenance.json`).
- **Software:** `0.1.0` in provenance until semver is managed centrally.

## Operator responsibilities

- Provide the **correct** input file (unzipped `.txt` where applicable).
- Do not treat outputs as **regulatory determinations** or substitutes for certified analytical methods.
- Archive `provenance.json` with any downstream use for traceability.

## Shiny (optional preview)

In **Data & Endpoints**, **Python pipeline output (priority triage)** accepts the same **`run_id`** as `--run-id` and reads **`runs/<run_id>/priority_report.csv`** (first N rows only) for in-app review.
