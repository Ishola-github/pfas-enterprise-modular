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

- **`app.R`** — **Recommended default:** loads **Enterprise 4.0** from `LatestPFAS.R` on tab *Enterprise 4.0*, and **Cloud API 5.0** (`POST /predict` to `PFAS_API_URL`) on tab *Cloud API 5.0*. API inputs are a **Shiny module** (`api5_…`) so they do not clash with duplicate IDs such as `sample_id` in the legacy app.
- **`app_enterprise5_api_only.R`** — **API-only** demo (same as the previous standalone 5.0 UI). Use when you do not have `LatestPFAS.R` or want a minimal Shiny surface.
- **`app_enterprise4_latestpfas.R`** — **Legacy 4.0 only** (no API tab): `source()`s `LatestPFAS.R` and returns its `shinyApp`. Use if you need the exact single-page app without `navbarPage`.
- **`app_oecd_predictive_tox_skeleton.R`** — OECD/QSAR documentation-style Shiny skeleton (placeholders).

## Local API test

From the repo root (`pfas-toxicology/`). On Windows, prefer **`python -m uvicorn`** so you do not rely on the `Scripts` folder being on `PATH` (Store Python often warns that `uvicorn.exe` is not on `PATH`).

```bash
python -m uvicorn api.main:app --reload --host 127.0.0.1 --port 8000
```

Equivalent if `uvicorn` is on your `PATH`:

```bash
uvicorn api.main:app --reload --host 127.0.0.1 --port 8000
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

- `Dockerfile` (build context is repo root; `.dockerignore` excludes large local `data/`, legacy trees, and Shiny-only artifacts)
- `render.yaml` (Blueprint: Docker web service + PostgreSQL on a **current** instance type, e.g. `basic-256mb`; legacy DB `starter` is rejected for new databases)
- PostgreSQL from the blueprint (optional for the current demo API stub; connect in code when you add persistence)
- Environment variables from `.env.example`

### Render (Blueprint)

1. In [Render](https://render.com): **New** → **Blueprint**.
2. Connect your GitHub account and select the repo that contains this `Dockerfile` and `render.yaml` (for example **`pfas-enterprise-modular`** or this project’s canonical remote).
3. Review the detected services and **Apply**.

After deploy, substitute your service URL:

- `https://<your-service>.onrender.com/healthz`
- `POST https://<your-service>.onrender.com/predict`

Use this line in demos and UI footers:

> PFAS Enterprise 5.0 is a screening decision-support platform, not a certified laboratory replacement.

## Demo tagline

Not a lab replacement. A force multiplier for the humans who run them.
