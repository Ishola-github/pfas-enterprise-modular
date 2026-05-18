# External reproducibility runbook — serum demo v1

**Audience:** Independent reviewer (toxicology, environmental health, exposure science).  
**Time:** ~45–90 minutes first run (includes Docker build).  
**Goal:** Reproduce canonical `run_id` and output SHA-256 values in [README.md](README.md).

For **blind** external review (clean clone, no sponsor outputs, signed attestation), use
[BLIND_EXTERNAL_REPRO_PROTOCOL.md](BLIND_EXTERNAL_REPRO_PROTOCOL.md) — **Mode A (Docker-only) preferred.**

---

## Prerequisites

- Windows 10/11 with PowerShell, **or** Linux/WSL2 with Docker  
- Git  
- Python 3.10+ with repo `requirements.txt` installed, **or** use Docker image only  
- ~2 GB disk for NHANES raw XPTs (optional for demo; required only to rebuild reference tables)

---

## 1. Clone and checkout frozen tag

```powershell
git clone https://github.com/Ishola-github/pfas-enterprise-modular.git pfas-enterprise
cd pfas-enterprise
git fetch --tags
git checkout serum-v2.0.0-temporal
```

Record commit SHA:

```powershell
git rev-parse HEAD
```

---

## 2. Confirm reference table integrity

**PowerShell:**

```powershell
(Get-FileHash -Algorithm SHA256 data\reference_tables\nhanes_pfas_weighted_reference_tables_v1_1.csv).Hash.ToLower()
```

**Expected:** `fe195d6206d98d1e2281213fdc937dace468b57f9f8518bfca0e3496d0ba8f19`

**Docker/Ubuntu cross-check:**

```powershell
docker run --rm -v "${PWD}:/app" -w /app ubuntu:22.04 bash -c "sed -i 's/\r$//' scripts/confirm_reference_tables_docker.sh && bash scripts/confirm_reference_tables_docker.sh"
```

---

## 3. Run V2 cross-cycle contextualization (primary demo)

```powershell
python -m src.v2.cli `
  --input data\v1\fixtures\nhanes_j_governed_v1_input.csv `
  --output-dir data\v2\outputs\external_repro
```

**Pass criteria:**

- Exit code 0  
- JSON summary printed to stdout  
- `run_id` = `2bda057f5ab18ff6`  
- `output_csv_sha256` = `87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67`  
- `n_rows` = 7716, `n_in_domain` = 7716, `n_refused` = 0  
- `n_cross_cycle_shift_ge_15` = 1189  

---

## 4. Run V1.1 (race-aware) contextualization

```powershell
python -m src.v1.cli --v1-1 `
  --input data\v1\fixtures\nhanes_j_governed_v1_input.csv `
  --output-dir data\v1\outputs\external_repro
```

**Pass criteria:**

- `run_id` = `583780b861049800`  
- `output_csv_sha256` = `ebb3daf421c291292b7c0c891d9fdf75313bd57fb8011f0aa1c8451ddd4057fa`  

---

## 5. Docker full verify (optional but recommended)

```powershell
docker build -f Dockerfile.linux-verify -t pfas-linux-verify .
docker run --rm -v "${PWD}:/app" -w /app pfas-linux-verify
```

Must end with: `=== Linux verify: ALL PASS ===`

V2-only:

```powershell
docker run --rm --entrypoint bash -v "${PWD}:/app" -w /app pfas-linux-verify scripts/docker_recheck_v2.sh
```

---

## 6. Shiny UI smoke (optional)

Sync to RStudio project per SOP §8, launch Shiny, upload `nhanes_j_governed_v1_input.csv`, run V1.1 and V2. Capture screenshots per [EVIDENCE_CHECKLIST.md](EVIDENCE_CHECKLIST.md).

---

## 7. Submit findings

Email or share:

1. Your `git rev-parse HEAD`  
2. stdout JSON from V2 run (or manifest path)  
3. Whether SHA-256 values matched  
4. Usability notes (1–5 scale): install friction, clarity of outputs, trust in manifests  
5. Any refusal rows or unexpected strata  

**Do not** share patient-identifiable data in pilot feedback.

---

## Failure escalation

| Symptom | Likely cause |
|---------|----------------|
| Reference table drift error | Wrong or stale `v1_1` CSV — re-sync repo |
| Different `run_id` | Input fixture changed — verify input SHA |
| Docker CRLF errors | Run `sed` strip on bash scripts (see SOP §34) |
| R smoke JSON parse fail | Install `jsonlite` in R or use Python CLI only |
