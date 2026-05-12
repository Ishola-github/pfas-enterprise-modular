# Pilot reviewer validation — protocol (v1)

**When:** After **repeatability** evidence and **external blind** validation (or in parallel with blind analysis, but not before the frozen model and τ are settled).

**What this is:** Human-factors and **operational** validation — not “is the model perfect?” but **“does this improve decision workflow?”**

## Research question

```text
Will environmental reviewers trust and use the workflow outputs?
```

## What you provide to reviewers

- Predictions / exceedance probabilities (at frozen **τ**, e.g. **0.25** per **`FREEZE_v1.md`**)
- Flags / prioritization ordering
- Applicability-domain and uncertainty messaging
- Intended-use and limitation language **as shipped** (no coaching beyond normal onboarding)

## Reviewer profiles (examples)

- Environmental scientist  
- PFAS consultant  
- Wastewater / utility reviewer  
- Toxicologist (as appropriate)  
- Laboratory reviewer (screening / triage lens — **not** as ISO 17025 replacement)

## Questions to ask (see `../pilot_review/forms/reviewer_feedback_template.md`)

- Was the output **understandable** without heavy support?  
- Was **prioritization** useful?  
- Were **false positives** acceptable given screening intent?  
- Were **uncertainty / applicability** warnings useful?  
- Would this **reduce workload** or **improve sample prioritization**?  
- Any **reporting clarity** gaps (threshold, limitations, intended use)?

## What you are validating

| In scope | Out of scope |
| -------- | ------------ |
| Workflow utility, clarity, trust in **screening / prioritization** | Proof of regulatory compliance or accredited analytical equivalence |
| Honest applicability behavior | “Perfect” precision |
| Whether review burden is **operationally** acceptable | Replacing analyst judgment |

## Product positioning (guardrail)

**Strong:** PFAS **screening** and **sample prioritization** decision-support.  
**Weak / risky:** PFAS **compliance automation** or accredited-lab replacement narratives.

## Early market fit (typical)

Consultants, utilities, wastewater operators, site assessment / remediation prioritization, academic collaborators — **not** “fully accredited compliance lab” as the first beachhead claim.

## Deliverables

Store under **`../pilot_review/`**:

- Completed (prefer **anonymized**) feedback  
- Workflow timing notes  
- False-positive / review-burden impressions  
- Usability observations  

See **`../pilot_review/README.md`** for folder layout.

## Sequencing note

Defer **Docker lockfiles, deployment manifests, hosted enterprise demos** until **repeatability**, **external blind**, and **pilot reviewer** evidence exist — otherwise you risk industrializing an unvalidated workflow.
