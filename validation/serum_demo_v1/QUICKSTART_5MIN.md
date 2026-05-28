# 5-minute reviewer path — serum demo v1

**Program:** Independent Reproducibility Pilot (RUO).  
**Frozen tag:** `serum-v2.0.0-temporal` · **Do not use moving `main` during active pilot.**

---

## Prerequisites

- Git, Docker (Linux containers on Windows/macOS/Linux)
- ~5 minutes after image build (first build ~3–8 min)

---

## Commands (copy/paste)

```bash
git clone https://github.com/Ishola-github/pfas-enterprise-modular.git pfas-repro
cd pfas-repro
git fetch --tags
git checkout serum-v2.0.0-temporal

docker build -f Dockerfile.linux-verify -t pfas-linux-verify .
docker run --rm -e CI=true -e GITHUB_ACTIONS=true -v "$(pwd):/app" -w /app pfas-linux-verify
```

**Windows PowerShell** (same steps; use `${PWD}` instead of `$(pwd)` in the volume mount).

---

## Expected result (PASS)

Terminal must end with:

```text
=== Linux verify: ALL PASS ===
```

This run includes:

- R parse smoke
- V2 recheck (CLI + tests)
- V1.1 race-aware column guard
- Reference registry verification (CI scope)
- API smoke

---

## Optional: canonical run SHA check (~2 min extra)

```bash
docker run --rm -v "$(pwd):/app" -w /app pfas-linux-verify bash -c "
  export PYTHONPATH=/app
  python -m src.v2.cli --input data/v1/fixtures/nhanes_j_governed_v1_input.csv --output-dir data/v2/outputs/quickstart
  python -m src.v1.cli --v1-1 --input data/v1/fixtures/nhanes_j_governed_v1_input.csv --output-dir data/v1/outputs/quickstart
"
```

Compare stdout JSON to `validation/serum_demo_v1/canonical_pins.json`:

| Field | Expected |
|-------|----------|
| V2 `run_id` | `2bda057f5ab18ff6` |
| V2 `output_csv_sha256` | `87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67` |
| V1.1 `run_id` | `583780b861049800` |
| V1.1 `output_csv_sha256` | `ebb3daf421c291292b7c0c891d9fdf75313bd57fb8011f0aa1c8451ddd4057fa` |

---

## Return

Complete `REVIEWER_ATTESTATION_TEMPLATE.txt` and email to the program operator.

Full protocol: `BLIND_EXTERNAL_REPRO_PROTOCOL.md`
