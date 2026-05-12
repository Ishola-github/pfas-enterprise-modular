# PFAS Enterprise — Drinking-water validation plan (v1)

## 0. Intended use (locked)

```text
The PFAS app is a screening and prioritization decision-support tool.
It does not replace EPA 533, EPA 537.1, EPA 1633, LC-MS/MS confirmation,
ISO/IEC 17025 reporting, analyst review, or regulatory release.
```

**Regulatory / method context (reference only):** EPA describes Methods **533** and **537.1** as drinking-water PFAS laboratory methods and states that together they can measure **29 PFAS** in drinking water. See [EPA PFAS drinking water laboratory methods](https://www.epa.gov/pfas/epa-pfas-drinking-water-laboratory-methods).

This document describes **software** and **scientific/model** validation layers for a **single** workflow first; it does not claim accreditation, formal method validation, or compliance release.

### 0b. Structured validation evidence (v1)

| Deliverable | Path |
| ----------- | ---- |
| Version freeze (what must not drift without a version bump) | `reports/FREEZE_v1.md` |
| Intended use (standalone text for bundles / PDF) | `reports/intended_use.txt` |
| Acceptance criteria before further testing | `reports/acceptance_criteria_v1.md` |
| Files to copy from pipeline outputs | `reports/EVIDENCE_COPY_CHECKLIST.md` |
| Repeatability (three identical runs) | `reports/REPEATABILITY_v1.md` |
| Failure-case / bad-input matrix | `reports/failure_case_validation.md` |
| Applicability domain (validated scope) | `reports/applicability_domain.txt` |
| Validation summary PDF outline | `reports/VALIDATION_SUMMARY_PDF_OUTLINE.md` |
| Product-status framing (strict verdict) | `reports/STRICT_VERDICT_PRODUCT_STATUS.md` |
| External blind protocol | `reports/EXTERNAL_BLIND_PROTOCOL_v1.md` |
| External blind pack (data / results / screenshots) | `external_blind/` |
| External blind results template | `external_blind/results/EXTERNAL_BLIND_RESULTS_v1.md` |
| One-command SHA-256 for frozen bundle | `scripts/write_run_hashes.ps1` or `scripts/write_run_hashes.cmd` → `runs/<run_id>/hashes.txt` (see `runs/_TEMPLATE/README.md`) |
| Pilot reviewer protocol (human / operational) | `reports/PILOT_REVIEW_PROTOCOL_v1.md` |
| Pilot review pack (forms, results, observations) | `pilot_review/` |
| Controlled doc index & register (repo) | `docs/SOP_INDEX.md`, `docs/CONTROLLED_DOCUMENTS.md`, `docs/CHANGELOG.md` |

### 0c. Recommended validation sequence (v1)

| Phase | Goal | Primary evidence |
| ----- | ---- | ---------------- |
| **1 — Repeatability** | Same inputs → same outputs (3×) | `reports/REPEATABILITY_v1.md`, stable hashes/metrics |
| **2 — External blind** | Generalization to unseen PFAS data; **no** retrain; **no** τ tuning | `external_blind/results/EXTERNAL_BLIND_RESULTS_v1.md` |
| **3 — Pilot reviewers** | Workflow utility, trust, operational burden | `pilot_review/results/` (anonymized), `forms/` templates |

Defer heavy **deployment locking** (Docker, CI, hosted enterprise) until these three are substantively underway — avoid industrializing an unvalidated workflow.

---

## 1. Two validation layers

| Layer | What it proves | Primary evidence |
| ----- | -------------- | ---------------- |
| **Software validation** | Correct handling of inputs, schema, units, errors, workflow separation, exports, reproducibility of the pipeline | Automated checks, scripted runs, logs, screenshots, version pins |
| **Scientific / model validation** | Performance of the screening model under a declared design (splits, threshold policy, metrics) for **drinking-water–style** UCMR5 / EPA 533 / EPA 537.1–style data | Holdout and **external blind** metrics, confusion matrices, failure analysis |

---

## 2. Validate one workflow first (scope lock)

**In scope for v1:**

```text
Drinking-water PFAS screening using UCMR5 / EPA 533 / EPA 537.1 style data
```

**Out of scope for v1 (do not mix into the same acceptance run):** sludge, serum, air, and other matrices until this workflow is closed with a signed-off report.

---

## 3. Validation datasets (three sets)

| Dataset | Purpose | Rules |
| ------- | ------- | ----- |
| **Training set** | Fit / train the model | Document source, time window, and inclusion criteria |
| **Internal holdout** | Tune **threshold** and compare variants | Never tune threshold on the external blind set |
| **External blind set** | **Real** scientific validation | Held out until design and acceptance criteria are fixed; no peeking for threshold tuning |

**Hard rule:** Never tune the decision threshold on the same dataset you label “external validation.”

---

## 4. Acceptance criteria (define before testing)

Set numeric targets for the **screening** use case (recall and NPV prioritized). Example starting point—**adjust with sponsor sign-off** before any formal gate:

| Metric | Minimum / target (example) |
| ------ | ---------------------------- |
| Recall | ≥ 0.90 |
| NPV | ≥ 0.90 |
| Precision | Improve above current baseline (~0.35) |
| False-positive rate (negatives) | Reduce below current baseline (~0.60) |
| Group overlap (train vs holdout vs external IDs) | **0** |
| Audit artifacts | **100%** generated for each gated run |

Document the **exact** definitions used (e.g. how non-detects are scored, which column is “truth,” which population defines specificity/NPV).

---

## 5. Per-run validation checklist (save for every run)

Store under `validation/drinking_water_v1/runs/<run_id>/` (or equivalent):

```text
input file hash(es)
model version / artifact id
script version (git SHA or tagged release)
threshold used
training / holdout split specification (seed, indices file, or hash of split script)
confusion matrix
recall, precision, specificity, NPV, false positive rate
feature importance (or model-specific explainability artifact)
test predictions CSV
app screenshot(s) for UI-gated steps
pipeline / audit logs
```

---

## 6. Reproducibility test

Run the **same** labeled pipeline **three times** with identical:

```text
same input + same seed + same model version = same metrics
```

If metrics drift without an intentional change, treat the build as **not validation-ready** until nondeterminism is removed or bounded (documented variance).

---

## 7. Software validation — app behavior matrix

| Test | Pass criteria |
| ---- | ------------- |
| Wrong file uploaded | App rejects with a clear, actionable message |
| Missing columns | App reports **exact** missing fields (schema-aligned) |
| Wrong units | App blocks or converts with an **audit-visible** note |
| Duplicate samples | App flags duplicates (ID + key fields) |
| Non-detects | Consistent handling vs schema and documented rules |
| Threshold change | Reported metrics update consistently with the new threshold |
| Report export | Includes **disclaimer** + **provenance** (versions, data sources, intended use) |
| Screening vs evidence-governed | **No silent mixing** of paths, outputs, or claims |

---

## 8. Applicability domain gate (requirements)

The app should **warn or block** when inputs fall outside the v1 drinking-water screening domain, including when appropriate:

```text
matrix ≠ drinking water
method not EPA 533 / 537.1–style (or not declared / not recognized)
unknown analyte
unknown unit
missing sample date
missing result value
out-of-range concentration (per declared plausibility rules)
```

Implementation status should be tracked in software validation results (pass / partial / not implemented) with references to UI text and logs.

---

## 9. Validation report outline (deliverable)

```text
1. Intended use
2. Data sources
3. Version numbers (app, scripts, model, environment)
4. Validation design (splits, blinding, threshold policy)
5. Acceptance criteria (as approved)
6. Results (software + model), including confusion matrices
7. Failure cases and root causes
8. Limitations and applicability domain
9. Decision rule (how screening output is used / not used)
10. Conclusion: screening / triage / prioritization only — not compliance release
```

---

## 10. Strict verdict (product claims)

| Claim | Allowed today |
| ----- | ------------- |
| PFAS **screening / triage / prioritization** software | Yes — validate against Sections 1–9 |
| **ISO/IEC 17025 analytical reporting system** | No — not a substitute for laboratory QMS, accreditation, or regulatory release |

---

## 11. Artifact layout (this repo)

```text
validation/drinking_water_v1/
  VALIDATION_PLAN.md          ← this file
  reports/                    ← intended use, freeze, acceptance criteria, outlines
  artifacts/                  ← frozen copies of metrics JSON, manifests, etc. (see EVIDENCE_COPY_CHECKLIST)
  screenshots/                ← UI / ML results panel captures
  datasets/                   ← hashes, small manifests; large raw tables usually local-only
  runs/                       ← per-run bundles (manifest + logs; gitignored if large)
    _TEMPLATE/                ← README + manifest.example.json + manifest.schema.json
  external_blind/             ← blind validation pack: README, data/, results/, screenshots/
  pilot_review/               ← reviewer study: forms/, results/, observations/, raw/ (gitignored)
```

Large CSVs or exports should be **gitignored** or stored outside git; store **hashes** and small manifests in-repo when needed.

---

## 12. Quick command (folder bootstrap)

From the project root:

```powershell
mkdir validation\drinking_water_v1\runs -Force
mkdir validation\drinking_water_v1\external_blind -Force
mkdir validation\drinking_water_v1\external_blind\data -Force
mkdir validation\drinking_water_v1\external_blind\results -Force
mkdir validation\drinking_water_v1\external_blind\screenshots -Force
mkdir validation\drinking_water_v1\artifacts -Force
mkdir validation\drinking_water_v1\reports -Force
mkdir validation\drinking_water_v1\screenshots -Force
mkdir validation\drinking_water_v1\datasets -Force
mkdir validation\drinking_water_v1\pilot_review\forms -Force
mkdir validation\drinking_water_v1\pilot_review\results -Force
mkdir validation\drinking_water_v1\pilot_review\observations -Force
mkdir validation\drinking_water_v1\pilot_review\raw -Force
```

Place every gated validation run’s artifacts under `runs\<run_id>\` with the checklist in Section 5. Use `artifacts\`, `screenshots\`, and `reports\` for the **v1.0 frozen evidence** set described in `reports/EVIDENCE_COPY_CHECKLIST.md`.
