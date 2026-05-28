# Provenance — serum lane v1.0

| Field | Value |
| --- | --- |
| Lane | `serum` (human biomonitoring) |
| Version | 1.0 |
| Issued | 2026-05-13 |
| Authority | This file is the **chain of custody** for the v1.0 serum CSV |
| Companion documents | `schema_contract.md`, `data_dictionary.md`, `applicability_domain.txt`, `limitations.md` |

This file documents (a) where the v1.0 serum data came from, (b) how
it was converted, and (c) the integrity anchor that lets a reviewer
verify they are looking at the same artifact this contract was
written against.

---

## 1. Authoritative source

| Attribute | Value |
| --- | --- |
| Provider | U.S. Centers for Disease Control and Prevention (CDC), National Center for Health Statistics (NCHS) |
| Program | National Health and Nutrition Examination Survey (NHANES) |
| Cycle | J (2017-2018) |
| Component | Laboratory — PFAS Special Subsample (`PFAS_J`) |
| Source URL (raw XPT) | <https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/PFAS_J.xpt> |
| Documentation URL | <https://wwwn.cdc.gov/Nchs/Nhanes/2017-2018/PFAS_J.htm> |
| Release type | Public-use, de-identified survey microdata |
| Distribution format | SAS Transport (`.xpt`, XPORT v5/v8) |

NHANES PFAS_J is the CDC's 2017-2018 "PFAS Special Subsample": a
randomly selected subset of NHANES cycle J respondents (aged ≥12
years) with PFAS serum analytes measured by an isotope-dilution
LC-MS/MS method at the CDC Division of Laboratory Sciences. The
public-use file is de-identified and released under NCHS data use
agreements.

## 2. Local download and conversion

### 2.1 Download

Performed by the repository script:

```text
download_nhanes_pfas.ps1
```

This script pulls `PFAS_J.XPT` from the CDC URL above and writes it
to:

```text
data/raw/nhanes_pfas/PFAS_J_2017_2018.XPT
```

(For v1.0 this is the only NHANES file in scope. The script also
fetches `P_PFAS.XPT`, `P_DEMO.xpt`, `P_INQ.xpt`, and `PFAS_I.XPT`,
all of which are **out of scope** for v1.0 — see §6.)

### 2.2 Conversion (XPT → CSV)

Performed by the repository script:

```text
scripts/convert_nhanes_xpt_to_csv.R
```

The conversion is intentionally narrow:

- One input `.xpt` → one output `.csv`.
- Reader: `haven::read_xpt()` (SAS Transport v5/v8).
- Writer: `readr::write_csv()`.
- **No** column renaming, **no** analyte mapping, **no** LOD
  re-encoding, **no** harmonization with any other matrix.
- Column names land in lowercase snake_case (the SAS variable
  case is normalized to lowercase by the reader; this matches
  the `janitor::clean_names` convention recorded in
  `schema_contract.md`).
- SAS variable labels are preserved in the in-memory data frame
  (via `labelled::var_label()`) but are not written to CSV by
  design.

The repository-canonical converted artifact is:

```text
data/training/serum/nhanes_serum_pfas_2017_2018.csv
```

## 3. Integrity anchor for v1.0

The following identifies the **exact** CSV artifact this contract was
written against. Any reviewer who recomputes the SHA-256 against the
file at `data/training/serum/nhanes_serum_pfas_2017_2018.csv` must
get this value, byte-for-byte, or the artifact has drifted from the
contract.

| Attribute | Value |
| --- | --- |
| Path | `data/training/serum/nhanes_serum_pfas_2017_2018.csv` |
| Format | CSV, UTF-8, LF (per `readr::write_csv` defaults), comma-delimited |
| Header row | Yes (1 row) |
| Data rows | 2,133 (one row per PFAS subsample respondent) |
| Column count | 20 (2 structural + 9 analyte values + 9 LOD-code columns) |
| Byte length | 159,118 |
| SHA-256 | `dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f` |
| Algorithm | SHA-256 (per FIPS 180-4) |
| Issued | 2026-05-13 |

### 3.1 How to verify

```powershell
# PowerShell (Windows)
Get-FileHash -Algorithm SHA256 `
  data/training/serum/nhanes_serum_pfas_2017_2018.csv
```

```bash
# bash (Linux / macOS / WSL)
sha256sum data/training/serum/nhanes_serum_pfas_2017_2018.csv
```

If the computed hash does **not** match `dfd4db…490f`, the artifact
has drifted. Do **not** train, score, or publish against it without
re-running §2 and re-issuing this provenance file with the new hash
under a new version (`serum_v1.0.1` or `serum_v1.1`).

### 3.2 Relation to the scope-freeze manifest

This hash must be carried into the scope-freeze manifest for serum
(see `validation/scope_freeze/` and `SCOPE_AND_INTENDED_USE.md` §8)
before any model trained on this lane is promoted to a deployed
prediction endpoint. The promotion gate is normative in
`schema_contract.md` §8.

## 4. Reproducibility recipe

A second operator can reproduce the v1.0 CSV with:

```text
# 1. Download the raw XPT from CDC
pwsh ./download_nhanes_pfas.ps1

# 2. Convert XPT -> CSV (R, with haven + readr installed)
Rscript scripts/convert_nhanes_xpt_to_csv.R

# 3. Re-hash and compare to §3
Get-FileHash -Algorithm SHA256 `
  data/training/serum/nhanes_serum_pfas_2017_2018.csv
```

Required toolchain:

