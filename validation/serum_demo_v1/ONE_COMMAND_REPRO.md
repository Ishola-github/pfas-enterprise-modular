# One-command reproducibility (reviewer path)

**Program:** Independent Reproducibility Pilot · **RUO only**  
**Frozen tag:** `serum-v2.0.0-temporal`

---

## 1. Clone

```bash
git clone https://github.com/Ishola-github/pfas-enterprise-modular.git pfas-repro
cd pfas-repro
git checkout serum-v2.0.0-temporal
```

---

## 2. Run ONE command

```bash
bash scripts/repro_one_shot.sh
```

**Windows:** use WSL2 or Git Bash with Docker Desktop running.

---

## 3. Compare ONE hash

**PASS** if output ends with:

```text
ONE_SHOT_REPRO: PASS
V2 output_csv_sha256: 87c8b97e8a2c9002b183b0fabe161f531f1b933dd95e9ef4f4df980666310b67
```

---

## 4. Sign ONE template

Complete and return: `REVIEWER_ATTESTATION_MINIMAL.txt`

---

Full protocol (optional): `BLIND_EXTERNAL_REPRO_PROTOCOL.md`
