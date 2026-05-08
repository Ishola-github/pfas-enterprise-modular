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

**RStudio:** In the **R Console** (not PowerShell), set the API base if needed, then Run App:

```r
Sys.setenv(PFAS_API_URL = "https://pfas-enterprise-5.onrender.com")
# shiny::runApp()  or  Run App on app.R
```

In **PowerShell**, `Sys.setenv(...)` is invalid. Use `$env:PFAS_API_URL = "https://..."` for tools you launch from that shell only.

**RStudio vs `Rscript`:** They may use **different R executables** and **different package libraries**. Packages can appear installed in RStudio but be missing when you run `Rscript` in PowerShell. Compare environments with:

```powershell
Rscript scripts/check_r_environment.R
```

Run the same in **RStudio** via **Source** or `source("scripts/check_r_environment.R")` and diff the output.

**PowerShell + `Rscript`:** Packages install under **`%USERPROFILE%\Documents\R\win-library\<R-x.y>`** (not under `C:\Program Files\R\...`) unless you run as Administrator. So either use **RStudio** (it uses its configured R + library), or:

1. One-time:  
   `Rscript --vanilla scripts/install_r_deps_win_user_lib.R`
2. Then set **`R_LIBS_USER`** to that folder, or run:  
   `.\scripts\run_shiny_app.ps1`  
   (run **from the repo root**; the script sets **`R_LIBS_USER`** and starts **`shiny::runApp`**).

Install R packages for full `LatestPFAS.R` once: rely on **`scripts/install_r_deps_win_user_lib.R`** or in R:  
`install.packages(c("shiny", "shinydashboard", "shinymanager", "DT", "ggplot2", "dplyr", "tidyr", "tibble", "purrr", "stringr", "scales", "jsonlite", "httr", "digest", "DBI", "RSQLite"))`

- **`app.R`** — **Default Run App entry:** loads **`LatestPFAS.R`**, which includes sidebar **Enterprise 5.0 (Cloud API)** (`POST /predict` via **`PFAS_API_URL`**) plus the full dashboard, GLP, and data-collection workflows.
- **`app_enterprise4_latestpfas.R`** — Same as **`app.R`** (thin `source("LatestPFAS.R")` loader); kept for older docs/scripts that reference this filename.
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
