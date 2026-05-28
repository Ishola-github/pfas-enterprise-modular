#!/usr/bin/env bash
# =============================================================================
# Docker/Ubuntu fetch -- NHANES PFAS + DEMO XPTs for reference table builder
# =============================================================================
#
# Downloads the eight NHANES public-use SAS Transport files required
# by:
#   * scripts/build_nhanes_reference_tables.py           (unweighted)
#   * scripts/build_nhanes_weighted_reference_tables.py  (weighted)
#
# into the layout those scripts expect:
#
#   data/raw/nhanes/<cycle>/PFAS_*.XPT
#   data/raw/nhanes/<cycle>/DEMO_*.XPT
#
# Cycles covered:
#   2013_2014  : PFAS_H.XPT + DEMO_H.XPT
#   2015_2016  : PFAS_I.XPT + DEMO_I.XPT
#   2017_2018  : PFAS_J.XPT + DEMO_J.XPT
#   2017_2020  : P_PFAS.XPT + P_DEMO.XPT       (pre-pandemic combined)
#
# What this script does NOT do:
#   * Touch validation/serum_v1/ or validation/serum_h_v1/. Those
#     are governance directories anchored to the SHAs of the files
#     under data/external/nhanes_serum*/. This script writes a
#     PEER copy of PFAS_J.XPT / PFAS_H.XPT into data/raw/nhanes/...
#     (the path the user's reference-table builder expects). The
#     two copies are byte-identical; both anchors stay valid.
#   * Mutate the cycle-J anchor CSV (frozen at SHA-256
#     dfd4dbb59128043e91870265acc15f91f673ec81ee3d00d91223022755e4490f).
#
# Idempotent: re-running is safe. Existing files are overwritten
# with byte-identical content because NHANES public-use files are
# frozen at publication time.
#
# Recommended invocation (PowerShell host):
#
#   docker run --rm `
#     -v "${PWD}:/workspace" `
#     -w /workspace `
#     ubuntu:22.04 `
#     bash scripts/docker_fetch_nhanes_pfas_demo.sh
#
# Recommended invocation (bash host):
#
#   docker run --rm \
#     -v "$(pwd):/workspace" \
#     -w /workspace \
#     ubuntu:22.04 \
#     bash scripts/docker_fetch_nhanes_pfas_demo.sh
#
# =============================================================================

set -euo pipefail

REPO_ROOT="${PWD}"
RAW_ROOT="${REPO_ROOT}/data/raw/nhanes"
HASH_LOG="${REPO_ROOT}/data/raw/nhanes/.docker_fetch_hashes.txt"

mkdir -p "${RAW_ROOT}"

# --- (1) ensure curl + ca-certificates ----------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  echo "[fetch] installing curl + coreutils (one-time)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    ca-certificates curl coreutils
fi

# CDC public NHANES data file URLs follow a stable pattern:
#   https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/<YYYY>/DataFiles/<FILE>.xpt
# Pre-pandemic combined cycle (P_*) is published under the "limited
# access" structure but the files we need (PFAS, DEMO) are public.
#
# The exact filename case follows CDC's published URL casing.

# CDC public NHANES URL patterns:
#   * Regular cycles: Public/<starting_year>/DataFiles/<file>.xpt
#   * Pre-pandemic combined (P_ prefix): Public/2017/DataFiles/<file>.xpt
#     (the pre-pandemic 2017-March 2020 files live in the 2017
#     directory; there is no "2017-2020" directory on the public
#     NCHS host -- that URL returns 404)
#
# Each entry is "url_primary[|url_fallback1|url_fallback2]" so we
# can probe alternative locations if CDC reorganizes a single
# file without us needing to ship a new fetcher.

