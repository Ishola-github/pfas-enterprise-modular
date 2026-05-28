# Provenance — serum_h lane v1.0

| Field | Value |
| --- | --- |
| Lane | `serum_h` (human biomonitoring, NHANES cycle H) |
| Version | 1.0 (`serum_h_v1`) |
| Issued | 2026-05-13 |
| Authority | This file is the **chain of custody** for the serum_h v1.0 CSV |
| Companion documents | `schema_contract.md`, `data_dictionary.md`, `applicability_domain.txt`, `limitations.md`, `intended_use.txt` |

This file documents (a) where the serum_h v1.0 data came from, (b)
how it was fetched and converted in a documented Docker / Ubuntu
container, and (c) the integrity anchors that let a reviewer verify
they are looking at the same artifact this contract was written
against.

The cycle-J serum lane is **not** affected by anything in this file.
That lane is governed by `validation/serum_v1/provenance.md` and is
frozen at SHA-256 `dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f`.

---

## 1. Authoritative source

| Attribute | Value |
| --- | --- |
| Provider | U.S. Centers for Disease Control and Prevention (CDC), National Center for Health Statistics (NCHS) |
| Program | National Health and Nutrition Examination Survey (NHANES) |
| Cycle | H (2013-2014) |
| Component | Laboratory — PFAS Special Subsample (`PFAS_H`) |
| Source URL (raw XPT) | <https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/PFAS_H.xpt> |
| Documentation URL | <https://wwwn.cdc.gov/Nchs/Nhanes/2013-2014/PFAS_H.htm> |
| Companion XPT (isomer file, paired non-admitted) | <https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/SSPFAS_H.xpt> |
| Companion documentation | <https://wwwn.cdc.gov/Nchs/Nhanes/2013-2014/SSPFAS_H.htm> |
| Release type | Public-use, de-identified survey microdata |
| Distribution format | SAS Transport (`.xpt`, XPORT v5/v8) |

NHANES PFAS_H is the CDC's 2013-2014 "PFAS Special Subsample": a
random subset of NHANES cycle H respondents (aged ≥12 years) with
PFAS serum analytes measured by an isotope-dilution online SPE
HPLC-TIS-MS/MS method (Kuklenyik 2005) at the CDC Division of
Laboratory Sciences. The public-use file is de-identified and
released under NCHS data use agreements.

`SSPFAS_H.XPT` is the surplus-serum companion file from the same
cycle, carrying the n-/Sb- PFOA and n-/Sm- PFOS isomer split that
cycle J merges into a single file. It is **recorded** here for
chain-of-custody purposes, but **not** admitted under
`serum_h_v1`'s anchor CSV (see `schema_contract.md` §7.1).

## 2. Local fetch and conversion (Docker / Ubuntu)

The fetch + conversion is performed inside a containerized Ubuntu
environment so a second operator gets bit-identical results
regardless of their host OS.

### 2.1 Pipeline script

```text
scripts/docker_fetch_pfas_h.sh
```

Runs inside `rocker/r-ver:4.4` (literally Ubuntu jammy 22.04 + R
4.4 + Posit Public Package Manager). The script is idempotent: a
second invocation produces the same hashes if the upstream CDC
files have not changed (NHANES public-use data are frozen at
publication time).

### 2.2 What the script does

1. Installs `curl` from `apt` (if not present in the base image).
2. Installs `haven`, `readr`, and `janitor` from the P3M binary
   repository, R version 4.4.
3. Downloads `PFAS_H.XPT` and `SSPFAS_H.XPT` from the CDC public
   data file URLs.
4. Verifies each downloaded file starts with the SAS Transport
   header (`HEADER RECORD*******LIBRARY HEADER RECORD!!!!!!!`)
   to defend against the CDC site serving an HTML codebook page
   instead of the binary XPT.
5. Computes SHA-256 of both raw XPT files.
6. Converts `PFAS_H.XPT` → `nhanes_serum_pfas_h_2013_2014.csv`
   with the **identical** R pipeline used by `serum` v1.0:
   `haven::read_xpt → janitor::clean_names → readr::write_csv`.
7. Computes SHA-256 of the produced CSV.
8. Writes the full hash log to
   `validation/serum_h_v1/.docker_pipeline_hashes.txt`.

