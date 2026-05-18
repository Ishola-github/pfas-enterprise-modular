# Validation Evidence Bundle v1 — collection checklist

Use after completing [BLIND_EXTERNAL_REPRO_PROTOCOL.md](BLIND_EXTERNAL_REPRO_PROTOCOL.md) or [EXTERNAL_REPRO_RUNBOOK.md](EXTERNAL_REPRO_RUNBOOK.md).  
Return signed [REVIEWER_ATTESTATION_TEMPLATE.txt](REVIEWER_ATTESTATION_TEMPLATE.txt).  
Automated assembly: `scripts/build_serum_validation_evidence_bundle.ps1`

---

## Required artifacts

| # | Artifact | Source | Notes |
|---|----------|--------|-------|
| 1 | V2 manifest JSON | `data/v2/outputs/.../v2_manifest_2bda057f5ab18ff6.json` | Full provenance |
| 2 | V2 report CSV | `v2_report_2bda057f5ab18ff6.csv` | Governed output |
| 3 | V2 report PDF (RUO stub) | `v2_report_2bda057f5ab18ff6.pdf` | Optional visual |
| 4 | V1.1 manifest JSON | `v1_manifest_583780b861049800.json` | Race-aware run |
| 5 | V1.1 report CSV | `v1_report_583780b861049800.csv` | |
| 6 | Reference confirm (Docker) | `data/reference_tables/.confirm_docker.txt` | Includes v1_1 SHA |
| 7 | Reference confirm (PS) | `data/reference_tables/.confirm_powershell.txt` | If generated |
| 8 | Git tag list | `git tag -l serum-*` | Screenshot or text |
| 9 | Docker verify log | Terminal capture | Ends with ALL PASS |
| 10 | SOP Rev 2.1 | `docs/sop/PFAS_Enterprise_5_SOP_Rev2.1.docx` or `.md` | Controlled doc |

---

## Recommended screenshots

1. Shiny Reports tab — V1.1 panel with successful run status  
2. Shiny V2 panel — `run_id=2bda057f5ab18ff6`, demographics 7716/7716  
3. V2 report preview table (cross-cycle percentile columns)  
4. Docker `ALL PASS` terminal line  
5. `Get-FileHash` for v1_1 reference table showing `fe195d62…`  

Store under: `validation/serum_demo_v1/evidence_bundle/screenshots/`

---

## Reviewer sign-off block (paste into cover email)

```text
Reviewer name:
Organization:
Date:
Git commit tested:
V2 output_csv_sha256 matched canonical: YES / NO
V1.1 output_csv_sha256 matched canonical: YES / NO
Docker verify passed: YES / NO / NOT RUN
Usability (1-5):
Would pay for governed contextualization report: YES / NO / MAYBE
Comments:
```

---

## Bundle layout (after script run)

```text
validation/serum_demo_v1/evidence_bundle/
├── BUNDLE_MANIFEST.json
├── hashes.txt
├── canonical_pins.json
├── manifests/
├── reports/
├── confirm/
└── screenshots/   (manual)
```
