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

**RStudio — use the right tab:** The **Console** runs **R code only** (`source()`, `Sys.setenv()`, `shiny::runApp()`). Do **not** paste `Rscript ...`, `.\run_shiny_app.ps1`, or `Set-Location "C:\..."` there — those belong in **Terminal** (or external PowerShell). In the Console, run diagnostics with  
`source("scripts/check_r_environment.R", encoding = "UTF-8")`  
after **`Session → Set Working Directory → To Project Directory`** (or **`setwd(...)`** to your repo root).

**PowerShell — execution policy:** If `.\run_shiny_app.ps1` says scripts are disabled, either allow scripts for your user once:  
`Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`  
or run a single session without changing policy:  
`powershell -NoProfile -ExecutionPolicy Bypass -File .\run_shiny_app.ps1`

**Paths:** Replace any placeholder like `C:\path\to\repo-root` with your real folder (the one where **`Test-Path .\LatestPFAS.R`** is **`True`**), e.g.  
`Set-Location "C:\Users\you\OneDrive\Desktop\python_work\PFAS_on_R_Studio"`  
(or **`...\pfas-enterprise-modular`** if that is where the clone lives).

**RStudio vs `Rscript`:** They may use **different R executables** and **different package libraries**. Packages can appear installed in RStudio but be missing when you run `Rscript` in PowerShell. Compare environments with:

```powershell
Rscript scripts/check_r_environment.R
```

Run the same in **RStudio** via **Source** or `source("scripts/check_r_environment.R")` and diff the output.

**PowerShell + `Rscript`:** Packages install under your **per-user** library (not `C:\Program Files\R\...` unless you run as Administrator). On Windows this is often **`%LOCALAPPDATA%\R\win-library\<x.y>`** or **`%USERPROFILE%\Documents\R\win-library\<x.y>`** — they can differ between machines and R versions. Scripts **`scripts/_win_user_lib.R`** / **`r_user_lib_path.R`** respect **`R_LIBS_USER`** if set, otherwise pick an existing folder or default to LocalAppData. Either use **RStudio** (its configured R + library), or:

1. One-time:  
   `Rscript --vanilla scripts/install_r_deps_win_user_lib.R`
2. Then set **`R_LIBS_USER`** to that folder, or run:  
   `.\run_shiny_app.ps1` or `.\scripts\run_shiny_app.ps1`  
   (run **from the repo root**; the script sets **`R_LIBS_USER`** and starts **`shiny::runApp`**).

**Repo root:** the folder that contains **`LatestPFAS.R`**, **`app.R`**, and **`run_shiny_app.ps1`** (not a parent folder). If **`.\run_shiny_app.ps1`** is missing, you may be one level too high (e.g. `PFAS_on_R_Studio` with the real clone in **`pfas-enterprise-modular\`**). Check:

```powershell
Test-Path .\LatestPFAS.R
Get-ChildItem -Path . -Recurse -Filter run_shiny_app.ps1 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
```

Then **`Set-Location`** into that directory and run the script again.

**Find `Rscript.exe` (do not type `R-4.x.x` — that is not a real folder on your PC):** In PowerShell:

```powershell
& ".\scripts\find_rscript.ps1"
```

If policy blocks `.ps1`, use:

```powershell
( Get-ItemProperty "HKLM:\SOFTWARE\R-core\R" ).InstallPath
```

Then build the path yourself, e.g. `...\R-4.6.0\bin\Rscript.exe` (your version will differ). Or list installs:

```powershell
Get-ChildItem "C:\Program Files\R" | ForEach-Object { Join-Path $_.FullName "bin\Rscript.exe" } | Where-Object { Test-Path $_ }
```

**Without the `.ps1` wrapper** — from the repo root. Use the **same** `Rscript.exe` for install and for `runApp`:

```powershell
$Rscript = & ".\scripts\find_rscript.ps1"
$lib = (& $Rscript --vanilla .\scripts\r_user_lib_path.R).Trim()
$env:R_LIBS_USER = $lib
& $Rscript --vanilla .\scripts\install_r_deps_win_user_lib.R
& $Rscript -e "shiny::runApp('.', port=3838, launch.browser=TRUE)"
```

(`shiny::runApp` takes an **application directory** that contains `app.R`, not the filename `app.R` alone.)

If **Git** says *no tracking information for the current branch*, set upstream once:  
`git branch --set-upstream-to=origin/main main` then `git pull` (or after a **force push**: `git fetch origin` and `git reset --hard origin/main` only if you accept losing unpushed local commits).

**`refusing to merge unrelated histories`:** the folder had a separate initial commit vs `origin/main`. Use **`git fetch origin`** then **`git reset --hard origin/main`** to match GitHub (discard local-only history), or re-clone into a new folder.

If **`git reset`** warns it **cannot unlink** `pfas_collection.sqlite`, close **RStudio** / any app using that file, then run **`git reset --hard origin/main`** again (or delete the locked file after backup, only if safe).

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
