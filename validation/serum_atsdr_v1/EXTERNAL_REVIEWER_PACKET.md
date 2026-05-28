# ATSDR External Reviewer Packet (Kickoff v1)

Use this packet to run the first 2-5 external reviewer conversations for the
ATSDR lane without scope creep.

RUO only. Do not make clinical, regulatory, or certification claims.

---

## 1) Who to contact first (priority order)

Focus on professionals who can validate operational value, not generic app users.

| Priority | Persona | Why they matter | Target count |
|---|---|---|---|
| 1 | PFAS consulting scientists | Immediate paid-report buyers | 4 |
| 2 | Environmental-health academics | External method credibility | 3 |
| 3 | Exposure/toxicology analysts in small firms | Repeat workflow fit | 3 |

Do not start with consumer channels or broad social media audiences.

---

## 2) Outreach script (copy/paste)

Subject: RUO PFAS serum contextualization reproducibility pilot

```text
Hi <Name>,

I run PFAS Enterprise 5.0, a governed RUO workflow for serum PFOS/PFOA
contextualization using weighted NHANES references (with manifest + SHA
reproducibility and Docker parity).

I’m opening a small external reviewer pilot (2-5 experts) to test operational
fit for an ATSDR external-validation lane. This is not a clinical or regulatory
tool.

Would you be willing to do a 30-minute review and complete a short reproducibility
and usability checklist?

What you receive:
- frozen demo runbook
- evidence bundle format
- exact pass/fail criteria (run_id + output SHA)

Thank you,
<Your name>
```

---

## 3) Packet contents to send

Send these files/links only:

1. `validation/serum_demo_v1/EXTERNAL_REPRO_RUNBOOK.md`
2. `validation/serum_demo_v1/EVIDENCE_CHECKLIST.md`
3. `validation/serum_demo_v1/README.md`
4. `docs/GOVERNANCE.md`
5. `docs/RELEASES.md`
6. `validation/serum_atsdr_v1/INGEST_SOP.md`

Optional attachment: latest SOP Word/PDF export from `docs/sop/`.

---

## 4) What to ask reviewers to return

Required return set:

- `git rev-parse HEAD` tested
- V2 `run_id` and `output_csv_sha256`
- V1.1 `run_id` and `output_csv_sha256`
- Docker pass/fail (`ALL PASS`)
- 1-5 ratings:
  - installation friction
  - output clarity
  - trust in manifest/provenance
  - usefulness for client/report workflows
- willingness-to-pay signal:
  - `YES / MAYBE / NO` for paid contextualization report
- top 3 blockers

Use the sign-off template already in:
`validation/serum_demo_v1/EVIDENCE_CHECKLIST.md`.

---

## 5) Pass/fail gates for pilot readiness

Promote to ATSDR ingest only if:

1. At least 2 external reviewers reproduce canonical SHA outputs.
2. No unresolved high-severity reproducibility failure remains.
3. At least 1 reviewer indicates paid pilot interest (`YES` or strong `MAYBE`).
4. Requested feature changes do not violate RUO/matrix-governance boundaries.

If any gate fails, fix governance/packaging first, then rerun pilot.

---

## 6) Commercial framing to use (and avoid)

Use:
- governed PFAS contextualization
- reproducible exposure intelligence workflow
- RUO external-validation support

Avoid:
- AI diagnosis
- EPA-approved software
- automated compliance engine
- clinical interpretation claims

---

## 7) 30-day execution cadence

| Week | Action |
|---|---|
| 1 | Send 20 targeted outreach messages |
| 2 | Run 3 reviewer calls; collect sign-off forms |
| 3 | Resolve reproducibility/packaging blockers |
| 4 | Run 2 more reviews; decide go/no-go for ATSDR ingest |

Success metric: first paid pilot scoped from reviewer workflow demand.
