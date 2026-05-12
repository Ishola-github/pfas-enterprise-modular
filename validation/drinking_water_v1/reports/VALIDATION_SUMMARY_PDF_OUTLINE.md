# Validation summary PDF — outline (future deliverable)

Use this as the chapter list when generating a single PDF for sponsors or auditors.

1. Intended use (`reports/intended_use.txt`)
2. System architecture (high level: R/Shiny, Python steps, artifact paths)
3. Data sources (UCMR, NHANES serum bridge if used, external uploads — each documented)
4. Validation design (splits, blinding, threshold policy, freeze reference `FREEZE_v1.md`)
5. Metrics at freeze (link / embed `artifacts/` JSON excerpts)
6. Confusion matrices (holdout; external blind when available)
7. Repeatability evidence (`REPEATABILITY_v1.md`, stable hashes)
8. Pilot reviewer / operational validation (`pilot_review/` anonymized summaries)
9. Limitations and disclaimers
10. Failure-case results (`failure_case_validation.md`)
11. Applicability domain (`applicability_domain.txt`)
12. Conclusion: screening / triage / prioritization only — **not** regulatory compliance release