### 2.3 Recommended invocation (PowerShell host, Docker Desktop)

```powershell
docker run --rm `
  -v "${PWD}:/workspace" `
  -w /workspace `
  rocker/r-ver:4.4 `
  bash scripts/docker_fetch_pfas_h.sh
```

### 2.4 Recommended invocation (bash host)

```bash
docker run --rm \
  -v "$(pwd):/workspace" \
  -w /workspace \
  rocker/r-ver:4.4 \
  bash scripts/docker_fetch_pfas_h.sh
```

### 2.5 R-only reproducibility (no Docker)

For an operator who wants to reproduce the CSV without Docker, the
peer R converter is:

```text
scripts/convert_pfas_h_xpt_to_csv.R
```

It applies the same three-call pipeline (`haven::read_xpt →
janitor::clean_names → readr::write_csv`) to the raw XPT files
once they are on disk at `data/external/nhanes_serum_h/`. Run it
from the repository root in any R 4.x session that has `haven`,
`readr`, and `janitor` installed.

## 3. Integrity anchors for serum_h v1.0

### 3.1 Raw NHANES SAS Transport files

| File | Path | SHA-256 | Size (bytes) |
| --- | --- | --- | ---: |
| `PFAS_H.XPT` | `data/external/nhanes_serum_h/PFAS_H.XPT` | `ab062b2ecf99989b1731cb63588d8305409c2e554a76de7e05946f4877091652` | — |
| `SSPFAS_H.XPT` (paired non-admitted) | `data/external/nhanes_serum_h/SSPFAS_H.XPT` | `1e23688dfa6bdfdc14c0447f4d34032983271063a1a343c04338ae4258515c99` | 158,480 |

### 3.2 Derived anchor CSV (governed artifact)

| Attribute | Value |
| --- | --- |
| Path | `data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv` |
| Format | CSV, UTF-8, LF (per `readr::write_csv` defaults), comma-delimited |
| Header row | Yes (1 row) |
| Data rows | 2,339 (one row per cycle-H PFAS subsample respondent) |
| Column count | 18 (2 structural + 8 analyte values + 8 LOD-code columns) |
| SHA-256 | `98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f` |
| Algorithm | SHA-256 (per FIPS 180-4) |
| Issued | 2026-05-13 |
| Reproducibility | `scripts/docker_fetch_pfas_h.sh` (Docker / Ubuntu) and `scripts/convert_pfas_h_xpt_to_csv.R` (R-only) both regenerate this file byte-for-byte from the raw XPT in §3.1. |

### 3.3 How to verify

```powershell
# PowerShell (Windows)
Get-FileHash -Algorithm SHA256 `
  data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv
