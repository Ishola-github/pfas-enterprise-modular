# Limitations — serum lane V2 (cross-cycle temporal)

| Field | Value |
|-------|-------|
| Lane | serum (human biomonitoring) |
| Version | 2.0.0 |
| Builds on | V1.1 single-cycle contextualization |

## Non-claims (binding)

- **Not individual longitudinal follow-up.** NHANES cycles are independent
  cross-sections. V2 compares **population reference distributions**, not the
  same participant over time.
- **Not causal inference.** A change in percentile rank across cycles does
  not prove exposure increased or decreased in the U.S. population without
  additional epidemiologic design.
- **Not diagnostic, not clinical, not regulatory.** Inherits all V1 non-claims.
- **Not a substitute for V1.** Regulatory or contractual single-cycle
  reporting must cite V1/V1.1 outputs, not V2 alone.
- **Cycle P caveat.** Cycle P (2017-2020) uses pre-pandemic weights (`WTSBAPRP`)
  and a different survey window; cross-cycle deltas involving P require
  explicit analyst acknowledgment.

## What V2 adds beyond V1

V1 answers: "Where does this value sit in cycle J (or chosen cycle)?"

V2 answers: "How does that rank shift if the same demographic stratum were
referenced against cycles I, J, and P?"

That supports **temporal exposure intelligence** at the population-reference
level only.
