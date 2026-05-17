# PFAS Enterprise 5.0 — Serum lane governed releases

Immutable git tags for the serum PFOS/PFOA contextualization lane. Each release is
identified by **ontology version**, **pinned reference-table SHA-256**, and **reproducible
smoke evidence** (manifest `run_id` + output CSV hash).

**RUO only.** Not diagnostic, clinical, or regulatory. See [GOVERNANCE.md](GOVERNANCE.md).

---

## Release index

| Tag | Commit | Ontology | Reference table SHA-256 | Role |
|-----|--------|----------|-------------------------|------|
| `serum-v1.0-governed` | `864e473` | `pfos_pfoa_v1.json` v1.0.1 | `715cd8968e21c9e2404b4a10054ea44d78e52707c70d4b10289f1ba9c463e45c` | Sex/age strata; single-cycle weighted percentiles |
| `serum-v1.1-demographics` | `17f3a2d` | `pfos_pfoa_v1_1.json` v1.1.1 | `fe195d6206d98d1e2281213fdc937dace468b57f9f8518bfca0e3496d0ba8f19` | **Production default:** race-aware strata, LOD policy, cycles I/J/P in ref table |
| `serum-v1.1-race-aware` | `17f3a2d` | *(alias of `serum-v1.1-demographics`)* | same as v1.1 | Synonym tag for external naming |
| `serum-v2.0.0-temporal` | `d7f3398` | `pfos_pfoa_v2.json` v2.0.0 | uses v1.1 table (`fe195d62…`) | Cross-cycle population percentile comparison (I/J/P) |
| *(infra)* | `e237739` | — | — | Docker verify + V2 recheck wired (`Dockerfile.linux-verify`) |

---

## Canonical fixture (NHANES cycle J, full demographics)

| Artifact | SHA-256 | Notes |
|----------|---------|-------|
| `data/v1/fixtures/nhanes_j_governed_v1_input.csv` | `73b5b5da3faec469a05a082c53060b1b6bca2a9bb0900acab448e7b4cded96ee` | 7,716 rows (1,929 × 4 isomers) |
| V2 output report (fixture run) | `87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67` | `run_id=2bda057f5ab18ff6` |
| V1.1 output report (fixture run) | `ebb3daf421c291292b7c0c891d9fdf75313bd57fb8011f0aa1c8451ddd4057fa` | `run_id=583780b861049800` |

---

## Reproduce a release

### Checkout

```bash
git fetch --tags
git checkout serum-v2.0.0-temporal   # example
```

### V1.1 (production default)

```powershell
cd <repo-root>
python -m src.v1.cli --v1-1 `
  --input data\v1\fixtures\nhanes_j_governed_v1_input.csv `
  --output-dir data\v1\outputs
```

### V2 temporal

```powershell
python -m src.v2.cli `
  --input data\v1\fixtures\nhanes_j_governed_v1_input.csv `
  --output-dir data\v2\outputs
```

### Three-environment reference confirmation

```powershell
# PowerShell
Get-FileHash -Algorithm SHA256 data\reference_tables\nhanes_pfas_weighted_reference_tables_v1_1.csv

# Docker/Ubuntu
docker run --rm -v "${PWD}:/app" -w /app ubuntu:22.04 bash -c `
  "sed -i 's/\r$//' scripts/confirm_reference_tables_docker.sh && bash scripts/confirm_reference_tables_docker.sh"
```

Expected v1.1 line: `fe195d6206d98d1e2281213fdc937dace468b57f9f8518bfca0e3496d0ba8f19`.

### Full Linux/Docker verify (bind-mount repo)

```powershell
docker build -f Dockerfile.linux-verify -t pfas-linux-verify .
docker run --rm -v "${PWD}:/app" -w /app pfas-linux-verify
```

---

## Shiny operational default

After commit `main` ≥ governance hardening: **Reports → V1** uses `--v1-1` by default
(race-aware). Legacy V1.0 available via checkbox **Use legacy V1.0 ontology**.

---

## Tag discipline

1. Do not move or force-push serum lane tags.
2. Rebuild reference tables only with versioned builder scripts; update ontology pins and this file.
3. Record new `run_id` / output SHA in manifest JSON under `data/v1/outputs` or `data/v2/outputs` when validating a release candidate.
