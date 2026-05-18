# Serum Demo External Reviewer Packet (Kickoff v1)

Use this packet to run the first **2–5 external blind reproducibility reviews** for
`validation/serum_demo_v1` (Phase 1 technical validation).

**RUO only.** Do not make clinical, regulatory, or certification claims.

---

## 1) Who to contact first (priority order)

| Priority | Persona | Why they matter | Target count |
|----------|---------|-----------------|--------------|
| 1 | PFAS consulting scientists | Operational report buyers | 4 |
| 2 | Environmental-health academics | Method credibility | 3 |
| 3 | Exposure/toxicology analysts (small firms) | Repeat workflow fit | 3 |

Do not start with consumer channels or broad social audiences.

---

## 2) Outreach script (copy/paste)

**Subject:** RUO PFAS serum contextualization — blind reproducibility pilot (30 min)

```text
Hi <Name>,

I run PFAS Enterprise 5.0, a governed research-use-only workflow for serum
PFOS/PFOA contextualization against weighted NHANES references, with manifest
provenance (run_id + SHA-256) and Docker/Linux parity checks.

I am opening a small external reviewer pilot (2–5 experts) to validate blind
reproducibility of a frozen demo package. This is not a clinical or regulatory tool.

Would you complete a ~45–90 minute reproducibility run and return a short
checklist (pass/fail on canonical run_id and output SHA)?

You receive:
- BLIND_EXTERNAL_REPRO_PROTOCOL.md (primary — Docker-only Mode A preferred)
- EXTERNAL_REPRO_RUNBOOK.md (host Python fallback)
- canonical_pins.json (expected hashes)
- REVIEWER_ATTESTATION_TEMPLATE.txt (signed return)

Repo: https://github.com/Ishola-github/pfas-enterprise-modular
Tag: serum-v2.0.0-temporal

Thank you,
<Your name>
```

---

## 3) Packet contents to send

Send **only** these paths (zip or shared folder):

1. `validation/serum_demo_v1/BLIND_EXTERNAL_REPRO_PROTOCOL.md`
2. `validation/serum_demo_v1/EXTERNAL_REPRO_RUNBOOK.md`
3. `validation/serum_demo_v1/REVIEWER_ATTESTATION_TEMPLATE.txt`
4. `validation/serum_demo_v1/EVIDENCE_CHECKLIST.md`
5. `validation/serum_demo_v1/README.md`
6. `validation/serum_demo_v1/canonical_pins.json`
7. `validation/serum_demo_v1/INTENDED_USE.txt`
8. `docs/GOVERNANCE.md` (excerpt or full — reviewer preference)
9. `docs/RELEASES.md` (release pin table)

**Do not** send pre-built report CSVs/PDFs from sponsor machines (defeats blind repro).

Optional: `docs/sop/PFAS_Enterprise_5_SOP_Rev2.1.docx` export.

**Do not** send unrelated matrix-lane training data or internal pilot CSVs.

---

## 4) What reviewers must return

Required:

| Field | Example |
|-------|---------|
| Git commit tested | `a269445…` or tag `serum-v2.0.0-temporal` |
| V2 `run_id` | `2bda057f5ab18ff6` |
| V2 `output_csv_sha256` | `87c8b97e…` |
| V1.1 `run_id` | `583780b861049800` |
| V1.1 `output_csv_sha256` | `ebb3daf4…` |
| Reference v1_1 SHA match | YES / NO |
| Docker `ALL PASS` | YES / NO / NOT RUN |

Usability (1–5): install friction, output clarity, manifest trust, client-report usefulness.

Sign-off block: see `EVIDENCE_CHECKLIST.md`.

---

## 5) Pass / fail gates (promote to “validated demo”)

| Gate | Pass |
|------|------|
| V2 reproducibility | `run_id` + CSV SHA match canonical |
| V1.1 reproducibility | `run_id` + CSV SHA match canonical |
| Reference integrity | v1_1 SHA = `fe195d6206d98d1e2281213fdc937dace468b57f9f8518bfca0e3496d0ba8f19` |
| No silent schema loss | V1.1 race columns present in CSV header |
| Docker (recommended) | Full verify ends `ALL PASS` |

**Fail:** any SHA mismatch without documented, governed pin update in `RELEASES.md`.

---

## 6) 30-day execution cadence

| Week | Action |
|------|--------|
| 1 | Send packet to 5–8 contacts; goal 3 accepts |
| 2 | Office hours (30 min) for install blockers |
| 3 | Collect returns; log in `validation/serum_demo_v1/reviewer_log.csv` |
| 4 | Summarize: pass rate, friction themes, go/no-go for institutional pilot |

---

## 7) Commercial framing (allowed)

- Governed PFAS exposure contextualization with audit trail
- Population-referenced percentiles (NHANES-weighted)
- Cohort/temporal comparison for consulting narratives

**Not allowed:** diagnosis, EPA approval, ISO certification, litigation automation.

---

## 8) Operator commands (you, before send)

```powershell
cd C:\Users\techj\Downloads\pfas-toxicology\pfas-toxicology
$env:PYTHONPATH = (Get-Location).Path

python -m src.v2.cli `
  --input data\v1\fixtures\nhanes_j_governed_v1_input.csv `
  --output-dir data\v2\outputs\external_repro

python -m src.v1.cli --v1-1 `
  --input data\v1\fixtures\nhanes_j_governed_v1_input.csv `
  --output-dir data\v1\outputs\external_repro

powershell -ExecutionPolicy Bypass -File scripts\confirm_reference_tables_powershell.ps1
powershell -ExecutionPolicy Bypass -File scripts\build_serum_validation_evidence_bundle.ps1
```

Optional zip for email:

```powershell
Compress-Archive -Path validation\serum_demo_v1\*.md,validation\serum_demo_v1\*.json,validation\serum_demo_v1\*.txt `
  -DestinationPath validation\serum_demo_v1\serum_demo_reviewer_packet.zip -Force
```
