# ONE COMMAND REPRODUCIBILITY

**Program:** Independent Reproducibility Pilot · **RUO only**  
**Frozen tag:** `serum-v2.0.0-temporal` (commit `8ce2492`)  
**Zenodo:** https://doi.org/10.5281/zenodo.20348369

Full reviewer copy also lives at `validation/serum_demo_v1/ONE_COMMAND_REPRO.md`.

---

## 1. Clone and checkout

```bash
git clone https://github.com/Ishola-github/pfas-enterprise-modular.git pfas-repro
cd pfas-repro
git checkout serum-v2.0.0-temporal
```

**Windows:** use WSL2 or Git Bash with Docker Desktop running.

---

## 2. Run ONE command (Mode A — governance repro)

This is the **blind reviewer path**. It runs the same Linux verify stack as CI
(registry, schema guards, smoke API) plus a canonical V2 hash gate.

```bash
bash scripts/repro_one_shot.sh
```

**PASS** when the script exits `0` and prints:

```text
ONE_SHOT_REPRO: PASS
V2 output_csv_sha256: 87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67
```

Expect the Docker verify segment to end with:

```text
=== Linux verify: ALL PASS ===
```

**Expected runtime:** ~30-90 minutes (image build + verify), depending on network and CPU.

---

## Expected PASS conditions

| Gate | Evidence |
|------|----------|
| Docker/Linux reproducibility | `=== Linux verify: ALL PASS ===` inside `repro_one_shot.sh` |
| Registry CI pins | Step 1 of `docker_verify_linux.sh` (13 rows, `CI=true`) |
| Schema lock | pytest in Docker verify |
| Smoke API | 24/24 inside Docker verify |
| Canonical V2 output | `ONE_SHOT_REPRO: PASS` + SHA above |
| Frozen release | Tag `serum-v2.0.0-temporal` on commit `8ce2492` |

Governance CI on GitHub (operator): Governance Checks **#24** on `8ce2492`.

---

## Reviewer workflow

1. Clone repository (clean machine preferred).
2. `git checkout serum-v2.0.0-temporal`
3. Run `bash scripts/repro_one_shot.sh`
4. Compare printed V2 SHA to `validation/serum_demo_v1/canonical_pins.json`
5. Complete `validation/serum_demo_v1/REVIEWER_ATTESTATION_MINIMAL.txt`
6. Return **signed** attestation (no code changes, no scope expansion)

Optional protocol: `validation/serum_demo_v1/BLIND_EXTERNAL_REPRO_PROTOCOL.md`

---

## Mode B — operational API only (NOT the blind PASS path)

`docker compose up --build` starts the FastAPI service on port 8000. It requires
a local `.env` with `PFAS_API_KEYS` and does **not** run the full governance
repro bundle or canonical V2 hash check. Use only for API smoke after PASS, or
separate operational testing:

```bash
cp .env.example .env   # set PFAS_API_KEYS
docker compose up -d --build
python scripts/smoke_docker_compose.py
docker compose down
```

See `api/README.md` for details.
