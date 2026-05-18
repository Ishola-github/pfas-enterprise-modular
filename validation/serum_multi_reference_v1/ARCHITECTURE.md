# Multi-reference architecture

```text
                    ┌─────────────────────────────────────┐
                    │   Cohort / row-level serum input     │
                    │   (governed schema, manifest in)     │
                    └─────────────────┬───────────────────┘
                                      │
          ┌───────────────────────────┼───────────────────────────┐
          ▼                           ▼                           ▼
   ┌──────────────┐           ┌──────────────┐           ┌──────────────┐
   │    NHANES    │           │  ATSDR EA    │           │   HBM4EU     │
   │  baseline    │           │   exposed    │           │ international│
   │  weighted %  │           │  communities │           │  comparison  │
   └──────┬───────┘           └──────┬───────┘           └──────┬───────┘
          │                           │                           │
          └───────────────────────────┼───────────────────────────┘
                                      ▼
                    ┌─────────────────────────────────────┐
                    │  Cross-reference deviation table     │
                    │  (manifest + SHA, RUO interpretation)│
                    └─────────────────────────────────────┘

   UCMR5 (environmental) ──► separate matrix lane ──► linkage only, not serum AD
```

## Scientific coherence

| Layer | Question answered |
|-------|-------------------|
| NHANES | Where does this sit in the **general U.S. population**? |
| ATSDR EA | How does this compare to **documented exposed communities**? |
| HBM4EU | How does this compare to **harmonized European HBM**? |
| UCMR5 | What **environmental** occurrence context exists? (not body burden %) |

## Product positioning

PFAS Enterprise 5.0 is **governed PFAS exposure contextualization infrastructure**,
not PFAS disease-prediction AI. Multi-reference comparison is the differentiated
capability that supports consulting, institutional pilots, and external validation.