declare -A FILES=(
  ["2013_2014/PFAS_H.XPT"]="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/PFAS_H.xpt"
  ["2013_2014/DEMO_H.XPT"]="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2013/DataFiles/DEMO_H.xpt"
  ["2015_2016/PFAS_I.XPT"]="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2015/DataFiles/PFAS_I.xpt"
  ["2015_2016/DEMO_I.XPT"]="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2015/DataFiles/DEMO_I.xpt"
  ["2017_2018/PFAS_J.XPT"]="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/PFAS_J.xpt"
  ["2017_2018/DEMO_J.XPT"]="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/DEMO_J.xpt"
  ["2017_2020/P_PFAS.XPT"]="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_PFAS.xpt|https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017-2020/DataFiles/P_PFAS.xpt"
  ["2017_2020/P_DEMO.XPT"]="https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_DEMO.xpt|https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017-2020/DataFiles/P_DEMO.xpt"
)

verify_xpt_header() {
  # SAS Transport (XPT) files start with the literal ASCII signature
  # "HEADER RECORD*******LIBRARY HEADER RECORD!!!!!!!" (80 bytes).
  # If we accidentally downloaded an HTML 404 / codebook page,
  # this catches it before we hash + commit a fake.
  local f="$1"
  local magic
  magic=$(head -c 32 "$f")
  case "$magic" in
    HEADER\ RECORD*) return 0 ;;
    *)
      echo "[fetch] ERROR: $f does not start with a SAS Transport header"
      echo "[fetch]        first 64 bytes follow (cat -A):"
      head -c 64 "$f" | cat -A
      echo
      return 1
      ;;
  esac
}

echo "[fetch] downloading 8 NHANES XPT files into ${RAW_ROOT}"
{
  echo "# NHANES PFAS + DEMO fetch hashes"
  echo "# Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# Host (uname -a): $(uname -a)"
  echo
} > "${HASH_LOG}"

# Track per-file success so a single 404 doesn't abort the whole
# batch. The reference table builder is already designed to skip
# missing cycles gracefully; here we just report the truth.
declare -a FAILED=()
declare -a SUCCEEDED=()

for rel in "${!FILES[@]}"; do
  url_field="${FILES[$rel]}"
  out="${RAW_ROOT}/${rel}"
  mkdir -p "$(dirname "${out}")"

  # url_field may carry "primary|fallback1|fallback2"
  IFS='|' read -r -a candidates <<< "${url_field}"

  ok=0
  for url in "${candidates[@]}"; do
    echo "[fetch] ${rel}  <-  ${url}"
    if curl -fsSL --retry 3 --retry-delay 2 -o "${out}" "${url}"; then
      if verify_xpt_header "${out}"; then
        ok=1
        SUCCEEDED+=("${rel}")
        break
      else
        rm -f "${out}"
        echo "[fetch]   header verify failed; trying next candidate"
      fi
    else
      echo "[fetch]   curl failed (HTTP error or transport error); trying next candidate"
    fi
  done

  if [ "${ok}" -ne 1 ]; then
    FAILED+=("${rel}")
  fi
done

echo
echo "[fetch] hashing downloaded files"
{
  echo "## Raw NHANES SAS Transport files (successful)"
  for rel in "${SUCCEEDED[@]}"; do
    sha256sum "${RAW_ROOT}/${rel}"
  done
  echo
  echo "## URLs (for traceability)"
  for rel in "${!FILES[@]}"; do
    echo "${rel}  <-  ${FILES[$rel]}"
  done
  if [ "${#FAILED[@]}" -gt 0 ]; then
    echo
    echo "## FAILED (no URL candidate worked)"
    for rel in "${FAILED[@]}"; do
      echo "  ${rel}"
    done
  fi
} >> "${HASH_LOG}"

cat "${HASH_LOG}"
echo
echo "[fetch] complete. Hash log: ${HASH_LOG}"
echo "[fetch] succeeded: ${#SUCCEEDED[@]}; failed: ${#FAILED[@]}"
if [ "${#FAILED[@]}" -gt 0 ]; then
  # Exit nonzero so a caller scripted on top of this knows we
  # were not fully successful, but the log records the partial
  # state for forensics.
  exit 3
fi