- PowerShell 5.1+ (Windows) or `pwsh` 7+ (cross-platform).
- R 4.x with `haven`, `readr`, and `janitor` installed (auto-installed
  by the conversion script if missing). `janitor::clean_names()` is
  the step that normalizes the uppercase SAS variable names (e.g.
  `SEQN`, `LBXNFOA`) to the lowercase snake_case convention
  (`seqn`, `lbxnfoa`) declared in `schema_contract.md` §1; without it
  the produced CSV would not byte-reproduce the v1.0 anchor in §3.
- Network access to `wwwn.cdc.gov`.

The CDC public-use URL has historically been stable, but is **not**
guaranteed to remain at the same path indefinitely. If CDC moves the
file, the new URL must be recorded here under a new version; the
old URL must not be silently overwritten.

## 5. License and attribution

### 5.1 License of the source data

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

### 5.2 Suggested citation

> Centers for Disease Control and Prevention (CDC), National Center
> for Health Statistics (NCHS). *National Health and Nutrition
> Examination Survey Data: 2017-2018 PFAS Special Subsample
> (PFAS_J)*. U.S. Department of Health and Human Services, Centers
> for Disease Control and Prevention.
> <https://wwwn.cdc.gov/Nchs/Nhanes/2017-2018/PFAS_J.htm>

### 5.3 Survey-design fields (out of scope for v1.0 anchor)

`PFAS_J.XPT` carries `SEQN` and the two-year subsample weight
`WTSB2YR`. NHANES survey-design strata and PSUs (`SDMVSTRA`,
`SDMVPSU`) live in the demographics file `P_DEMO.XPT` and are
**not** included in v1.0's anchor CSV. Any defensible variance
estimate or weighted population statistic must be produced by a
downstream artifact that joins `PFAS_J` on `SEQN` to the relevant
demographics file. That join is out of scope for the v1.0
contract and must be issued as its own versioned artifact.

## 6. What is **not** in v1.0 (explicit non-claims)

The following cycles and files are deliberately **out of scope** for
v1.0 even though the download script can fetch them:

| File | Cycle | Status under v1.0 |
| --- | --- | --- |
| `P_PFAS.XPT` | Pre-pandemic 2017-March 2020 | NOT in v1.0; requires `serum_v1.1` or `serum_v2` |
| `PFAS_I.XPT` | I (2015-2016) | NOT in v1.0; legacy panel, requires a new AD revision |
| `PFAS_H.XPT` | H (2013-2014) | NOT in v1.0; 8-analyte panel (adds PFBS / PFHP / PFDO, lacks the v1.0 isomer split); SAS labels say `(ug/L)` while the codebook LLOD table cites `ng/mL`. Now governed as a peer lane under `validation/serum_h_v1/` (anchor SHA-256 `98d11b27beadad159a9bb596caa2e8839b5bfca279fd32f618e60539c53f644f`); cycle H is **still** out of scope for v1.0 and cannot be merged into the cycle-J anchor without a separate cross-cycle harmonization artifact. See `schema_contract.md` \u00a77.1 and `validation/serum_h_v1/`. |
| `SSPFAS_H.XPT` | H (2013-2014) | NOT in v1.0; also NOT admitted under `serum_h_v1`. Surplus-serum isomer companion for `PFAS_H.XPT`. Carries the n-/Sb- PFOA and n-/Sm- PFOS isomer split that v1.0's PFAS_J merges into a single file. Recorded by SHA-256 in `validation/serum_h_v1/provenance.md` \u00a73.1 only. |
| `L06AGE_C.XPT` | C (2003-2004) | NOT in v1.0; legacy panel, different analyte set |
| `P_DEMO.XPT` | Pre-pandemic demographics | Not part of the v1.0 anchor (see §5.3) |
| `P_INQ.XPT` | Pre-pandemic income | Not part of v1.0 |

A future version of this lane that incorporates any of these files
must:

1. Be issued under a new directory (`validation/serum_v1.1/` or
   `validation/serum_v2/`).
2. Carry its own download / conversion / SHA-256 record in a new
   `provenance.md`.
3. Re-derive the observed envelope in `schema_contract.md` against
   the merged panel (not v1.0's envelope).
4. State explicitly whether it adds rows (more respondents),
   adds columns (more analytes), or both.

A silent expansion of v1.0 to include any of these files is a
governance violation.

## 7. Change control for this provenance file

| Version | Date | Change | Re-verification |
| --- | --- | --- | --- |
| 1.0   | 2026-05-13 | Initial provenance record for the NHANES PFAS_J → CSV conversion. SHA-256 anchored. | `Get-FileHash` on `data/training/serum/nhanes_serum_pfas_2017_2018.csv` matches §3. |
| 1.0.1 | 2026-05-13 | **Pipeline alignment** (no anchor change). External-confirm run discovered that `scripts/convert_nhanes_xpt_to_csv.R` did not normalize SAS variable names to lowercase snake_case, so a fresh run produced a CSV with uppercase headers (same bytes, same data, different hash). The script now calls `janitor::clean_names(df)` between `haven::read_xpt()` and `readr::write_csv()`, matching `schema_contract.md` §1. The v1.0 CSV SHA-256 is unchanged. | Three-environment external confirm: PowerShell + Docker/Ubuntu fetch identical XPT (`bd2460dc…e4e6b3`, 344,800 bytes) from CDC; Rscript pipeline re-derives the v1.0 anchor (`dfd4db…490f`, 159,118 bytes) byte-for-byte. |

Any change to the source URL, the conversion script behavior, the
column set, the row count, or the SHA-256 of the canonical CSV
**requires** a new version entry above and a corresponding new
version of `schema_contract.md` / `applicability_domain.txt` if
either of those becomes inconsistent.
