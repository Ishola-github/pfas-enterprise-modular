# Serum lane V2 — cross-cycle temporal contextualization

V2 extends V1 governed serum PFOS/PFOA contextualization with **population-reference
comparison across NHANES cycles I, J, and P**.

## Relationship to V1

| Layer | Package | Purpose |
|-------|---------|---------|
| V1 / V1.1 | `src/v1/` | Single-cycle percentile vs weighted NHANES reference |
| **V2** | `src/v2/` | Same input row contextualized against **multiple cycles**; reports cross-cycle percentile shift and reference median shift |

V2 **does not** replace V1. It delegates single-cycle lookup to the V1.1 reference engine and adds temporal comparison metadata.

## Governance documents

| File | Role |
|------|------|
| `intended_use.txt` | Permitted temporal comparison uses |
| `limitations.md` | Non-claims (not individual longitudinal follow-up) |
| `applicability_domain.txt` | In-domain cycles, analytes, units |
| `scope.md` | V2 output contract and flags |

## Run (after implementation)

```powershell
cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
C:\pfasenv\Scripts\python.exe -m src.v2.cli `
  --input data\v1\fixtures\nhanes_j_governed_v1_input.csv `
  --output-dir data\v2\outputs
```

Requires the V1.1 weighted reference table (cycles I, J, P precomputed).
