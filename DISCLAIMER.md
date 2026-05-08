This document states what the PFAS Enterprise codebase **is** and **is not**, so expectations stay aligned with what the software can honestly support today.

## What this project is today

This is a **technical prototype / research scaffold**, **not** a production-grade PFAS regulatory platform.

It is valuable mainly as:

- A portfolio project and demonstration of scientific software craft  
- An internal R&D or data-integration workspace  
- A machine-learning and QSAR **experimentation** environment  
- A **screening / prioritization** demonstration aligned with transparency and weight-of-evidence thinking  
- A **compliance-oriented architecture** demo (audit concepts, QMS/ISO-style structure, checklists)—not proof of certification  

It is **not yet**:

- A validated EPA-compliant analytical system  
- A certified risk-assessment engine  
- A legally defensible regulatory-submission platform  
- A commercially mature SaaS with production SLAs, security review, and operational guarantees  

## What the application can realistically do now

### 1. PFAS data organization and exploration

The stack can help **centralize** datasets, **compare** model outputs, **track** experiments, **hold** metadata, **visualize** screening-oriented views, and **draft** internal reporting—when fed real or curated data. Much of the built-in content remains **placeholder or illustrative** until replaced with production assets.

### 2. Screening and prioritization (primary realistic use case)

The appropriate framing is **screening, prioritization, transparency review, and weight-of-evidence support** for R&D—not regulatory truth or compliance certification.

Reasonable uses include ranking compounds, flagging candidates for review, prioritizing follow-up testing, and triage—**provided**:

- Limitations are clearly disclosed  
- Predictions are not presented as regulatory determinations  
- Uncertainty and applicability domain are considered  
- No false compliance or analytical claims are made  

### 3. Internal ML / QSAR experimentation

The repository may be **strongest** as a place to benchmark descriptors, compare models, test thresholds, exercise applicability-domain logic, and build **reproducible** workflows—with validation discipline, not as a substitute for external blind validation or interlaboratory study.

### 4. Demonstration for grants, investors, or employers

The project can illustrate environmental toxicology familiarity, ML integration, QSAR architecture, validation-oriented thinking, ISO/QMS awareness, Shiny deployment, and multi-language glue (e.g. R + Python). That is a **legitimate** use for proposals, interviews, and consulting demos when described honestly.

## What the application cannot honestly do yet

### 1. Regulatory decision-making

Do **not** claim EPA approval, ELAP validation, regulatory equivalence, compliance certification, or defensible risk determination on the basis of this codebase alone. Production models, external validation, prospective testing, and regulatory acceptance are **not** established here by default.

### 2. Replacement for analytical chemistry (e.g. LC-MS/MS)

This software does **not**:

- Identify PFAS analytically in samples  
- Quantify PFAS concentrations for compliance  
- Replace EPA Methods **533**, **537.1**, **1633**, or isotope-dilution LC-MS/MS workflows  

It may **prioritize**, **screen**, **estimate** (with caveats), **organize**, and **suggest** next steps—not certify drinking water or replace certified laboratory measurement.

### 3. Commercial SaaS for regulated buyers without further work

Enterprise buyers typically expect validated models, security posture, provenance, uptime, user management, audit evidence, benchmarking studies, and documented uncertainty. This repository provides **partial architecture and demos**, not that full product maturity.

## Recommended public positioning

**Honest and viable:**

> PFAS screening and prioritization platform for environmental toxicology R&D and decision support—with clear limitations and human review.

**Avoid** overclaiming, for example:

> “PFAS compliance platform,” “AI PFAS detection,” “EPA-approved predictive engine,” or implying substitution for certified analytical methods.

## Suggested next steps (technical credibility)

1. **Replace placeholders** with curated real data (e.g. UCMR, CompTox, public PFAS literature datasets—subject to licensing and quality review).  
2. **Pick one narrow workflow** and drive it to genuine validation (e.g. water exceedance prioritization, AD flagging, one endpoint class)—instead of breadth without depth.  
3. **Surface uncertainty and applicability domain** consistently in UI and exports.  
4. **Publish or preprint** one retrospective or external validation study tied to that workflow—often more valuable than UI polish alone.  

## Summary

Closest honest comparison today: **advanced environmental toxicology / QSAR research prototype and screening dashboard**, not a **commercial enterprise PFAS compliance suite**.

Regulators and certified laboratories would not treat this as a substitute for methods or lab certification without substantial additional evidence. Researchers, consultants, startups, and reviewers **may** still find it useful **when scoped honestly** and evolved with real data and validation.

---

*This file is project documentation, not legal advice. Operators remain responsible for their claims, jurisdictions, and use contexts.*
