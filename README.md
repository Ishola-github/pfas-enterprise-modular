# PFAS Enterprise 5.0

Human-centered PFAS screening intelligence platform.

PFAS Enterprise 5.0 helps laboratories, consultants, and environmental teams harmonize PFAS data, screen samples, generate model-card reports, route uncertain results to human review, and track sustainability impact.

## 5.0 Pillars

| Pillar | Purpose |
|--------|---------|
| Model Card PDF | OECD-style defensibility and client reporting |
| Provenance + Audit Log | Traceable run history, model version, recipe ID, report path |
| Human Review | QA approval, override, and reviewer notes |
| Applicability Domain Gate | Defers unknown samples to laboratory confirmation |
| Sustainability Metrics | Estimates avoided cost and CO₂ impact |

## Intended Use

Screening decision-support only.

This platform is **not**:

- EPA-approved
- ISO-accredited
- a certified laboratory method
- a replacement for EPA Method 1633 or EPA Method 533
- a clinical diagnostic system

**Strict demo wording:** PFAS Enterprise 5.0 is a screening decision-support platform, not a certified laboratory replacement.

## Shiny front ends

Install R packages for the 5.0 demo once: `install.packages(c("shiny", "httr", "jsonlite"))`.

- **`app.R`** — Minimal **PFAS Enterprise 5.0** UI that calls the HTTP API (`PFAS_API_URL`). Use for sales/demo against a deployed or local API.
- **`app_enterprise4_latestpfas.R`** — Loads the full **PFAS Enterprise 4.0** dashboard from `LatestPFAS.R` (historical main app). In RStudio: open this file and choose **Run App**, or `shiny::runApp("app_enterprise4_latestpfas.R")`.
- **`app_oecd_predictive_tox_skeleton.R`** — OECD/QSAR documentation-style Shiny skeleton (placeholders).

## Local API test

```bash
uvicorn api.main:app --reload
```

Health check:

```bash
curl http://127.0.0.1:8000/healthz
```

Prediction:

```bash
curl -X POST http://127.0.0.1:8000/predict \
  -H "Content-Type: application/json" \
  -d "{\"sample_id\":\"DEMO_001\",\"dtxsid\":\"DTXSID8030271\",\"method_id\":\"EPA_533\",\"matrix\":\"water\"}"
```

## Deployment

Deploy using:

- `Dockerfile`
- `render.yaml`
- PostgreSQL database (optional for the current demo API stub; wire in for production persistence)
- Environment variables from `.env.example`

## Demo tagline

Not a lab replacement. A force multiplier for the humans who run them.
