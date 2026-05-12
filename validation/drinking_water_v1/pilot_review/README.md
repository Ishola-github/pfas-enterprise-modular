# Pilot reviewer validation — drinking water v1

Human and operational validation: **can real reviewers use the system correctly, and are outputs useful for screening / prioritization?**

This phase tests **trust and workflow**, not model architecture. It belongs **after** (or late alongside) **external blind** validation, once the frozen model and **τ** are credible.

## Folder layout

| Path | Purpose |
| ---- | ------- |
| **`forms/`** | Blank templates; do not commit filled forms with PII — use **`raw/`** locally (gitignored) |
| **`templates/`** | Session and synthesis scaffolds (**session plan, observation log, synthesis**) |
| **`results/`** | Anonymized syntheses, aggregated scores, quotes approved for internal use |
| **`observations/`** | Facilitator notes: timing, task completion, false-positive burden impressions |
| **`raw/`** | **Local only** — original signed forms, identifiable notes (see `.gitignore`) |

## Bootstrap (PowerShell)

From project root:

```powershell
mkdir .\validation\drinking_water_v1\pilot_review\forms -Force
mkdir .\validation\drinking_water_v1\pilot_review\results -Force
mkdir .\validation\drinking_water_v1\pilot_review\observations -Force
mkdir .\validation\drinking_water_v1\pilot_review\raw -Force
```

## Protocol

**`../reports/PILOT_REVIEW_PROTOCOL_v1.md`**

## Feedback instrument

**`forms/reviewer_feedback_template.md`** — copy per reviewer; archive completed copies under **`raw/`**; summarize in **`results/`**.

Additional templates:

- **`templates/PILOT_REVIEW_SESSION_PLAN_v1.md`**
- **`templates/PILOT_REVIEW_OBSERVATION_LOG_v1.csv`**
- **`templates/PILOT_REVIEW_SYNTHESIS_v1.md`**

## Evaluation dimensions

1. **Flag usefulness** — Did flagged items deserve review?  
2. **False-positive burden** — Overwhelming vs acceptable for screening? (High recall / lower precision can still be OK if disclosed.)  
3. **Applicability-domain behavior** — Honest rejection of unsupported matrices/methods?  
4. **Reporting clarity** — Threshold, uncertainty, intended use, limitations understandable **without** ad hoc explanation?

## Cross-references

- **`../reports/intended_use.txt`** — must match what reviewers see  
- **`../reports/FREEZE_v1.md`** — frozen **τ** and metrics context  
- **`../reports/applicability_domain.txt`** — scope reviewers should judge against  
