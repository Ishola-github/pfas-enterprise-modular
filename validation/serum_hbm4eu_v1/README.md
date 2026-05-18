# HBM4EU serum lane scaffold (v1)

**Status:** specification only — no European HBM raw data ingested.

## Official entry points

| Resource | URL |
|----------|-----|
| HBM4EU initiative | https://www.hbm4eu.eu/ |
| PFAS substances overview | https://www.hbm4eu.eu/hbm4eu-substances/per-polyfluorinated-compounds/ |
| European HBM Dashboard | https://hbm.vito.be/eu-hbm-dashboard |
| IPCHEM HBM4EU portal | https://ipchem.jrc.ec.europa.eu/hbm4eu_overview.html |

## Lane role

International validation and cross-country comparison — **not** U.S. baseline replacement.

Requires a harmonization artifact and explicit EU↔U.S. stratum cross-walk before any
ontology pin. Do not assume NHANES demographic strata map 1:1.

## Integration policy

1. Separate lane (`validation/serum_hbm4eu_v1/`) — never merge into NHANES reference tables.
2. Pin all downloads in `data/reference/registry/reference_registry.csv`.
3. Feed multi-reference engine per `validation/serum_multi_reference_v1/SPEC.md`.

## Next step

Complete ATSDR P0 acquisition first; HBM4EU follows with harmonization spec.
