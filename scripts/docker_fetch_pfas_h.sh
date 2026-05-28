#!/usr/bin/env bash
# =============================================================================
# Docker/Ubuntu fetch + convert pipeline for the serum_h_v1 lane
# =============================================================================
#
# This script runs inside a containerized Ubuntu environment. It:
#   1. Downloads two NHANES 2013-2014 (cycle H) PFAS SAS Transport (.xpt)
#      files from the CDC's public NCHS server:
#        - PFAS_H.XPT     (the 8-analyte cycle-H PFAS file; lane anchor)
#        - SSPFAS_H.XPT   (the surplus-serum companion file carrying the
#                          n-/Sb- PFOA and n-/Sm- PFOS isomer split)
#   2. Records the SHA-256 of each downloaded .xpt.
#   3. Converts PFAS_H.XPT to CSV using the SAME R pipeline as v1.0:
#         haven::read_xpt  ->  janitor::clean_names  ->  readr::write_csv
#      so the cycle-H anchor CSV is reproducible byte-for-byte from the
#      raw CDC artifact via a single documented R toolchain.
#   4. Records the SHA-256 of the produced CSV.
#
# What this script does NOT do:
#   - Convert SSPFAS_H.XPT to CSV. The isomer companion is admitted at the
#     governance bundle level only (provenance.md records its hash); a
#     future pair-admission artifact will handle that conversion.
#   - Touch any v1.0 artifact. The cycle-J anchor at
#     data/training/serum/nhanes_serum_pfas_2017_2018.csv must remain
#     byte-for-byte unchanged (SHA-256
#     dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f).
#
# Idempotent: re-running this script is safe. Existing files are
# overwritten with byte-identical content if the upstream source has not
# changed (NHANES public data files are frozen at publication time).
#
# Intended invocation (from the repo root on the host):
#
#   docker run --rm \
#     -v "$(pwd):/workspace" \
#     -w /workspace \
#     rocker/r-ver:4.4 \
#     bash scripts/docker_fetch_pfas_h.sh
#
# On Windows PowerShell:
#
#   docker run --rm `
#     -v "${PWD}:/workspace" `
#     -w /workspace `
#     rocker/r-ver:4.4 `
#     bash scripts/docker_fetch_pfas_h.sh
#
# Image notes
# -----------
# rocker/r-ver:4.4 is literally Ubuntu jammy (22.04 LTS) with R 4.4 added
# and the Posit Public Package Manager (P3M) binary repo pre-configured.
# We intentionally use a fixed R version (4.4) so the haven / readr /
# janitor combination is byte-for-byte reproducible across machines.
# Ubuntu's own r-base-core in jammy ships R 4.1, which is too old for
# the current P3M binary repo and forces a slow source compile; the
# rocker image avoids that without changing the underlying OS family.
#
# =============================================================================

set -euo pipefail

REPO_ROOT="${PWD}"
EXT_DIR="${REPO_ROOT}/data/external/nhanes_serum_h"
OUT_DIR="${REPO_ROOT}/data/training/serum_h"
LOG_DIR="${REPO_ROOT}/validation/serum_h_v1"

mkdir -p "${EXT_DIR}" "${OUT_DIR}" "${LOG_DIR}"

PFAS_H_URL="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/PFAS_H.xpt"
SSPFAS_H_URL="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/SSPFAS_H.xpt"
PFAS_H_XPT="${EXT_DIR}/PFAS_H.XPT"
SSPFAS_H_XPT="${EXT_DIR}/SSPFAS_H.XPT"
ANCHOR_CSV="${OUT_DIR}/nhanes_serum_pfas_h_2013_2014.csv"
HASH_LOG="${LOG_DIR}/.docker_pipeline_hashes.txt"

echo "[serum_h_v1] running in $(uname -a)"
echo "[serum_h_v1] repo root: ${REPO_ROOT}"
echo

# --- (1) ensure system + R packages ------------------------------------------
# rocker/r-ver:4.4 ships with R 4.4 + curl + P3M wired in. We only need
# to add haven, readr, janitor (binary install via P3M, ~30 seconds).
# The R toolchain (haven::read_xpt + janitor::clean_names +
# readr::write_csv) is identical to v1.0's converter, so the byte-for-
# byte reproducibility property carries over.
if ! command -v curl >/dev/null 2>&1; then
  echo "[serum_h_v1] installing curl from apt (one-time)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends ca-certificates curl coreutils
