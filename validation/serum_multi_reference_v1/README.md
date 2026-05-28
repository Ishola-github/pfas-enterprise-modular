# Multi-reference percentile comparison (v1 scaffold)

**Status:** specification only — implements the next infrastructure layer after V2 cohort
and cross-cohort comparators.

## Objective

Compare the **same serum cohort** (or cohort summary) against **multiple pinned reference
layers** without pooling reference distributions:

```text
Patient / cohort serum PFAS
        ↓
NHANES weighted percentile (baseline U.S. population)
        ↓
ATSDR exposed-community reference (when lane active)
        ↓
HBM4EU harmonized percentile (when lane active)
        ↓
Cross-reference deviation interpretation (manifest-backed)
```

## Reference layer roles

| Layer | Dataset | Role |
|-------|---------|------|
| `NHANES` | NHANES cycles I/J/P | Baseline population contextualization (operational) |
| `ATSDR_EA` | PFAS Exposure Assessments | High-exposure community validation |
| `HBM4EU` | European HBM harmonized data | International comparison |
| `UCMR5` | Drinking water occurrence | Environmental linkage only (non-serum AD) |

## Relationship to existing tools

| Existing | Scope |
|----------|-------|
| `src/v1.cli` | Row-level NHANES percentiles |
| `src/v2.cli` | NHANES cross-cycle temporal |
| `src/v2.cohort_cli` | Cohort summary within one V2 report |
| `src/v2.cross_cohort_cli` | Compare two **cohort summary** CSVs (same schema) |
| **multi_reference (planned)** | One cohort → N reference percentiles + deviation table |

## Governance

- No raw ingest in this folder.
- No clinical, diagnostic, or regulatory claims.
- Each reference layer requires pinned SHA in `data/reference/registry/reference_registry.csv`.
- Schema changes require version bump + schema-lock test.

See `SPEC.md` and `ARCHITECTURE.md`.