```

```bash
# bash (Linux / macOS / WSL)
sha256sum data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv
```

If the computed hash does **not** match `98d11b27…644f`, the
artifact has drifted. Do **not** train, score, or publish against
it without re-running §2 and re-issuing this provenance file with
the new hash under a new version (`serum_h_v1.0.1` or
`serum_h_v1.1`).

## 4. Relation to the cycle-J anchor (frozen)

| Lane | Anchor file | SHA-256 | Governance |
| --- | --- | --- | --- |
| `serum` (cycle J, v1.0) | `data/training/serum/nhanes_serum_pfas_2017_2018.csv` | `dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f` | `validation/serum_v1/` |
| `serum_h` (cycle H, v1.0) | `data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv` | `98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f` | `validation/serum_h_v1/` (this directory) |

The two anchors are **independent peer artifacts**. Operations on
either MUST NOT modify the other. The cycle-J anchor is governed by
its own `provenance.md`, its own `schema_contract.md` §8 promotion
gate, and its own SHA-256.

## 5. Label-unit reconciliation (cycle-H specific, recorded for posterity)

The SAS variable labels in `PFAS_H.XPT` annotate every concentration
column with `(ug/L)`. The NHANES PFAS_H online codebook documents
the LLOD table in `ng/mL` and treats the two units as equivalent
for aqueous matrices (`1 ug/L = 1 ng/mL` to within ~2.5% for serum
density ~1.025 g/mL). The cycle-H anchor CSV records the
**numerical values exactly as NHANES published them**, no
conversion. `schema_contract.md` §3.2 is the normative location for
this rule; this provenance file simply records that the rule was
known at the time the anchor was issued.

## 6. License and attribution

### 6.1 License of the source data

NHANES public-use data are published by a U.S. Federal Government
agency (CDC / NCHS, U.S. Department of Health and Human Services).
Works of the U.S. Federal Government are not subject to copyright
protection in the United States under 17 U.S.C. §105. NHANES
microdata are released for public statistical research subject to
the NCHS data use agreements.

- The public-use file is **de-identified**. Operators must not
  attempt re-identification of any respondent.
- Inclusion of NHANES in this repository does **not** imply CDC,
  NCHS, NIH, or HHS endorsement of this platform or of any model
  trained on this lane.

### 6.2 Suggested citation

> Centers for Disease Control and Prevention (CDC), National Center
> for Health Statistics (NCHS). *National Health and Nutrition
> Examination Survey Data: 2013-2014 PFAS Special Subsample
> (PFAS_H)*. U.S. Department of Health and Human Services, Centers
> for Disease Control and Prevention.
> <https://wwwn.cdc.gov/Nchs/Nhanes/2013-2014/PFAS_H.htm>

### 6.3 Survey-design fields (out of scope for v1.0 anchor)

`PFAS_H.XPT` carries `SEQN` and the two-year subsample weight
`WTSB2YR`. NHANES survey-design strata and PSUs (`SDMVSTRA`,
`SDMVPSU`) live in the cycle-H demographics file `DEMO_H.XPT` and
are **not** included in serum_h v1.0's anchor CSV. Any defensible
variance estimate or weighted population statistic must be produced
by a downstream artifact that joins `PFAS_H` on `SEQN` to
`DEMO_H.XPT`. That join is out of scope for this contract.

## 7. What is **not** in serum_h v1.0 (explicit non-claims)

| File | Cycle | Status under serum_h v1.0 |
| --- | --- | --- |
| `SSPFAS_H.XPT` | H (2013-2014) isomer companion | Recorded (SHA-256 above), **not** admitted; admission requires the follow-up artifact described in `schema_contract.md` §7.1 |
| `PFAS_J.XPT` | J (2017-2018) | NOT in serum_h; governed separately by `validation/serum_v1/` |
| `P_PFAS.XPT` | Pre-pandemic 2017-2020 | NOT in serum_h; requires its own `serum_prepandemic_v1` lane |
| `PFAS_I.XPT` | I (2015-2016) | NOT in serum_h; requires its own `serum_i_v1` lane |
| `L06AGE_C.XPT` | C (2003-2004) | NOT in serum_h; requires its own `serum_c_v1` lane |
| `DEMO_H.XPT` | Cycle-H demographics | Not part of the serum_h v1.0 anchor (see §6.3) |

A future version of this lane that incorporates any of these files
must:

1. Be issued under a new directory (`validation/serum_h_v1.1/` or
   `validation/serum_h_v2/`).
2. Carry its own download / conversion / SHA-256 record in a new
   `provenance.md`.
3. Re-derive the observed envelope in `schema_contract.md` against
   the merged panel (not v1.0's envelope).
4. State explicitly whether it adds rows (more respondents),
   adds columns (more analytes), or both.

A silent expansion of serum_h v1.0 to include any of these files
is a governance violation.

## 8. Change control for this provenance file

| Version | Date | Change | Re-verification |
| --- | --- | --- | --- |
| 1.0 | 2026-05-13 | Initial provenance record for the NHANES PFAS_H → CSV conversion via `scripts/docker_fetch_pfas_h.sh` (rocker/r-ver:4.4). Raw XPT SHA-256s and derived anchor CSV SHA-256 anchored. SSPFAS_H.XPT recorded as paired non-admitted artifact. | Re-run `scripts/docker_fetch_pfas_h.sh`; sha256sums in `validation/serum_h_v1/.docker_pipeline_hashes.txt` must match §3.1 and §3.2. |

Any change to the source URL, the conversion script behavior, the
column set, the row count, or the SHA-256 of the canonical CSV
**requires** a new version entry above and a corresponding new
version of `schema_contract.md` / `applicability_domain.txt` if
either of those becomes inconsistent.