fi

if ! Rscript -e 'stopifnot(all(c("haven","readr","janitor") %in% rownames(installed.packages())))' >/dev/null 2>&1; then
  echo "[serum_h_v1] installing R packages haven + readr + janitor (P3M binaries)"
  Rscript -e 'install.packages(c("haven","readr","janitor"), quiet = TRUE)'
fi

# --- (2) download both XPT files ---------------------------------------------
verify_xpt_header() {
  # SAS Transport (XPT) files start with the literal ASCII signature
  # "HEADER RECORD*******LIBRARY HEADER RECORD!!!!!!!" (80 bytes).
  # If we ever silently downloaded an HTML error / codebook page
  # instead, this check catches it before we hash + commit a fake.
  local f="$1"
  local magic
  magic=$(head -c 32 "$f")
  case "$magic" in
    HEADER\ RECORD*) return 0 ;;
    *) echo "[serum_h_v1] ERROR: $f does not start with a SAS Transport header"; echo "[serum_h_v1]        first 64 bytes: $(head -c 64 "$f" | cat -A)"; return 1 ;;
  esac
}

echo "[serum_h_v1] downloading PFAS_H.xpt"
curl -fsSL --retry 3 --retry-delay 2 -o "${PFAS_H_XPT}" "${PFAS_H_URL}"
verify_xpt_header "${PFAS_H_XPT}"

echo "[serum_h_v1] downloading SSPFAS_H.xpt (isomer companion)"
curl -fsSL --retry 3 --retry-delay 2 -o "${SSPFAS_H_XPT}" "${SSPFAS_H_URL}"
verify_xpt_header "${SSPFAS_H_XPT}"

# --- (3) hash raw XPT files ---------------------------------------------------
{
  echo "# Docker/Ubuntu fetch + convert hashes -- serum_h_v1 lane"
  echo "# Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# Host (uname -a): $(uname -a)"
  echo "# R: $(Rscript --version 2>&1)"
  echo "# bash: ${BASH_VERSION}"
  echo
  echo "## Raw NHANES SAS Transport files"
  sha256sum "${PFAS_H_XPT}" "${SSPFAS_H_XPT}"
} > "${HASH_LOG}"

echo "[serum_h_v1] raw XPT hashes:"
sha256sum "${PFAS_H_XPT}" "${SSPFAS_H_XPT}"

# --- (4) convert PFAS_H.XPT -> CSV via the v1.0-compatible R pipeline ---------
# IMPORTANT: this is the SAME pipeline as v1.0's
# scripts/convert_nhanes_xpt_to_csv.R. The same three calls -- read_xpt,
# janitor::clean_names, readr::write_csv -- guarantee that the cycle-H
# anchor CSV is byte-for-byte reproducible from the raw XPT under the
# same R toolchain.
Rscript - <<'RSCRIPT_EOF'
suppressPackageStartupMessages({
  library(haven)
  library(readr)
  library(janitor)
})
df <- haven::read_xpt("data/external/nhanes_serum_h/PFAS_H.XPT")
df <- janitor::clean_names(df)
readr::write_csv(df, "data/training/serum_h/nhanes_serum_pfas_h_2013_2014.csv")
cat("[R] rows=", nrow(df), " cols=", ncol(df), "\n", sep = "")
cat("[R] columns: ", paste(names(df), collapse = ", "), "\n", sep = "")
RSCRIPT_EOF

# --- (5) hash the produced CSV ------------------------------------------------
{
  echo
  echo "## Derived anchor CSV (PFAS_H.XPT -> read_xpt -> clean_names -> write_csv)"
  sha256sum "${ANCHOR_CSV}"
} >> "${HASH_LOG}"

echo
echo "[serum_h_v1] anchor CSV hash:"
sha256sum "${ANCHOR_CSV}"

echo
echo "[serum_h_v1] complete. Hash log written to:"
echo "  ${HASH_LOG}"
